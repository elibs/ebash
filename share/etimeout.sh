#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Timeout
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage etimeout <<'END'
`etimeout` will execute an arbitrary bash command for you, but will only let it use up the amount of time (i.e. the
"timeout") you specify.

If the command tries to take longer than that amount of time, it will be killed and etimeout will return 124.
Otherwise, etimeout will return the value that your called command returned.

All arguments to `etimeout` (i.e. everything that isn't an option, or everything after --) is assumed to be part of the
command to execute. `Etimeout` is careful to retain your quoting.
END
etimeout()
{
    $(opt_parse \
        ":signal sig s=TERM | First signal to send if the process doesn't complete in time. KILL will still be sent
                              later if it's not dead." \
        ":timeout t         | After this duration, command will be killed if it hasn't already completed." \
        "@cmd               | Command and its arguments that should be executed.")

    argcheck timeout

    # Background the command to be run
    local start=${SECONDS}

    # If no command to execute just return success immediately
    if [[ -z "${cmd[*]:-}" ]]; then
        return 0
    fi

    # COMMAND TO EVAL
    local rc="" pid=""
    (
        disable_die_parent
        quote_eval "${cmd[@]}"
    ) &
    pid=$!
    edebug "Executing $(lval cmd timeout signal pid)"

    #-------------------------------------------------------------------------------------------------------------------
    # WATCHER
    #
    # Launch a background "wathcher" process that is simply waiting for the timeout timer to expire. If it does, it
    # will kill the original command.
    (
        disable_die_parent
        close_fds

        # Wait for the timeout to elapse
        sleep ${timeout}

        # Upon getting here, we know that either 1) the timeout elapsed or 2) our sleep process was killed.
        #
        # We can check to see if anything is still running, though, because we know the command's PID. If it's gone, it
        # must've finished and we can exit
        #
        local pre_pids=()
        pre_pids=( $(process_tree ${pid}) )
        if array_empty pre_pids ; then
            exit 0
        else
            # Since it did not exit and we must've completed our timeout sleep, the command must've outlived its
            # usefulness. Do away with it.
            ekilltree -s=${signal} -k=2s ${pid}

            # Return sentinel 124 value to let the main process know that we encountered a timeout.
            exit 124
        fi

    ) &>/dev/null &

    #-------------------------------------------------------------------------------------------------------------------
    # HANDLE RESULTS
    {
        # Now we need to wait for the original process to finish. We know that it will _either_ finish because it
        # completes normally or because the watcher will kill it.
        #
        # Note that we do _not_ know which. The return code we get from that process might be its normal rc, or it
        # might be the rc that it got because it was killed by the watcher.
        local watcher=$!
        wait ${pid} && rc=0 || rc=$?

        # Once the above has completed, we know that the watcher is no longer needed, so we can kill it, too.
        ekilltree -s=TERM ${watcher}

        # We need the return code from the watcher process to determine what happened. If it returned our sentinel
        # value (124), then we know that it determined there was a timeout. Otherwise, we know that the original
        # command returned on its own.
        wait ${watcher} && watcher_rc=0 || watcher_rc=$?

        local stop seconds
        stop=${SECONDS}
        seconds=$(( ${stop} - ${start} ))

    } &>/dev/null

    # Now if we got that sentinel 124 value, we can report the timeout
    if [[ ${watcher_rc} -eq 124 ]] ; then
        edebug "Timeout $(lval cmd rc seconds timeout signal pid)"
        return 124
    else
        # Otherwise, we report the value reported by the original command
        return ${rc}
    fi
}
