# Module cgroup

Cgroups are a capability of the linux kernel designed for categorizing processes. They're most typically used in ways
that not only categorize processes, but also control them in some fasion. A popular reason is to limit the amount of
resources a particular process can use.

This file contains support only for the newer cgroups v2 implemented in newer kernels and new linux distros. For the
older v1 support see cgroup_v1.sh instead.

For newer distros cgroup V1 has been replaced with V2. V2 is simpler in that there are no separate subsystems. Instead
a process can only ever be part of a single cgroup. The specific resource limits assigned to that process are not tied
to separate cgroups.

## func cgroup_supported

Detect whether the machine currently running this code is built with kernel support for all of the cgroups subsystems
that ebash depends on.
