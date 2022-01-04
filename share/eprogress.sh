#!/bin/bash
#
# Copyright 2011-2022, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

# Default eprogress settings
: ${EPROGRESS:=1}
: ${EPROGRESS_DELAY:=}
: ${EPROGRESS_SPINNER:=1}
: ${EPROGRESS_INLINE:=1}

opt_usage spintout <<'END'
`spinout` is used to print a spinner to STDERR and is used by various function such as `eprogress`.
END
spinout()
{
    local char="$1"
    echo -n -e "\b${char}" >&2
    sleep 0.10
}

opt_usage eprogress <<'END'
`eprogress` is used to print a progress bar to STDERR in a highly configurable format. The typical use case for this is
to handle very long-running commands and give the user some indication that the command is still in-progress rather than
hung. The ticker can be customized:

- Disabled entirely using `EPROGRESS=0`
- Show on the left or right via `--align`
- Change how often it is printed via `--delay`
- Show the **timer** but not the **spinner** via `--no-spinner`
- Display contents of a **file** on each iteration
END
eprogress()
{
    $(opt_parse \
        ":align=left                   | Where to align the tickker to (valid options are 'left' and 'right')."        \
        ":delay=${EPROGRESS_DELAY}     | Optional delay between tickers to avoid flooding the screen. Useful for
                                         automated CI/CD builds where we are not writing to an actual terminal but want
                                         to see periodic updates."                                                     \
        "+spinner=${EPROGRESS_SPINNER} | Display spinner inline with the message and timer."                           \
        "+inline=${EPROGRESS_INLINE}   | Display message, timer and spinner all inline. If you disable this the full
                                         message and timer is printed on a separate line on each iteration instead. This
                                         is useful for automated CI/CD builds where we are not writing to a real TTY." \
        "+delete d=1                   | Delete file when eprogress completes if one was specified via --file."        \
        ":file f                       | A file whose contents should be continually updated and displayed along with
                                         the ticker. This file will be deleted by default when eprogress completes."   \
        "+time=1                       | As long as not turned off with --no-time, the amount of time since eprogress
                                         start will be displayed next to the ticker."                                  \
        ":style=einfo                  | Style used when displaying the message. You might want to use, for instance,
                                         einfos or ewarn or eerror instead. Or 'echo' if you don't want any special emsg
                                         formatting at the start of the message."                                      \
        "@message                      | A message to be displayed once prior to showing a time ticker. This will occur
                                         before the file contents if you also use --file."                             \
    )

    assert_match "${align}" "(left|right)"

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0. Simply display static message and then return.
    if [[ ${EPROGRESS} -eq 0 ]]; then

        "${style}" -n "$* "

        # Delete file if requested
        if [[ -n ${file} && -r ${file} && ${delete} -eq 1 ]] ; then
            rm --force "${file}"
        fi

        return 0
    fi

    # Background a subshell to perform actual eprogress ticker work. Store the new pid in our list of eprogress PIDs
    # and setup a trap to ensure we kill this background process in the event we die before calling eprogress_kill.
    (
        # Close any file descriptors our parent had open.
        close_fds

        # Don't produce any errors when tools here catch a signal. That's what we expect to happen
        nodie_on_error

        # Hide cursor to avoid seeing it move back and forth
        if [[ "${inline}" -eq 1 ]]; then
            tput civis >&2
        fi

        # Sentinal for breaking out of the loop on signal from eprogress_kill
        local done=0
        trap "done=1" "${DIE_SIGNALS[@]}"

        # Display static message.
        "${style}" -n "$*"

        # Save current position and start time
        if [[ ${inline} -eq 1 ]]; then
            ecolor save_cursor >&2
        fi
        local start=${SECONDS}

        # Infinite loop until we are signaled to stop at which point 'done' is set to 1 and we'll break out
        # gracefully at the right point in the loop.
        local new="" lines=0 columns=0 offset=0
        while true; do

            # Display file contents if appropriate (minus final newline)
            if [[ -n ${file} && -r ${file} ]] ; then
                printf "%s" "$(<${file})"
            fi

            if [[ ${time} -eq 1 ]] ; then

                # Terminal magic that moves our cursor to the bottom right corner of the screen then backs it up just
                # enough to allow the ticker to display such that it is right justified instead of lost on the far left
                # of the screen intermingled with actions being performed.
                if [[ "${align}" == "right" ]]; then
                    lines=$(tput lines)
                    columns=$(tput cols)
                    offset=$(( columns - 18 ))
                    tput cup "${lines}" "${offset}" 2>/dev/null
                fi

                ecolor bold
                printf " [$(time_duration ${start})] "
                ecolor none
            fi

            # Optionally display the spinner.
            if [[ ${spinner} -eq 1 ]]; then
                echo -n " "
                ecolor clear_to_eol

                spinout "/"
                spinout "-"
                spinout "\\"
                spinout "|"
                spinout "/"
                spinout "-"
                spinout "\\"
                spinout "|"
            fi

            # If we are done then break out of the loop and perform necessary clean-up. Otherwise prepare for next
            # iteration.
            if [[ ${done} -eq 1 ]]; then
                break
            fi

            # Optionally sleep if delay was requested.
            if [[ -n "${delay}" ]]; then
                sleep "${delay}"
            fi

            # If we are NOT in inline mode, then emit a newline followed by the static message to prepare for the next
            # iteration.
            if [[ ${inline} -eq 0 ]]; then
                printf "\n"
                "${style}" -n "$*"
            else
                ecolor restore_cursor
            fi

        done >&2

        # If we're terminating delete whatever character was lost displayed and print a blank space over it
        if [[ ${inline} -eq 1 ]]; then
            { ecolor move_left ; echo -n " " ; } >&2
        fi

        # Delete file if requested
        if [[ -n ${file} && -r ${file} && ${delete} -eq 1 ]] ; then
            rm --force "${file}"
        fi

        # Always exit with success
        exit 0

    ) &

    __EBASH_EPROGRESS_PIDS+=( $! )
    trap_add "eprogress_kill -r=1 $!"
}

opt_usage eprogress_kill <<'END'
Kill the most recent eprogress in the event multiple ones are queued up. Can optionally pass in a specific list of
eprogress pids to kill.
END
eprogress_kill()
{
    $(opt_parse \
        "+all a                      | If set, kill ALL known eprogress processes, not just the current one"           \
        ":callback=eend              | Callback to call as each progress ticker is killed."                            \
        ":return_code rc r=0         | Should this eprogress show a mark for success or failure?"                      \
        "+inline=${EPROGRESS_INLINE} | Display message, timer and spinner all inline. If you disable this the full
                                       message and timer is printed on a separate line on each iteration instead. This
                                       is useful for automated CI/CD builds where we are not writing to a TTY."        \
    )

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    if [[ ${EPROGRESS} -eq 0 ]] ; then
        ${callback} ${return_code}
        return 0
    fi

    # If given a list of pids, kill each one. Otherwise kill most recent. If there's nothing to kill just return.
    local pids=()
    if [[ $# -gt 0 ]]; then
        pids=( ${@} )
    elif array_not_empty __EBASH_EPROGRESS_PIDS; then
        if [[ ${all} -eq 1 ]] ; then
            pids=( "${__EBASH_EPROGRESS_PIDS[@]}" )
        else
            pids=( "${__EBASH_EPROGRESS_PIDS[-1]}" )
        fi
    else
        return 0
    fi

    # Kill requested eprogress pids
    local pid
    for pid in "${pids[@]}"; do

        # Don't kill the pid if it's not running or it's not an eprogress pid. This catches potentially disasterous
        # errors where someone would do "eprogress_kill ${return_code}" when they really meant "eprogress_kill
        # -r=${return_code}"
        if process_not_running ${pid} || ! array_contains __EBASH_EPROGRESS_PIDS ${pid}; then
            continue
        fi

        # Kill process and wait for it to complete
        ekill ${pid} &>/dev/null
        wait ${pid} &>/dev/null || true
        array_remove __EBASH_EPROGRESS_PIDS ${pid}

        # Output
        if einteractive && [[ "${callback}" == "eend" ]]; then
            echo "" >&2
        fi

        ${callback} ${return_code}
    done

    # Display cursor again
    if [[ "${inline}" -eq 1 ]]; then
        tput cnorm >&2
    fi

    return 0
}
