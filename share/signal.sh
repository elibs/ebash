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
# Signal
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage disable_signals <<'END'
Save off the current state of signal-based traps and disable them. You may be interested in doing this if you're very
concerned that a short bit of code should not be interrupted by a signal. Be _SURE_ to call renable signals when you're
done.
END
disable_signals()
{
    declare -Ag __EBASH_SAVED_TRAPS
    __EBASH_SAVED_TRAPS[$BASHPID]=$(trap -p "${DIE_SIGNALS[@]}")
    trap "" "${DIE_SIGNALS[@]}"
}

reenable_signals()
{
    if [[ -v __EBASH_SAVED_TRAPS ]]; then
        eval "${__EBASH_SAVED_TRAPS[$BASHPID]}"
    fi
}

opt_usage signum <<'END'
Given a name or number, echo the signal name associated with it.
END
signum()
{
    if [[ "$1" =~ ^[[:digit:]]$ ]] ; then
        echo "$1"

    # For a complete list of bash pseudo-signals, see help trap (this is the
    # complete list at time of writing)
    elif [[ "$1" == "EXIT" || "$1" == "ERR" || "$1" == "DEBUG" || "$1" == "RETURN" ]] ; then
        die "Bash pseudo signal $1 does not have a signal number."

    else
        kill -l "$1"
    fi
    return 0
}

opt_usage signame <<'END'
Given a signal name or number, echo the signal number associated with it.

With the --include-sig option, SIG will be part of the name for signals where that is appropriate. For instance,
SIGTERM or SIGABRT rather than TERM or ABRT. Note that bash pseudo signals never use SIG. This function treats those
appropriately (i.e. even with --include sig will return EXIT rather than SIGEXIT)
END
signame()
{
    $(opt_parse \
        "+include_sig s | Get the form of the signal name that includes SIG.")

    local prefix=""
    if [[ ${include_sig} -eq 1 ]] ; then
        prefix="SIG"
    fi

    if [[ "$1" =~ ^[[:digit:]]+$ ]] ; then
        echo "${prefix}$(kill -l "$1")"

    elif [[ "${1^^}" == @(RETURN|SIGRETURN) ]]; then
        echo "RETURN"

    elif [[ "${1^^}" == @(EXIT|SIGEXIT) ]]; then
        echo "EXIT"

    elif [[ "${1^^}" == @(ERR|SIGERR) ]]; then
        echo "ERR"

    elif [[ "${1^^}" == @(DEBUG|SIGDEBUG) ]]; then
        echo "DEBUG"

    else
        # Find the associated number, and then get the name that bash believes is associated with that number
        echo "${prefix}$(kill -l "$(kill -l "$1")")"
    fi

    return 0
}

opt_usage sigexitcode <<'END'
Given a signal name or number, echo the exit code that a bash process would produce if it died due to the specified
signal.
END
sigexitcode()
{
    echo "$(( 128 + $(signum $1) ))"
    return 0
}
