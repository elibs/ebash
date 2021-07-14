# Module syslog


## func syslog


syslog provides a simple interface for logging a message to the system logger with full support for structured logging.
The structured details provided to this function are passed as an optional list of "KEY KEY=VALUE ..." entries identical
to `ebanner` and underlying `expand_vars` function. If provided only a KEY, then it will be automatically expanded to
its value, if any. If it doesn not refer to any value than it will expand to an empty string. If provided "KEY=VALUE"
and "VALUE" refers to another valid variable name, then it will be expanded to that other variable's value. Otherwise it
will be used as-is. This allows maximum flexibility where you can log things to the system logger in three very useful
idioms:

```shell
expand_vars details HOME DIR=PWD DIR2="/home/foo"
```

Note three clear idioms demonstrated here:
- `HOME` is a variable, so it is expanded to the value of `${HOME}`.
- Because `PWD` is a variable, `DIR=PWD` will use the key `DIR` and the value of `${PWD}`
- Because `"/home/foo"` is not a variable, `DIR2="/home/foo"` will use a key `DIR2` and a literal value of `"/home/foo"`

In addition to these optional list of details, the following list of default details are always included:

- CODE_FILE         : Caller's filename
- CODE_LINE         : Caller's line of code
- CODE_FUNC         : Caller's function name
- MESSAGE           : The log message to emit
- PRIORITY          : Requsted priority (defaulting to "notice")
- SYSLOG_IDENTIFIER : Name of the program that called syslog.
- TID               : Thread ID. Bash doesn't use threads but does use subshells. In any event, the Thread ID is always
                      equal to BASHPID and always equals our subshell PID.

For more details on structured logging and fields see:
https://www.freedesktop.org/software/systemd/man/systemd.journal-fields.html

Under the hook, syslog is implemented using the familiar `logger` tool. Only the structured logging facility is simpler
to use as it's just a variadic list of KEY=VALUE pairs instead of the more complex use of a heredoc with logger.

syslog supports two different backends:
- journald
- syslog

Unfortunately, structured logging is not supported with the `syslog` backend. In that case, the structured details are
by default ignored. But you can optionally have them embedded into the actual message via the --syslog-details flag. In
this case, they are appended to the message. For example:

```
This is a log message ([KEY]="Value" [KEY2]="Something else")
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --backend, -b <value>
         Syslog backend (e.g. journald, syslog)

   --priority, -p <value>
         Priority to use (emerg panic alert crit err warning notice info debug).

   --syslog-details
         Embed details into syslog message with syslog backend.


ARGUMENTS

   message
         Message to send to syslog backend.

   entries
         Structured key/value details to include in syslog message.
```

## func syslog_detect_backend

syslog_detect_backend is used to automatically detect what backend to use by default according to the following rules:

If all of the following are true, then we will use the more advanced journald backend which supports structured logging:
1) systemctl exists
2) systemd-journald is running
3) logger accepts --journald flag

Otherwise default to vanilla syslog. This can of course be globally set by the application or explicitly provided
at the logging call site.
