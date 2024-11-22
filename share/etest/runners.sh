#!/usr/bin/env bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# TEST RUNNERS
#
#-----------------------------------------------------------------------------------------------------------------------

run_single_test()
{
    $(opt_parse \
        ":testidx       | Test index of current test. Mose useful if the test is a function inside a test suite." \
        ":testidx_total | Total number of tests. Most useful if the test is a function inside a test suite." \
        ":testdir       | Temporary directory that the test should use as its current working directory." \
        ":source        | Name of the file to be sourced in the shell that will run the test. Most useful if the test is
                          a function inside that file." \
        "testname       | Command to execute to run the test")

    local rc=0

    # Record start time of the test and at the end of the test we'll update the total duration for the test. This will
    # be total duration including any suite setup, test setup, test teardown and suite teardown.
    local start_time="${SECONDS}"

    local display_testname=${testname}
    if [[ -n ${source} ]] ; then
        display_testname="${source}:${testname}"
    fi

    local progress="${NUM_TESTS_EXECUTED}/${NUM_TESTS_TOTAL} (${PERCENT}%%)"
    ebanner --uppercase "${testname}" \
        OS                   \
        debug                \
        exclude              \
        failfast             \
        filter               \
        jobs                 \
        progress             \
        repeat=REPEAT_STRING \
        retries              \
        timeout              \
        total_timeout        \
        verbose

    # If this file is being sourced then it's an ETEST so log it as a subtest via einfos. Otherwise log via einfo as a
    # top-level test script.
    local einfo_message einfo_message_length
    if [[ -n "${source}" ]]; then
        einfo_message=$(einfos -n "${testname#ETEST_}" 2>&1)
    else
        einfo_message=$(EMSG_PREFIX="" einfo -n "${testname}" 2>&1)
    fi

    echo -n "${einfo_message}" &>>${ETEST_OUT}
    einfo_message_length=$(echo -n "${einfo_message}" | noansi | wc -c)

    increment NUM_TESTS_EXECUTED
    decrement NUM_TESTS_QUEUED
    if [[ ${NUM_TESTS_QUEUED} -lt 0 ]]; then
        NUM_TESTS_QUEUED=0
    fi

    local suite
    if [[ -n "${source}" ]]; then
        suite="$(basename "${source}" ".etest")"
    else
        suite="$(basename "${testname}")"
    fi

    local attempt=0
    for (( attempt=0; attempt <= ${retries}; attempt++ )); do

        rc=0

        # We want to make sure that any traps from the tests execute _before_ we run teardown, and also we don't want
        # the teardown to run inside the test-specific cgroup. This subshell solves both issues.
        try
        {
            export EBASH EBASH_HOME TEST_DIR_OUTPUT=${testdir}
            if [[ -n ${source} ]] ; then
                source "${source}"

                # If the test name we were provided doesn't exist after sourcing this script then there is some
                # conditional in the test that is designed to prevent us from running it so we should simply return.
                if ! is_function ${testname}; then
                    edebug "Skipping $(lval source testname)"
                    return 0
                fi
            fi

            # Pretend that the test _not_ executing inside a try/catch so that the error stack will get printed if part
            # of the test fails, as if etest weren't running it inside a try/catch
            __EBASH_INSIDE_TRY=0

            # Create our temporary workspace in the directory specified by the caller
            efreshdir "${testdir}"
            mkdir "${testdir}/tmp"
            TMPDIR="$(readlink -m ${testdir}/tmp)"
            export TMPDIR

            if cgroup_supported; then
                cgroup_create ${ETEST_CGROUP}
                cgroup_move ${ETEST_CGROUP} ${BASHPID}
            fi

            # Determine the command that etest needs to run.
            # Also set ETEST_COMMAND in case caller wants to know what command is being run inside Setup or suite_setup, etc.
            local command="${testname}"
            if ! is_function "${testname}" ; then
                command="${PWD}/${testname}"
            fi
            ETEST_COMMAND="${command}"

            cd "${testdir}"

            # Run suite setup function if provided and we're on the first test.
            if is_function suite_setup && [[ ${testidx} -eq 0 ]]; then
                etestmsg "Running suite_setup $(lval testidx testidx_total)"
                (
                    if cgroup_supported; then
                        cgroup_move "${ETEST_CGROUP_BASE}" ${BASHPID}
                    fi
                    suite_setup
                )
            fi

            # Register __suite_teardown function as a trap callback and trigger it when the test receives an interrupt.
            # If running the last test case, instead of triggering it by interrupt, always trigger it at the end of the test.
            if [[ ${testidx} -eq ${testidx_total} ]]; then
                trap_add __suite_teardown EXIT
            else
                trap_add __suite_teardown "${DIE_SIGNALS[@]}"
            fi

            # Run optional test setup function if provided
            if is_function setup ; then
                etestmsg "Running setup"
                setup
            fi

            : ${ETEST_TIMEOUT:=${timeout}}
            : ${ETEST_JOBS:=${jobs}}
            etestmsg "Running $(lval command attempt retries testidx testidx_total timeout=ETEST_TIMEOUT jobs=ETEST_JOBS)"

            if [[ -n "${ETEST_TIMEOUT}" && "${ETEST_TIMEOUT}" != "infinity" ]]; then
                etimeout --timeout="${ETEST_TIMEOUT}" "${command}"
            else
                "${command}"
            fi

            # Run optional test teardown function if provided
            if is_function teardown ; then
                etestmsg "Running teardown"
                teardown
            fi
        }
        catch
        {
            rc=$?
            # If failfast flag is enabled and is not running the last test case, call __suite_teardown in the catch block.
            # Otherwise, nothing to do here as __suite_teardown will be triggered at the end of the test.
            if [[ ${failfast} -eq 1 && ${testidx} -ne ${testidx_total} ]]; then
                if [[ -n ${source} ]] ; then
                    source "${source}"
                fi
                __suite_teardown
            fi
        }
        edebug "Finished $(lval testname display_testname rc attempt retries)"

        # Verify there are no process or memory leaks. If so kill them and try again if that is permitted.
        #
        # NOTE: We skip checking for process and mount leaks if we're running multiple jobs at the same time as they
        # all share the same cgroup and working directory so we would have false positives. It doesn't really matter
        # because we will do a final check for process and mount leaks in `global_teardown`. And this isn't really an
        # issue anymore like it was 10 years ago as we're running inside docker now.
        if [[ ${jobs} -eq 0 ]]; then
            try
            {
                assert_no_process_leaks
                assert_no_mount_leaks
            }
            catch
            {
                rc+=$?
                eerror "${display_testname} FAILED due to process or mount leak."
            }
        fi

        if [[ ${rc} -eq 0 ]]; then
            break
        fi
    done

    if ! array_contains TEST_SUITES "${suite}"; then
        TEST_SUITES+=( "${suite}" )
    fi

    # If the test eventually passed (rc==0) but we had to try more than one time (attempt > 0) then by definition
    # this is a flaky test.
    if [[ ${rc} -eq 0 && ${attempt} -gt 0 ]]; then
        TESTS_FLAKY[$suite]+="${testname} "
        (( NUM_TESTS_FLAKY += 1 ))
    fi

    if [[ ${rc} -eq 0 ]]; then
        einfo "$(ecolor green)${display_testname} PASSED."
        TESTS_PASSED[$suite]+="${testname} "
        (( NUM_TESTS_PASSED += 1 ))
    else
        eerror "${display_testname} FAILED."
        TESTS_FAILED[$suite]+="${testname} "
        (( NUM_TESTS_FAILED += 1 ))
    fi

    eend --inline --inline-offset=${einfo_message_length} ${rc} &>>${ETEST_OUT}

    # Unit test provided teardown
    if declare -f teardown &>/dev/null ; then
        etestmsg "Calling test_teardown"
        $(tryrc -r=teardown_rc teardown)
    fi

    # Finally record the total duration of this test
    TESTS_DURATION[${testname}]=$(( ${SECONDS} - ${start_time} ))

    # NOTE: If failfast is enabled don't DIE here just log the error for informational purposes and return.
    # etest already knows how to detect and report errors.
    if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
        eerror "${display_testname} failed and failfast=1" &>>${ETEST_OUT}
    fi

    # If jobs==0 update status json file inline. Otherwise this happens in chunks as jobs are finished
    # for parallel execution in __process_completed_jobs
    if [[ ${jobs} -eq 0 ]]; then
        create_status_json
    fi
}

# A wrapper function that calls suite_teardown if it is defined by user.
__suite_teardown()
{
    if is_function suite_teardown; then
        etestmsg "Running suite_teardown $(lval testidx testidx_total)"
        suite_teardown
    fi
}

run_etest_file()
{
    $(opt_parse \
        "testfile       | Name of the etest file to test." \
        "?functions_raw | Whitespace separated list of tests to run inside the testfile.")

    local testfilename
    testfilename=$(basename ${testfile})

    local functions
    array_init functions "${functions_raw}"

    if array_empty functions; then
        ewarn "No tests found in $(lval testfile)"
        return 0
    fi

    EMSG_PREFIX="" einfo "${testfile}" &>>${ETEST_OUT}

    # Run all tests for this suite
    local idx
    for idx in $(array_indexes functions); do

        local testfunc=${functions[$idx]}
        local testdir="${workdir}/${testfilename}/${testfunc}"

        run_single_test                                 \
            --testidx ${idx}                            \
            --testidx-total $(( ${#functions[@]} - 1 )) \
            --testdir "${testdir}"                      \
            --source "${testfile}"                      \
            "${testfunc}"

        # NOTE: If failfast is enabled don't DIE here just return. etest already knows how to detect and report errors.
        # No need to log the error here as it was logged inside run_single_test.
        if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
            return 0
        fi

    done
}

# run_all_tests runs all test files discovered in `find_matching_tests`. This function has some intelligence to detect
# if we should run the tests serially or in parallel based on the value of --jobs. If that value is greater than 1, then
# all tests will be run in parallel via __run_all_tests_parallel. Otherwise the tests will be run serially via
# __run_all_tests_serially.
run_all_tests()
{
    OS="$(os_pretty_name)"
    if running_in_container; then
        OS+=" (container)"
    else
        OS+=" (native)"
    fi

    local etest_name="ETEST"
    if [[ -n "${name}" ]]; then
        etest_name+=" - \"${name//_/ }\""
    fi

    if [[ "${verbose}" -eq 1 ]]; then
        ebanner --uppercase "${etest_name}" OS debug exclude failfast filter jobs repeat=REPEAT_STRING retries timeout total_timeout verbose
    else
        ebanner --uppercase "${etest_name}" OS debug exclude failfast filter jobs repeat=REPEAT_STRING retries timeout total_timeout verbose &>>${ETEST_OUT}
    fi

    NUM_TESTS_QUEUED=${NUM_TESTS_TOTAL}

    if [[ ${jobs} -gt 0 ]]; then
        elogfile_kill --all
        __run_all_tests_parallel
    else
        NUM_TESTS_RUNNING=1
        __run_all_tests_serially
        NUM_TESTS_RUNNING=0
    fi
}

# __run_all_tests_serially is a special internal helper function which is called by its parent function run_all_tests to
# run all tests one at a time in serial fashion.
__run_all_tests_serially()
{
    for testfile in "${TEST_FILES_TO_RUN[@]}"; do

        # Record start time of entire test suite
        local suite_start_time="${SECONDS}"

        # Run the test which could be a single test file or an entire suite (etest) file.
        if [[ "${testfile}" =~ \.etest$ ]]; then
            run_etest_file "${testfile}" "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}"
        else
            run_single_test --testdir "${workdir}/$(basename ${testfile})" "${testfile}"
        fi

        if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
             die "Failure encountered and failfast=1" &>${ETEST_OUT}
        fi

        SUITE_DURATION[$(basename ${testfile} .etest)]=$(( ${SECONDS} - ${suite_start_time} ))
    done
}

# __run_all_tests_parallel is a special internal helper function which is called by its parent function run_all_tests to
# run all tests in parallel. It uses the --jobs option to control how many test suites can be run in parallel at the
# same time. All test suites are essentially queued up into a runnable list. In has a `while true` loop where on each
# iteration it will launch a new backgrounded job up until it reaches our limit specified via --jobs. During that loop
# it will also wait on any previously backgrounded jobs and collect results about that job as they finish. It will also
# delay up to jobs_delay on each iteration to avoid hammering the system too much busy waiting for long running results.
__run_all_tests_parallel()
{
    local etest_jobs_running=()
    local etest_jobs_finished=()
    local etest_jobs_queued=( ${TEST_FILES_TO_RUN[@]} )
    local etest_job_total=${#TEST_FILES_TO_RUN[@]}
    local etest_job_count=0
    declare -A pidmap=()
    efreshdir "${logdir}/jobs"
    local etest_eprogress_pids=()

    # Create eprogress status file
    local etest_progress_file="${logdir}/jobs/progress.txt"
    __update_jobs_progress_file
    if [[ ${jobs_progress} -eq 1 ]]; then
        EMSG_PREFIX= eprogress              \
            --style einfo                   \
            --file "${etest_progress_file}" \
            "Total: $(ecolor bold)${NUM_TESTS_TOTAL}$(ecolor reset)" &>> ${ETEST_OUT}

        # NOTE: We must explicitly empty out __EBASH_EPROGRESS_PIDS otherwise subsequent tests we run may kill this
        # eprogress and we want it to continue running. So we'll manually handle that here.
        array_copy __EBASH_EPROGRESS_PIDS etest_eprogress_pids
        trap_add "__EBASH_EPROGRESS_PIDS=( ${etest_eprogress_pids[*]} ); eprogress_kill -r=1 ${etest_eprogress_pids[*]} &>> ${ETEST_OUT}"
        __EBASH_EPROGRESS_PIDS=()
    fi

    while true; do

        __update_jobs_progress_file

        __process_completed_jobs

        if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
            eerror "Failure encountered and failfast=1" &>> ${ETEST_OUT}
            break
        fi

        if [[ ${#etest_jobs_running[@]} -eq 0 && ${#etest_jobs_finished[@]} -ge ${etest_job_total} ]]; then
            edebug "All etest jobs finished"
            break
        elif [[ ${#etest_jobs_running[@]} -lt ${jobs} && ${etest_job_count} -lt ${etest_job_total} ]]; then
            __spawn_new_job
        else
            edebug "Throttling by $(lval jobs_delay)"
            sleep "${jobs_delay}"
        fi

    done

    # One final update of progress file so we see everything complete as expected.
    NUM_TESTS_RUNNING=0
    __update_jobs_progress_file
    sleep ${EPROGRESS_DELAY:-1}

    # Update pids
    array_copy etest_eprogress_pids __EBASH_EPROGRESS_PIDS
    eprogress_kill --rc=${NUM_TESTS_FAILED} &>> ${ETEST_OUT}

    # Display results table
    if [[ ${jobs_progress} -eq 1 ]]; then
        __display_results_table &>> ${ETEST_OUT}
    fi
}

# __update_jobs_progress_file is a special internal helper function called by __run_all_tests_parallel to update the
# eprogress ticker file which we use to show the status of the parellel builds that are running asynchronously.
__update_jobs_progress_file()
{
    local tmpfile="${etest_progress_file}.tmp"
    local width="${#NUM_TESTS_TOTAL}"

    {
        printf "  Queued: $(ecolor dim)%*s" ${width} ${NUM_TESTS_QUEUED}
        ecolor reset

        printf "  Running: $(ecolor bold)%*s" ${width} ${NUM_TESTS_RUNNING}
        ecolor reset

        printf "  Percent: $(ecolor bold)%*s%%" 3 ${PERCENT}
        ecolor reset

        printf "  Passed: $(ecolor bold green)%*s" ${width} ${NUM_TESTS_PASSED}
        ecolor reset

        if [[ "${NUM_TESTS_FAILED}" -gt 0 ]]; then
            printf "  Failed: $(ecolor bold red)%*s" ${width} ${NUM_TESTS_FAILED}
            ecolor reset
        fi

        if [[ "${NUM_TESTS_FLAKY}" -gt 0 ]]; then
            printf "  Flaky: $(ecolor bold yellow)%*s" ${width} ${NUM_TESTS_FLAKY}
            ecolor reset
        fi

        echo -n " "

    } > "${tmpfile}"

    mv "${tmpfile}" "${etest_progress_file}"
}

# __process_completed_jobs is a special internal helper function called by __run_all_tests_parallel to process any jobs
# which may have run to completion. Essentially this captures the return code of the process and collects some stats
# about the job that are stored in global variables and then updates our internal job related lists accordingly.
#
# NOTE: The concurrent reading and writing of the global variables is safe as each job runs in an isolated subshell. The
# stats are specific to a single suite which is the granularity if our parallelism.
__process_completed_jobs()
{
    for pid in ${etest_jobs_running[*]:-}; do

        if process_running "${pid}"; then
            continue
        fi

        path=${pidmap[$pid]}

        # Capture PID and wait for the process to exit. Then capture all info from on-disk pack
        wait "${pid}" || true
        assert_exists "${path}/info.pack"
        local info=""
        pack_load info "${path}/info.pack"
        $(pack_import info)

        NUM_TESTS_RUNNING=${#etest_jobs_running[@]}
        etest_jobs_finished+=( ${pid} )
        array_remove etest_jobs_running ${pid}

        # Unpack base64 encoded "tests_duration" associative array and from this specific test instance and copy those
        # values into the gloval TESTS_DURATION associative array.
        eval "$(echo "${tests_duration}" | base64 --decode)"
        local key
        for key in "${!tests_duration[@]}"; do
            TESTS_DURATION[$key]=${tests_duration[$key]}
        done

        # Update global stats
        SUITE_DURATION[${suite}]=$(( ${SUITE_DURATION[${suite}]:-0} + ${duration} ))
        increment NUM_TESTS_EXECUTED ${num_tests_executed}
        increment NUM_TESTS_PASSED   ${num_tests_passed}
        increment NUM_TESTS_FAILED   ${num_tests_failed}
        increment NUM_TESTS_FLAKY    ${num_tests_flaky}
        NUM_TESTS_QUEUED=$(( NUM_TESTS_TOTAL - NUM_TESTS_EXECUTED - NUM_TESTS_RUNNING ))
        if [[ ${NUM_TESTS_QUEUED} -lt 0 ]]; then
            NUM_TESTS_QUEUED=0
        fi

        # Update list of tests
        if [[ -n "${tests_passed}" ]]; then
            TESTS_PASSED[$suite]+="${tests_passed} "
        fi

        if [[ -n "${tests_failed}" ]]; then
            TESTS_FAILED[$suite]+="${tests_failed} "
        fi

        if [[ -n "${tests_flaky}" ]]; then
            TESTS_FLAKY[$suite]+="${tests_flaky} "
        fi

        # Update our final status json file with new results
        create_status_json

        if ! array_contains TEST_SUITES "${suite}"; then
            TEST_SUITES+=( "${suite}" )
        fi

        if edebug_enabled; then
            einfo "Job finished: $(lval pid path etest_jobs_finished etest_job_total etest_job_count)"
            pack_to_json info | jq --color-output --sort-keys .
        fi

        # Append the output of this completed job to our LOG file
        #
        # NOTE: Strip out PROGRESS as it's confusing and incorrect since jobs finish out of order.
        cat "${path}/output.log" | sed '/• PROGRESS.*/d' >> "${ETEST_LOG}"

        # If jobs_progress mode is disabled then display etest status in non-verbose mode or display the actual test
        # output in verbose mode.
        #
        # NOTE: Strip out PROGRESS as it's confusing and incorrect since jobs finish out of order.
        if [[ ${jobs_progress} -eq 0 && ${verbose} -eq 0 ]]; then
            cat "${path}/etest.out" >> "$(fd_path)/${ETEST_STDERR_FD}"
        elif [[ ${jobs_progress} -eq 0 && ${verbose} -eq 1 ]]; then
            cat "${path}/output.log" | sed '/• PROGRESS.*/d' >> "$(fd_path)/${ETEST_STDERR_FD}"
        fi
    done
}

# __spawn_new_job is a special internal helper function to take a job from the queued list and run that job
# asynchronously in the background. We store off the pid and add it to an internal associative array `pidmap` which is
# used to be able to lookup the status of our backgrounded jobs later in `__process_completed_jobs`.
__spawn_new_job()
{
    local testfile=${etest_jobs_queued[${etest_job_count}]}
    edebug "Starting next job: ${testfile}"

    local jobpath="${logdir}/jobs/${etest_job_count}"
    mkdir -p "${jobpath}"

    # Run the test which could be a single test file or an entire suite (etest) file.
    (
        # Setup logfile for this background job and also set ETEST_OUT to a per-job file to collect etest output so we
        # can display it when the test completes (if ticker is turned off). The test output itself always goes to
        # /dev/null because elogfile is collecting the output for us and we'll aggregate it when etest is finished.
        elogfile "${jobpath}/output.log"
        trap_add "elogfile_kill --all"
        ETEST_OUT="${jobpath}/etest.out"
        TEST_OUT="/dev/null"

        # Initialize counters to 0. Otherwise they inherit the external incrementing value. We want to only get the
        # delta from this test run on its own.
        NUM_TESTS_EXECUTED=0
        NUM_TESTS_PASSED=0
        NUM_TESTS_FAILED=0
        NUM_TESTS_FLAKY=0
        TESTS_DURATION=()

        # Capture suite name and start time.
        local suite=""
        local duration="" start_time=${SECONDS}

        # Run the correct test runner depending on the type of file.
        if [[ "${testfile}" =~ \.etest$ ]]; then
            run_etest_file "${testfile}" "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}"
            suite=$(basename "${testfile}" ".etest")
        else
            run_single_test --testdir "${workdir}/$(basename ${testfile})" "${testfile}"
            suite="$(basename "${testfile}")"
        fi

        # We need to manually encode TESTS_DURATION as it's an associative array so we can't directly store this into a
        # pack. So we print out the key/value pairs using "declare -p" and then base64 encode this. We can then store
        # that directly into the pack and then unpack it in the result processing step.
        tests_duration="$(declare -p TESTS_DURATION | sed 's|declare -A TESTS_DURATION|declare -A tests_duration|' | base64 --wrap 0)"

        # Capture all state from this test run and save it into a pack.
        local info=""
        pack_set info                                  \
            jobpath="${jobpath}"                       \
            job=$(basename "${jobpath}")               \
            rc="${NUM_TESTS_FAILED}"                   \
            duration=$(( ${SECONDS} - ${start_time} )) \
            tests_duration="${tests_duration}"         \
            suite="${suite}"                           \
            testfile="${testfile}"                     \
            num_tests_passed="${NUM_TESTS_PASSED}"     \
            num_tests_failed="${NUM_TESTS_FAILED}"     \
            num_tests_flaky="${NUM_TESTS_FLAKY}"       \
            num_tests_executed="${NUM_TESTS_EXECUTED}" \
            tests_passed="${TESTS_PASSED[$suite]:-}"   \
            tests_failed="${TESTS_FAILED[$suite]:-}"   \
            tests_flaky="${TESTS_FLAKY[$suite]:-}"     \

        pack_save info "${jobpath}/info.pack"

    ) &

    pid=$!
    echo "${pid}" > "${jobpath}/pid"
    pidmap[$pid]="${jobpath}"
    trap_add "ekill $pid 2>/dev/null"

    etest_jobs_running+=( ${pid} )
    increment etest_job_count
}

# Display a summary table of failing tests since there is no output on the screen to help them.
__display_results_table()
{
    echo

    declare -a table
    array_init_nl table "Suite|Result|# Passed|# Failed|# Flaky"

    local entry
    for entry in ${logdir}/jobs/*; do

        if [[ ! -e "${entry}/info.pack" ]]; then
            job="$(basename "${entry}")"
            status="$(ecolor dim red)ABORTED$(ecolor none)"
            array_add_nl table "${job}|-|${status}|-|-|-|${entry}/output.log"
            continue
        fi

        local info=""
        pack_load info "${entry}/info.pack"
        $(pack_import info)

        # Derive status to display with color annotations
        local status
        if [[ ${num_tests_failed} -ne 0 ]]; then
            status="$(ecolor bold red)FAILED$(ecolor none)"
        elif [[ ${num_tests_flaky} -ne 0 ]]; then
            status="$(ecolor bold yellow)FLAKY$(ecolor none)"
        else
            status="$(ecolor bold green)PASSED$(ecolor none)"
        fi

        # Annotate numver of failed and flaky tests with color
        if [[ ${num_tests_failed} -gt 0 ]]; then
            num_tests_failed="$(ecolor bold red)${num_tests_failed}$(ecolor none)"
        fi

        if [[ ${num_tests_flaky} -gt 0 ]]; then
            num_tests_flaky="$(ecolor bold yellow)${num_tests_flaky}$(ecolor none)"
        fi

        array_add_nl table "${suite}|${status}|${num_tests_passed}|${num_tests_failed}|${num_tests_flaky}"

    done

    etable --title="$(ecolor bold)Test Results$(ecolor none)" "${table[@]}"
}
