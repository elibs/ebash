#!/bin/bash

# Copyright 2015, SolidFire, Inc. All rights reserved.

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
# Detect whether the machine currently running this code is built with kernel
# support for all of the cgroups subsystems that bashutils depends on.
#
cgroup_supported()
{
    local subsystem missing_count=0
    for subsystem in "${CGROUP_SUBSYSTEMS[@]}" ; do
        if ! grep -qw "^${subsystem}" /proc/cgroups ; then
            edebug "Missing support for ${subsystem}"
            (( missing_count += 1 ))
        fi
    done

    return ${missing_count}
}


#-------------------------------------------------------------------------------
# Prior to using a cgroup, you must create it.  It is safe to attempt to
# "create" a cgroup that already exists.
#
cgroup_create()
{
    edebug "creating cgroups ${@}"
    for cgroup in "${@}" ; do

        for subsystem in ${CGROUP_SUBSYSTEMS[@]} ; do
            local subsys_path=/sys/fs/cgroup/${subsystem}/${cgroup}
            mkdir -p ${subsys_path}
        done

    done
}


#-------------------------------------------------------------------------------
# If you want to get rid of a cgroup, you can do so by calling cgroup_destroy.
#
# NOTE: It is an error to try to destroy a cgroup that contains any processes
# or any child cgroups.  You can use cgroup_kill_and_wait to ensure that they
# are if you like.
#
# Options:
#   -r: Destroy cgroup as well as all of its children.
#
cgroup_destroy()
{
    $(declare_args)

    local msg
    msg="destroying cgroups ${@}"
    opt_false r || msg+=" recursively"
    edebug "${msg}"

    for cgroup in "${@}" ; do

        for subsystem in ${CGROUP_SUBSYSTEMS[@]} ; do

            local subsys_path=/sys/fs/cgroup/${subsystem}/${cgroup}
            [[ -d ${subsys_path} ]] || { edebug "Skipping ${subsys_path} that is already gone." ; continue ; }

            if opt_true "r" ; then
                find ${subsys_path} -depth -type d -exec rmdir {} \;
            else
                rmdir ${subsys_path}
            fi

        done

    done
}


#-------------------------------------------------------------------------------
# Returns true if all specified cgroups exist.  In other words, they have been
# created via cgroup_create but have not yet been removed with cgroup_destroy)
#
cgroup_exists()
{
    local all missing_cgroups cgroup subsys
    all=("${@}")
    missing_cgroups=()

    for cgroup in "${all[@]}" ; do

        for subsys in "${CGROUP_SUBSYSTEMS[@]}" ; do
            if [[ ! -d /sys/fs/cgroup/${subsys}/${cgroup} ]] ; then
                missing_cgroups+=("${subsys}:${cgroup}")
            fi
        done

    done

    edebug "cgroup_exists: $(lval all cgroup missing_cgroups CGROUP_SUBSYSTEMS)"
    if [[ $(array_size missing_cgroups) -eq $(( $(array_size CGROUP_SUBSYSTEMS) * $(array_size all) )) ]] ; then
        edebug "Cgroup doesn't exist in any subsystems $(lval cgroup)"
        return 1

    elif [[ $(array_size missing_cgroups) -gt 0 ]] ; then
        ewarn "Cgroup is inconsistent across subsystems $(lval cgroup CGROUP_SUBSYSTEMS, missing_subsystems)"
        return 2

    else
        return 0
    fi
}


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

    local pids=( "${@}" )

    array_remove -a pids ""

    if [[ $(array_size pids) -gt 0 ]] ; then
        for subsystem in ${CGROUP_SUBSYSTEMS[@]} ; do
            local tmp="$(array_join_nl pids)"
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
# Recursively find all of the pids that live underneath a set of sections in
# the cgorups hierarchy.  You may specify as many different cgroups as you
# like, and the processes in those cgroups AND THEIR CHILDREN will be echoed to
# stdout.
#
# Cgroup_pids will return success as long as all of the specified cgroups
# exist, and failure if they do not (but it will still echo pids for any
# cgroups that _do_ exist).  On failure, it returns the number of specified
# cgroups that did not exist.
#
# Options:
#       -x=space separated list of pids not to return -- default is to return
#          all
#
cgroup_pids()
{
    $(declare_args)

    local cgroups cgroup ignorepids all_pids rc
    cgroups=( ${@} )
    rc=0

    array_init ignorepids "$(opt_get x)"

    for cgroup in "${cgroups[@]}" ; do
        local subsystem_paths=()
        for subsystem in "${CGROUP_SUBSYSTEMS[@]}" ; do
            subsystem_paths+=("/sys/fs/cgroup/${subsystem}/${cgroup}")
        done

        local files file
        if opt_true r ; then
            array_init files "$(find "${subsystem_paths[@]}" -depth -name tasks 2>/dev/null)"
        else
            for file in "${subsystem_paths[@]}" ; do
                [[ -e ${file} ]] && files+=("${file}/tasks") || true
            done
        fi

        if ! [[ $(array_size files) -gt 0 ]] ; then
            edebug "cgroup_pids is unable to find cgroup ${cgroup}"
            (( rc += 1 ))
            continue
        else
            edebug "looking for processes $(lval cgroup files)"
        fi

        local subsystem_file 
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

            array_empty subsystem_pids || all_pids+="${subsystem_pids[@]} "
        done

    done

    # Take all of the found pids, sort and remove duplicates, and grep away the ignored pids.
    #
    # NOTE: I could use array_sort -u and array_remove for this, but they're
    # really slow for large arrays.  They're nice when you need to worry about
    # not losing whitespace (esp newlines) in your array, but I know there are
    # just pids so in this case I use the much faster command here.  As of
    # 2015-09-16, array_sort/array_remove takes multiple seconds for a cgroup
    # containing 2k processes, while the following command is nearly
    # instantaneous.
    #
    local found_pids
    local ignore_regex="($(echo "${ignorepids[@]:-}" | tr ' ' '\n' | paste -sd\|))"
    [[ -z "${all_pids:-}" ]]                    \
        || found_pids=($(echo "${all_pids}"     \
            | tr ' ' '\n'                       \
            | sort -u                           \
            | egrep -vw "${ignore_regex}"))

    edebug "$(lval all_pids found_pids ignorepids ignore_regex )"
    echo "${found_pids[@]:-}"
    return "${rc}"
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

    local options=()
    opt_true r && options+=("-r")

    local pid cgroup_pids
    cgroup_pids=($(cgroup_pids ${options[@]:-} -x="${BASHPID} $(opt_get x)" ${cgroup}))

    array_empty cgroup_pids && return 0

    edebug "Done with cgroup_pids"

    # Put together an awk regex that will match any of those pids as long as
    # it's the whole string
    local awk_regex='^('$(array_join cgroup_pids '|')')$'

    edebug "$(lval awk_regex)"

    ps -e --format pid,start,nlwp,nice,command ${COLUMNS+--columns ${COLUMNS}} --forest | awk 'NR == 1 ; match($1,/'${awk_regex}'/) { print }'
}


#-------------------------------------------------------------------------------
# Return all items in the cgroup hierarchy.  By default this will echo to
# stdout all directories in the cgroup hierarchy.  You may optionally specify
# one or more cgroups and then only those cgroups descended from them it will
# be returned.
#
# For example, if you've run this cgroup_create command...
#    cgroup_create a/{1,2,3} b/{10,20} c
#
# Cgroup_tree will produce output as follows:
#
#    % cgroup_tree 
#    a/1 a/2 a/3 b/10 b/20 c
#
#    % cgroup_tree a
#    a/1 a/2 a/3
#
#    % cgroup_tree b c
#    b/10 b/20 c
#
cgroup_tree()
{
    $(declare_args)
    local cgroups=("${@}")

    # If none were specified, we'll start at cgroup root
    [[ $(array_size cgroups) -gt 0 ]] || cgroups=("")

    local cgroup found_cgroups=()
    for cgroup in "${cgroups[@]}" ; do

        local subsys
        for subsys in "${CGROUP_SUBSYSTEMS[@]}" ; do

            # Pick out the paths to the subsystem and the cgroup within it --
            # and because we'll be text processing the result, be sure there
            # are not multiple sequential slashes in the output
            local subsys_path=$(echo /sys/fs/cgroup/${subsys}/ | sed 's#/\+#/#g')
            local cgroup_path=$(echo ${subsys_path}/${cgroup}/ | sed 's#/\+#/#g')

            edebug $(lval subsys_path cgroup_path)

            # Then find all the directories inside the cgroup path (while
            # stripping off the part contributed by the subsystem) and again
            # reduce multiple slashes to only one
            array_add found_cgroups \
                "$(find ${subsys_path}/${cgroup} -type d | sed -e 's#/\+#/#g' -e 's#^'${subsys_path}'##' )"
        done

    done

    array_sort -u found_cgroups
    edebug "cgroups_tree $(lval cgroups found_cgroups)"
    echo "${found_cgroups[@]:-}"
}



#-------------------------------------------------------------------------------
# Display a graphical representation of all cgroups descended from those
# specified as arguments.
#
cgroup_pstree()
{
    $(declare_args)

    local cgroup
    for cgroup in $(cgroup_tree "${@}") ; do

        # Note: must subtract 3 from columns here to account for the three
        # characters added to the string below (i.e. "|  ")
        local cols=$(( ${COLUMNS:-120} - 3 ))
        local ps_output=$(COLUMNS=${cols} cgroup_ps ${cgroup})
        local count=$(( $(echo "${ps_output}" | wc -l) - 1 ))

        echo "$(ecolor green)+--${cgroup} [${count}]$(ecolor off)"

        echo "${ps_output}" | sed 's#^#'$(ecolor green)\|$(ecolor off)\ \ '#g'

    done >&2
}


#-------------------------------------------------------------------------------
# Recursively KILL (or send a signal to) all of the pids that live underneath
# all of the specified cgroups (and their children!).  Accepts any number of
# cgroups.
#
# Options:
#       -s=<signal>
#       -x=space separated list of pids not to kill.  NOTE: $$ and $BASHPID are
#          always added to this list so as to not kill the calling process
#
cgroup_kill()
{
    $(declare_args)
    local cgroups=( ${@} )

    [[ $(array_size cgroups) -gt 0 ]] || return 0

    local ignorepids pids

    ignorepids="$(opt_get x)"
    ignorepids+=" $$ ${BASHPID}"

    # NOTE: BASHPID must be added here in addition to above because it's
    # different inside this command substituion (subshell) than it is outside.
    array_init pids "$(cgroup_pids -r -x="${ignorepids} ${BASHPID}" ${cgroups[@]} || true)"

    if [[ $(array_size pids) -gt 0 ]] ; then
        edebug "Killing processes in cgroups $(lval cgroups pids ignorepids)"
        local signal=$(opt_get s SIGTERM)

        # Ignoring errors here because we don't want to die simply because a
        # process that was in the cgroup disappeared of its own volition before we
        # got around to killing it.
        #
        # NOTE: This also has the side effect of causing cgroup_kill to NOT fail
        # when the calling user doesn't have permission to kill everything in the
        # cgroup.
        ekill -s=${signal} ${pids[@]} || true
    else
        edebug "All processes in cgroup are already dead.  $(lval cgroups pids ignorepids)"
    fi
}

#-------------------------------------------------------------------------------
# Ensure that no processes are running all of the specified cgroups by killing
# all of them and waiting until the group is empty.
#
# NOTE: This probably won't work well if your script is already in that cgroup.
#
# Options:
#       -s=<signal>
#       -x=space separated list of pids not to kill.  NOTE: $$ and $BASHPID are
#          always added to this list to avoid killing the calling process.
#       -t=Maximum number of seconds to wait.  If processes still exist at this
#          point, an error will be returned instead of hanging forever.  The
#          default is zero, which means to WAIT FOREVER.
#   
cgroup_kill_and_wait()
{
    $(declare_args)
    local cgroups=( ${@} )
    local startTime=${SECONDS}
    local timeout=$(opt_get t 0)

    [[ $# -gt 0 ]] || return 0

    # Don't need to add $$ and $BASHPID to ignorepids here because cgroup_kill
    # will do that for me
    local ignorepids=$(opt_get x)

    edebug "Ensuring that there are no processes in $(lval cgroups ignorepids)."

    local times=0
    while true ; do
        cgroup_kill -x="${ignorepids} ${BASHPID}" -s=$(opt_get s SIGTERM) "${cgroups[@]}"

        local remaining_pids=$(cgroup_pids -r -x="${ignorepids} ${BASHPID}" "${cgroups[@]}" || true)
        if [[ -z ${remaining_pids} ]] ; then
            edebug "Done.  All processes in cgroup are gone.  $(lval cgroups ignorepids)"
            break
        else
            if [[ ${timeout} -gt 0 ]] && (( SECONDS - startTime > timeout )) ; then
                eerror "Tried to kill all processes in cgroup, but some remain.  Giving up after ${timeout} seconds.  $(lval cgroup remaining_pids)"
                return 1
            fi

            edebug_disabled || 
                for pid in ${remaining_pids} ; do
                    local ps_output="$(ps hp ${pid} 2>/dev/null || true)"
                    [[ -z ${ps_output} ]] || edebug "   ${ps_output}"
                done
            sleep .1
        fi

        (( times += 1 ))
        if ((times % 50 == 0 )) ; then
            ewarn "Still trying to kill processes. $(lval cgroups remaining_pids)"
        fi

    done
}


cgroup_find_setting_file()
{
    $(declare_args cgroup setting)
    ls /sys/fs/cgroup/*/${cgroup}/${setting}
}

return 0
