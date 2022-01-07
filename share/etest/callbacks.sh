#!/usr/bin/env bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# TEST CALLBACKS
#
#-----------------------------------------------------------------------------------------------------------------------

global_setup()
{
    ecolor hide_cursor &>>${ETEST_OUT}
    edebug "Running global_setup"

    # Create a specific directory to run this test in. That way the test can create whatever directories and files it
    # needs and assuming the test succeeds we'll auto remove the directory after the test completes.
    efreshdir "${workdir}"

    # If cgroups are supported, create a new parent cgroup which will contain all our processes including the elogfile
    # processes we already launched.
    if cgroup_supported ; then
        cgroup_create ${ETEST_CGROUP}
        cgroup_move ${ETEST_CGROUP_BASE} $$ $(elogfile_pids)
    fi

    edebug "Finished global_setup"
}

global_teardown()
{
    ecolor show_cursor &>>${ETEST_OUT}

    edebug "Running global_teardown: PID=$$ BASHPID=${BASHPID} PPID=${PPID}"

    # Try to clean up any lingering process leaks or mount leaks but do not fail here as we need to perform additional
    # cleanup after this.
    $(tryrc assert_no_process_leaks)
    $(tryrc assert_no_mount_leaks)

    # Convert logfile to HTML if requested
    if [[ ${html} -eq 1 ]] && which ansi2html &>/dev/null; then
        edebug "Converting ${ETEST_LOG} into HTML"
        cat ${ETEST_LOG} | ansi2html --scheme=xterm > ${ETEST_LOG/.log/.html}
        noansi ${ETEST_LOG}
    fi

    edebug "Finished global_teardown"

    # Gracefully stop elogfile
    elogfile_kill --all

    # Destroy parent cgroup
    if cgroup_supported ; then
        cgroup_destroy --recursive ${ETEST_CGROUP}
    fi
}
