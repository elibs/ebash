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

On older distros cgroup V1 support provided different "subsystems" and a process could be in different cgroups for each
subsystem. For example you'd have /sys/fs/cgroup/cpu /sys/fs/cgroup/memory, etc. Within each of these subsystems, a
process may exist at one point in a hierarchy. That is, within the CPU subsystem, a process may only be owned by a
single cgroup. And in the memory subsystem, it may be owned by a different cgroup. For the purposes of THIS ebash code,
though, we duplicate a similar tree of groups within _all_ of the subsystems that we interact with.

CGROUP_CONTROLLERS defines which subsystems those are. So when you use these functions, the hierarchy that you create
is created in parallel under all of the subsystems defined by CGROUP_CONTROLLERS

For newer distros cgroup V1 has been replaced with V2. V2 is simpler in that there are no separate subsystems. Instead
a process can only ever be part of a single cgroup. The specific resource limits assigned to that process are not tied
to separate cgroups.

This file will include a version specific version of cgroup_v1.sh or cgroup_v2.sh depending on what version is supported
on this system.

> **_NOTE:_** On Docker, The cgroups functions work when run within docker containers, operating on a cgroup inside the
one that docker set up for them. This requires said containers to be started with --privileged or suitable other
capabilities (which I have not investigated -- it could be done, though)
END
#-----------------------------------------------------------------------------------------------------------------------

# Sysfs path
CGROUP_SYSFS=/sys/fs/cgroup

# See if we're running on a system with Cgroup V1 or V2 support
if grep -q "cgroup cgroup" /proc/self/mountinfo 2>/dev/null; then
    CGROUP_VERSION=1
elif grep -q cgroup2 /proc/self/mountinfo 2>/dev/null; then
    CGROUP_VERSION=2
else
    CGROUP_VERSION=0
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
    # Cgroups are fundamentally broken on alpine. Even though they are present and pass our other criteria we are
    # unable to create new cgroups on Alpine only as it fails with: ./bin/../share/cgroup.sh: line 191: echo: write
    # error: Invalid argument
    if os_distro alpine; then
        edebug "Cgroups do not work properly on alpine"
        return 1
    fi

    if [[ ${CGROUP_VERSION} -eq 1 ]]; then
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
    elif [[ ${CGROUP_VERSION} -eq 2 ]]; then
        return 0
    else
        return 1
    fi
}

[[ ${EBASH_OS} == Linux && -e /proc/cgroups ]] || return 0

# Include version-specific implementation
if [[ ${CGROUP_VERSION} -eq 1 ]]; then
    source "${EBASH}/cgroup_v1.sh"
elif [[ ${CGROUP_VERSION} -eq 2 ]]; then
    source "${EBASH}/cgroup_v2.sh"
fi
