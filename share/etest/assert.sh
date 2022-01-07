#!/usr/bin/env bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# TEST ASSERTIONS
#
#-----------------------------------------------------------------------------------------------------------------------

die_handler()
{
    $(opt_parse \
        ":rc return_code r=1 | Return code that die will exit with")

    # Append any error message to logfile
    if [[ ${verbose} -eq 0 ]]; then
        echo "" >&2
        eerror "${@}"

        # Call eerror_stacktrace but skip top three frames to skip over the frames containing stacktrace_array,
        # eerror_stacktrace and die itself. Also skip over the initial error message since we already displayed it.
        eerror_stacktrace -f=4 -s

    fi &>>${ETEST_OUT}

    exit ${rc}
}

assert_no_process_leaks()
{
    if ! cgroup_supported; then
        return 0
    fi

    edebug "Checking for process leaks in ${ETEST_CGROUP}"

    if ! cgroup_exists "${ETEST_CGROUP}"; then
        edebug "$(lval ETEST_CGROUP) does not exist -- returning"
        return 0
    fi

    # Check if any processes leaked. Check quickly to avoid unecessary delays at clean-up time. If there are any
    # leaked processes remaining, THEN do an eretry to give them time to shutdown. Finally, assert that there are none
    # left.
    try
    {
        eretry -T=5s cgroup_empty "${ETEST_CGROUP}"
    }
    catch
    {
        local leaked_processes=""
        leaked_processes=$(cgroup_ps "${ETEST_CGROUP}")

        if [[ -n ${leaked_processes} ]]; then
            cgroup_kill_and_wait -s=SIGKILL "${ETEST_CGROUP}"
            eerror "Process leaks detected: ${ETEST_CGROUP}:\n${leaked_processes}"
            return 1
        fi
    }

    edebug "Finished checking for process leaks in ${ETEST_CGROUP}"
}

assert_no_mount_leaks()
{
    local mounts=()
    mounts=( $(efindmnt "${workdir}" ) )

    if ! array_empty mounts; then
        eunmount --all --recursive --delete=${delete} "${workdir}"
        eerror "Mount leaks detected: $(lval mounts workdir)"$'\n'"$(array_join_nl mounts)"
        return 1
    fi

    if [[ ${delete} -eq 1 ]]; then
        rm --recursive --force "${workdir}"
    fi

    edebug "Finished"
}
