# Module elogfile


## func elogfile

elogfile provides the ability to duplicate the calling processes STDOUT and STDERR and send them both to a list of files
while simultaneously displaying them to the console. Using this function is much preferred over manually doing this with
tee and named pipe redirection as we take special care to ensure STDOUT and STDERR pipes are kept separate to avoid
problems with logfiles getting truncated.

elogfile creates some background processes to take care of logging for us asynchronously. The list of PIDs from these
background processes are stored in an internal array __EBASH_ELOGFILE_PID_SETS. This array stores a series of "pidsets"
which is just a set of pids created on a specific call to elogfile. The reason we use this approach is because depending
on the flags passed into elogfile we may launch one or two different pids. And we'd like the ability to gracefully kill
the set of pids launched by a specific elogfile instance gracefully via elogfile_kill. To that end, we store the pid or
pids as a comma separated list of pids launched.

For example, if you call `elogfile foo` then __EBASH_ELOGFILE_PID_SETS will contain two pids comma-delimited as they
were launched as part of a single call to elogfile, e.g. ("1234,1245"). If you again call `elogfile bar` two more
processes will get launched, and we'll end up with ("1234,1235", "2222,2223"). We can then control which set of pids
we gracefully kill via elogfile_kill.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --merge, -m
         Whether to merge stdout and stderr into a single stream on stdout.

   --rotate-count, -r <value>
         When rotating log files, keep this number of log files.

   --rotate-size, -s <value>
         Rotate log files when they reach this size. Units as accepted by find.

   --stderr, -e
         Whether to redirect stderr to the logfile.

   --stdout, -o
         Whether to redirect stdout to the logfile.

   --tail, -t
         Whether to continue to display output on local stdout and stderr.

```

## func elogfile_kill

Kill previously launched elogfile processes. By default if no parameters are provided kill any elogfiles that were
launched by our process. Or alternatively if `--all` is provided then kill all elogfile processes. Can also optionally
pass in a specific list of elogfile pids to kill.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --all, -a
         If set, kill ALL known eprogress processes, not just the current one

```

## func elogfile_pids

elogfile_pids is used to convert the pidset stored in __EBASH_ELOGFILE_PID_SETS into a newline delimited list of PIDs.
Being newline delimited helps the output of this easily slurp into `readarray`.
