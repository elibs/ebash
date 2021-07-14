# Module cgroup

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

## func cgroup_create

Prior to using a cgroup, you must create it. It is safe to attempt to "create" a cgroup that already exists.

## func cgroup_current


Display the name of the cgroup that the specified process is in. Defaults to the current process (i.e. ${BASHPID}).

```Groff
ARGUMENTS

   pid
         Process whose cgroup should be listed. Default is the current process.

```

## func cgroup_destroy


If you want to get rid of a cgroup, you can do so by calling cgroup_destroy.

> **_NOTE:_**: It is an error to try to destroy a cgroup that contains any processes or any child cgroups. You can use
cgroup_kill_and_wait to ensure that they are if you like.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --recursive, -r
         Destroy cgroup's children recursively

```

## func cgroup_exists

Returns true if all specified cgroups exist. In other words, they have been created via cgroup_create but have not yet
been removed with cgroup_destroy)

## func cgroup_find_setting_file


Find the full path to a cgroup setting file.

```Groff
ARGUMENTS

   cgroup
        cgroup

   setting
        setting

```

## func cgroup_get


Read the existing value of a subsystem-specific cgroups setting for the specified cgroup. See cgroup_set for more info

```Groff
ARGUMENTS

   cgroup
         Name of the cgroup (e.g distbox/dtest or usa/colorado)

   setting
         Name of the subsystem-specific setting e.g. memory.kmem.limit_in.bytes)

```

## func cgroup_kill


Recursively KILL (or send a signal to) all of the pids that live underneath all of the specified cgroups (and their
children!). Accepts any number of cgroups.

> **_NOTE:_** `$$` and `$BASHPID` are always added to this list so as to not kill the calling process

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Space separated list of processes not to kill. Note: current process and ancestors are
         always excluded.

   --signal, -s <value>
         The signal to send to processs in the specified cgroup


ARGUMENTS

   cgroups
         Cgroups whose processes should be signalled.
```

## func cgroup_kill_and_wait


Ensure that no processes are running all of the specified cgroups by killing all of them and waiting until the group is
empty.

> **_NOTE:_** This probably won't work well if your script is already in that cgroup.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Space-separated list of processes not to kill. Current process and ancestors are always
         excluded.

   --signal, -s <value>
         Signal to send to processes in the cgroup

   --timeout, --max, -t <value>
         Maximum number of seconds to wait for all processes to die. If some still exist at
         that point, an error code will be returned. WARNING: The default of 0 will cause this
         function to wait forever.


ARGUMENTS

   cgroups
         Cgroups whose processes should be signalled and waited upon
```

## func cgroup_move


Move one or more processes to a specific cgroup. Once added, all (future) children of that process will also
automatically go into that cgroup.

It's worth noting that _all_ pids live in exactly one place in each cgroup subsystem. By default, processes are started
in the cgroup of their parent (which by default is the root of the cgroup hierarchy). If you'd like to remove a process
from your cgroup, you should simply move it up to that root (i.e. cgroup_move "/" $pid)

```Groff
ARGUMENTS

   cgroup
         Name of a cgroup which should already have been created.

   pids
         IDs of processes to move. Empty strings are allowed and ignored.
```

## func cgroup_pids


Recursively find all of the pids that live underneath a set of sections in the cgorups hierarchy. You may specify as
many different cgroups as you like, and the processes in those cgroups AND THEIR CHILDREN will be echoed to stdout.

Cgroup_pids will return success as long as all of the specified cgroups exist, and failure if they do not (but it will
still echo pids for any cgroups that _do_ exist). On failure, it returns the number of specified cgroups that did not
exist.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Space separated list of pids not to return. By default returns all.

   --recursive, -r
         Additionally return pids for processes of this cgroup's children.


ARGUMENTS

   cgroups
         Cgroups whose processes should be listed.
```

## func cgroup_ps


Run ps on all of the processes in a cgroup.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Space separated list of pids not to display.

   --recursive, -r
         List processes for specified cgroup and all children.


ARGUMENTS

   cgroup
         Name of cgroup to examine.

```

## func cgroup_pstree

Display a graphical representation of all cgroups descended from those specified as arguments.

## func cgroup_set


Change the value of a cgroups subsystem setting for the specified cgroup. For instance, by using the memory subsystem,
you could limit the amount of memory used by all pids underneath the distbox hierarchy like this:

```shell
cgroup_set distbox memory.kmem.limit_in.bytes $((4*1024*1024*1024))
```

```Groff
ARGUMENTS

   cgroup
         Name of the cgroup (e.g. distbox/distcc or fruit/apple or fruit)

   setting
         Name of the subsystem-specific setting

   value
         Value that should be assined to that subsystem-specific setting

```

## func cgroup_supported

Detect whether the machine currently running this code is built with kernel support for all of the cgroups subsystems
that ebash depends on.

## func cgroup_tree


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

```Groff
ARGUMENTS

   cgroups
        @cgroups
```
