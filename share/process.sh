#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.


# This is a simple override of the linux pstree command. The trouble with that command is that it likes to segfault.
# It's buggy. So here, we simply ignore the error codes that would come from it.
#
if [[ ${__EBASH_OS} == Linux ]] ; then
    pstree()
    {
        (
            ulimit -c 0
            command pstree "${@}" || true
        )
    }
fi

opt_usage process_running <<'END'
Check if a given process is running. Returns success (0) if all of the specified processes are running and failure (1)
otherwise.
END
process_running()
{
    local pid
    for pid in "${@}" ; do
        if ! ps -p ${pid} &>/dev/null ; then
            return 1
        fi
    done
    return 0
}

opt_usage process_not_running <<'END'
Check if a given process is NOT running. Returns success (0) if all of the specified processes are not running and
failure (1) otherwise.
END
process_not_running()
{
    ! process_running "${@}"
}

opt_usage process_tree <<'END'
Generate a depth first recursive listing of entire process tree beneath a given PID. If the pid does not exist this will
produce an empty string.
END
process_tree()
{
    $(opt_parse \
        ":ps_all | Pre-prepared output of \"ps -eo ppid,pid\" so I can avoid calling ps repeatedly")

    : ${ps_all:=$(ps -eo ppid,pid)}

    # Assume current process if none is specified
    if [[ ! $# -gt 0 ]] ; then
        set -- ${BASHPID}
    fi

    local parent children child
    for parent in "${@}"; do

        children=$(process_children --ps-all "${ps_all}" ${parent})
        for child in ${children} ; do
            process_tree --ps-all "${ps_all}" "${child}"
        done

        # NOTE: It's vital that we echo the parent AFTER the above code rather than before otherwise this would not
        # yield the desired depth first ordering.
        echo ${parent}

    done
}

opt_usage process_children <<'END'
Print the pids of all children of the specified list of processes. If no processes were specified, default to
`${BASHPID}`.

Note, this doesn't print grandchildren and other descendants. Just children. See process_tree for a recursive tree of
descendants.
END
process_children()
{
    $(opt_parse \
        ":ps_all | The contents of \"ps -eo ppid,pid\", produced ahead of time to avoid calling ps over and over")
    : ${ps_all:=$(ps -eo ppid,pid)}

    # If nothing was specified, assume the current process
    if [[ ! $# -gt 0 ]] ; then
        set -- ${BASHPID}
    fi

    local parent
    local children=()
    for parent in "${@}" ; do
        children+=( $(echo "${ps_all}" | awk '$1 == '${parent}' {print $2}') )
    done

    echo "${children[@]:-}"
}

opt_usage process_parent <<'END'
Print the pid of the parent of the specified process, or of $BASHPID if none is specified.
END
process_parent()
{
    $(opt_parse "?child | pid of child process")
    [[ $# -gt 0 ]] && die "process_parent only accepts one child to check."

    : ${child:=${BASHPID}}

    # NOTE: Echo the output here to avoid whitespace being captured by the caller
    echo $(ps -p "${child}" -o ppid=)
}

opt_usage process_parent_tree <<'END'
Similar to process_ancestors (which gives a list of pids), this prints a tree of the process's parents, including pids
and commandlines, from the pid specified (BASHPID by default) to toppid (1 or init by default)
END
process_parent_tree()
{
    $(opt_parse \
        ':format f=-o args= | ps format'     \
        ':toppid t=1        | pid to run to' \
        "?pid               | pid to check")

    : ${pid:=${BASHPID}}

    local chain=( ${pid} )
    local parent

    while [[ ${pid} -gt 1 && ${pid} -gt ${toppid} ]] ; do
        parent=$(ps -o ppid= ${pid})
        pid=${parent}
        chain=( ${pid} ${chain[@]} )
    done

    local indent="" link=""
    for link in "${chain[@]}"; do
        echo "$(printf "(%5d)" ${link})${indent}* $(ps ${format} ${link})"
        indent+=" "
    done
}

opt_usage process_ancestors <<'END'
Print pids of all ancestores of the specified list of processes, up to and including init (pid 1). If no processes are
specified as arguments, defaults to ${BASHPID}
END
process_ancestors()
{
    $(opt_parse "?child | pid of process whose ancestors will be printed.")
    [[ $# -gt 0 ]] && die "process_ancestors only accepts one child to check."

    [[ -z ${child} ]] && child=${BASHPID}

    local ps_all=""
    ps_all=$(ps -eo ppid,pid)

    local parent=${child}
    local ancestors=()
    while [[ ${parent} -gt 1 ]] ; do
        parent=$(echo "${ps_all}" | awk '$2 == '${parent}' {print $1}')
        ancestors+=( ${parent} )
    done

    echo "${ancestors[@]}"
}

opt_usage ekill <<'END'
Kill all pids provided as arguments to this function using the specified signal. This function is best effort only. It
makes every effort to kill all the specified pids but ignores any errors while calling kill. This is largely due to the
fact that processes can exit before we get a chance to kill them. If you really care about processes being gone consider
using process_not_running or cgroups.
END
ekill()
{
    $(opt_parse \
        ":signal sig s=SIGTERM | The signal to send to specified processes, either as a number or a signal name.
                                 Default is SIGTERM." \
        ":kill_after k         | Elevate to SIGKILL after waiting for this duration after sending the initial signal.
                                 Accepts any duration that sleep would accept. By default no elevated signal is sent" \
        "@processes            | Process IDs of processes to signal.")

    # Don't kill init, unless init has been replaced by our parent bash script in which case we really do want to kill
    # it.
    if [[ $$ -ne 1 ]] ; then
        array_remove processes 1
        array_empty processes && { edebug "nothing besides init to kill." ; return 0 ; }
    fi


    # When debugging, display the full list of processes to kill
    if edebug_enabled ; then
        edebug "killing $(lval signal processes kill_after) BASHPID=${BASHPID}"

        # Print some process info for any processes that are still alive
        ps -o "pid,user,start,command" -p $(array_join processes ',') | tail -n +2 >&2 || true
    fi

    # Kill all requested PIDs using requested signal.
    kill -${signal} "${processes[@]}" &>/dev/null || true

    if [[ -n ${kill_after} && $(signame ${signal}) != "KILL" ]] ; then
        # Note: double fork here in order to keep ekilltree from paying any attention to these processes.
        (
            :
            (
                close_fds
                disable_die_parent

                sleep ${kill_after}

                kill -SIGKILL "${processes[@]}" &>/dev/null || true
            ) &
        ) &
    fi
}


opt_usage ekilltree <<'END'
Kill entire process tree for each provided pid by doing a depth first search to find all the descendents of each pid and
kill all leaf nodes in the process tree first. Then it walks back up and kills the parent pids as it traverses back up
the tree. Like `ekill`, this function is best effort only. If you want more robust guarantees consider
process_not_running or cgroups.

Note that ekilltree will never kill the current process or ancestors of the current process, as that would cause
ekilltree to be unable to succeed.
END
ekilltree()
{
    $(opt_parse \
        ":signal sig s=SIGTERM | The signal to send to the process tree, either as a number or a name." \
        ":exclude x            | Processes to exclude from being killed." \
        ":kill_after k         | Elevate to SIGKILL after this duration if the processes haven't died." \
        "@pids                 | IDs of processes to be affected. All of these plus their children will receive the
                                 specified signal.")

    # Determine what signal to send to the processes
    local excluded="" processes=()

    excluded="$(process_ancestors ${BASHPID}) ${exclude}"
    processes=( $(process_tree "${pids[@]:-}") )
    array_remove -a processes ${excluded}

    edebug "Killing $(lval processes signal kill_after excluded)"
    if array_empty processes; then
        return 0
    fi

    # Kill all requested PIDs using requested signal.
    # WARNING: Do not just blindly use `kill` here on all the processes as that is non-deterministic in the order the
    # processes get killed and we need to honor the tree ordering of the processes so that we kill the leaf nodes first
    # and walk up the tree.
    local pid
    for pid in "${processes[@]}"; do
        edebug "Killing $(lval pid) of $(lval processes)"
        ekill -s=${signal} -k=${kill_after} ${pid}
    done

    return 0
}
