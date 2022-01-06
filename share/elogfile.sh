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
# Logfile
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage elogfile <<'END'
elogfile provides the ability to duplicate the calling processes STDOUT and STDERR and send them both to a list of files
while simultaneously displaying them to the console. Using this function is much preferred over manually doing this with
tee and named pipe redirection as we take special care to ensure STDOUT and STDERR pipes are kept separate to avoid
problems with logfiles getting truncated.

elogfile creates some background processes to take care of logging for us asynchronously. The list of PIDs from these
background processes are stored in an internal array __EBASH_ELOGFILE_PID_SETS. This array stores a series of "pidsets"
which is just a set of pids created on a specific call to elogfile. The reason we use this approach is because depending
on the flags passed into elogfile we may launch one or two different pids. And we'd like the ability to gracefully kill
the set of pids launched by a specific elogfile instance gracefully via elogfile_kill. To that end, we store the pid or
pids as a comma separated list of pids launched.

For example, if you call `elogfile foo` then __EBASH_ELOGFILE_PID_SETS will contain two pids comma-delimited as they
were launched as part of a single call to elogfile, e.g. ("1234,1245"). If you again call `elogfile bar` two more
processes will get launched, and we'll end up with ("1234,1235", "2222,2223"). We can then control which set of pids
we gracefully kill via elogfile_kill.

END
elogfile()
{
    $(opt_parse \
        "+stderr e=1       | Whether to redirect stderr to the logfile." \
        "+stdout o=1       | Whether to redirect stdout to the logfile." \
        ":rotate_count r=0 | When rotating log files, keep this number of log files." \
        ":rotate_size s=0  | Rotate log files when they reach this size. Units as accepted by find." \
        "+tail t=1         | Whether to continue to display output on local stdout and stderr." \
        "+merge m          | Whether to merge stdout and stderr into a single stream on stdout.")

    edebug "$(lval stdout stderr tail rotate_count rotate_size merge)"

    # Return if nothing to do
    if [[ ${stdout} -eq 0 && ${stderr} -eq 0 ]] || [[ -z "$*" ]]; then
        return 0
    fi

    # Rotate logs as necessary but only if they are regular files
    if [[ ${rotate_count} -gt 0 ]]; then
        local name
        for name in "${@}"; do
            [[ -f $(readlink -f "${name}") ]] || continue
            elogrotate -c=${rotate_count} -s=${rotate_size} "${name}"
        done
    fi

    # Setup EINTERACTIVE so our output formats properly even though stderr won't be connected to a console anymore.
    if [[ ! -v EINTERACTIVE ]]; then
        [[ -t 2 ]] && export EINTERACTIVE=1 || export EINTERACTIVE=0
    fi

    # Export COLUMNS properly so that eend and eprogress output properly even though stderr won't be connected to a
    # console anymore.
    if [[ ! -v COLUMNS ]]; then
        COLUMNS=$(tput cols)
        export COLUMNS
    fi

    # Temporary directory to hold our FIFOs
    local tmpdir
    tmpdir=$(mktemp --tmpdir --directory elogfile-XXXXXX)
    trap_add "rm --recursive --force ${tmpdir}"
    local pid_pipe="${tmpdir}/pids"
    mkfifo "${pid_pipe}"

    # List of pids we launch in this call
    local pids=()

    # Internal function to avoid code duplication in setting up the pipes and redirection for stdout and stderr.
    elogfile_redirect()
    {
        $(opt_parse name)

        # If we're not redirecting the requested stream then just return success
        [[ ${!name} -eq 1 ]] || return 0

        # Create pipe
        local pipe="${tmpdir}/${name}"
        mkfifo "${pipe}"
        edebug "$(lval name pipe)"

        # Double fork so that the process doing the tee won't be one of our children processes anymore. The purose of
        # this is to ensure when we kill our process tree that we won't kill the tee process. If we allowed tee to get
        # killed then any future output would HANG indefinitely because there wouldn't be a reader attached to the pipe.
        # Without a reader attached to the pipe all writes block indefinitely. Since this is blocking in the kernel the
        # process essentially becomes unkillable once in this state.
        (
            disable_die_parent
            close_fds
            (
                # Don't hold open a directory
                local relative_files=( "${@}" ) files=( )
                for file in "${relative_files[@]}" ; do
                    files+=( "$(readlink -m "${file}")" )
                done
                cd /

                # If we are in a cgroup, move the tee process out of that cgroup so that we do not kill the tee. It
                # will nicely terminate on its own once the process dies.
                if cgroup_supported && [[ ${EUID} -eq 0 && -n "$(cgroup_current)" ]] ; then
                    edebug "Moving tee process out of cgroup"
                    cgroup_move "/" ${BASHPID}
                fi

                # Ignore signals that came from the TTY for these special processes.
                #
                # This will keep them alive long enough to display our error output and such. SIGPIPE will take care of
                # them, and the kill -9 below will make double sure.
                trap "" "${TTY_SIGNALS[@]}"
                echo "${BASHPID}" >${pid_pipe}

                # Past this point, we hand control to the tee processes which we expect to die in their own time. We no
                # longer want to be notified if something goes wrong (such as the tee being killed)
                nodie_on_error

                if [[ ${tail} -eq 1 ]]; then
                    # shellcheck disable=SC2261
                    # This tee is carefully constructed to send stdout to a named file descriptor so disable shellcheck
                    tee -a "${files[@]}" <${pipe} >&$(get_stream_fd ${name}) 2>/dev/null
                else
                    tee -a "${files[@]}" <${pipe} >/dev/null 2>&1
                fi
            ) &
        ) &

        # Save pid into our list of local pids that we'll add to __EBASH_ELOGFILE_PID_SETS at the end of this function.
        pids+=( $(cat ${pid_pipe}) )

        # Re-exec so  our output stream(s) are redirected to the pipe.
        # NOTE: If we're merging stdout+stderr we redirect both streams into the pipe
        if [[ ${merge} -eq 1 ]]; then
            eval "exec &>${pipe}"
        else
            eval "exec $(get_stream_fd ${name})>${pipe}"
        fi
    }

    # Redirect stdout and stderr as requested to the provided list of files.
    if [[ ${merge} -eq 1 ]]; then
        elogfile_redirect stdout "${@}"
    else
        elogfile_redirect stdout "${@}"
        elogfile_redirect stderr "${@}"
    fi

    # Add all pids we launched in this call to our global pids array. This array stores pidsets not pids. So we join
    # the array with a comma to keep them as a single non-whitespace delimited entry.
    edebug "Spawned $(lval elogfile_pids=pids)"
    __EBASH_ELOGFILE_PID_SETS+=( $(array_join pids ",") )
    trap_add "elogfile_kill ${pids[*]}"
}

opt_usage elogfile_pids <<'END'
elogfile_pids is used to convert the pidset stored in __EBASH_ELOGFILE_PID_SETS into a newline delimited list of PIDs.
Being newline delimited helps the output of this easily slurp into `readarray`.
END
elogfile_pids()
{
    # Convert provided pid sets into a single flat array of pids. Split on either a comma or a space so that we can
    # flatten the list of pid sets into a single pid list.
    local pids=()
    array_init pids "${__EBASH_ELOGFILE_PID_SETS[*]:-}" ", "

    echo "${pids[*]:-}" | tr ' ' '\n'
}

opt_usage __elogfile_pid_remove <<'END'
__elogfile_pid_remove is an internal helper function used to safely remove a pid from the __EBASH_ELOGFILE_PID_SETS. We
can't just use array_remove since it is an array of pidsets rather than just a flat array of pids. This helper function
handles that problem for us gracefully. It will return success if the pid is successfully removed and failure otherwise.
END
elogfile_pid_remove()
{
    $(opt_parse \
        "pid | The pid to remove from the elogfile pidsets." \
    )

    local idx entry
    for idx in "${!__EBASH_ELOGFILE_PID_SETS[@]}"; do

        entry=${__EBASH_ELOGFILE_PID_SETS[$idx]}

        if [[ "${entry}" == "${pid}" ]]; then
            entry=""
        elif [[ "${entry}" =~ ^${pid}, ]]; then
            entry="${entry/${pid},/}"
        elif [[ "${entry}" =~ ,${pid}, ]]; then
            entry="${entry/,${pid},/}"
        elif [[ "${entry}" =~ ,${pid}$ ]]; then
            entry="${entry/,${pid}/}"
        fi

        # If we made a change update this index in the array and return success.
        if [[ "${entry}" != "${__EBASH_ELOGFILE_PID_SETS[$idx]}" ]]; then
            if [[ -z "${entry}" ]]; then
                unset __EBASH_ELOGFILE_PID_SETS[$idx]
            else
                __EBASH_ELOGFILE_PID_SETS[$idx]="${entry}"
            fi

            return 0
        fi
    done

    # If we didn't find a match in the above loop then we couldn't delete it so we need to return an error.
    return 1
}

opt_usage elogfile_kill <<'END'
Kill previously launched elogfile processes. By default if no parameters are provided kill any elogfiles that were
launched by our process. Or alternatively if `--all` is provided then kill all elogfile processes. Can also optionally
pass in a specific list of elogfile pids to kill.
END
elogfile_kill()
{
    $(opt_parse \
        "+all a | If set, kill ALL known eprogress processes, not just the current one"  \
    )

    # If given a list of pids, kill each one. Otherwise kill most recent. If there's nothing to kill just return.
    local pid_sets=()
    if [[ $# -gt 0 ]]; then
        pid_sets=( ${@} )
    elif array_not_empty __EBASH_ELOGFILE_PID_SETS; then
        if [[ ${all} -eq 1 ]] ; then
            pid_sets=( "${__EBASH_ELOGFILE_PID_SETS[@]}" )
        else
            pid_sets=( "${__EBASH_ELOGFILE_PID_SETS[-1]}" )
        fi
    else
        return 0
    fi

    # Convert provided pid sets into a single flat array of pids. Split on either a comma or a space so that we can
    # flatten the list of pid sets into a single pid list.
    local pids=()
    array_init pids "${pid_sets[*]}" ", "
    edebug "Killing elogfile $(lval pids)"

    # Get a flat list of elogfile pids so we can check each pid against the list to ensure it's a valid elogfile pid to
    # be killing.
    local valid_pids
    readarray -t valid_pids < <(elogfile_pids)

    # Kill requested pids
    local pid
    for pid in "${pids[@]}"; do

        # Don't kill the pid if it's not running or it's not an elogfile pid. This catches potentially disasterous
        # errors where someone would do "elogfile_kill $?" instead of "elogfile_kill $!".
        if process_not_running ${pid} || ! array_contains valid_pids ${pid}; then
            continue
        fi

        # Kill process and wait for it to complete
        ekill ${pid} &>/dev/null
        wait ${pid} &>/dev/null || true
        elogfile_pid_remove ${pid}
    done
}
