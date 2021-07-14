# Module die


## func die


`die` is our central error handling function for all ebash code which is called on any unhandled error or via the `ERR`
trap. It is responsible for printing a stacktrace to STDERR indicating the source of the fatal error and then killing
our process tree and finally signalling our parent process that we died via `SIGTERM`. With this careful setup, we do
not need to do any error checking in our bash scripts. Instead we rely on the `ERR` trap getting invoked for any
unhandled error which will call `die`. At that point we take extra care to ensure that process and all its children exit
with error.

You may call die and tell it what message to print upon death if you'd like to produce a descriptive error message.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --color, -c <value>
         DEPRECATED OPTION -- no longer has any effect.

   --frames, -f <value>
         Number of stack frames to skip.

   --nostack, -n
         Do not print a stacktrace.

   --return-code, --rc, -r <value>
         Return code that die will eventually exit with.

   --signal, -s <value>
         Signal that caused this die to occur.


ARGUMENTS

   message
         Message to display.
```

## func die_on_abort

Enable default traps for all DIE_SIGNALS to call `die`.

## func die_on_error

`die_on_error` registers a trap handler for `ERR`. It is extremely important that we use this mechanism instead of the
expected `set -e` so that we have control over how the process exit is handled by calling our own internal `die`
handler. This allows us to either exit or kill the entire process tree as needed.

> **_NOTE:_** This is extremely unobvious, but setting a trap on `ERR` implicitly enables `set -e`.

## func die_stacktrace_enabled

`die_stacktrace_enabled` returns success (0) if `die` should emit stacktraces and failure (1) otherwise.

## func disable_die_stacktrace

`disable_die_stacktrace` is a convenience mechanism for disabling stacktraces emitted by `die`. They can be re-enabled
via `enable_die_stacktrace`.

## func enable_die_stacktrace

`enable_die_stacktrace` is a convenience mechanism for enabling stacktraces emitted by `die`. They can be disabled via
`disable_die_stacktrace`.

## func exit

`exit` is a replacement for the builtin `exit` function with our own internal `exit` function so we can detect abnormal
exit conditions through an `EXIT` trap which we setup to ensure `die` is called on exit if it didn't go through our own
internal exit mechanism.

The primary use case for this trickery is to detect and catch unset variables. With `set -u` turned on, bash immediately
exits the program -- NOT by calling bash `exit` function but by calling the C `exit(2)` function. The problem is that
even though it exits, it does NOT call the `ERR` trap. Thus `die` doesn't get invoked even though there was a fatal
error causing abnormal termination. We can catch this scenario by setting up an `EXIT` trap and invoking `die` if exit
was invoked outside of our internal exit function.

The other advantage to this approach is that if someone calls `exit` directly inside bash code sourcing ebash in order to
gracefully exit they probably do NOT want to see a stacktrace and have `die` get invoked. This mechanism will ensure
that works properly because they will go through our internal exit function and that will bypass `die`.

## func nodie_on_abort

Disable default traps for all DIE_SIGNALS.

## func nodie_on_error

`nodie_on_error` disable the ebash `ERR` trap handler. Calling this is akin to calling `set +e`. ebash will no longer
detect errors for you in this shell.
