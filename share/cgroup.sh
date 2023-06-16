#!/bin/bash
#
# Copyright 2015-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2015-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
opt_usage module_cgroup <<'END'
Cgroups are a capability of the linux kernel designed for categorizing processes. They're most typically used in ways
that not only categorize processes, but also control them in some fasion. A popular reason is to limit the amount of
resources a particular process can use.

Within each of many different _subsystems_ that are set up by code in the kernel, a process may exist at one point in
a hierarchy. That is, within the CPU subsystem, a process may only be owned by a single cgroup. And in the memory
subsystem, it may be owned by a different cgroup. For the purposes of THIS ebash code, though, we duplicate a similar
tree of groups within _all_ of the subsystems that we interact with.

CGROUP_SUBSYSTEMS defines which subsystems those are. So when you use these functions, the hierarchy that you create
is created in parallel under all of the subsystems defined by CGROUP_SUBSYSTEMS

Positions within the cgroup hierarchy created here are identified by names that look like relative directories. This
is no accident -- cgroups are represented to the kernel by a directory structure created within a filesystem of type
cgroups.

Hopefully these functions make accessing the cgroups filesystem a little bit easier, and also help you to keep
parallel hierarchies identical across the various cgroups subsystems.

> **_NOTE:_** On Docker, The cgroups functions work when run within docker containers, operating on a cgroup inside the
one that docker set up for them. This requires said containers to be started with --privileged or suitable other
capabilities (which I have not investigated -- it could be done, though)
END
#-----------------------------------------------------------------------------------------------------------------------

# systemd altered how it mounts the default cgroup subsystems. So explicitly look for old and new naming conventions.
CGROUP_SYSFS=/sys/fs/cgroup
if [[ -e "${CGROUP_SYSFS}/cpu,cpuacct" ]]; then
    CGROUP_SUBSYSTEMS=(cpu,cpuacct memory freezer)
else
    CGROUP_SUBSYSTEMS=(cpu cpuacct memory freezer)
fi

opt_usage cgroup_supported <<'END'
Detect whether the machine currently running this code is built with kernel support for all of the cgroups subsystems
that ebash depends on.
END
cgroup_supported()
{
    if [[ ! -e /proc/cgroups ]] ; then
        edebug "No support for cgroups"
        return 1
    fi

    # Blacklist cgroup support on Alpine
    #
    # Cgroups are fundamentally broken on archive. Even though they are present and pass our other criteria we are
    # unable to create new cgroups on Alpine only as it fails with: ./bin/../share/cgroup.sh: line 191: echo: write
    # error: Invalid argument
    if os_distro alpine; then
        edebug "Cgroups do not work properly on alpine"
        return 1
    fi

    local subsystem missing_count=0
    for subsystem in "${CGROUP_SUBSYSTEMS[@]}" ; do
        if ! grep -q ":${subsystem}:" /proc/1/cgroup ; then
            edebug "Missing support for ${subsystem}"
            (( missing_count += 1 ))
        fi

        # If the subsystem is present but read-only then it's not useable.
        if [[ ! -w "/sys/fs/cgroup/${subsystem}" ]]; then
            edebug "Missing writeable support for ${subsystem}"
            (( missing_count += 1 ))
        fi
    done

    return ${missing_count}
}

[[ ${EBASH_OS} == Linux && -e /proc/cgroups ]] || return 0

# We may already be in a cgroup and if so we need to constrain ourselves to only operate within that root cgroup. If we
# are not in a cgroup at all, this will be just '/'. We filter out user.slice as that's not an actual cgroup we want
# to stay within.
CGROUP_ROOT="$(awk -F: '$2 == "'${CGROUP_SUBSYSTEMS[0]}'" {print $3}' /proc/$$/cgroup | sed 's|user.slice||')"

opt_usage cgroup_create <<'END'
Prior to using a cgroup, you must create it. It is safe to attempt to "create" a cgroup that already exists.
END
cgroup_create()
{
    edebug "creating cgroups ${*}"
    for cgroup in "${@}" ; do

        for subsystem in "${CGROUP_SUBSYSTEMS[@]}"; do
            local subsys_path=${CGROUP_SYSFS}/${subsystem}/${cgroup}
            mkdir -p ${subsys_path}
        done

    done
}

opt_usage cgroup_destroy <<'END'
If you want to get rid of a cgroup, you can do so by calling cgroup_destroy.

> **_NOTE:_**: It is an error to try to destroy a cgroup that contains any processes or any child cgroups. You can use
cgroup_kill_and_wait to ensure that they are if you like.
END
cgroup_destroy()
{
    $(opt_parse "+recursive r | Destroy cgroup's children recursively")

    local msg
    msg="destroying cgroups ${@}"
    [[ ${recursive} -eq 1 ]] && msg+=" recursively"
    edebug "${msg}"

    for cgroup in "${@}" ; do

        for subsystem in "${CGROUP_SUBSYSTEMS[@]}"; do

            local subsys_path=${CGROUP_SYSFS}/${subsystem}/${cgroup}
            [[ -d ${subsys_path} ]] || { edebug "Skipping ${subsys_path} that is already gone." ; continue ; }

            if [[ ${recursive} -eq 1 ]] ; then
                find ${subsys_path} -depth -type d -exec rmdir {} \;
            else
                rmdir ${subsys_path}
            fi

        done

    done
}

opt_usage cgroup_exists <<'END'
Returns true if all specified cgroups exist. In other words, they have been created via cgroup_create but have not yet
been removed with cgroup_destroy)
END
cgroup_exists()
{
    local all missing_cgroups cgroup subsys
    all=("${@}")
    missing_cgroups=()

    for cgroup in "${all[@]}" ; do

        for subsys in "${CGROUP_SUBSYSTEMS[@]}" ; do
            if [[ ! -d ${CGROUP_SYSFS}/${subsys}/${cgroup} ]] ; then
                missing_cgroups+=("${subsys}:${cgroup}")
            fi
        done

    done

    edebug "cgroup_exists: $(lval all cgroup missing_cgroups CGROUP_SUBSYSTEMS)"
    if (( ${#missing_cgroups[@]} == ${#CGROUP_SUBSYSTEMS[@]} * ${#all[@]} )) ; then
        edebug "Cgroup doesn't exist in any subsystems $(lval cgroup)"
        return 1

    elif [[ $(array_size missing_cgroups) -gt 0 ]] ; then
        ewarn "Cgroup is inconsistent across subsystems $(lval cgroup CGROUP_SUBSYSTEMS, missing_subsystems)"
        return 2

    else
        return 0
    fi
}

opt_usage cgroup_move <<'END'
Move one or more processes to a specific cgroup. Once added, all (future) children of that process will also
automatically go into that cgroup.

It's worth noting that _all_ pids live in exactly one place in each cgroup subsystem. By default, processes are started
in the cgroup of their parent (which by default is the root of the cgroup hierarchy). If you'd like to remove a process
from your cgroup, you should simply move it up to that root (i.e. cgroup_move "/" $pid)
END
cgroup_move()
{
    $(opt_parse \
        "cgroup | Name of a cgroup which should already have been created." \
        "@pids  | IDs of processes to move. Empty strings are allowed and ignored.")

    array_remove -a pids ""

    edebug "$(lval pids cgroup)"
    if array_not_empty pids ; then
        local tmp
        for subsystem in "${CGROUP_SUBSYSTEMS[@]}"; do
            tmp="$(array_join_nl pids)"
            echo -e "${tmp}" > ${CGROUP_SYSFS}/${subsystem}/${cgroup}/tasks
        done
    fi
}

opt_usage cgroup_set <<'END'
Change the value of a cgroups subsystem setting for the specified cgroup. For instance, by using the memory subsystem,
you could limit the amount of memory used by all pids underneath the distbox hierarchy like this:

```shell
cgroup_set distbox memory.kmem.limit_in.bytes $((4*1024*1024*1024))
```
END
cgroup_set()
{
    $(opt_parse \
        "cgroup  | Name of the cgroup (e.g. distbox/distcc or fruit/apple or fruit)" \
        "setting | Name of the subsystem-specific setting" \
        "value   | Value that should be assined to that subsystem-specific setting")

    echo "${value}" > $(cgroup_find_setting_file ${cgroup} ${setting})
}

opt_usage cgroup_get <<'END'
Read the existing value of a subsystem-specific cgroups setting for the specified cgroup. See cgroup_set for more info
END
cgroup_get()
{
    $(opt_parse \
        "cgroup  | Name of the cgroup (e.g distbox/dtest or usa/colorado)" \
        "setting | Name of the subsystem-specific setting e.g. memory.kmem.limit_in.bytes)")

    cat $(cgroup_find_setting_file ${cgroup} ${setting})
}

opt_usage cgroup_pids <<'END'
Recursively find all of the pids that live underneath a set of sections in the cgorups hierarchy. You may specify as
many different cgroups as you like, and the processes in those cgroups AND THEIR CHILDREN will be echoed to stdout.

Cgroup_pids will return success as long as all of the specified cgroups exist, and failure if they do not (but it will
still echo pids for any cgroups that _do_ exist). On failure, it returns the number of specified cgroups that did not
exist.
END
cgroup_pids()
{
    $(opt_parse \
        ":exclude x   | Space separated list of pids not to return. By default returns all." \
        "+recursive r | Additionally return pids for processes of this cgroup's children." \
        "@cgroups     | Cgroups whose processes should be listed.")

    local cgroups cgroup ignorepids all_pids rc
    rc=0

    array_init ignorepids "${exclude}"

    for cgroup in "${cgroups[@]}" ; do
        local subsystem_paths=()
        for subsystem in "${CGROUP_SUBSYSTEMS[@]}" ; do
            subsystem_paths+=("$(readlink -m ${CGROUP_SYSFS}/${subsystem}/${cgroup})")
        done

        local files file
        if [[ ${recursive} -eq 1 ]] ; then
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
            edebug "looking for processes $(lval cgroup)"
        fi

        local subsystem_file
        for subsystem_file in "${files[@]}" ; do
            local subsystem_pids

            # NOTE: It's very important to not create another process while reading the tasks file, because if your
            # process is running in the cgroup being checked, its pid will be there during this command but disappear
            # before it returns
            #
            # It is also safe to ignore failures here, because these files are set up by the kernel. Read fails if the
            # file is empty, but that is a perfectly valid situation to be in. It just means the cgroup is empty. And
            # we shouldn't see other failures because we "trust" the kernel
            readarray -t subsystem_pids < "${subsystem_file}"

            array_empty subsystem_pids || all_pids+="${subsystem_pids[@]} "
        done

    done

    # Take all of the found pids, sort and remove duplicates, and grep away the ignored pids.
    #
    # NOTE: I could use array_sort -u and array_remove for this, but they're really slow for large arrays. They're nice
    # when you need to worry about not losing whitespace (esp newlines) in your array, but I know there are just pids so
    # in this case I use the much faster command here. As of 2015-09-16, array_sort/array_remove takes multiple seconds
    # for a cgroup containing 2k processes, while the following command is nearly instantaneous.
    local found_pids=() ignore_regex=""
    ignore_regex="($(echo "${ignorepids[@]:-}" | tr ' ' '\n' | paste -sd\|))"
    if [[ -n "${all_pids:-}" ]]; then
        found_pids=( $(echo "${all_pids}" | tr ' ' '\n' | sort -u | grep -E -vw "${ignore_regex}") )
    fi

    edebug "$(lval found_pids ignorepids ignore_regex)"
    echo "${found_pids[@]:-}"
    return "${rc}"
}

opt_usage cgroup_ps <<'END'
Run ps on all of the processes in a cgroup.
END
cgroup_ps()
{
    $(opt_parse \
        ":exclude x   | Space separated list of pids not to display." \
        "+recursive r | List processes for specified cgroup and all children." \
        "cgroup       | Name of cgroup to examine.")

    local options=()
    [[ ${recursive} -eq 1 ]] && options+=("-r")

    local pid cgroup_pids
    cgroup_pids=($(cgroup_pids "${options[@]:-}" -x="${BASHPID} ${exclude}" "${cgroup}"))

    array_empty cgroup_pids && return 0

    edebug "Done with cgroup_pids"

    # Put together an awk regex that will match any of those pids as long as
    # it's the whole string
    local awk_regex
    awk_regex='^('$(array_join cgroup_pids '|')')$'

    edebug "$(lval awk_regex)"

    ps -e --format pid,ppid,start,nlwp,nice,stat,command ${COLUMNS+--columns ${COLUMNS}} --forest | awk 'NR == 1 ; match($1,/'${awk_regex}'/) { print }'
}

opt_usage cgroup_tree <<'END'
Return all items in the cgroup hierarchy. By default this will echo to stdout all directories in the cgroup hierarchy.
You may optionally specify one or more cgroups and then only those cgroups descended from them it will be returned.

For example, if you've run this cgroup_create command:

```shell
cgroup_create a/{1,2,3} b/{10,20} c
```

`cgroup_tree` will produce output as follows:

```
$ cgroup_tree
a/1 a/2 a/3 b/10 b/20 c

$ cgroup_tree a
a/1 a/2 a/3

$ cgroup_tree b c
b/10 b/20 c
```
END
cgroup_tree()
{
    $(opt_parse "@cgroups")

    # If none were specified, we'll start at cgroup root
    [[ $(array_size cgroups) -gt 0 ]] || cgroups=("")

    local cgroup found_cgroups=()
    for cgroup in "${cgroups[@]}" ; do

        local subsys subsys_path cgroup_path
        for subsys in "${CGROUP_SUBSYSTEMS[@]}" ; do

            # Pick out the paths to the subsystem and the cgroup within it -- and because we'll be text processing the
            # result, be sure there are not multiple sequential slashes in the output
            subsys_path=$(readlink -m ${CGROUP_SYSFS}/${subsys}/)
            cgroup_path=$(readlink -m ${subsys_path}/${cgroup}/)

            # Then find all the directories inside the cgroup path (while stripping off the part contributed by the
            # subsystem) and again reduce multiple slashes to only one
            array_add found_cgroups \
                "$(find "${cgroup_path}" -type d | sed -e 's#^'${subsys_path}/'##' )"

            edebug $(lval subsys_path cgroup_path)

        done

    done

    array_sort -u found_cgroups
    edebug "cgroups_tree $(lval cgroups found_cgroups)"
    echo "${found_cgroups[@]:-}"
}


opt_usage cgroup_pstree <<'END'
Display a graphical representation of all cgroups descended from those specified as arguments.
END
cgroup_pstree()
{
    local cgroup cols ps_output count
    for cgroup in $(cgroup_tree "${@}") ; do

        # Must subtract 3 from columns here to account for the three characters added to the string below (i.e. "| ")
        cols=$(( ${COLUMNS:-120} - 3 ))
        ps_output=$(COLUMNS=${cols} cgroup_ps ${cgroup})
        count=$(( $(echo "${ps_output}" | wc -l) - 1 ))

        echo "$(ecolor green)+--${cgroup} [${count}]$(ecolor off)"

        echo "${ps_output}" | sed 's#^#'$(ecolor green)\|$(ecolor off)\ \ '#g'

    done >&2
}


opt_usage cgroup_current <<'END'
Display the name of the cgroup that the specified process is in. Defaults to the current process (i.e. ${BASHPID}).
END
cgroup_current()
{
    $(opt_parse "?pid | Process whose cgroup should be listed. Default is the current process.")
    : ${pid:=${BASHPID}}

    local line=""
    line=$(grep -w "${CGROUP_SUBSYSTEMS[0]}" /proc/${pid}/cgroup)
    echo "${line##*:}" | sed 's#^'"${CGROUP_ROOT}"'/*##'
}


opt_usage cgroup_kill <<'END'
Recursively KILL (or send a signal to) all of the pids that live underneath all of the specified cgroups (and their
children!). Accepts any number of cgroups.

> **_NOTE:_** `$$` and `$BASHPID` are always added to this list so as to not kill the calling process
END
cgroup_kill()
{
    $(opt_parse \
        ":signal s=TERM | The signal to send to processs in the specified cgroup" \
        ":exclude x     | Space separated list of processes not to kill. Note: current process and
                          ancestors are always excluded." \
        "@cgroups       | Cgroups whose processes should be signalled.")

    [[ $(array_size cgroups) -gt 0 ]] || return 0

    local ignorepids pids

    ignorepids+="${exclude} $$ ${BASHPID}"

    # NOTE: BASHPID must be added here in addition to above because it's different inside this command substituion
    # (subshell) than it is outside.
    array_init pids "$(cgroup_pids -r -x="${ignorepids} ${BASHPID}" "${cgroups[@]}" || true)"

    if [[ $(array_size pids) -gt 0 ]] ; then
        edebug "Killing processes in cgroups $(lval signal cgroups pids ignorepids)"

        # Ignoring errors here because we don't want to die simply because a process that was in the cgroup disappeared
        # of its own volition before we got around to killing it.
        #
        # NOTE: This also has the side effect of causing cgroup_kill to NOT fail when the calling user doesn't have
        # permission to kill everything in the cgroup.
        ekill -s=${signal} "${pids[@]}" || true
    else
        edebug "All processes in cgroup are already dead. $(lval cgroups pids ignorepids)"
    fi

    return 0
}

opt_usage cgroup_kill_and_wait <<'END'
Ensure that no processes are running all of the specified cgroups by killing all of them and waiting until the group is
empty.

> **_NOTE:_** This probably won't work well if your script is already in that cgroup.
END
cgroup_kill_and_wait()
{
    $(opt_parse \
        ":signal s=TERM   | Signal to send to processes in the cgroup" \
        ":exclude x       | Space-separated list of processes not to kill. Current process and ancestors are always
                            excluded." \
        ":timeout max t=0 | Maximum number of seconds to wait for all processes to die. If some still exist at that
                            point, an error code will be returned. WARNING: The default of 0 will cause this function
                            to wait forever." \
        "@cgroups         | Cgroups whose processes should be signalled and waited upon")

    local startTime=${SECONDS}

    [[ $# -gt 0 ]] || return 0

    local ignorepids="$$ $BASHPID ${exclude}"

    edebug "Ensuring that there are no processes in $(lval cgroups ignorepids signal)."

    local times=0 remaining_pids=""
    while true ; do
        cgroup_kill -x="${ignorepids} ${BASHPID}" -s=${signal} "${cgroups[@]}"

        remaining_pids=$(cgroup_pids -r -x="${ignorepids} ${BASHPID}" "${cgroups[@]}" || true)
        if [[ -z ${remaining_pids} ]] ; then
            edebug "Done. All processes in cgroup are gone. $(lval cgroups ignorepids)"
            break
        else
            if [[ ${timeout} -gt 0 ]] && (( SECONDS - startTime > timeout )) ; then
                eerror "Tried to kill all processes in cgroup, but some remain. Giving up after ${timeout} seconds. $(lval cgroup remaining_pids)"
                return 1
            fi

            if edebug_enabled; then
                local pid="" ps_output=""
                for pid in ${remaining_pids} ; do
                    ps_output="$(ps hp ${pid} 2>/dev/null || true)"
                    [[ -z ${ps_output} ]] || edebug "   ${ps_output}"
                done
            fi

            sleep .1
        fi

        (( times += 1 ))
        if ((times % 50 == 0 )) ; then
            ewarn "Still trying to kill processes. $(lval cgroups remaining_pids)"
        fi

    done

    return 0
}

opt_usage cgroup_find_setting_file <<'END'
Find the full path to a cgroup setting file.
END
cgroup_find_setting_file()
{
    $(opt_parse cgroup setting)
    ls ${CGROUP_SYSFS}/*/${cgroup}/${setting}
}

opt_usage cgroup_empty <<'END'
cgroup_empty is a simple wrapper around cgroup_pids. It simply checks if all the provided cgroups are empty or not.
Which means that there are no pids running in the provided cgroups.
END
cgroup_empty()
{
    $(opt_parse \
        ":exclude x   | Space separated list of pids not to return. By default returns all." \
        "+recursive r | Additionally return pids for processes of this cgroup's children." \
        "@cgroups     | Cgroups whose processes should be listed.")

    local pids=()
    pids=( $(opt_forward cgroup_pids exclude recursive -- "${cgroups[@]}") )

    edebug "Checking cgroups are empty: $(lval cgroups exclude recursive pids)"

    # Now just return the result of array_empty on the pids we just found
    array_empty pids
}
