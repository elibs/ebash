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

        # Grab the pid of the backgrounded pipe process and setup a trap to ensure we kill it when we exit for any
        # reason.
        local pid
        pid=$(cat ${pid_pipe})
        trap_add "kill -9 ${pid} 2>/dev/null || true"

        # Finally re-exec so that our output stream(s) are redirected to the pipe. NOTE: If we're merging stdout+stderr
        # we redirect both streams into the pipe
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
}
