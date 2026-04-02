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
    # Strip ANSI codes and get length (pure bash, no subprocesses)
    local einfo_message_stripped="${einfo_message//$'\e'\[*([0-9;])m/}"
    einfo_message_length=$(( ${#einfo_message_stripped} + 1 ))

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

            # Move test process into cgroup. Skip cgroup_create since global_setup already created ETEST_CGROUP.
            if cgroup_supported; then
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

            # Register trap to ensure we call teardown regardless of how we exit this subshell.
            trap_add __teardown

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

        # NOTE: Process and mount leak detection is deferred to global_teardown for efficiency.
        # Per-test leak checking added significant overhead and global_teardown catches all leaks anyway.
        # This isn't really an issue anymore like it was 10 years ago as we're running inside docker now.

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

    # Finally record the total duration of this test
    TESTS_DURATION[${testname}]=$(( ${SECONDS} - ${start_time} ))

    # NOTE: If failfast is enabled don't DIE here just log the error for informational purposes and return.
    # etest already knows how to detect and report errors.
    if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
        eerror "${display_testname} failed and failfast=1" &>>${ETEST_OUT}
    fi

    # If jobs==0 update status json file inline. Otherwise this happens in chunks as jobs are finished
    # for parallel execution in __process_completed_jobs.
    # Only update every 10 tests or on the last test to reduce I/O overhead.
    if [[ ${jobs} -eq 0 ]]; then
        if (( (NUM_TESTS_PASSED + NUM_TESTS_FAILED) % 10 == 0 )) || [[ ${testidx} -eq ${testidx_total} ]]; then
            create_status_json
        fi
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

# A wrapper function that calls teardown if it is defined by user.
__teardown()
{
    if is_function teardown; then
        etestmsg "Running teardown"
        teardown
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

    local etest_name="ETEST ${EBASH_VERSION:-}"
    if [[ -n "${name}" ]]; then
        etest_name+=" - \"${name//_/ }\""
    fi

    local banner_args=(OS debug exclude failfast filter jobs repeat=REPEAT_STRING retries timeout total_timeout verbose)
    [[ -n "${directory}" ]] && banner_args+=(directory)

    if [[ "${verbose}" -eq 1 ]]; then
        ebanner --uppercase "${etest_name}" "${banner_args[@]}"
    else
        ebanner --uppercase "${etest_name}" "${banner_args[@]}" &>>${ETEST_OUT}
    fi

    # Reset all counters at the start of each run (important for repeat mode)
    NUM_TESTS_QUEUED=${NUM_TESTS_TOTAL}
    NUM_TESTS_EXECUTED=0
    NUM_TESTS_PASSED=0
    NUM_TESTS_FAILED=0
    NUM_TESTS_FLAKY=0
    PERCENT=0

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
# it will also wait on any previously backgrounded jobs and collect results about that job as they finish. When all job
# slots are full, it uses `wait -n` to efficiently block until any child process exits.
__run_all_tests_parallel()
{
    local etest_jobs_running=()
    local etest_jobs_finished=()

    # Build job queue: for serial files, one job per file; for parallel files, one job per function
    # Job format: "filepath:funcname" for function-level, "filepath:" for file-level
    local etest_jobs_queued=()
    local testfile func funcs
    for testfile in "${TEST_FILES_TO_RUN[@]}"; do
        if [[ -n "${SERIAL_FILES[$testfile]:-}" ]]; then
            # Serial file: single job runs all functions
            etest_jobs_queued+=( "${testfile}:" )
        elif [[ -n "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}" ]]; then
            # Parallel file: one job per function
            array_init funcs "${TEST_FUNCTIONS_TO_RUN[$testfile]}"
            for func in "${funcs[@]}"; do
                etest_jobs_queued+=( "${testfile}:${func}" )
            done
        else
            # Standalone script (not .etest)
            etest_jobs_queued+=( "${testfile}:" )
        fi
    done

    local etest_job_total=${#etest_jobs_queued[@]}
    local etest_job_count=0
    declare -A pidmap=()
    efreshdir "${logdir}/jobs"

    # Pre-create all job directories upfront (batch mkdir is faster than one per spawn)
    local _i
    for (( _i=0; _i < etest_job_total; _i++ )); do
        mkdir "${logdir}/jobs/${_i}"
    done

    local etest_eprogress_pids=()

    # Cache nproc for progress updates (constant value, avoid repeated calls)
    local etest_nproc
    etest_nproc=$(nproc 2>/dev/null) || etest_nproc=1

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

    # Phase 1: Fill all job slots as fast as possible
    # Main shell spawns so Running counter updates immediately
    while [[ ${#etest_jobs_running[@]} -lt ${jobs} && ${etest_job_count} -lt ${etest_job_total} ]]; do
        __spawn_new_job
        __update_jobs_progress_file
    done

    # Phase 2: Monitor completions and spawn replacements
    while [[ ${#etest_jobs_finished[@]} -lt ${etest_job_total} ]]; do

        if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
            eerror "Failure encountered and failfast=1" &>> ${ETEST_OUT}
            break
        fi

        # Wait for any job to finish
        wait -n 2>/dev/null || true

        # Fast completion check using kill -0 instead of process_running
        for pid in "${etest_jobs_running[@]}"; do
            if ! kill -0 "${pid}" 2>/dev/null; then
                # Process is gone - check if it's a zombie or fully reaped
                local state=""
                state=$(sed 's/.*) //' "/proc/${pid}/stat" 2>/dev/null | cut -c1) || state="X"
                if [[ "${state}" == "Z" ]] || [[ "${state}" == "X" ]]; then
                    path=${pidmap[$pid]}
                    wait "${pid}" || true

                    if [[ -f "${path}/info.pack" ]]; then
                        local info=""
                        pack_load info "${path}/info.pack"
                        $(pack_import info)

                        etest_jobs_finished+=( ${pid} )
                        array_remove etest_jobs_running ${pid}
                        NUM_TESTS_RUNNING=${#etest_jobs_running[@]}

                        eval "$(echo "${tests_duration}" | base64 --decode)"
                        for key in "${!tests_duration[@]}"; do
                            TESTS_DURATION[$key]=${tests_duration[$key]}
                        done

                        SUITE_DURATION[${suite}]=$(( ${SUITE_DURATION[${suite}]:-0} + ${duration} ))
                        increment NUM_TESTS_EXECUTED ${num_tests_executed}
                        increment NUM_TESTS_PASSED   ${num_tests_passed}
                        increment NUM_TESTS_FAILED   ${num_tests_failed}
                        increment NUM_TESTS_FLAKY    ${num_tests_flaky}

                        [[ -n "${tests_passed}" ]] && TESTS_PASSED[$suite]+="${tests_passed} "
                        [[ -n "${tests_failed}" ]] && TESTS_FAILED[$suite]+="${tests_failed} "
                        [[ -n "${tests_flaky}" ]]  && TESTS_FLAKY[$suite]+="${tests_flaky} "

                        if ! array_contains TEST_SUITES "${suite}"; then
                            TEST_SUITES+=( "${suite}" )
                        fi

                        # Use sed directly on file instead of cat|sed (1 subprocess instead of 2)
                        sed '/• PROGRESS.*/d' "${path}/output.log" >> "${ETEST_LOG}"
                        if [[ ${jobs_progress} -eq 0 ]]; then
                            local _fd_path
                            _fd_path="$(fd_path)/${ETEST_STDERR_FD}"
                            if [[ ${verbose} -eq 0 ]]; then
                                cat "${path}/etest.out" >> "${_fd_path}"
                            else
                                sed '/• PROGRESS.*/d' "${path}/output.log" >> "${_fd_path}"
                            fi
                        fi
                    fi

                    # Immediately spawn replacement
                    if [[ ${#etest_jobs_running[@]} -lt ${jobs} && ${etest_job_count} -lt ${etest_job_total} ]]; then
                        __spawn_new_job
                    fi

                    __update_jobs_progress_file
                    NUM_TESTS_QUEUED=$(( NUM_TESTS_TOTAL - NUM_TESTS_EXECUTED - NUM_TESTS_RUNNING ))
                    [[ ${NUM_TESTS_QUEUED} -lt 0 ]] && NUM_TESTS_QUEUED=0
                    create_status_json
                fi
            fi
        done
    done

    # One final update of progress file so we see everything complete as expected.
    # eprogress will read and display this final state before exiting.
    NUM_TESTS_RUNNING=0
    NUM_TESTS_QUEUED=0
    PERCENT=100
    __update_jobs_progress_file

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

        # Show CPU usage as percentage (load / cores * 100)
        # Uses etest_nproc cached at parallel run start to avoid subprocess per update
        # Use read builtin (single line) + bash string manipulation instead of cut subprocess
        local load cpu_pct _loadavg=""
        read _loadavg < /proc/loadavg 2>/dev/null || _loadavg="0"
        load="${_loadavg%% *}"  # First space-separated field
        [[ -z "${load}" ]] && load="0"
        cpu_pct=$(( (${load%.*} * 100) / etest_nproc ))
        printf "  CPU: $(ecolor cyan)%3d%%" "${cpu_pct}"
        ecolor reset


        echo -n " "

    } > "${tmpfile}" 2>/dev/null || true

    mv "${tmpfile}" "${etest_progress_file}" 2>/dev/null || true
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

        # Check if process is still actively running (not exited or zombie)
        # ps -p returns true for zombies, so also check /proc state
        # Format: "pid (comm) state ..." - must parse after closing paren since comm can have spaces
        if process_running "${pid}"; then
            local state=""
            state=$(sed 's/.*) //' "/proc/${pid}/stat" 2>/dev/null | cut -c1) || true
            if [[ "${state}" != "Z" ]]; then
                continue
            fi
        fi

        path=${pidmap[$pid]}

        # Capture PID and wait for the process to exit. Then capture all info from on-disk pack
        wait "${pid}" || true
        assert_exists "${path}/info.pack"
        local info=""
        pack_load info "${path}/info.pack"
        $(pack_import info)

        etest_jobs_finished+=( ${pid} )
        array_remove etest_jobs_running ${pid}
        NUM_TESTS_RUNNING=${#etest_jobs_running[@]}

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
#
# Job format: "filepath:funcname" for function-level jobs, "filepath:" for file-level jobs
__spawn_new_job()
{
    local job_spec=${etest_jobs_queued[${etest_job_count}]}
    local testfile="${job_spec%%:*}"
    local single_func="${job_spec#*:}"
    edebug "Starting next job: ${job_spec}"

    local jobpath="${logdir}/jobs/${etest_job_count}"

    # Run the test which could be a single test file or an entire suite (etest) file.
    (
        # Redirect all output to log file. This is much lighter than elogfile which spawns background tee processes.
        # We don't need live console output during parallel execution - output is aggregated at the end.
        exec &> "${jobpath}/output.log"

        # ETEST_OUT is only needed when jobs_progress=0 (non-ticker mode) to show per-test status.
        # In ticker mode, skip creating this file to reduce I/O.
        ETEST_OUT="/dev/null"
        [[ ${jobs_progress} -eq 0 ]] && ETEST_OUT="${jobpath}/etest.out"
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

        # Run the correct test runner depending on the type of job.
        if [[ "${testfile}" =~ \.etest$ ]]; then
            suite=$(basename "${testfile}" ".etest")
            if [[ -n "${single_func}" ]]; then
                # Function-level job: run single test function (no suite_setup/teardown)
                local testfilename testdir
                testfilename=$(basename "${testfile}")
                testdir="${workdir}/${testfilename}/${single_func}"
                EMSG_PREFIX="" einfo "${testfile}:${single_func}" &>>${ETEST_OUT}
                run_single_test --testdir "${testdir}" --source "${testfile}" "${single_func}"
            else
                # File-level job: run all functions with suite_setup/teardown
                run_etest_file "${testfile}" "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}"
            fi
        else
            run_single_test --testdir "${workdir}/$(basename ${testfile})" "${testfile}"
            suite="$(basename "${testfile}")"
        fi

        # Build tests_duration manually as base64-encoded "declare -A" string.
        # This avoids the "declare -p | sed | base64" pipeline (3 processes → 1).
        local _td_str="declare -A tests_duration=("
        for _td_key in "${!TESTS_DURATION[@]}"; do
            _td_str+="[${_td_key}]=\"${TESTS_DURATION[$_td_key]}\" "
        done
        _td_str+=")"
        tests_duration=$(echo -n "${_td_str}" | base64 --wrap 0)

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
    pidmap[$pid]="${jobpath}"
    trap_add "ekill $pid 2>/dev/null"

    etest_jobs_running+=( ${pid} )
    NUM_TESTS_RUNNING=${#etest_jobs_running[@]}
    NUM_TESTS_QUEUED=$(( NUM_TESTS_TOTAL - NUM_TESTS_EXECUTED - NUM_TESTS_RUNNING ))
    if [[ ${NUM_TESTS_QUEUED} -lt 0 ]]; then
        NUM_TESTS_QUEUED=0
    fi
    increment etest_job_count
}

# Display a summary table of results aggregated by suite (file).
# Uses already-aggregated global arrays instead of re-reading info.pack files.
__display_results_table()
{
    echo

    declare -a table
    array_init_nl table "Suite|Result|# Passed|# Failed|# Flaky"

    local suite_name
    for suite_name in "${TEST_SUITES[@]}"; do
        # Count tests from space-separated lists
        local passed=0 failed=0 flaky=0
        local test_list

        if [[ -n "${TESTS_PASSED[$suite_name]:-}" ]]; then
            array_init test_list "${TESTS_PASSED[$suite_name]}"
            passed=${#test_list[@]}
        fi
        if [[ -n "${TESTS_FAILED[$suite_name]:-}" ]]; then
            array_init test_list "${TESTS_FAILED[$suite_name]}"
            failed=${#test_list[@]}
        fi
        if [[ -n "${TESTS_FLAKY[$suite_name]:-}" ]]; then
            array_init test_list "${TESTS_FLAKY[$suite_name]}"
            flaky=${#test_list[@]}
        fi

        # Derive status
        local status
        if [[ ${failed} -ne 0 ]]; then
            status="$(ecolor bold red)FAILED$(ecolor none)"
        elif [[ ${flaky} -ne 0 ]]; then
            status="$(ecolor bold yellow)FLAKY$(ecolor none)"
        else
            status="$(ecolor bold green)PASSED$(ecolor none)"
        fi

        # Color annotate counts
        local failed_display="${failed}"
        local flaky_display="${flaky}"
        if [[ ${failed} -gt 0 ]]; then
            failed_display="$(ecolor bold red)${failed}$(ecolor none)"
        fi
        if [[ ${flaky} -gt 0 ]]; then
            flaky_display="$(ecolor bold yellow)${flaky}$(ecolor none)"
        fi

        array_add_nl table "${suite_name}|${status}|${passed}|${failed_display}|${flaky_display}"
    done

    etable --style=boxart --title="$(ecolor bold)Test Results$(ecolor none)" "${table[@]}"
}
