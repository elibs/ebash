#!/usr/bin/env bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# TEST LISTS
#
#-----------------------------------------------------------------------------------------------------------------------

create_test_list()
{
    # Layer the filter setting by first looking for any static filter settings in the config file, then any explicit filter
    # options passed in on the command-line. Join any whitespace with a '|' to convert it to a bash style regex.
    base_filter=$(conf_get _EBASH_CONF etest.filter)
    : ${filter:=${FILTER:-}}
    filter="${base_filter} ${filter}"
    filter="${filter// /|}"
    filter="${filter#|}"
    filter="${filter%|}"

    # Layer the exclude setting by first looking for any static exclusions in the config file, then any explicit exclusions
    # passed in on the command-line. Join any whitespace with a '|' to convert it to a bash style regex.
    base_exclude=$(conf_get _EBASH_CONF etest.exclude)
    : ${exclude:=${EXCLUDE:-}}
    exclude="${base_exclude} ${exclude}"
    exclude="${exclude// /|}"
    exclude="${exclude#|}"
    exclude="${exclude%|}"

    # Layer the list of tests by first looking for any static tests in the config file, then any explicit tests
    # passed in on the command-line. Append all of these into a single array.
    tests+=( $(conf_get _EBASH_CONF etest.tests) )
    if array_not_empty test_list ; then
        # Read non-comment lines from test_list and treat them as if they were passed as arguments to this script
        edebug "Grabbing test list from $(lval test_list)"
        array_init_nl tests_from_list "$(grep -vP '^\s*(#.*)$' "${test_list[@]}")"
        if array_not_empty tests_from_list ; then
            edebug "Found $(lval test_list tests_from_list)"
            tests+=( "${tests_from_list[@]}" )
        else
            edebug "Found no tests in $(lval test_list)"
        fi
    fi
}

find_matching_tests()
{
    # Expand tests to find all standalone executable scripts as well as any *.etest files.
    # Use sort -u to deduplicate in case the same file is found via multiple paths (e.g., directory + explicit file)
    local all_scripts all_etests
    readarray -t all_scripts < <(find -L "${tests[@]}" \( -type f -or -type l \) -executable -not -name "*.etest" 2>/dev/null | sort -u || true)
    readarray -t all_etests < <(find -L "${tests[@]}" -type f -name "*.etest" 2>/dev/null | sort -u || true)

    # Build function list for all .etest files in a single grep pass (much faster than per-file grep)
    # Output format: "filepath:ETEST_funcname()" - we parse this to build TEST_FUNCTIONS_TO_RUN
    # When --disabled is set, also include DISABLED_ETEST_ functions
    if [[ ${#all_etests[@]} -gt 0 ]]; then
        local grep_line testfile function grep_pattern
        if [[ ${disabled:-0} -eq 1 ]]; then
            grep_pattern="^(DISABLED_)?ETEST_[a-zA-Z0-9_]+\(\)"
        else
            grep_pattern="^ETEST_[a-zA-Z0-9_]+\(\)"
        fi

        # Track functions per file to detect duplicates within the same file
        # (Same function name in different files is OK - they're scoped by suite)
        local -A seen_in_file=()
        local -a duplicate_errors=()

        while IFS= read -r grep_line; do
            # Extract testfile (everything before :ETEST_ or :DISABLED_ETEST_)
            testfile="${grep_line%%:*ETEST_*}"
            function="${grep_line#*:}"
            function="${function%%\(\)*}"

            if [[ -n ${exclude} && ( ${function} =~ ${exclude} || ${testfile} =~ ${exclude} ) ]]; then
                continue
            fi

            if [[ -z ${filter} || ${testfile} =~ ${filter} || ${function} =~ ${filter} ]]; then
                # Check for duplicate function names within the same file
                local key="${testfile}:${function}"
                if [[ -n "${seen_in_file[$key]:-}" ]]; then
                    duplicate_errors+=( "  ${function} defined multiple times in ${testfile}" )
                else
                    seen_in_file[$key]=1
                fi
                TEST_FUNCTIONS_TO_RUN[$testfile]+="${function} "
            fi
        done < <(grep -E -H "${grep_pattern}" "${all_etests[@]}" 2>/dev/null || true)

        # Fail if any duplicate test functions were found
        if [[ ${#duplicate_errors[@]} -gt 0 ]]; then
            eerror "Duplicate test function names detected:"
            printf '%s\n' "${duplicate_errors[@]}" >&2
            die "Test function names must be unique within each test file"
        fi

        # Detect files that require serial execution (all tests in file run as single job):
        # - Has suite_setup() or suite_teardown() (shared lifecycle)
        # - Has ETEST_SERIALIZE=1 (explicit opt-out of parallelism)
        # Files without these markers can parallelize at the function level.
        while IFS= read -r testfile; do
            SERIAL_FILES[$testfile]=1
        done < <(grep -l -E "^suite_setup\(\)|^suite_teardown\(\)|^ETEST_SERIALIZE=1" "${all_etests[@]}" 2>/dev/null || true)
    fi

    # Process standalone scripts (each script counts as 1 test)
    local testfile num_standalone_scripts=0
    for testfile in "${all_scripts[@]}"; do
        if [[ -n ${exclude} && ${testfile} =~ ${exclude} ]] ; then
            continue
        fi
        if [[ -z ${filter} || ${testfile} =~ ${filter} ]]; then
            TEST_FILES_TO_RUN+=( "${testfile}" )
            (( ++num_standalone_scripts ))
        fi
    done

    # Process .etest files - add to TEST_FILES_TO_RUN if they have matching functions or match filter
    for testfile in "${all_etests[@]}"; do
        if [[ -n ${exclude} && ${testfile} =~ ${exclude} ]] ; then
            continue
        fi
        local has_matching_functions=false
        if [[ -n "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}" ]]; then
            has_matching_functions=true
        fi
        if [[ -z ${filter} || ${testfile} =~ ${filter} || ${has_matching_functions} == "true" ]]; then
            TEST_FILES_TO_RUN+=( "${testfile}" )
        fi
    done

    # Compute total number of tests to run across all files
    local fname fname_tests
    NUM_TESTS_TOTAL=${num_standalone_scripts}
    for fname in "${!TEST_FUNCTIONS_TO_RUN[@]}"; do
        array_init fname_tests "${TEST_FUNCTIONS_TO_RUN[$fname]}"
        NUM_TESTS_TOTAL=$(( NUM_TESTS_TOTAL + ${#fname_tests[@]} ))
    done
}

print_tests()
{
    ebanner --uppercase "ETEST TESTS" OS exclude failfast filter repeat

    local suite
    for suite in "${TEST_FILES_TO_RUN[@]}"; do
        einfo "${suite}"
        local tests
        array_init tests "${TEST_FUNCTIONS_TO_RUN[$suite]:-}"
        printf '%s\n' "${tests[@]}"
    done
}

print_tests_json_array()
{
    $(opt_parse \
        "input   | Name of the associative array to convert to json array." \
        "?indent | Amount of space to indent."                              \
    )

    echo "["

    local first=1 suite tests
    for suite in $(array_indexes_sort ${input}); do

        [[ ${first} -eq 1 ]] && first=0 || echo ","

        eval "entry=\${${input}[$suite]:-}"
        array_init tests "${entry}" " "
        echo "${indent}${indent}{"
        echo "${indent}${indent}${indent}\"suite\": \"$(basename ${suite%.*})\","
        echo "${indent}${indent}${indent}\"tests\": $(array_to_json tests)"
        echo -n "${indent}${indent}}"
    done

    echo ""
    echo "${indent}]"
}

print_tests_json()
{
    echo "{"
    echo "    \"exclude\": \"${exclude}\","
    echo "    \"filter\": \"${filter}\","
    echo -n "    \"suites\": "
    print_tests_json_array TEST_FUNCTIONS_TO_RUN "    "
    echo "}"
}
