# Module process


## func ekill


Kill all pids provided as arguments to this function using the specified signal. This function is best effort only. It
makes every effort to kill all the specified pids but ignores any errors while calling kill. This is largely due to the
fact that processes can exit before we get a chance to kill them. If you really care about processes being gone consider
using process_not_running or cgroups.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --kill-after, -k <value>
         Elevate to SIGKILL after waiting for this duration after sending the initial signal.
         Accepts any duration that sleep would accept. By default no elevated signal is sent

   --signal, --sig, -s <value>
         The signal to send to specified processes, either as a number or a signal name.
         Default is SIGTERM.


ARGUMENTS

   processes
         Process IDs of processes to signal.
```

## func ekilltree


Kill entire process tree for each provided pid by doing a depth first search to find all the descendents of each pid and
kill all leaf nodes in the process tree first. Then it walks back up and kills the parent pids as it traverses back up
the tree. Like `ekill`, this function is best effort only. If you want more robust guarantees consider
process_not_running or cgroups.

Note that ekilltree will never kill the current process or ancestors of the current process, as that would cause
ekilltree to be unable to succeed.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Processes to exclude from being killed.

   --kill-after, -k <value>
         Elevate to SIGKILL after this duration if the processes haven't died.

   --signal, --sig, -s <value>
         The signal to send to the process tree, either as a number or a name.


ARGUMENTS

   pids
         IDs of processes to be affected. All of these plus their children will receive the
         specified signal.
```

## func process_ancestors


Print pids of all ancestores of the specified list of processes, up to and including init (pid 1). If no processes are
specified as arguments, defaults to ${BASHPID}

```Groff
ARGUMENTS

   child
         pid of process whose ancestors will be printed.

```

## func process_children


Print the pids of all children of the specified list of processes. If no processes were specified, default to
`${BASHPID}`.

Note, this doesn't print grandchildren and other descendants. Just children. See process_tree for a recursive tree of
descendants.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --ps-all <value>
         The contents of "ps -eo ppid,pid", produced ahead of time to avoid calling ps over
         and over

```

## func process_not_running

Check if a given process is NOT running. Returns success (0) if all of the specified processes are not running and
failure (1) otherwise.

## func process_parent


Print the pid of the parent of the specified process, or of $BASHPID if none is specified.

```Groff
ARGUMENTS

   child
         pid of child process

```

## func process_parent_tree


Similar to process_ancestors (which gives a list of pids), this prints a tree of the process's parents, including pids
and commandlines, from the pid specified (BASHPID by default) to toppid (1 or init by default)

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --format, -f <value>
         ps format

   --toppid, -t <value>
         pid to run to


ARGUMENTS

   pid
         pid to check

```

## func process_running

Check if a given process is running. Returns success (0) if all of the specified processes are running and failure (1)
otherwise.

## func process_tree


Generate a depth first recursive listing of entire process tree beneath a given PID. If the pid does not exist this will
produce an empty string.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --ps-all <value>
         Pre-prepared output of "ps -eo ppid,pid" so I can avoid calling ps repeatedly

```
