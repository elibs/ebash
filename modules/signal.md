# Module signal


## func disable_signals

Save off the current state of signal-based traps and disable them. You may be interested in doing this if you're very
concerned that a short bit of code should not be interrupted by a signal. Be _SURE_ to call renable signals when you're
done.

## func sigexitcode

Given a signal name or number, echo the exit code that a bash process would produce if it died due to the specified
signal.

## func signame

Given a signal name or number, echo the signal number associated with it.

With the --include-sig option, SIG will be part of the name for signals where that is appropriate. For instance,
SIGTERM or SIGABRT rather than TERM or ABRT. Note that bash pseudo signals never use SIG. This function treats those
appropriately (i.e. even with --include sig will return EXIT rather than SIGEXIT)

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --include-sig, -s
         Get the form of the signal name that includes SIG.

```

## func signum

Given a name or number, echo the signal name associated with it.
