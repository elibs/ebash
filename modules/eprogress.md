# Module eprogress


## func eprogress

`eprogress` is used to print a progress bar to STDERR in a highly configurable format. The typical use case for this is
to handle very long-running commands and give the user some indication that the command is still in-progress rather than
hung. The ticker can be customized:

- Disabled entirely using `EPROGRESS=0`
- Show on the left or right via `--align`
- Change how often it is printed via `--delay`
- Show the **timer** but not the **spinner** via `--no-spinner`
- Display contents of a **file** on each iteration

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --align <value>
         Where to align the tickker to (valid options are 'left' and 'right').

   --delay <value>
         Optional delay between tickers to avoid flooding the screen. Useful for automated CI/CD
         builds where we are not writing to an actual terminal but want to see periodic updates.

   --delete, -d
         Delete file when eprogress completes if one was specified via --file.

   --file, -f <value>
         A file whose contents should be continually updated and displayed along with the
         ticker. This file will be deleted by default when eprogress completes.

   --inline
         Display message, timer and spinner all inline. If you disable this the full message
         and timer is printed on a separate line on each iteration instead. This is useful for
         automated CI/CD builds where we are not writing to a real TTY.

   --spinner
         Display spinner inline with the message and timer.

   --style <value>
         Style used when displaying the message. You might want to use, for instance, einfos
         or ewarn or eerror instead. Or 'echo' if you don't want any special emsg formatting at
         the start of the message.

   --time
         As long as not turned off with --no-time, the amount of time since eprogress start will
         be displayed next to the ticker.


ARGUMENTS

   message
         A message to be displayed once prior to showing a time ticker. This will occur before
         the file contents if you also use --file.
```

## func eprogress_kill

Kill the most recent eprogress in the event multiple ones are queued up. Can optionally pass in a specific list of
eprogress pids to kill.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --all, -a
         If set, kill ALL known eprogress processes, not just the current one

   --callback <value>
         Callback to call as each progress ticker is killed.

   --inline
         Display message, timer and spinner all inline. If you disable this the full message
         and timer is printed on a separate line on each iteration instead. This is useful for
         automated CI/CD builds where we are not writing to a TTY.

   --return-code, --rc, -r <value>
         Should this eprogress show a mark for success or failure?

```
