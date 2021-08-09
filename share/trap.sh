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
# Traps
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage trap_get <<'END'
Print the trap command associated with a given signal (if any). This essentially parses trap -p in order to extract the
command from that trap for use in other functions such as call_die_traps and trap_add.
END
trap_get()
{
    $(opt_parse "sig | Signal name to print traps for.")

    # Normalize the signal description (which might be a name or a number) into the form trap produces
    sig="$(signame -s "${sig}")"

    local existing
    existing=$(trap -p "${sig}")
    existing=${existing##trap -- \'}
    existing=${existing%%\' ${sig}}

    echo -n "${existing}"
}

opt_usage trap_add <<'END'
Appends a command to a trap. By default this will use the default list of signals: ${DIE_SIGNALS[@]}, ERR and EXIT so
that this trap gets called by default for any signal that would cause termination. If that's not the desired behavior
then simply pass in an explicit list of signals to trap.
END
trap_add()
{
    $(opt_parse \
        "?cmd     | Command to be added to the trap, quoted to be one argument." \
        "@signals | Signals (or pseudo-signals) that should invoke the trap. Default is EXIT.")

    array_not_empty signals || signals=( "EXIT" )

    local sig
    for sig in "${signals[@]}"; do
        sig=$(signame -s ${sig})

        # If we're at the same shell level where we have set any trap, then it's safe to append to the existing trap.
        # If we haven't set any trap in this shell level, bash will show us the parent shell's traps instead and we
        # don't want to copy those into this shell.
        local existing=""
        if [[ ${__EBASH_TRAP_LEVEL:-0} -eq ${BASH_SUBSHELL} ]]; then
            existing="$(trap_get ${sig})"

            # Strip off our ebash internal cleanup from the trap, because we'll add it back in later.
            existing=${existing%%; _ebash_on_exit_end}
            existing=${existing##_ebash_on_exit_start; }

            # __EBASH_TRAP_LEVEL is owned and updated by our trap() function. It'll update it soon.
        fi

        # Now we need to split the single existing command into an array of commands so that we can safely manipulate it
        local trap_commands=()

        if [[ ${sig} == "EXIT" ]]; then
            trap_commands+=( "_ebash_on_exit_start" )
        fi

        if [[ -n "${cmd}" ]]; then
            trap_commands+=( "${cmd}" )
        fi

        if [[ -n "${existing}" ]]; then
            trap_commands+=( "${existing}" )
        fi

        if [[ ${sig} == "EXIT" ]]; then
            trap_commands+=( "_ebash_on_exit_end" )
        fi

        # Join array of commands into a single command again separated by ';' and then register a trap with it.
        local complete_trap=""
        complete_trap="$(printf "%s;" "${trap_commands[@]}")"
        complete_trap="${complete_trap%;}"

        trap -- "${complete_trap}" "${sig}"

    done
}

# Set the trace attribute for trap_add function. This is required to modify DEBUG or RETURN traps because functions
# don't inherit them unless the trace attribute is set.
declare -f -t trap_add

opt_usage trap <<'END'
ebash asks bash to let the ERR and DEBUG traps be inherited from shell to subshell by setting appropriate shell options.
Unfortunately, its method of enforcing that inheritance is somewhat limited. It only lasts until someone sets any other
trap. At that point, the inhertied trap is erased.

To workaround this behavior, ebash overrides "trap" such that it will do the normal work that you expect trap to do, but
it will also make sure that the ERR and DEBUG traps are truly inherited from shell to shell and persist regardless of
whether other traps are created.
END
trap()
{
    # If trap received any options, don't do anything special. Only -l and -p are supported by bash's trap and they
    # don't affect the current set of traps.
    if [[ "$1" == "--" || "$1" != -* ]] ; then

        # __EBASH_TRAP_LEVEL is the ${BASH_SUBSHELL} value that was used the last time trap was called. BASH_SUBSHELL
        # is incremented for each nested subshell. At the top level, that is 0
        if [[ ${__EBASH_TRAP_LEVEL:=0} -lt ${BASH_SUBSHELL} ]] ; then

            local trapsToSave
            trapsToSave="$(builtin trap -p ERR DEBUG)"

            # Call "builtin trap" rather than "trap" because we don't want to recurse infinitely. Note, the backslashes
            # before the hyphens in this pattern are superfluous to bash, but they make vim's syntax highlighting much
            # happier.
            trapsToSave="${trapsToSave//trap --/builtin trap \-\-}"

            # Call the trap builtin to set those ERR and DEBUG traps first
            eval "${trapsToSave}"

            __EBASH_TRAP_LEVEL=${BASH_SUBSHELL}
        fi

    fi

    builtin trap "${@}"
}
