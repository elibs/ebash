#!/bin/bash
#
# Copyright 2020, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.


opt_usage checkbox_open <<'END'
Dispay an open checkbox with an optional message to display. You can then later call checkbox_close to have the checkbox
filled in with a successful check mark or with a failing X. This is useful to display a list of dependencies or tasks.
END
checkbox_open()
{
    echo -n "$(tput setaf 209)$(tput bold)[ ]$(tput sgr0) ${@}" >&2
}

opt_usage checkbox_open_timer <<'END'
Display an open checkbox with an optional message as well as a timer. This is similar in purpose as checkbox_open only
this also displays a timer. This is useful when you want to have a long-running task with a timer and then fill in the
checkbox with a successful check mark or a failing X.
END
__CHECKBOX_TIMER_PID=
checkbox_open_timer()
{
    (
        trap - ERR

        # Hide cursor to avoid seeing it move back and forth
        tput civis

        local start=${SECONDS} new="" diff=""
        while true; do
            now=${SECONDS}
            diff=$(( ${now} - ${start} ))
            printf "$(tput setaf 209)$(tput bold)[ ]$(tput sgr0) %-20s" "$@"
            printf " $(tput bold)[%02d:%02d:%02d]\r$(tput sgr0)" $(( ${diff} / 3600 )) $(( (${diff} % 3600) / 60 )) $(( ${diff} % 60 ))

            # Optionally display a newline between each ticker. This is helpful from jenkins jobs where we want to see
            # progress in the build rather than waiting until the entire checkbox timer job completes.
            if [[ "${CHECKBOX_TIMER_NEWLINE:-0}" -eq 1 ]]; then
                echo
            fi

            # Optionally delay some amount of time to avoid showing the ticker every second
            if [[ -n "${CHECKBOX_TIMER_DELAY:-}" ]]; then
                sleep "${CHECKBOX_TIMER_DELAY:-}"
            fi

        done
    ) >&2 &

    # Store the PID and also add it to EBASH_EPROGRESS_PIDS so that it will get killed explicitly in die(). Also set a
    # trap to ensure we kill it.
    __CHECKBOX_TIMER_PID=$!
    __EBASH_EPROGRESS_PIDS+=( $! )
    trap_add "checkbox_close 1 $!"
}

opt_usage checkbox_close <<'END'
This is used to close a previosly opened checkbox with optional return code. The default if no return code is passed in
is `0` for success. This will move the curser up a line and fill in the open `[ ]` checkbox with a checkmark on success
and an `X` on failure.
END
checkbox_close()
{
    local rc=${1:-0}

    {
        if [[ -n "${__CHECKBOX_TIMER_PID}" ]]; then
            kill "${__CHECKBOX_TIMER_PID}" 2>/dev/null || true
            wait "${__CHECKBOX_TIMER_PID}" 2>/dev/null || true

            tput cnorm
        fi

        printf "\r"

        if [[ "${rc}" -eq 0 ]]; then
            echo "$(tput setaf 2)$(tput bold)[✓]$(tput sgr0)"
        else
            echo "$(tput setaf 1)$(tput bold)[✘]$(tput sgr0)"
        fi
    } >&2

    return 0
}

opt_usage checkbox <<'END'
checkbox is a simple function to display a checkbox at the start of the line followed by an optional message.
END
checkbox()
{
    echo "$(tput setaf 2)$(tput bold)[✓]$(tput sgr0) ${@}" >&2
}

opt_usage checkbox_passed <<'END'
checkbox_passed is a simple wrapper around checkbox that displays a successful checkbox and PASSED followed by an
optional message.
END
checkbox_passed()
{
    echo -e "$(tput setaf 2)$(tput bold)[✓] PASSED$(tput sgr0) ${@}" >&2
}

opt_usage checkbox_failed <<'END'
checkbox_failed is a simple wrapper around checkbox that displays a failure checkbox and FAILED followed by an optional
message.
END
checkbox_failed()
{
    echo -e "$(tput setaf 1)$(tput bold)[✘] FAILED$(tput sgr0) ${@}" >&2
}
