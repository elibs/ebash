#!/usr/bin/env bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
# DAEMON TEST INFRASTRUCTURE NOTE
#
# The tests below use a very tightly coupled test mechanism to ensure the daemon and the test code execute in lockstep
# so that the tests will be more deterministic by removing various race conditions that existed before when trying to
# poll on the daemon status as state transitions could be missed.
#
# This test framework essentially has two major components: daemon_expect and daemon_react. daemon_expect is the TEST
# side, whereas daemon_react is the part the daemon will execute.
#
# These two functions work in tandem with the help of a lockfile so that the test code sets up what state it expects the
# daemon to enter next. The daemon will essentially loop inside daemon_react until the expected state has been setup by
# the test code. Once setup, the daemon will verify it's in the state the test code expected. If so, it will CLEAR out
# the state file to signal to the test code that it reached the desired state. Then it can safely return from the hook
# callback. The test code will then observe the file is empty and return from daemon_expect.
#
# It's important to note that if the daemon races around very quickly and gets into daemon_react again at this point the
# file is EMPTY and it will simply loop waiting for the test code to setup the next expected state.
#-----------------------------------------------------------------------------------------------------------------------

DAEMON_LOCK="daemon.lock"
DAEMON_STATE="daemon_state"
DAEMON_EXPECT=(
    pre_start="daemon_react pre_start"
    pre_stop="daemon_react pre_stop"
    post_mount="daemon_react post_mount"
    post_stop="daemon_react post_stop"
    post_crash="daemon_react post_crash"
    post_abort="daemon_react post_abort"
)

daemon_react()
{
    $(opt_parse actual)

    edebug "Reached hook ${actual}"
    (
        while true; do

            elock ${DAEMON_LOCK}
            expected=$(cat ${DAEMON_STATE} 2>/dev/null || true)
            if [[ -z ${expected} ]]; then
                edebug "Waiting for test code to setup expected state...$(lval actual)"
                eunlock ${DAEMON_LOCK}
                sleep .5
                continue
            fi

            # Do NOT clear the state file if it's not the expected state!!  Because most hooks swallow errors
            # intentionally, we can't just call die here. Instead just emit error message and then sleep forever. The
            # test code itself will timeout and detect and report the failure.
            if [[ "${expected}" != "${actual}" ]]; then
                eunlock ${DAEMON_LOCK}
                eerror_stacktrace "Unexpected state $(lval expected actual)"
                sleep infinity
            fi

            >${DAEMON_STATE}
            break
        done
    )
}

daemon_expect()
{
    $(opt_parse state)

    etestmsg "Waiting for daemon to reach $(lval state)"

    (
        SECONDS=0
        elock ${DAEMON_LOCK}
        echo "${state}" >${DAEMON_STATE}
        eunlock ${DAEMON_LOCK}

        while true; do

            elock ${DAEMON_LOCK}
            pending=$(cat "${DAEMON_STATE}" || true)
            eunlock ${DAEMON_LOCK}
            [[ -z ${pending} ]] && break

            edebug "Still waiting for daemon to reach $(lval state SECONDS)"
            assert test ${SECONDS} -lt 30
            sleep .5

        done
    )

    etestmsg "Daemon reached $(lval state)"
}

