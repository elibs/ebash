#!/bin/bash
#
# Copyright 2011-2016, SolidFire, Inc. All rights reserved.
#


# This is a simple override of the linux pstree command.  The trouble with that
# command is that it likes to segfault.  It's buggy.  So here, we simply ignore
# the error codes that would come from it.
#
if [[ ${__BU_OS} == Linux ]] ; then
    pstree()
    {
        (
            ulimit -c 0
            command pstree "${@}" || true
        )
    }
fi

# Check if a given process is running. Returns success (0) if all of the
# specified processes are running and failure (1) otherwise.
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

# Check if a given process is NOT running. Returns success (0) if all of the
# specified processes are not running and failure (1) otherwise.
process_not_running()
{
    local pid
    for pid in "${@}" ; do
        if ps -p ${pid} &>/dev/null ; then
            return 1
        fi
    done
    return 0
}

# Generate a depth first recursive listing of entire process tree beneath a given PID.
# If the pid does not exist this will produce an empty string.
#
process_tree()
{
    $(opt_parse \
        ":ps_all | Pre-prepared output of \"ps -eo ppid,pid\" so I can avoid calling ps repeatedly")
    : ${ps_all:=$(ps -eo ppid,pid)}


    # Assume current process if none is specified
    if [[ ! $# -gt 0 ]] ; then
        set -- ${BASHPID}
    fi

    local parent
    for parent in ${@} ; do

        echo ${parent}

        local children=$(process_children --ps-all "${ps_all}" ${parent})
        local child
        for child in ${children} ; do
            process_tree --ps-all "${ps_all}" "${child}"
        done

    done
}

# Print the pids of all children of the specified list of processes.  If no
# processes were specified, default to ${BASHPID}.
#
# Note, this doesn't print grandchildren and other descendants.  Just children.
# See process_tree for a recursive tree of descendants.
#
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

# Print the pid of the parent of the specified process, or of $BASHPID if none
# is specified.
#
process_parent()
{
    $(opt_parse "?child | pid of child process")
    [[ $# -gt 0 ]] && die "process_parent only accepts one child to check."

    : ${child:=${BASHPID}}

    ps -eo ppid,pid | awk '$2 == '${child}' {print $1}'
}

# Print pids of all ancestores of the specified list of processes, up to and
# including init (pid 1).  If no processes are specified as arguments, defaults
# to ${BASHPID}
#
process_ancestors()
{
    $(opt_parse "?child | pid of process whose ancestors will be printed.")
    [[ $# -gt 0 ]] && die "process_ancestors only accepts one child to check."

    [[ -z ${child} ]] && child=${BASHPID}

    local ps_all=$(ps -eo ppid,pid)

    local parent=${child}
    local ancestors=()
    while [[ ${parent} != 1 ]] ; do
        parent=$(echo "${ps_all}" | awk '$2 == '${parent}' {print $1}')
        ancestors+=( ${parent} )
    done

    echo "${ancestors[@]}"
}

# Kill all pids provided as arguments to this function using the specified signal. This function is
# best effort only. It makes every effort to kill all the specified pids but ignores any errors
# while calling kill. This is largely due to the fact that processes can exit before we get a chance
# to kill them. If you really care about processes being gone consider using process_not_running or
# cgroups.
#
# Options:
# -s=SIGNAL The signal to send to the pids (defaults to SIGTERM).
# -k=duration 
#   Elevate to SIGKILL after waiting for the specified duration after sending
#   the initial signal.  If unspecified, ekill does not elevate.
ekill()
{
    $(opt_parse \
        ":signal sig s=SIGTERM | The signal to send to specified processes, either as a number or a
                                 signal name.  Default is SIGTERM." \
        ":kill_after k         | Elevate to SIGKILL after waiting for this duration after sending
                                 the initial signal. Accepts any duration that sleep would accept.
                                 By default no elevated signal is sent" \
        "@processes            | Process IDs of processes to signal.")

    # Don't kill init, unless init has been replaced by our parent bash script
    # in which case we really do want to kill it.
    if [[ $$ != "1" ]] ; then
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
    kill -${signal} ${processes[@]} &>/dev/null || true

    if [[ -n ${kill_after} && $(signame ${signal}) != "KILL" ]] ; then
        # Note: double fork here in order to keep ekilltree from paying any
        # attention to these processes.
        (
            :
            (
                close_fds
                disable_die_parent

                sleep ${kill_after}
                kill -SIGKILL ${processes[@]} &>/dev/null || true
            ) &
        ) &
    fi
}

# Kill entire process tree for each provided pid by doing a depth first search to find
# all the descendents of each pid and kill all leaf nodes in the process tree first.
# Then it walks back up and kills the parent pids as it traverses back up the tree.
# Like ekill(), this function is best effort only. If you want more robust guarantees
# consider process_not_running or cgroups.
#
# Note that ekilltree will never kill the current process or ancestors of the
# current process, as that would cause ekilltree to be unable to succeed.

# Options:
# -s=SIGNAL 
#       The signal to send to the pids (defaults to SIGTERM).
# -x="pids"
#       Pids to exclude from killing.  Ancestors of the current process are
#       _ALWAYS_ excluded (because if not, it would likely prevent ekilltree
#       from succeeding)
# -k=duration 
#       Elevate to SIGKILL after waiting for the specified duration after
#       sending the initial signal.  If unspecified, ekilltree does not
#       elevate.
#
ekilltree()
{
    $(opt_parse \
        ":signal sig s=SIGTERM | The signal to send to the process tree, either as a number or a name." \
        ":exclude x            | Processes to exclude from being killed." \
        ":kill_after k         | Elevate to SIGKILL after this duration if the processes haven't died.")

    # Determine what signal to send to the processes
    local excluded="$(process_ancestors ${BASHPID}) ${exclude}"

    local processes=( $(process_tree ${@}) )
    array_remove -a processes ${excluded}

    edebug "Killing $(lval processes signal kill_after excluded)"
    if array_not_empty processes ; then
        ekill -s=${signal} -k=${kill_after} "${processes[@]}"
    fi

    return 0
}

return 0
