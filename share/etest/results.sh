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

create_summary()
{
    create_vcs_info

    {
        echo
        message="Finished testing $(pack_get VCS_INFO info)."
        message+=" $(( ${NUM_TESTS_PASSED} ))/${NUM_TESTS_EXECUTED} tests passed"
        message+=" in ${RUNTIME} seconds."

        if [[ ${NUM_TESTS_FAILED} -gt 0 ]]; then
            eerror "${message}"
        else
            einfo "${message}"
        fi
        echo

        if array_not_empty TESTS_FAILED; then
            eerror "FAILED TESTS:"
            for failed_test in $(echo "${TESTS_FAILED[@]}" | tr ' ' '\n') ; do
                echo "$(ecolor "red")      ${failed_test}"
            done
            ecolor off
        fi

        if array_not_empty TESTS_FLAKY; then
            ewarn "FLAKY TESTS:"
            for flaky_test in $(echo "${TESTS_FLAKY[@]}" | tr ' ' '\n') ; do
                echo "$(ecolor "yellow")      ${flaky_test}"
            done
            ecolor off
        fi

        # Create a summary file with relevant statistics
        if command_exists jq; then

			jq . <<-EOF > ${ETEST_JSON}
			{
				"numTestsExecuted": "${NUM_TESTS_EXECUTED}",
				"numTestsPassed": "${NUM_TESTS_PASSED}",
				"numTestsFailed": "${NUM_TESTS_FAILED}",
				"numTestsFlaky": "${NUM_TESTS_FLAKY}",
				"testsPassed": $(associative_array_to_json_split TESTS_PASSED),
				"testsFailed": $(associative_array_to_json_split TESTS_FAILED),
				"testsFlaky": $(associative_array_to_json_split TESTS_FLAKY),
				"runtime": "${RUNTIME} seconds",
				"datetime": "$(etimestamp_rfc3339)",
				"options": {
					"clean": "${clean}",
					"debug": "${debug}",
					"delete": "${delete}",
					"exclude": "${exclude}",
					"failfast": "${failfast}",
					"failures": "${failures}",
					"filter": "${filter}",
					"html": "${html}",
					"logdir": "${logdir}",
					"mountns": "${mountns}",
					"repeat": "${repeat}",
					"test_list": $(array_to_json test_list),
					"tests": $(array_to_json tests),
					"verbose": "${verbose}",
                    "workdir": "${workdir}"
				},
				"vcs": $(pack_to_json VCS_INFO)
			}
			EOF

            # Additionally display summary output to the terminal if requested
            if [[ "${summary}" -eq 1 ]]; then
                einfo "Summary"
                jq --color-output . ${ETEST_JSON}
            fi
        fi

    } |& tee -a ${ETEST_LOG} >&${ETEST_STDERR_FD}
}

create_xml()
{
    {
        printf '<?xml version="1.0" encoding="UTF-8" ?>\n'
        printf '<testsuites name="etest (%s)" tests="%d" failures="%d" time="%s">\n' \
            "$(etimestamp_rfc3339)" \
            "${NUM_TESTS_EXECUTED}" \
            "${NUM_TESTS_FAILED}"   \
            "${RUNTIME}"

        for suite in "${TEST_SUITES[@]}"; do

            local testcases_passed testcases_failed
            array_init testcases_passed "${TESTS_PASSED[$suite]:-}"
            array_init testcases_failed "${TESTS_FAILED[$suite]:-}"
            edebug "$(lval suite testcases_passed testcases_failed)"

            printf '<testsuite name="%s" tests="%d" failures="%d" time="%s">\n' \
                "${suite}"                                                      \
                $(( ${#testcases_passed[@]} + ${#testcases_failed[@]} ))        \
                ${#testcases_failed[@]}                                         \
                ${SUITE_RUNTIME[$suite]}

            local xml_lines=()
            local name

            # Add all passing tests
            for name in ${testcases_passed[*]:-}; do
                xml_lines+=( "$(printf '<testcase classname="%s" name="%s" time="%s"></testcase>\n' "${suite}" "${name}" "${TESTS_RUNTIME[$name]}")" )
            done

            # Add all failing tests
            for name in ${testcases_failed[*]:-}; do
                local failure_msg
                failure_msg="$(printf '<failure message="%s:%s failed" type="ERROR"></failure>' "${suite}" "${name}")"
                xml_lines+=( "$(printf '<testcase classname="%s" name="%s" time="%s">%s</testcase>\n' "${suite}" "${name}" "${TESTS_RUNTIME[$name]}" "${failure_msg}")" )
            done

            array_sort xml_lines
            edebug "$(lval xml_lines)"
            printf "%s\n" "${xml_lines[@]:-}"
            echo "</testsuite>"
        done

        echo "</testsuites>"

    } > ${ETEST_XML}
}
