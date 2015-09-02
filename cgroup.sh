#!/bin/bash

# Copyright 2015, SolidFire, Inc. All rights reserved.

source "${BASHUTILS}/efuncs.sh"   || { echo "Failed to find efuncs.sh" ; exit 1; }

#-------------------------------------------------------------------------------
# Cgroups are a capability of the linux kernel designed for categorizing
# processes.  They're most typically used in ways that not only categorize
# processes, but also control them in some fasion.  A popular reason is to
# limit the amount of resources a particular process can use.
#
# Within each of many different _subsystems_ that are set up by code in the
# kernel, a process may exist at one point in a hierarchy.  That is, within the
# CPU subsystem, a process may only be owned by a single cgroup.  And in the
# memory subsystem, it may be owned by a different cgroup.  For the purposes of
# THIS bashutils code, though, we duplicate a similar tree of groups within
# _all_ of the subsystems that we interact with.
#
# CGROUP_SUBSYSTEMS defines which subsystems those are. So when you use these
# functions, the hierarchy that you create is created in parallel under all of
# the subsystems defined by CGROUP_SUBSYSTEMS
#
# Positions within the cgroup hierarchy created here are identified by names
# that look like relative directories.  This is no accident -- cgroups are
# represented to the kernel by a directory structure created within a
# filesystem of type cgroups.
#
# Hopefully these functions make accessing the cgroups filesystem a little bit
# easier, and also help you to keep parallel hierarchies identical across the
# various cgroups subsystems.
#
#-------------------------------------------------------------------------------

CGROUP_SUBSYSTEMS=(cpu memory freezer)

#-------------------------------------------------------------------------------
# Move one or more processes to a specific cgroup.  Once added, all (future)
# children of that process will also automatically go into that cgroup.
#
# It's worth noting that _all_ pids live in exactly one place in each cgroup
# subsystem.  By default, processes are started in the cgroup of their parent
# (which by default is the root of the cgroup hierarchy).  If you'd like to
# remove a process from your cgroup, you should simply move it up to that root
# (i.e. cgroup_move "/" $pid)
#
#
# $1:   The name of a cgroup (e.g. distbox/distcc or colorado/denver or alpha)
# rest: PIDs of processes to add to that cgroup (NOTE: empty strings are
#       allowed, but have no effect on cgroups)
#
# Example:
#      cgroup_move distbox $$
#
cgroup_move()
{
    $(declare_args cgroup)
    cgroup_create ${cgroup}

    local pids=( "${@}" )

    array_remove -a pids ""

    if [[ $(array_size pids) -gt 0 ]] ; then
        for subsystem in ${CGROUP_SUBSYSTEMS[@]} ; do
            local tmp
            tmp="$(array_join_nl pids)"
            edebug "$(lval pids tmp)"
            echo -e "${tmp}" > /sys/fs/cgroup/${subsystem}/${cgroup}/tasks
        done
    fi
}

#-------------------------------------------------------------------------------
# Change the value of a cgroups subsystem setting for the specified cgroup.
# For instance, by using the memory subsystem, you could limit the amount of
# memory used by all pids underneath the distbox hierarchy like this:
#
#     cgroup_set distbox memory.kmem.limit_in.bytes $((4*1024*1024*1024))
#
#  $1: Name of the cgroup (e.g. distbox/distcc or fruit/apple or fruit)
#  $2: Name of the subsystem-specific setting
#  $3: Value that should be assigned to that subsystem-specific setting
#
cgroup_set()
{
    $(declare_args cgroup setting value)
    cgroup_create ${cgroup}

    echo "${value}" > $(cgroup_find_setting_file ${cgroup} ${setting})
}

#-------------------------------------------------------------------------------
# Read the existing value of a subsystem-specific cgroups setting for the
# specified cgroup.  See cgroup_set for more info
#
# $1: Name of the cgroup (i.e. distbox/dtest or usa/colorado)
# $2: Name of the subsystem-specific setting (e.g. memory.kmem.limit_in.bytes)
#
cgroup_get()
{
    $(declare_args cgroup setting)
    cat $(cgroup_find_setting_file ${cgroup} ${setting})
}

#-------------------------------------------------------------------------------
# Recursively find all of the pids that live underneath a specified portion of
# the cgorups hierarchy.
#
# $1: Name of the cgroup (e.g. flintstones/barney or distbox/sshd)
#
# Options:
#       -x=space separated list of pids not to return -- default is to return
#          all
#
cgroup_pids()
{
    $(declare_args cgroup)

    local subsystem_paths=()
    for subsystem in "${CGROUP_SUBSYSTEMS[@]}" ; do
        subsystem_paths+=("/sys/fs/cgroup/${subsystem}/${cgroup}")
    done

    local all_pids ignorepids file files

    array_init ignorepids "$(opt_get x)"
    array_init files "$(find "${subsystem_paths[@]}" -name tasks)"
    [[ $(array_size files) -gt 0 ]] || die "Unable to find cgroup ${cgroup}"
    
    for subsystem_file in "${files[@]}" ; do
        local subsystem_pids

        # NOTE: It's very important to not create another process while reading
        # the tasks file, because if your process is running in the cgroup
        # being checked, its pid will be there during this command but
        # disappear before it returns
        #
        # It is also safe to ignore failures here, because these files are set
        # up by the kernel.  Read fails if the file is empty, but that is a
        # perfectly valid situation to be in. It just means the cgroup is
        # empty.  And we shouldn't see other failures because we "trust" the
        # kernel
        readarray -t subsystem_pids < "${subsystem_file}"

        array_empty subsystem_pids || all_pids+=( "${subsystem_pids[@]}" )
    done

    array_sort -u all_pids
    array_remove -a all_pids "${ignorepids[@]:-}"

    edebug "Found pids $(lval all_pids) after exceptions ${ignorepids[@]:-}"
    echo "${all_pids[@]:-}"
}

#-------------------------------------------------------------------------------
# Run ps on all of the processes in a cgroup.
#
# Options:
#       -x=space separated list of pids not to list.  By default all are listed.
#
cgroup_ps()
{
    $(declare_args cgroup)

    local pid cgroup_pids
    cgroup_pids=$(cgroup_pids -x="${BASHPID} $(opt_get x)" ${cgroup})
    for pid in ${cgroup_pids} ; do
        ps hp ${pid}
    done
}

#-------------------------------------------------------------------------------
# Recursively KILL (or send a signal to) all of the pids that live underneath a
# specified portion of the cgorups hierarchy.
#
# $1: Name of the cgroup (e.g. flintstones/barney or distbox/sshd)
#
# Options:
#       -s=<signal>
#       -x=space separated list of pids not to kill.  NOTE: $$ and $BASHPID are
#          always added to this list so as to not kill the calling process
#
cgroup_kill()
{
    $(declare_args cgroup)

    local ignorepids pids

    ignorepids="$(opt_get x)"
    ignorepids+=" $$ ${BASHPID}"

    # NOTE: BASHPID must be added here in addition to above because it's
    # different inside this command substituion (subshell) than it is outside.
    array_init pids "$(cgroup_pids -x="${ignorepids} ${BASHPID}" ${cgroup})"

    edebug "Killing pids in cgroup $(lval cgroup pids ignorepids)"
    local signal
    signal=$(opt_get s SIGTERM)

    # Ignoring errors here because we don't want to die simply because a
    # process that was in the cgroup disappeared of its own volition before we
    # got around to killing it.
    #
    # NOTE: This also has the side effect of causing cgroup_kill to NOT fail
    # when the calling user doesn't have permission to kill everything in the
    # cgroup.
    [[ -z ${pids[@]:-} ]] || ekill -s=${signal} ${pids} || true
}

#-------------------------------------------------------------------------------
# Ensure that no processes are running in the specified cgroup by killing all
# of them and waiting until the group is empty.
#
# NOTE: This probably won't work well if your script is already in that cgroup.
#
# ALSO NOTE: Contrary to other kill functions, this one defaults to SIGKILL.
#
# Options:
#       -s=<signal>
#       -x=space separated list of pids not to kill.  NOTE: $$ and $BASHPID are
#          always added to this list to avoid killing the calling process.
#   
cgroup_kill_and_wait()
{
    $(declare_args cgroup)
    edebug "Ensuring that there are no processes in ${cgroup}."
    cgroup_create "${cgroup}"

    # Don't need to add $$ and $BASHPID to ignorepids here because cgroup_kill
    # will do that for me
    local ignorepids
    ignorepids=$(opt_get x)

    local times=0
    while true ; do
        cgroup_kill -x="${ignorepids} ${BASHPID}" -s=$(opt_get s SIGKILL) "${cgroup}"

        local remaining_pids
        remaining_pids=$(cgroup_pids -x="${ignorepids} ${BASHPID}" "${cgroup}")
        if [[ -z ${remaining_pids} ]] ; then
            break;
        else
            sleep .5
        fi

        (( times += 1 ))
        if ((times % 20 == 0 )) ; then
            ewarn "Still trying to kill processes in cgroup. $(lval cgroup remaining_pids)"
        fi

    done

    local pidsleft
    pidsleft=$(cgroup_pids -x="${ignorepids} ${BASHPID}" ${cgroup})
    [[ -z ${pidsleft} ]] || die "Internal error -- processes (${pidsleft}) remain in ${cgroup}"
}

cgroup_find_setting_file()
{
    $(declare_args cgroup setting)
    ls /sys/fs/cgroup/*/${cgroup}/${setting}
}

# This function is mostly internal.  Other cgroups functions use it to create
# the cgroup hierarchy on demand.
cgroup_create()
{
    for cgroup in "${@}" ; do

        for subsystem in ${CGROUP_SUBSYSTEMS[@]} ; do
            local subsys_path=/sys/fs/cgroup/${subsystem}/${cgroup}
            mkdir -p ${subsys_path}
        done

    done
}

