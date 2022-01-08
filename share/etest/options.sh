#!/usr/bin/env bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# OPTIONS
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage main <<'END'
etest is an extensible test framework primarily focused at providing a rich test framework for bash complete with test
suites and a rich set of test assertions and other various test related frameworks. It also supports running any
standalone executable binaries or scripts written in any language. In this mode it is essentially a simple test driver.

Tests can be grouped into test suites by placing them into a *.etest file. Each test is then a function inside that file
with the naming scheme `ETEST_${suite}_${testcase}` (e.g. `ETEST_array_init` for the `array` suite and the testcase
`init`). Each test suite *.etest file can contain optional `sutie_setup` and `suite_teardown` functions which are
performed only once at the start and end of a suite, respectively. It can also optionally contain `setup` and
`teardown` functions which are run before and after every single individual test.

etest provides several additional security and auditing features of interest:

    1) Every test is run in its own subshell to ensure process isolation.
    2) Every test is run inside a unique cgroup (on Linux) to further isolate the process, mounts and networking from
       the rest of the system.
    3) Each test is monitored for process leaks and mount leaks.

Tests can be repeated, filtered, excluded, debugged, traced and a host of other extensive developer friendly features.

etest produces a JUnit/XUnit compatible etest.xml file at the end of the test run listing all the tests that were
executed along with runtimes and specific lists of passing, failing and flaky tests. This file can be directly hooked
into Jenkins, GitHub Actions, and BitBucket Pipelines for clear test visibility and reporting.
END
: ${FAILFAST:=${BREAK:-0}}
$(opt_parse \
    "+failfast break b=${FAILFAST} | Stop immediately on first failure."                                               \
    "+clean   c=0                  | Clean only and then exit."                                                        \
    ":debug   D=${EDEBUG:-}        | EDEBUG output."                                                                   \
    "+delete  d=1                  | Delete all output files when tests complete."                                     \
    ":name                         | Name of this test run to use for artifacts and display purposes (default=etest)." \
    "+print_only print p           | Print list of tests that would be executed based on provided filter and exclude
                                     to stdout and then exit without actually running any tests."                      \
    ":exclude x                    | Tests whose name or file match this regular expression will not be run."          \
    ":failures=${FAILURES:-0}      | Number of failures per-test to permit. Normally etest will return non-zero if any
                                     test fails at all. However, in certain circumstances where flaky tests exist it may
                                     be desireable to allow each test to retried a specified number of times and only
                                     classify it as a failure if that test fails more than the requested threshold."   \
    ":filter  f                    | Tests whose name or file match this (bash-style) regular expression will be run." \
    "+html    h=0                  | Produce an HTML logfile and strip color codes out of etest.log."                  \
    ":jobs    j=0                  | Number of parallel jobs to run. If this is greater than 0, then the output will
                                     show a progress bar to monitor the parallel jobs. There will be a separate state
                                     directory for each job available in the jobs subdirectory under work directory.
                                     Note that a value of 0 disables parallel job execution. A value of 1 only runs a
                                     single job at a time but allows execution of the parallel job code paths. This
                                     is useful as it allows consistency for the caller to just pass the value of nproc
                                     into etest and the results and output will be identical."                         \
    ":jobs_delay=5s                | Amount of time to sleep in job monitor while waiting for jobs to complete. This
                                     uses sleep(1) time syntax."                                                       \
    "+jobs_progress=1              | Show jobs eprogress summary ticker while running."                                \
    ":logdir log_dir               | Directory to place logs in. Defaults to the current directory."                   \
    "+mount_ns=1                   | Run tests inside a mount namespace."                                              \
    ":repeat  r=${REPEAT:-1}       | Number of times to repeat each test."                                             \
    "+summary s=0                  | Display final summary to terminal in addition to logging it to etest.json."       \
    "&test_list l                  | File that contains a list of tests to run. This file may contain comments on lines
                                     that begin with the # character. All other nonblank lines will be interpreted as
                                     things that could be passed as @tests -- directories, executable scripts, or .etest
                                     files. Relative paths will be interpreted against the current directory. This
                                     option may be specified multiple times."                                          \
    "+verbose v=${VERBOSE:-0}     | Verbose output."                                                                   \
    ":workdir work_dir            | Temporary location where etest can place temporary files. This location will be both
                                    created and deleted by etest."                                                     \
    ":timeout=infinity            | Per-Test timeout. After this duration the test will be killed if not completed. You
                                    can also define this programmatically in setup() using the ETEST_TIMEOUT variable.
                                    This uses sleep(1) time syntax."                                                   \
    ":total_timeout=infinity      | Total test timeout for entire etest run. This is different than timeout which is for
                                    a single unit test. This is the total timeout for ALL test suites and tests being
                                    executed. After this duration etest will be killed if it has not completed. This
                                    uses sleep(1) time syntax."                                                        \
    "+subreaper=1                 | On Linux, set the CHILD_SUBREAPER flag so that any processes created by etest get
                                    reparented to etest itself instead of to init or whatever process ancestor may have
                                    set this flag. This allows us to properly detect process leak detections and ensure
                                    they are cleaned up properly. This only works on Linux with gdb installed."       \
    "@tests                       | Any number of individual tests, which may be executables to be executed and checked
                                    for exit code or may be files whose names end in .etest, in which case they will be
                                    sourced and any test functions found will be executed. You may also specify
                                    directories in which case etest will recursively find executables and .etest files
                                    and treat them in similar fashion."                                                \
)

#-----------------------------------------------------------------------------------------------------------------------
#
# OPTION POST PROCESSING
#
#-----------------------------------------------------------------------------------------------------------------------

# Verify --jobs is a valid integer.
assert_int_ge "${jobs}" 0 "jobs must be an integer value greater than or equal to 0"

# Use mount namespaces as long as:
#   1) they weren't forcibly turned off
#   2) we're on linux
#   3) we're not inside docker (because docker requires us to be privileged, and because the benefit is no longer there
#      -- docker already protects us inside a mount namespace)
if [[ ${mount_ns} -eq 1 ]] && os linux && ! running_in_docker; then
    reexec --mount-ns
fi

# On Linux, if requested, set the CHILD_SUBREAPER flag so that any processes created by etest get reparented to etest.
# This allows us to properly detect process leaks and ensure they are cleaned up properly.
#
# NOTE: There is no native bash way to make system calls. But we can do it through GDB. This may be worth abstracting
# into a module to allow calling system calls in bash natively.
#
if [[ ${subreaper} -eq 1 ]]; then

    if ! os linux; then
        edebug "Subreaper disabled (non-Linux)"
    elif ! command_exists gdb; then
        edebug "Subreaper disabled (gdb missing)"
    else
        gdb -batch -ex 'call (int)prctl((int)36,(long)1,(long)0,(long)0,(long)0)' -ex detach -ex quit -p $$ |& edebug
        trap "" SIGTERM
    fi
fi

# Read in possible configuration files. We support the older name `.ebash` and the newer name `.ebash.conf`
declare -A _EBASH_CONF
conf_read _EBASH_CONF .ebash .ebash.conf

START_TIME=${SECONDS}

# Default log directory from conf file if unspecified on the command line
: ${logdir:=$(conf_get _EBASH_CONF etest.logdir)}
: ${logdir:=$(conf_get _EBASH_CONF etest.log_dir)}
: ${logdir:=.}
mkdir -p "${logdir}"
logdir=$(readlink -f ${logdir})

# Default working directory from conf file if unspecified, or ./output if not in either place
: ${workdir:=$(conf_get _EBASH_CONF etest.workdir)}
: ${workdir:=$(conf_get _EBASH_CONF etest.work_dir)}
: ${workdir:=./etest}
mkdir -p "${workdir}"
workdir=$(readlink -f ${workdir})

EDEBUG=${debug}

(( ${repeat} < 1 )) && repeat=1
[[ ${EDEBUG:-0} != "0" || ${print_only} -eq 1 ]] && verbose=1 || true
edebug "$(lval TOPDIR TEST_DIR) $(opt_dump)"

if ! cgroup_supported ; then
    export ETEST_CGROUP_BASE=unsupported
else
    # Global cgroup name for all unit tests run here
    export ETEST_CGROUP_BASE="etest"
fi
export ETEST_CGROUP="${ETEST_CGROUP_BASE}/$$"

# Setup logfile
exec {ETEST_STDERR_FD}<&2
artifact_name="$(echo "${logdir}/${name:-etest}" | tr ' ' '_')"
ETEST_LOG="${artifact_name}.log"
ETEST_JSON="${artifact_name}.json"
ETEST_XML="${artifact_name}.xml"

# Setup redirection for "etest" and actual "test" output
if [[ ${verbose} -eq 0 ]]; then
    ETEST_OUT="$(fd_path)/${ETEST_STDERR_FD}"
    TEST_OUT="/dev/null"
else
    ETEST_OUT="/dev/null"
    TEST_OUT="/dev/stderr"
fi
