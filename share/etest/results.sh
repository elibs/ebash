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
        pids=( $(cgroup_pids -r ${ETEST_CGROUP_BASE}) )
    else
        pids=( $(process_tree) )
    fi

	cat <<-EOF > ${ETEST_JSON}.tmp
	{
	    "cgroup": "${ETEST_CGROUP_BASE}",
	    "datetime": "$(etimestamp_rfc3339)",
	    "duration": "${DURATION}s",
	    "numTestsQueued": ${NUM_TESTS_QUEUED},
	    "numTestsRunning": ${NUM_TESTS_RUNNING},
	    "numTestsExecuted": ${NUM_TESTS_EXECUTED},
	    "numTestsFailed": ${NUM_TESTS_FAILED},
	    "numTestsFlaky": ${NUM_TESTS_FLAKY},
	    "numTestsPassed": ${NUM_TESTS_PASSED},
	    "numTestsTotal": ${NUM_TESTS_TOTAL},
	    "percent": ${PERCENT},
	    "pids": $(array_to_json pids),
	    "testsFailed": $(print_tests_json_array TESTS_FAILED "    "),
	    "testsFlaky": $(print_tests_json_array TESTS_FLAKY "    "),
	    "testsPassed": $(print_tests_json_array TESTS_PASSED "    ")
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
	    "retries": "${retries}",
	    "silent": "${silent}",
	    "test_list": $(array_to_json test_list),
	    "tests": $(array_to_json tests),
	    "verbose": "${verbose}",
	    "workdir": "${workdir}"
	}
	EOF

    mv "${ETEST_OPTIONS}.tmp" "${ETEST_OPTIONS}"
}

create_failure_output()
{
    # Always create the file (even if empty) so it exists for consumers
    : > "${ETEST_FAILURE_LOG}"

    if array_empty TESTS_FAILED; then
        return 0
    fi

    if [[ ! -f "${ETEST_LOG}" ]]; then
        return 0
    fi

    # Write plain text (no ANSI codes) to the failure log file
    {
        local cols text="Failure Output" inner padding
        cols=120
        inner=$(( cols - 2 ))
        padding=$(( inner - 2 - ${#text} ))

        # Create repeated character strings using pure bash
        local __border __spaces
        printf -v __border '%*s' "${inner}" ''
        __border="${__border// /═}"
        printf -v __spaces '%*s' "${padding}" ''

        echo
        printf '╔%s╗\n' "${__border}"
        printf '║  %s%s║\n' "${text}" "${__spaces}"
        printf '╚%s╝\n' "${__border}"

        local suite test_name
        for suite in "${!TESTS_FAILED[@]}"; do
            for test_name in ${TESTS_FAILED[$suite]}; do
                echo
                echo "● ${suite}:${test_name#ETEST_}"
                echo

                # Extract output for this test from the log file (last occurrence only)
                # Match from "Running command" line to FAILED line (pattern accounts for ANSI codes)
                # Strip ANSI codes for clean file output
                tac "${ETEST_LOG}" \
                    | sed -n "/${test_name}.*FAILED/,/Running command=\"${test_name}\"/p" \
                    | tac \
                    | sed 's/\x1b\[[0-9;]*m//g' \
                    | sed 's/^/   /'
            done
        done
    } > "${ETEST_FAILURE_LOG}"

    # Optionally display to stderr with colors
    if [[ "${failure_output}" -eq 1 ]]; then
        local line
        while IFS= read -r line; do
            # Color the box border and header lines
            if [[ "${line}" == "╔"* ]] || [[ "${line}" == "╚"* ]] || [[ "${line}" == "║"* ]]; then
                echo "$(ecolor bold red)${line}$(ecolor off)"
            elif [[ "${line}" == "● "* ]]; then
                echo "$(ecolor red)${line}$(ecolor off)"
            else
                echo "${line}"
            fi
        done < "${ETEST_FAILURE_LOG}" >&${ETEST_STDERR_FD}
    fi
}

create_summary()
{
    create_vcs_info
    pack_to_json VCS_INFO > "${ETEST_VCS}"

    create_status_json

    {
        echo
        message="Finished testing $(pack_get VCS_INFO info)."
        message+=" $(( ${NUM_TESTS_PASSED} ))/${NUM_TESTS_EXECUTED} tests passed"
        message+=" in ${DURATION} seconds."

        if [[ ${NUM_TESTS_FAILED} -gt 0 ]]; then
            eerror "${message}"
        else
            einfo "${message}"
        fi
        echo

        if array_not_empty TESTS_FAILED; then
            eerror "FAILED TESTS:"
            local failed_test
            for failed_test in "${TESTS_FAILED[@]}"; do
                echo "$(ecolor "red")      ${failed_test}"
            done
            ecolor off
        fi

        if array_not_empty TESTS_FLAKY; then
            ewarn "FLAKY TESTS:"
            local flaky_test
            for flaky_test in "${TESTS_FLAKY[@]}"; do
                echo "$(ecolor "yellow")      ${flaky_test}"
            done
            ecolor off
        fi

        # Display summary output to the terminal if requested
        if [[ "${summary}" -eq 1 ]] && command_exists jq; then
            einfo "Summary"
            jq --color-output . ${ETEST_JSON}
        fi

    } |& tee -a ${ETEST_LOG} >&${ETEST_STDERR_FD}

    # Create failure output file and optionally display to stderr (after log is complete)
    create_failure_output
}

create_xml()
{
    {
        printf '<?xml version="1.0" encoding="UTF-8" ?>\n'
        printf '<testsuites name="etest (%s)" tests="%d" failures="%d" time="%s">\n' \
            "$(etimestamp_rfc3339)" \
            "${NUM_TESTS_EXECUTED}" \
            "${NUM_TESTS_FAILED}"   \
            "${DURATION}"

        for suite in "${TEST_SUITES[@]}"; do

            local testcases_passed testcases_failed
            array_init testcases_passed "${TESTS_PASSED[$suite]:-}"
            array_init testcases_failed "${TESTS_FAILED[$suite]:-}"
            edebug "$(lval suite testcases_passed testcases_failed)"

            printf '<testsuite name="%s" tests="%d" failures="%d" time="%s">\n' \
                "${suite}"                                                      \
                $(( ${#testcases_passed[@]} + ${#testcases_failed[@]} ))        \
                ${#testcases_failed[@]}                                         \
                "${SUITE_DURATION[$suite]:-0}"

            local name

            # Add all passing tests (sorted)
            local passing_lines=()
            for name in ${testcases_passed[*]:-}; do
                passing_lines+=( "<testcase classname=\"${suite}\" name=\"${name}\" time=\"${TESTS_DURATION[$name]:-0}\"></testcase>" )
            done
            array_sort passing_lines
            if array_not_empty passing_lines; then
                printf '%s\n' "${passing_lines[@]}"
            fi

            # Add all failing tests with output (sorted by name)
            local failing_names=( ${testcases_failed[*]:-} )
            array_sort failing_names
            for name in "${failing_names[@]}"; do
                local test_output=""
                local error_line=""
                local error_line_escaped=""
                if [[ -f "${ETEST_LOG}" ]]; then
                    # Extract test output (last occurrence only), strip ANSI codes, and escape CDATA end sequence
                    test_output=$(tac "${ETEST_LOG}" \
                        | sed -n "/${name}.*FAILED/,/Running command=\"${name}\"/p" \
                        | tac \
                        | sed 's/\x1b\[[0-9;]*m//g' \
                        | sed 's/]]>/]]]]><![CDATA[>/g')

                    # Extract the error line (line before stacktrace), strip timestamp
                    error_line=$(echo "${test_output}" | awk '/:: [^ ]+:[0-9]+/{print prev; exit} {prev=$0}' | sed 's/^\[[^]]*\] //')

                    # XML-escape for the attribute
                    error_line_escaped="${error_line//&/\&amp;}"
                    error_line_escaped="${error_line_escaped//</\&lt;}"
                    error_line_escaped="${error_line_escaped//>/\&gt;}"
                    error_line_escaped="${error_line_escaped//\"/\&quot;}"
                fi
                echo "<testcase classname=\"${suite}\" name=\"${name}\" time=\"${TESTS_DURATION[$name]:-0}\">"
                echo "<failure message=\"${suite}:${name} — ${error_line_escaped:-failed}\" type=\"ERROR\"><![CDATA["
                echo "${error_line:-No error details}"
                echo ""
                echo "${test_output}"
                echo "]]></failure>"
                echo "</testcase>"
            done
            echo "</testsuite>"
        done

        echo "</testsuites>"

    } > ${ETEST_XML}
}
