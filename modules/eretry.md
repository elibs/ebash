# Module eretry


## func eretry


Eretry executes arbitrary shell commands for you wrapped in a call to etimeout and retrying up to a specified count.

If the command eventually completes successfully eretry will return 0. If the command never completes successfully but
continues to fail every time the return code from eretry will be the failing command's return code. If the command is
prematurely terminated via etimeout the return code from eretry will be 124.

All direct parameters to eretry are assumed to be the command to execute, and eretry is careful to retain your quoting.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --delay, -d <value>
         Amount of time to delay (sleep) after failed attempts before retrying. Note that this
         value can accept sub-second values, just as the sleep command does. This parameter will
         be passed directly to sleep, so you can specify any arguments it accepts such as .01s,
         5m, or 3d.

   --fatal-exit-codes, -e <value>
         Space-separated list of exit codes. Any of the exit codes specified in this list
         will cause eretry to stop retrying. If eretry receives one of these codes, it will
         immediately stop retrying and return that exit code. By default, only a return code of
         zero will cause eretry to stop. If you specify -e, you should consider whether you want
         to include 0 in the list.

   --max-timeout, -T <value>
         Total timeout for entire eretry operation. This flag is different than --timeout in
         that --max-timeout applies to the entire eretry operation including all iterations and
         retry attempts and timeouts of each individual command. Uses sleep(1) time syntax.

   --retries, -r <value>
         Command will be attempted this many times total. If no options are provided to eretry
         it will use a default retry limit of 5.

   --signal, --sig, -s <value>
         When timeout seconds have passed since running the command, this will be the signal
         to send to the process to make it stop. The default is TERM. [NOTE: KILL will _also_
         be sent two seconds after the timeout if the first signal doesn't do its job]

   --timeout, -t <value>
         After this duration, command will be killed (and retried if that's the right thing to
         do). If unspecified, commands may run as long as they like and eretry will simply wait
         for them to finish. Uses sleep(1) time syntax.

   --warn-color, -c <value>
         Warning color to use.

   --warn-every, -w <value>
         A warning will be generated on (or slightly after) every SECONDS while the command
         keeps failing.

   --warn-message, -m <value>
         Custom message to display on each warn_every interval.


ARGUMENTS

   cmd
         Command to run along with any of its own options and arguments.
```

## func eretry_internal


Internal method called by eretry so that we can wrap the call to eretry_internal with a call to etimeout in order to
provide upper bound on entire invocation.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --delay, -d <value>
         Time to sleep between failed attempts before retrying.

   --fatal-exit-codes, -e <value>
         Space-separated list of exit codes that are fatal (i.e. will result in no retry).

   --retries, -r <value>
         Command will be attempted once plus this number of retries if it continues to fail.

   --signal, --sig, -s <value>
         Signal to be send to the command if it takes longer than the timeout.

   --timeout, -t <value>
         If one attempt takes longer than this duration, kill it and retry if appropriate.

   --warn-color, -c <value>
         Warning color to use.

   --warn-every, -w <value>
         Generate warning messages after failed attempts when it has been more than this long
         since the last warning.

   --warn-message <value>
         Custom message to display on each warn_every interval.


ARGUMENTS

   cmd
         Command to run followed by any of its own options and arguments.
```
