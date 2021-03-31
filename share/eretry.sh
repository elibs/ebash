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
# eretry
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage eretry <<'END'
Eretry executes arbitrary shell commands for you wrapped in a call to etimeout and retrying up to a specified count.

If the command eventually completes successfully eretry will return 0. If the command never completes successfully but
continues to fail every time the return code from eretry will be the failing command's return code. If the command is
prematurely terminated via etimeout the return code from eretry will be 124.

All direct parameters to eretry are assumed to be the command to execute, and eretry is careful to retain your quoting.
END
eretry()
{
    $(opt_parse \
        ":delay d=0              | Amount of time to delay (sleep) after failed attempts before retrying. Note that this
                                   value can accept sub-second values, just as the sleep command does. This parameter
                                   will be passed directly to sleep, so you can specify any arguments it accepts such as
                                   .01s, 5m, or 3d." \
        ":fatal_exit_codes e=0   | Space-separated list of exit codes. Any of the exit codes specified in this list will
                                   cause eretry to stop retrying. If eretry receives one of these codes, it will
                                   immediately stop retrying and return that exit code. By default, only a return code
                                   of zero will cause eretry to stop. If you specify -e, you should consider whether you
                                   want to include 0 in the list." \
        ":retries r              | Command will be attempted this many times total. If no options are provided to eretry
                                   it will use a default retry limit of 5." \
        ":signal sig s=TERM      | When timeout seconds have passed since running the command, this will be the signal
                                   to send to the process to make it stop. The default is TERM. [NOTE: KILL will _also_
                                   be sent two seconds after the timeout if the first signal doesn't do its job]" \
        ":timeout t              | After this duration, command will be killed (and retried if that's the right thing to
                                   do). If unspecified, commands may run as long as they like and eretry will simply
                                   wait for them to finish. Uses sleep(1) time syntax." \
        ":max_timeout T=infinity | Total timeout for entire eretry operation. This flag is different than --timeout in
                                   that --max-timeout applies to the entire eretry operation including all iterations
                                   and retry attempts and timeouts of each individual command. Uses sleep(1) time
                                   syntax." \
        ":warn_every w           | A warning will be generated on (or slightly after) every SECONDS while the command
                                   keeps failing." \
        ":warn_message m         | Custom message to display on each warn_every interval." \
        ":warn_color c           | Warning color to use." \
        "@cmd                    | Command to run along with any of its own options and arguments.")

    # If unspecified, limit timeout to the same as max_timeout
    : ${timeout:=${max_timeout:-infinity}}

    # If a total timeout was specified then wrap call to eretry_internal with etimeout
    if [[ ${max_timeout} != "infinity" ]]; then
        : ${retries:=infinity}

        etimeout -t=${max_timeout} -s=${signal} --    \
            opt_forward eretry_internal               \
                timeout delay fatal_exit_codes signal \
                warn_every warn_message warn_color    \
                retries -- "${cmd[@]}"
    else
        # If no total timeout or retry limit was specified then default to prior behavior with a max retry of 5.
        : ${retries:=5}

        opt_forward eretry_internal \
            timeout delay fatal_exit_codes signal \
            warn_every warn_message warn_color    \
            retries -- "${cmd[@]}"
    fi
}

opt_usage eretry_internal <<'END'
Internal method called by eretry so that we can wrap the call to eretry_internal with a call to etimeout in order to
provide upper bound on entire invocation.
END
eretry_internal()
{
    $(opt_parse \
        ":delay d                | Time to sleep between failed attempts before retrying." \
        ":fatal_exit_codes e     | Space-separated list of exit codes that are fatal (i.e. will result in no retry)." \
        ":retries r              | Command will be attempted once plus this number of retries if it continues to fail." \
        ":signal sig s           | Signal to be send to the command if it takes longer than the timeout." \
        ":timeout t              | If one attempt takes longer than this duration, kill it and retry if appropriate." \
        ":warn_every w           | Generate warning messages after failed attempts when it has been more than this long
                                   since the last warning." \
        ":warn_message           | Custom message to display on each warn_every interval." \
        ":warn_color c           | Warning color to use." \
        "@cmd                    | Command to run followed by any of its own options and arguments.")

    argcheck delay fatal_exit_codes retries signal timeout

    # Command
    local attempt=0
    local rc=0
    local exit_codes=()
    local stdout=""
    local start=${SECONDS}
    local warn_seconds="${SECONDS}"
    : ${warn_color:=${COLOR_WARN}}
    warn_every=${warn_every%s}

    # If no command to execute just return success immediately
    if [[ -z "${cmd[@]:-}" ]]; then
        return 0
    fi

    while true; do
        [[ ${retries} != "infinity" && ${attempt} -ge ${retries} ]] && break || (( attempt+=1 ))

        seconds=$(( ${SECONDS} - ${start} ))
        edebug "Executing $(lval cmd) timeout=(${seconds}s/${timeout}) retries=(${attempt}/${retries})"

        # Run the command through timeout wrapped in tryrc so we can throw away the stdout on any errors. The reason for
        # this is any caller who cares about the output of eretry might see part of the output if the process times out.
        # If we just keep emitting that output they'd be getting repeated output from failed attempts which could be
        # completely invalid output (e.g. truncated XML, Json, etc).
        stdout=""
        $(tryrc -o=stdout etimeout -t=${timeout} -s=${signal} "${cmd[@]}")

        # Append list of exit codes we've seen
        exit_codes+=(${rc})
        edebug "$(lval cmd seconds timeout exit_codes attempt retries)"

        # Break if the process exited with white listed exit code.
        if echo "${fatal_exit_codes}" | grep -wq "${rc}"; then
            edebug "Command reached terminal exit code $(lval rc fatal_exit_codes cmd)"
            break
        fi

        # Show warning if requested
        if [[ -n ${warn_every} ]] && (( SECONDS - warn_seconds > warn_every )); then
            if [[ -n "${warn_message}" ]]; then
                emsg "${warn_color}" ">>" "WARN" "${warn_message} timeout=(${seconds}s/${timeout}) retries=(${attempt}/${retries})"
            else
                emsg "${warn_color}" ">>" "WARN" "Failed $(lval cmd) timeout=(${seconds}s/${timeout}) retries=(${attempt}/${retries})"
            fi
            warn_seconds=${SECONDS}
        fi

        # Don't use "-ne" here since delay can have embedded units
        if [[ ${delay} != "0" ]] ; then
            edebug "Sleeping $(lval delay)"
            sleep ${delay}
        fi
    done

    [[ ${rc} -eq 0 ]] || ewarn "Failed $(lval cmd timeout exit_codes) retries=(${attempt}/${retries})"

    # Emit stdout
    echo -n "${stdout}"

    # Return final return code
    return ${rc}
}
