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
    filter=$(echo "${base_filter} ${filter}" | tr ' ' '|' | sed -e 's/^|//' -e 's/|$//')

    # Layer the exclude setting by first looking for any static exclusions in the config file, then any explicit exclusions
    # passed in on the command-line. Join any whitespace with a '|' to convert it to a bash style regex.
    base_exclude=$(conf_get _EBASH_CONF etest.exclude)
    : ${exclude:=${EXCLUDE:-}}
    exclude=$(echo "${base_exclude} ${exclude}" | tr ' ' '|' | sed -e 's/^|//' -e 's/|$//')

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
    local all_tests=(
        $(find "${tests[@]}" \( -type f -or -type l \) -executable -not -name "*.etest" | sort || true)
        $(find "${tests[@]}" -type f -name "*.etest" | sort || true)
    )

    # Get a list of tests we should actually run.
    local testfile
    for testfile in "${all_tests[@]}"; do

        # If the test name matches a specified EXCLUDE, then skip it
        if [[ -n ${exclude} && ${testfile} =~ ${exclude} ]] ; then
            continue
        fi

        # If this is an etest, see if any of the functions inside the file match the filter.
        local has_matching_functions=false
        if [[ ${testfile} =~ \.etest$ ]]; then

            local function
            for function in $(grep "^ETEST_.*()" "${testfile}" | sed 's|().*||' || true); do

                if [[ -n ${exclude} && ${function} =~ ${exclude} ]]; then
                    continue
                fi

                if [[ -z ${filter} || ${testfile} =~ ${filter} || ${function} =~ ${filter} ]]; then
                    TEST_FUNCTIONS_TO_RUN[$testfile]+="${function} "
                    has_matching_functions=true
                fi
            done
        fi

        # If the filename matches a non-empty filter or we found functions that match the filter then run it.
        if [[ -z ${filter} || ${testfile} =~ ${filter} || ${has_matching_functions} == "true" ]]; then
            TEST_FILES_TO_RUN+=( "${testfile}" )
        fi
    done
}
