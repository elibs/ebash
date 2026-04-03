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

    NUM_TESTS_EXECUTED=$(( NUM_TESTS_EXECUTED + 1 ))
    NUM_TESTS_QUEUED=$(( NUM_TESTS_QUEUED - 1 ))
    if [[ ${NUM_TESTS_QUEUED} -lt 0 ]]; then
        NUM_TESTS_QUEUED=0
    fi

    local suite
    if [[ -n "${source}" ]]; then
        suite="$(basename "${source}" ".etest")"
    else
        suite="$(basename "${testname}")"
    fi

    # We want to make sure that any traps from the tests execute _before_ we run teardown, and also we don't want
    # the teardown to run inside the test-specific cgroup. This subshell solves both issues.
    try
    {
        export EBASH EBASH_HOME TEST_DIR_OUTPUT=${testdir}
        local ETEST_SKIP_FILE=0
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
        # Skip if ETEST_SKIP_FILE was set by skip_file_if when the file was sourced.
        if is_function suite_setup && [[ ${testidx} -eq 0 ]] && [[ ${ETEST_SKIP_FILE:-0} -ne 1 ]]; then
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
        etestmsg "Running $(lval command testidx testidx_total timeout=ETEST_TIMEOUT jobs=ETEST_JOBS)"

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
    edebug "Finished $(lval testname display_testname rc)"

    # NOTE: Process and mount leak detection is deferred to global_teardown for efficiency.
    # Per-test leak checking added significant overhead and global_teardown catches all leaks anyway.
    # This isn't really an issue anymore like it was 10 years ago as we're running inside docker now.

    if ! array_contains TEST_SUITES "${suite}"; then
        TEST_SUITES+=( "${suite}" )
    fi

    if [[ ${rc} -eq 0 ]]; then
        einfo "$(ecolor green)${display_testname} PASSED."
        TESTS_PASSED[$suite]+="${testname} "
        NUM_TESTS_PASSED=$(( NUM_TESTS_PASSED + 1 ))
    elif [[ ${rc} -eq 77 ]]; then
        # Exit code 77 is the standard convention for skipped tests
        einfo "$(ecolor bold yellow)${display_testname} SKIPPED."
        TESTS_SKIPPED[$suite]+="${testname} "
        NUM_TESTS_SKIPPED=$(( NUM_TESTS_SKIPPED + 1 ))
        rc=0  # Don't treat skipped as failure for eend
    else
        eerror "${display_testname} FAILED."
        TESTS_FAILED[$suite]+="${testname} "
        NUM_TESTS_FAILED=$(( NUM_TESTS_FAILED + 1 ))
    fi

    eend --inline --inline-offset=${einfo_message_length} ${rc} &>>${ETEST_OUT}

    # Finally record the total duration of this test
    TESTS_DURATION[${testname}]=$(( ${SECONDS} - ${start_time} ))

    # NOTE: If failfast is enabled don't DIE here just log the error for informational purposes and return.
    # etest already knows how to detect and report errors.
    if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]] ; then
        eerror "${display_testname} failed and failfast=1" &>>${ETEST_OUT}
    fi

    # If jobs==0 update status json file inline. Otherwise this happens in the parallel execution loop.
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

    # Source the file first to check for skip_file_if
    local ETEST_SKIP_FILE=0
    source "${testfile}"

    # If the file set ETEST_SKIP_FILE=1, mark all tests as skipped
    if [[ ${ETEST_SKIP_FILE} -eq 1 ]]; then
        local suite
        suite="$(basename "${testfile}" ".etest")"
        ewarn "Skipping all tests in ${testfile}"

        for testfunc in "${functions[@]}"; do
            local display_testname="${testfile}:${testfunc}"
            einfo "$(ecolor bold yellow)${display_testname} SKIPPED." &>>${ETEST_OUT}
            TESTS_SKIPPED[$suite]+="${testfunc} "
            NUM_TESTS_SKIPPED=$(( NUM_TESTS_SKIPPED + 1 ))
            NUM_TESTS_EXECUTED=$(( NUM_TESTS_EXECUTED + 1 ))
        done

        if ! array_contains TEST_SUITES "${suite}"; then
            TEST_SUITES+=( "${suite}" )
        fi
        return 0
    fi

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

    local etest_name
    etest_name="$(ecolor bold cyan)ETEST$(ecolor bold magenta) ${EBASH_VERSION:-}$(ecolor reset)"
    if [[ -n "${name}" ]]; then
        etest_name+=" - \"${name//_/ }\""
    fi

    local banner_args=(OS debug exclude failfast filter jobs repeat=REPEAT_STRING timeout total_timeout verbose)
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
    NUM_TESTS_SKIPPED=0
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
# __worker_main is the main loop for a worker process in the worker pool.
# Each worker claims jobs from a shared counter and executes them until no jobs remain.
# Workers cache sourced files to avoid re-sourcing when consecutive jobs are from the same file.
__worker_main()
{
    local worker_id=$1
    local counter_file="${jobdir}/counter"
    local counter_lock="${jobdir}/counter.lock"
    local abort_file="${jobdir}/abort"
    local job_total=$2
    local last_sourced_file=""
    local last_sourced_skip=0

    local stop_file="${jobdir}/stop"

    while true; do
        # Check for stop signal (normal termination) or abort signal (failfast)
        [[ -f "${stop_file}" ]] && break
        [[ -f "${abort_file}" ]] && break

        # Atomically claim next job index using elock (cross-platform)
        local job_idx
        elock "${counter_lock}"
        read job_idx < "${counter_file}" 2>/dev/null || job_idx=0
        echo $(( job_idx + 1 )) > "${counter_file}"
        eunlock "${counter_lock}"

        # No more jobs available - wait for shutdown signal
        if [[ ${job_idx} -ge ${job_total} ]]; then
            sleep 0.1
            continue
        fi

        local job_spec="${etest_jobs_queued[$job_idx]}"
        local testfile="${job_spec%%:*}"
        local single_func="${job_spec#*:}"
        local jobpath="${jobdir}/${job_idx}"

        # Write our PID so crash detection knows which job we're running
        echo "${BASHPID}" > "${jobpath}/worker.pid"

        # Redirect output to job log
        exec &> "${jobpath}/output.log"

        # Setup output files
        ETEST_OUT="/dev/null"
        [[ ${jobs_progress} -eq 0 ]] && ETEST_OUT="${jobpath}/etest.out"
        TEST_OUT="/dev/null"

        # Reset counters for this job
        NUM_TESTS_EXECUTED=0
        NUM_TESTS_PASSED=0
        NUM_TESTS_FAILED=0
        NUM_TESTS_SKIPPED=0
        TESTS_DURATION=()

        local suite="" start_time=${SECONDS}

        # Source file if different from last (caching optimization)
        # ETEST_SKIP_FILE may be set by skip_file_if in the sourced file
        local ETEST_SKIP_FILE=0
        if [[ "${testfile}" != "${last_sourced_file}" && "${testfile}" =~ \.etest$ ]]; then
            # Clear previous file's setup/teardown/suite functions to avoid bleed
            unset -f setup teardown suite_setup suite_teardown 2>/dev/null
            ETEST_SKIP_FILE=0
            source "${testfile}"
            last_sourced_file="${testfile}"
            last_sourced_skip=${ETEST_SKIP_FILE}
        else
            # Use cached skip status for same file
            ETEST_SKIP_FILE=${last_sourced_skip}
        fi

        # Run the test
        if [[ "${testfile}" =~ \.etest$ ]]; then
            suite=$(basename "${testfile}" ".etest")
            if [[ -n "${single_func}" ]]; then
                # Function-level job
                local testfilename testdir
                testfilename=$(basename "${testfile}")
                testdir="${workdir}/${testfilename}/${single_func}"
                EMSG_PREFIX="" einfo "${testfile}:${single_func}" &>>${ETEST_OUT}

                # Check if file was skipped via skip_file_if
                if [[ ${ETEST_SKIP_FILE} -eq 1 ]]; then
                    local display_testname="${testfile}:${single_func}"
                    einfo "$(ecolor bold yellow)${display_testname} SKIPPED."
                    TESTS_SKIPPED[$suite]+="${single_func} "
                    NUM_TESTS_SKIPPED=$(( NUM_TESTS_SKIPPED + 1 ))
                    NUM_TESTS_EXECUTED=$(( NUM_TESTS_EXECUTED + 1 ))
                else
                    run_single_test --testdir "${testdir}" --source "${testfile}" "${single_func}"
                fi
            else
                # File-level job (serial file)
                run_etest_file "${testfile}" "${TEST_FUNCTIONS_TO_RUN[$testfile]:-}"
            fi
        else
            run_single_test --testdir "${workdir}/$(basename ${testfile})" "${testfile}"
            suite="$(basename "${testfile}")"
        fi

        # Build tests_duration as base64-encoded string
        local _td_str="declare -A tests_duration=("
        for _td_key in "${!TESTS_DURATION[@]}"; do
            _td_str+="[${_td_key}]=\"${TESTS_DURATION[$_td_key]}\" "
        done
        _td_str+=")"
        local tests_duration_enc
        tests_duration_enc=$(echo -n "${_td_str}" | base64 --wrap 0)

        # Save results
        local info=""
        pack_set info                                  \
            jobpath="${jobpath}"                       \
            job="${job_idx}"                           \
            rc="${NUM_TESTS_FAILED}"                   \
            duration=$(( SECONDS - start_time ))       \
            tests_duration="${tests_duration_enc}"     \
            suite="${suite}"                           \
            testfile="${testfile}"                     \
            num_tests_passed="${NUM_TESTS_PASSED}"     \
            num_tests_failed="${NUM_TESTS_FAILED}"     \
            num_tests_skipped="${NUM_TESTS_SKIPPED}"   \
            num_tests_executed="${NUM_TESTS_EXECUTED}" \
            tests_passed="${TESTS_PASSED[$suite]:-}"   \
            tests_failed="${TESTS_FAILED[$suite]:-}"   \
            tests_skipped="${TESTS_SKIPPED[$suite]:-}"

        pack_save info "${jobpath}/info.pack"

        # Signal completion by creating per-job done marker (cross-platform, no flock needed)
        touch "${jobpath}/done"
    done
}

__run_all_tests_parallel()
{
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
    local jobdir="${logdir}/jobs"
    efreshdir "${jobdir}"

    # Pre-create all job directories upfront
    local _i
    for (( _i=0; _i < etest_job_total; _i++ )); do
        mkdir "${jobdir}/${_i}"
    done

    # Initialize counter-based job queue (locking handled by elock)
    echo "0" > "${jobdir}/counter"

    # Create eprogress status file
    local etest_progress_file="${jobdir}/progress.txt"
    local etest_eprogress_pids=()
    NUM_TESTS_RUNNING=${jobs}
    NUM_TESTS_QUEUED=$(( etest_job_total - jobs ))
    [[ ${NUM_TESTS_QUEUED} -lt 0 ]] && NUM_TESTS_QUEUED=0

    __update_jobs_progress_file

    if [[ ${jobs_progress} -eq 1 ]]; then
        EMSG_PREFIX= eprogress              \
            --style einfo                   \
            --file "${etest_progress_file}" \
            "Total: $(ecolor bold)${NUM_TESTS_TOTAL}$(ecolor reset)" &>> ${ETEST_OUT}

        array_copy __EBASH_EPROGRESS_PIDS etest_eprogress_pids
        trap_add "__EBASH_EPROGRESS_PIDS=( ${etest_eprogress_pids[*]} ); eprogress_kill -r=1 ${etest_eprogress_pids[*]} &>> ${ETEST_OUT}"
        __EBASH_EPROGRESS_PIDS=()
    fi

    # Spawn worker pool - only ${jobs} workers, not one per job!
    local worker_pids=()
    local num_workers=${jobs}
    [[ ${num_workers} -gt ${etest_job_total} ]] && num_workers=${etest_job_total}

    for (( _i=0; _i < num_workers; _i++ )); do
        __worker_main "${_i}" "${etest_job_total}" &
        worker_pids+=($!)
    done

    # Add trap to kill workers on exit
    trap_add "for p in ${worker_pids[*]}; do ekill \$p 2>/dev/null; done"

    # Monitor progress by checking per-job done markers
    local done_count=0
    declare -A processed_jobs=()

    while true; do
        # Check if all workers have exited
        local workers_alive=0
        for pid in "${worker_pids[@]}"; do
            if kill -0 "${pid}" 2>/dev/null; then
                (( ++workers_alive )) || true
            fi
        done

        # Process newly completed jobs by checking for per-job done markers
        local job_idx jobs_this_batch=0
        for (( job_idx=0; job_idx < etest_job_total; job_idx++ )); do
            [[ -n "${processed_jobs[$job_idx]:-}" ]] && continue

            local path="${jobdir}/${job_idx}"
            # Check for done marker file (cross-platform, no flock needed)
            [[ -f "${path}/done" ]] || continue

            if [[ -f "${path}/info.pack" ]]; then
                local info=""
                pack_load info "${path}/info.pack"
                $(pack_import info)

                processed_jobs[$job_idx]=1

                eval "$(echo "${tests_duration}" | base64 --decode)"
                for key in "${!tests_duration[@]}"; do
                    TESTS_DURATION[$key]=${tests_duration[$key]}
                done

                SUITE_DURATION[${suite}]=$(( ${SUITE_DURATION[${suite}]:-0} + ${duration} ))
                NUM_TESTS_EXECUTED=$(( NUM_TESTS_EXECUTED + num_tests_executed ))
                NUM_TESTS_PASSED=$(( NUM_TESTS_PASSED + num_tests_passed ))
                NUM_TESTS_FAILED=$(( NUM_TESTS_FAILED + num_tests_failed ))
                NUM_TESTS_SKIPPED=$(( NUM_TESTS_SKIPPED + ${num_tests_skipped:-0} ))

                [[ -n "${tests_passed}" ]] && TESTS_PASSED[$suite]+="${tests_passed} "
                [[ -n "${tests_failed}" ]] && TESTS_FAILED[$suite]+="${tests_failed} "
                [[ -n "${tests_skipped:-}" ]] && TESTS_SKIPPED[$suite]+="${tests_skipped} "

                if ! array_contains TEST_SUITES "${suite}"; then
                    TEST_SUITES+=( "${suite}" )
                fi

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

                # Update progress every 10 jobs for smoother display
                (( ++jobs_this_batch ))
                if (( jobs_this_batch % 10 == 0 )); then
                    __update_jobs_progress_file
                fi

                # Check failfast - signal workers to stop via abort file
                if [[ ${failfast} -eq 1 && ${NUM_TESTS_FAILED} -gt 0 ]]; then
                    touch "${jobdir}/abort"
                    break 2
                fi
            fi
        done

        # Update progress display
        NUM_TESTS_RUNNING=${workers_alive}
        local claimed
        claimed=$(cat "${jobdir}/counter" 2>/dev/null || echo 0)
        NUM_TESTS_QUEUED=$(( etest_job_total - claimed ))
        [[ ${NUM_TESTS_QUEUED} -lt 0 ]] && NUM_TESTS_QUEUED=0
        __update_jobs_progress_file
        create_status_json

        # Check for crashed workers - ANY worker death before stop signal is a crash
        local wpid wrc
        for wpid in "${worker_pids[@]}"; do
            if ! kill -0 "${wpid}" 2>/dev/null; then
                # Worker is dead but we never told it to stop - this is a crash
                wait "${wpid}" 2>/dev/null && wrc=0 || wrc=$?

                # Find which job this worker was running
                local crashed_job="" crashed_jobpath="" j
                for (( j=0; j < etest_job_total; j++ )); do
                    local jpath="${jobdir}/${j}"
                    if [[ -f "${jpath}/worker.pid" ]] && [[ ! -f "${jpath}/done" ]]; then
                        local job_pid
                        job_pid=$(cat "${jpath}/worker.pid" 2>/dev/null || echo "")
                        if [[ "${job_pid}" == "${wpid}" ]]; then
                            crashed_job="${etest_jobs_queued[$j]}"
                            crashed_jobpath="${jpath}"
                            break
                        fi
                    fi
                done

                local jobs_remaining
                jobs_remaining=$(( etest_job_total - ${#processed_jobs[@]} ))
                eerror "FATAL: Worker ${wpid} died unexpectedly (exit code ${wrc})!"
                eerror "  Jobs total:     ${etest_job_total}"
                eerror "  Jobs processed: ${#processed_jobs[@]}"
                eerror "  Jobs remaining: ${jobs_remaining}"
                if [[ -n "${crashed_job}" ]]; then
                    eerror "  Crashed job:    ${crashed_job}"
                fi
                eerror ""

                # Display the crashed job's output
                if [[ -n "${crashed_jobpath}" && -f "${crashed_jobpath}/output.log" ]]; then
                    eerror "=== Output from crashed job ==="
                    cat "${crashed_jobpath}/output.log" >&2
                    eerror "=== End of crashed job output ==="
                fi

                # Kill remaining workers and eprogress before dying
                for wpid in "${worker_pids[@]}"; do
                    kill "${wpid}" 2>/dev/null || true
                done
                array_copy etest_eprogress_pids __EBASH_EPROGRESS_PIDS
                eprogress_kill --rc=1 &>> ${ETEST_OUT} || true

                die "Worker crashed - cannot continue"
            fi
        done

        # All jobs processed - signal workers to stop
        if [[ ${#processed_jobs[@]} -ge ${etest_job_total} ]]; then
            touch "${jobdir}/stop"
            break
        fi

        # Small sleep to avoid busy polling
        sleep 0.1
    done

    # Wait for any remaining workers and check exit codes
    local worker_failed=0
    for pid in "${worker_pids[@]}"; do
        if ! wait "${pid}" 2>/dev/null; then
            worker_failed=1
        fi
    done

    # Final progress update
    NUM_TESTS_RUNNING=0
    NUM_TESTS_QUEUED=0
    PERCENT=100
    __update_jobs_progress_file

    # Update pids and kill eprogress
    array_copy etest_eprogress_pids __EBASH_EPROGRESS_PIDS
    eprogress_kill --rc=${NUM_TESTS_FAILED} &>> ${ETEST_OUT}

    # Display prominent failfast abort message if we aborted early and populate TESTS_SKIPPED
    if [[ -f "${jobdir}/abort" ]]; then
        # Populate TESTS_SKIPPED with unprocessed jobs
        local job_idx job_spec testfile func suite
        for job_idx in "${!etest_jobs_queued[@]}"; do
            [[ -n "${processed_jobs[$job_idx]:-}" ]] && continue
            job_spec="${etest_jobs_queued[$job_idx]}"
            testfile="${job_spec%%:*}"
            func="${job_spec#*:}"
            suite="$(basename "${testfile}" .etest)"
            if [[ -n "${func}" ]]; then
                TESTS_SKIPPED[$suite]+="${func} "
                NUM_TESTS_SKIPPED=$(( NUM_TESTS_SKIPPED + 1 ))
            else
                # File-level job - count functions from TEST_FUNCTIONS_TO_RUN
                local funcs_list="${TEST_FUNCTIONS_TO_RUN[$testfile]:-}"
                if [[ -n "${funcs_list}" ]]; then
                    TESTS_SKIPPED[$suite]+="${funcs_list} "
                    local funcs_arr
                    array_init funcs_arr "${funcs_list}"
                    NUM_TESTS_SKIPPED=$(( NUM_TESTS_SKIPPED + ${#funcs_arr[@]} ))
                fi
            fi
            if ! array_contains TEST_SUITES "${suite}"; then
                TEST_SUITES+=( "${suite}" )
            fi
        done

        echo &>> ${ETEST_OUT}
        eerror "Aborted early due to failfast after ${NUM_TESTS_FAILED} failure(s)" &>> ${ETEST_OUT}
        ewarn "Skipped ${NUM_TESTS_SKIPPED} remaining test(s)" &>> ${ETEST_OUT}
    fi

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

    # Compute percent complete
    if [[ "${NUM_TESTS_TOTAL}" -eq 0 ]]; then
        PERCENT="0"
    else
        PERCENT=$((200*${NUM_TESTS_EXECUTED}/${NUM_TESTS_TOTAL} % 2 + 100*${NUM_TESTS_EXECUTED}/${NUM_TESTS_TOTAL}))
    fi

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

        if [[ "${NUM_TESTS_SKIPPED:-0}" -gt 0 ]]; then
            printf "  Skipped: $(ecolor bold yellow)%*s" ${width} ${NUM_TESTS_SKIPPED}
            ecolor reset
        fi

        echo -n " "

    } > "${tmpfile}" 2>/dev/null || true

    mv "${tmpfile}" "${etest_progress_file}" 2>/dev/null || true
}

# Display a summary table of results aggregated by suite (file).
# Uses already-aggregated global arrays instead of re-reading info.pack files.
__display_results_table()
{
    echo

    declare -a table
    array_init_nl table "Suite|Result|# Passed|# Failed|# Skipped"

    local suite_name
    for suite_name in "${TEST_SUITES[@]}"; do
        # Count tests from space-separated lists
        local passed=0 failed=0 skipped=0
        local test_list

        if [[ -n "${TESTS_PASSED[$suite_name]:-}" ]]; then
            array_init test_list "${TESTS_PASSED[$suite_name]}"
            passed=${#test_list[@]}
        fi
        if [[ -n "${TESTS_FAILED[$suite_name]:-}" ]]; then
            array_init test_list "${TESTS_FAILED[$suite_name]}"
            failed=${#test_list[@]}
        fi
        if [[ -n "${TESTS_SKIPPED[$suite_name]:-}" ]]; then
            array_init test_list "${TESTS_SKIPPED[$suite_name]}"
            skipped=${#test_list[@]}
        fi

        # Derive status
        local status
        if [[ ${failed} -ne 0 ]]; then
            status="$(ecolor bold red)FAILED$(ecolor none)"
        elif [[ ${skipped} -gt 0 && ${passed} -eq 0 ]]; then
            status="$(ecolor bold yellow)SKIPPED$(ecolor none)"
        else
            status="$(ecolor bold green)PASSED$(ecolor none)"
        fi

        # Color annotate counts
        local failed_display="${failed}"
        local skipped_display="${skipped}"
        if [[ ${failed} -gt 0 ]]; then
            failed_display="$(ecolor bold red)${failed}$(ecolor none)"
        fi
        if [[ ${skipped} -gt 0 ]]; then
            skipped_display="$(ecolor bold yellow)${skipped}$(ecolor none)"
        fi

        array_add_nl table "${suite_name}|${status}|${passed}|${failed_display}|${skipped_display}"
    done

    etable --style=boxart --title="$(ecolor bold)Test Results$(ecolor none)" "${table[@]}"
}
