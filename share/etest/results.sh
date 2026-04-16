#!/usr/bin/env bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# STATS
#
#-----------------------------------------------------------------------------------------------------------------------

create_vcs_info()
{
    declare -g VCS_INFO=""

    if [[ -d ".hg" ]] && command_exists hg; then
        pack_set VCS_INFO                                   \
            type="hg"                                       \
            info="$(hg id --id)"                            \
            url="$(hg paths default)"                       \
            branch="$(hg branch)"                           \
            bookmark="$(hg book | sed 's|no bookmarks set||' | awk '/ * / {print $2}')"  \
            commit="$(hg id --id)"

    elif command_exists git && git rev-parse --is-inside-work-tree &>/dev/null; then
        pack_set VCS_INFO                                             \
            type="git"                                                \
            info="$(git describe --abbrev=7 --always --tags --dirty)" \
            url="$(git config --get remote.origin.url)"               \
            branch="$(git rev-parse --abbrev-ref HEAD)"               \
            bookmark=""                                               \
            commit="$(git rev-parse --short=12 HEAD)"
    fi
}

create_status_json()
{
    DURATION=$(( SECONDS - START_TIME ))

    # Compute percent complete handling corner cases with zero tests to avoid division by zero
    if [[ "${NUM_TESTS_TOTAL}" -eq 0 ]]; then
        PERCENT="0"
    else
        PERCENT=$((200*${NUM_TESTS_EXECUTED}/${NUM_TESTS_TOTAL} % 2 + 100*${NUM_TESTS_EXECUTED}/${NUM_TESTS_TOTAL}))
    fi

    local pids=()
    if cgroup_supported; then
        pids=( $(cgroup_pids -r ${ETEST_CGROUP_BASE} 2>/dev/null || true) )
    else
        pids=( $(nodie_on_error; process_tree 2>/dev/null) ) || pids=()
    fi

    local _passed_json _failed_json _skipped_json
    _passed_json=$(print_tests_json_array TESTS_PASSED "    ")
    _failed_json=$(print_tests_json_array TESTS_FAILED "    ")
    _skipped_json=$(print_tests_json_array TESTS_SKIPPED "    ")

	cat <<-EOF > ${ETEST_JSON}.tmp
	{
	    "cgroup": "${ETEST_CGROUP_BASE}",
	    "datetime": "$(etimestamp_rfc3339)",
	    "duration": "${DURATION}s",
	    "numTestsTotal": ${NUM_TESTS_TOTAL},
	    "numTestsQueued": ${NUM_TESTS_QUEUED},
	    "numTestsRunning": ${NUM_TESTS_RUNNING},
	    "numTestsExecuted": ${NUM_TESTS_EXECUTED},
	    "numTestsPassed": ${NUM_TESTS_PASSED},
	    "numTestsFailed": ${NUM_TESTS_FAILED},
	    "numTestsSkipped": ${NUM_TESTS_SKIPPED},
	    "percent": ${PERCENT},
	    "pids": $(array_to_json pids),
	    "testsPassed": ${_passed_json},
	    "testsFailed": ${_failed_json},
	    "testsSkipped": ${_skipped_json}
	}
	EOF

    mv "${ETEST_JSON}.tmp" "${ETEST_JSON}"
}

create_options_json()
{
	cat <<-EOF > ${ETEST_OPTIONS}.tmp
	{
	    "clean": "${clean}",
	    "debug": "${debug}",
	    "delete": "${delete}",
	    "exclude": "${exclude}",
	    "failfast": "${failfast}",
	    "filter": "${filter}",
	    "html": "${html}",
	    "jobs": "${jobs}",
	    "logdir": "${logdir}",
	    "mountns": "${mountns}",
	    "repeat": "${repeat}",
	    "silent": "${silent}",
	    "test_list": $(array_to_json test_list),
	    "tests": $(array_to_json tests),
	    "verbose": "${verbose}",
	    "workdir": "${workdir}"
	}
	EOF

    mv "${ETEST_OPTIONS}.tmp" "${ETEST_OPTIONS}"
}

# Extract test output from the per-test state directory.
# Test state (output.log, tmp/) lives in ${testdir}.state to prevent tests from
# accidentally overwriting etest files when they create files in their working directory.
__extract_test_output()
{
    local suite=$1
    local name=$2

    # statedir is always ${testdir}.state (sibling directory pattern)
    local test_output="${workdir}/${suite}.etest/${name}.state/output.log"
    [[ -f "${test_output}" ]] || return 0

    # Strip ANSI codes and NUL bytes (which cause bash warnings in command substitution)
    noansi < "${test_output}" | tr -d '\0'
}

create_failure_output()
{
    # Always create the file (even if empty) so it exists for consumers
    : > "${ETEST_FAILURE_LOG}"

    if array_empty TESTS_FAILED; then
        return 0
    fi

    # Write plain text (no ANSI codes) to the failure log file
    {
        local cols suite test_name
        cols=$(tput cols)
        for suite in "${!TESTS_FAILED[@]}"; do
            for test_name in ${TESTS_FAILED[$suite]}; do
                echo
                local label="● ${suite}:${test_name#ETEST_} "
                local label_len=${#label}
                local dashes_len dashes
                dashes_len=$(( cols - label_len ))
                printf -v dashes '%*s' "${dashes_len}" ''
                dashes="${dashes// /─}"
                echo "${label}${dashes}"
                echo

                __extract_test_output "${suite}" "${test_name}" | sed 's/^/   /'
            done
        done
    } > "${ETEST_FAILURE_LOG}"

    # Optionally display to stderr with colors
    if [[ "${failure_output}" -eq 1 ]]; then
        {
            COLOR_BANNER="red" ebanner "Failure Output" 2>&1

            local line
            while IFS= read -r line; do
                # Color the test header lines
                if [[ "${line}" == "● "* ]]; then
                    echo "$(ecolor red)${line}$(ecolor off)"
                else
                    echo "${line}"
                fi
            done < "${ETEST_FAILURE_LOG}"
        } >&${ETEST_STDERR_FD}
    fi
}

create_results_log()
{
    EFUNCS_COLOR=1
    {
        __display_results_table

        local total
        total=$(( NUM_TESTS_PASSED + NUM_TESTS_FAILED + NUM_TESTS_SKIPPED ))
        printf "%s%s Total: %s%d%s  Passed: %s%d%s  Skipped: %s%d%s  Failed: %s%d%s" \
            "$(ecolor bold green)>>" "$(ecolor off)" \
            "$(ecolor bold)" "${total}" "$(ecolor off)" \
            "$(ecolor bold green)" "${NUM_TESTS_PASSED}" "$(ecolor off)" \
            "$(ecolor bold yellow)" "${NUM_TESTS_SKIPPED}" "$(ecolor off)" \
            "$(ecolor red)" "${NUM_TESTS_FAILED}" "$(ecolor off)"

        local runtime
        if [[ ${DURATION} -ge 60 ]]; then
            runtime="$((DURATION / 60))m$((DURATION % 60))s"
        else
            runtime="${DURATION}s"
        fi
        printf "  %s(Runtime: %s)%s\n" \
            "$(ecolor cyan)" "${runtime}" "$(ecolor off)"

    } > "${ETEST_RESULTS}"
}

create_summary()
{
    create_vcs_info
    pack_to_json VCS_INFO > "${ETEST_VCS}"
    create_status_json
    create_results_log

    {
        if array_not_empty TESTS_FAILED; then
            COLOR_BANNER="red" ebanner "Failed Tests" 2>&1

            local failed_test
            # shellcheck disable=SC2068 # Intentional word splitting for space-separated test names
            for failed_test in ${TESTS_FAILED[@]}; do
                echo "$(ecolor red)  [  FAILED  ] ${failed_test}$(ecolor off)"
            done

            echo
            local plural=""
            [[ ${NUM_TESTS_FAILED} -ne 1 ]] && plural="S"
            echo "$(ecolor red)  ${NUM_TESTS_FAILED} FAILED TEST${plural}$(ecolor off)"
            echo
        fi

        # Display summary output to the terminal if requested
        if [[ "${summary}" -eq 1 ]] && command_exists jq; then
            einfo "Summary"
            jq --color-output . ${ETEST_JSON}
        fi

    } |& tee -a ${ETEST_LOG} >&${ETEST_STDERR_FD}

    # Create failure output file and optionally display to stderr (after log is complete)
    create_failure_output

    # Print gotest-style summary with file locations
    {
        local cols line
        cols=$(tput cols)
        printf -v line '%*s' "${cols}" ''
        line="${line// /─}"

        # Test counts
        echo
        echo "$(ecolor cyan)${line}$(ecolor off)"
        echo
        local total
        total=$(( NUM_TESTS_PASSED + NUM_TESTS_FAILED + NUM_TESTS_SKIPPED ))
        printf "%s%s Total: %s%d%s  Passed: %s%d%s  Skipped: %s%d%s  Failed: %s%d%s" \
            "$(ecolor bold green)>>" "$(ecolor off)" \
            "$(ecolor bold)" "${total}" "$(ecolor off)" \
            "$(ecolor bold green)" "${NUM_TESTS_PASSED}" "$(ecolor off)" \
            "$(ecolor bold yellow)" "${NUM_TESTS_SKIPPED}" "$(ecolor off)" \
            "$(ecolor red)" "${NUM_TESTS_FAILED}" "$(ecolor off)"

        # Runtime
        local runtime
        if [[ ${DURATION} -ge 60 ]]; then
            runtime="$((DURATION / 60))m$((DURATION % 60))s"
        else
            runtime="${DURATION}s"
        fi
        printf "  %s(Runtime: %s)%s" \
            "$(ecolor cyan)" "${runtime}" "$(ecolor off)"
        echo

        # Log files (relative to original PWD when possible)
        local rel_failure_log rel_log rel_xml rel_json rel_results
        rel_failure_log=$(realpath --relative-to="${ETEST_ORIGINAL_PWD}" "${ETEST_FAILURE_LOG}" 2>/dev/null) || rel_failure_log="${ETEST_FAILURE_LOG}"
        rel_log=$(realpath  --relative-to="${ETEST_ORIGINAL_PWD}" "${ETEST_LOG}"  2>/dev/null) || rel_log="${ETEST_LOG}"
        rel_xml=$(realpath  --relative-to="${ETEST_ORIGINAL_PWD}" "${ETEST_XML}"  2>/dev/null) || rel_xml="${ETEST_XML}"
        rel_json=$(realpath --relative-to="${ETEST_ORIGINAL_PWD}" "${ETEST_JSON}" 2>/dev/null) || rel_json="${ETEST_JSON}"
        rel_results=$(realpath --relative-to="${ETEST_ORIGINAL_PWD}" "${ETEST_RESULTS}" 2>/dev/null) || rel_results="${ETEST_RESULTS}"

        echo
        if [[ ${show_artifacts} -eq 1 ]]; then
            if [[ ${NUM_TESTS_FAILED} -gt 0 ]]; then
                echo "$(ecolor red)Test failures:$(ecolor off) $(ecolor red)${rel_failure_log}$(ecolor off)"
            fi
            echo "$(ecolor cyan)Test details: $(ecolor off) $(ecolor magenta)${rel_json}$(ecolor off)"
            echo "$(ecolor cyan)Test output:  $(ecolor off) $(ecolor magenta)${rel_log}$(ecolor off)"
            echo "$(ecolor cyan)Test results: $(ecolor off) $(ecolor magenta)${rel_results}$(ecolor off)"
            echo "$(ecolor cyan)JUnit XML:    $(ecolor off) $(ecolor magenta)${rel_xml}$(ecolor off)"
            echo
        fi
    } >&${ETEST_STDERR_FD}
}

create_xml()
{
    {
        printf '<?xml version="1.0" encoding="UTF-8" ?>\n'
        printf '<testsuites name="etest (%s)" tests="%d" failures="%d" skipped="%d" time="%s">\n' \
            "$(etimestamp_rfc3339)"      \
            "${NUM_TESTS_EXECUTED}"      \
            "${NUM_TESTS_FAILED}"        \
            "${NUM_TESTS_SKIPPED}"       \
            "${DURATION}"

        for suite in "${TEST_SUITES[@]}"; do

            # Inline array splitting to avoid opt_parse overhead in array_init (called 3x per suite)
            local testcases_passed testcases_failed testcases_skipped
            IFS=' ' read -ra testcases_passed <<< "${TESTS_PASSED[$suite]:-}"
            IFS=' ' read -ra testcases_failed <<< "${TESTS_FAILED[$suite]:-}"
            IFS=' ' read -ra testcases_skipped <<< "${TESTS_SKIPPED[$suite]:-}"

            printf '<testsuite name="%s" tests="%d" failures="%d" skipped="%d" time="%s">\n' \
                "${suite}"                                                                   \
                $(( ${#testcases_passed[@]} + ${#testcases_failed[@]} + ${#testcases_skipped[@]} )) \
                ${#testcases_failed[@]}                                                      \
                ${#testcases_skipped[@]}                                                     \
                "${SUITE_DURATION[$suite]:-0}"

            # Add all passing tests
            local name
            for name in ${testcases_passed[*]:-}; do
                echo "<testcase classname=\"${suite}\" name=\"${name}\" time=\"${TESTS_DURATION[$name]:-0}\"></testcase>"
            done

            # Add all failing tests with output
            for name in ${testcases_failed[*]:-}; do
                local test_output=""
                local error_line=""
                local error_line_escaped=""

                # Extract test output and escape CDATA for XML
                test_output=$(__extract_test_output "${suite}" "${name}" | sed 's/]]>/]]]]><![CDATA[>/g')

                # Extract the error line (line before stacktrace), strip timestamp
                error_line=$(echo "${test_output}" | awk '/:: [^ ]+:[0-9]+/{print prev; exit} {prev=$0}' | sed 's/^\[[^]]*\] //')

                # XML-escape for the attribute
                error_line_escaped="${error_line//&/\&amp;}"
                error_line_escaped="${error_line_escaped//</\&lt;}"
                error_line_escaped="${error_line_escaped//>/\&gt;}"
                error_line_escaped="${error_line_escaped//\"/\&quot;}"

                echo "<testcase classname=\"${suite}\" name=\"${name}\" time=\"${TESTS_DURATION[$name]:-0}\">"
                echo "<failure message=\"${suite}:${name} — ${error_line_escaped:-failed}\" type=\"ERROR\"><![CDATA["
                echo "${error_line:-No error details}"
                echo ""
                echo "${test_output}"
                echo "]]></failure>"
                echo "</testcase>"
            done

            # Add all skipped tests
            # For tests skipped via failfast (never ran), there's no output to extract.
            # Optimization: if suite has no passed/failed tests, it never ran (failfast skip).
            local suite_ran=0
            if [[ ${#testcases_passed[@]} -gt 0 || ${#testcases_failed[@]} -gt 0 ]]; then
                suite_ran=1
            fi

            for name in ${testcases_skipped[*]:-}; do
                local test_output=""
                # Only try to extract output if the suite actually ran (has passed or failed tests)
                if [[ ${suite_ran} -eq 1 ]]; then
                    test_output=$(__extract_test_output "${suite}" "${name}" | sed 's/]]>/]]]]><![CDATA[>/g')
                fi

                echo "<testcase classname=\"${suite}\" name=\"${name}\" time=\"0\">"
                echo "<skipped><![CDATA["
                echo "${test_output:-Skipped}"
                echo "]]></skipped>"
                echo "</testcase>"
            done

            echo "</testsuite>"
        done

        echo "</testsuites>"

    } > ${ETEST_XML}
}
