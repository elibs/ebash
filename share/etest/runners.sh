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

    # Record start time of the test and at the end of the test we'll update the total runtime for the test. This will
    # be total runtime including any suite setup, test setup, test teardown and suite teardown.
    local start_time="${SECONDS}"

    local display_testname=${testname}
    if [[ -n ${source} ]] ; then
        display_testname="${source}:${testname}"
    fi

    local index_string="${testidx}/${testidx_total}"
    ebanner --uppercase "${testname}" OS debug exclude failfast failures filter jobs repeat=REPEAT_STRING INDEX=index_string timeout total_timeout verbose

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

    local suite
    if [[ -n "${source}" ]]; then
        suite="$(basename "${source}" ".etest")"
    else
        suite="$(basename "${testname}")"
    fi

    local tries=0
    for (( tries=0; tries <= ${failures}; tries++ )); do

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
                suite_setup
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
            etestmsg "Running $(lval command tries failures testidx testidx_total timeout=ETEST_TIMEOUT jobs=ETEST_JOBS)"

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
        edebug "Finished $(lval testname display_testname rc tries failures)"

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

    # If the test eventually passed (rc==0) but we had to try more than one time (tries > 0) then by definition
    # this is a flaky test.
    if [[ ${rc} -eq 0 && ${tries} -gt 0 ]]; then
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

    # Finally record the total runtime of this test
    TESTS_RUNTIME[${testname}]=$(( ${SECONDS} - ${start_time} ))

    # NOTE: If failfast is enabled don't DIE here just log the error for informational purposes and return.
    # etest already knows how to detect and report errors.
    if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
        eerror "${display_testname} failed and failfast=1" &>>${ETEST_OUT}
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
    if running_in_docker; then
        OS+=" (docker)"
    else
        OS+=" (native)"
    fi

    local etest_name="ETEST"
    if [[ -n "${name}" ]]; then
        etest_name+=" - \"${name//_/ }\""
    fi

    if [[ "${verbose}" -eq 1 ]]; then
        ebanner --uppercase "${etest_name}" OS debug exclude failfast failures filter jobs repeat=REPEAT_STRING timeout total_timeout verbose
    else
        ebanner --uppercase "${etest_name}" OS debug exclude failfast failures filter jobs repeat=REPEAT_STRING timeout total_timeout verbose &>>${ETEST_OUT}
    fi

    if [[ ${jobs} -gt 0 ]]; then
        elogfile_kill --all
        __run_all_tests_parallel
        cat "${logdir}"/jobs/*/output.log > "${ETEST_LOG}"
    else
        __run_all_tests_serially
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

        SUITE_RUNTIME[$(basename ${testfile} .etest)]=$(( ${SECONDS} - ${suite_start_time} ))
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
    local etest_jobs_passed=()
    local etest_jobs_failed=()
    local etest_jobs_flaky=()
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
        einfo "Running etest ($(lval jobs))" &>> ${ETEST_OUT}
        eprogress                           \
            --style einfos                  \
            --file "${etest_progress_file}" \
            "Total: $(ecolor bold)${etest_job_total}$(ecolor reset)" &>> ${ETEST_OUT}

        # NOTE: We must explicitly empty out __EBASH_EPROGRESS_PIDS otherwise subsequent tests we run may kill this
        # eprogress and we want it to continue running. So we'll manually handle that here.
        array_copy __EBASH_EPROGRESS_PIDS etest_eprogress_pids
        trap_add "__EBASH_EPROGRESS_PIDS=( ${etest_eprogress_pids[*]} ); eprogress_kill -r=1 ${etest_eprogress_pids[*]} &>> ${ETEST_OUT}"
        __EBASH_EPROGRESS_PIDS=()
    fi

    while true; do

        __update_jobs_progress_file

        __process_completed_jobs

        if [[ ${failfast} -eq 1 && ${#etest_jobs_failed[@]} -gt 0 ]] ; then
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

    array_copy etest_eprogress_pids __EBASH_EPROGRESS_PIDS
    eprogress_kill --rc=${#etest_jobs_failed[@]} &>> ${ETEST_OUT}

    if [[ ${jobs_progress} -eq 1 ]]; then
        __display_results_table &>> ${ETEST_OUT}
    fi
}

# __update_jobs_progress_file is a special internal helper function called by __run_all_tests_parallel to update the
# eprogress ticker file which we use to show the status of the parellel builds that are running asynchronously.
__update_jobs_progress_file()
{
    local tmpfile="${etest_progress_file}.tmp"

    {
        echo -n "   Queued: $(ecolor dim)$(( ${#etest_jobs_queued[@]} - ${etest_job_count} ))"
        ecolor reset

        echo -n "   Running: $(ecolor bold)${#etest_jobs_running[@]}"
        ecolor reset

        echo -n "   Passed: $(ecolor bold green)${#etest_jobs_passed[@]}"
        ecolor reset

        if [[ ${#etest_jobs_failed[@]} -gt 0 ]]; then
            echo -n "   Failed: $(ecolor bold red)${#etest_jobs_failed[@]}"
            ecolor reset
        fi

        if [[ ${#etest_jobs_flaky[@]} -gt 0 ]]; then
            echo -n "   Flaky: $(ecolor bold yellow)${#etest_jobs_flaky[@]}"
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

        # Record it as a passing or failing job
        if [[ ${rc} -eq 0 ]]; then
            etest_jobs_passed+=( ${pid} )
        else
            etest_jobs_failed+=( ${pid} )
        fi

        etest_jobs_finished+=( ${pid} )
        array_remove etest_jobs_running ${pid}

        # Update global stats
        TESTS_RUNTIME[${suite}]=${runtime}
        SUITE_RUNTIME[${suite}]=$(( ${SUITE_RUNTIME[${suite}]:-0} + ${runtime} ))
        increment NUM_TESTS_EXECUTED ${num_tests_executed}
        increment NUM_TESTS_PASSED   ${num_tests_passed}
        increment NUM_TESTS_FAILED   ${num_tests_failed}
        increment NUM_TESTS_FLAKY    ${num_tests_flaky}

        # Update list of tests
        array_add TESTS_PASSED "${tests_passed}"
        array_add TESTS_FAILED "${tests_failed}"
        array_add TESTS_FLAKY  "${tests_flaky}"

        if ! array_contains TEST_SUITES "${suite}"; then
            TEST_SUITES+=( "${suite}" )
        fi

        if edebug_enabled; then
            einfo "Job finished: $(lval pid path etest_jobs_finished etest_job_total etest_job_count)"
            pack_to_json info | jq --color-output --sort-keys .
        fi

        if [[ ${jobs_progress} -eq 0 ]]; then
            cat "${path}/etest.out"  >> "${ETEST_OUT}"
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

        # Capture suite name and start time.
        local suite=""
        local runtime="" start_time=${SECONDS}

        # Run the correct test runner depending on the type of file.
        if [[ "${testfile}" =~ \.etest$ ]]; then
            run_etest_file "${testfile}" "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}"
            suite=$(basename "${testfile}" ".etest")
        else
            run_single_test --testdir "${workdir}/$(basename ${testfile})" "${testfile}"
            suite="$(basename "${testfile}")"
        fi

        # Capture all state from this test run and save it into a pack.
        local info=""
        pack_set info                                  \
            jobpath="${jobpath}"                       \
            job=$(basename "${jobpath}")               \
            rc="${NUM_TESTS_FAILED}"                   \
            runtime=$(( ${SECONDS} - ${start_time} ))  \
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
    echo

    declare -a table
    array_init_nl table "Job|Suite|Result|# Passed|# Failed|# Flaky|Output"

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

        array_add_nl table "${job}|${suite}|${status}|${num_tests_passed}|${num_tests_failed}|${num_tests_flaky}|${entry}/output.log"

    done

    etable --title="$(ecolor bold green)Etest Results$(ecolor none)" "${table[@]}"
}
