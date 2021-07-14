# Module elogfile


## func elogfile


elogfile provides the ability to duplicate the calling processes STDOUT and STDERR and send them both to a list of files
while simultaneously displaying them to the console. Using this function is much preferred over manually doing this with
tee and named pipe redirection as we take special care to ensure STDOUT and STDERR pipes are kept separate to avoid
problems with logfiles getting truncated.

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
