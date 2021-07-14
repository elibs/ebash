# Module etimeout


## func etimeout


`etimeout` will execute an arbitrary bash command for you, but will only let it use up the amount of time (i.e. the
"timeout") you specify.

If the command tries to take longer than that amount of time, it will be killed and etimeout will return 124.
Otherwise, etimeout will return the value that your called command returned.

All arguments to `etimeout` (i.e. everything that isn't an option, or everything after --) is assumed to be part of the
command to execute. `Etimeout` is careful to retain your quoting.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --signal, --sig, -s <value>
         First signal to send if the process doesn't complete in time. KILL will still be sent
         later if it's not dead.

   --timeout, -t <value>
         After this duration, command will be killed if it hasn't already completed.


ARGUMENTS

   cmd
         Command and its arguments that should be executed.
```
