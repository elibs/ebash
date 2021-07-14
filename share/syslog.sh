#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Syslog
#
#-----------------------------------------------------------------------------------------------------------------------

# Ebash SYSLOG priority levels.
#
# These directly map to the values in https://www.freedesktop.org/software/systemd/man/systemd.journal-fields.html which
# define it as a value between 0 ("emerg") and 7 ("debug") formatted as a decimal string.
#
# This field is compatible with syslog's priority concept.
#
# There are three deprecated priorities which map to these new values:
#   panic -> emerg
#   error -> err
#   warn  -> warning
declare -A __EBASH_SYSLOG_PRIORITIES=(
    [emerg]=0
    [alert]=1
    [crit]=2
    [err]=3
    [warning]=4
    [notice]=5
    [info]=6
    [debug]=7

    # Deprecated aliases
    [panic]=0
    [error]=3
    [warn]=4
)

# Default backend to use. If this is not explicitly set then ebash will automatically detect what backend to use on
# first use via the `syslog_detect_backend` function.
: ${EBASH_SYSLOG_BACKEND:=""}

opt_usage syslog_detect_backend <<'END'
syslog_detect_backend is used to automatically detect what backend to use by default according to the following rules:

If all of the following are true, then we will use the more advanced journald backend which supports structured logging:
1) systemctl exists
2) systemd-journald is running
3) logger accepts --journald flag

Otherwise default to vanilla syslog. This can of course be globally set by the application or explicitly provided
at the logging call site.
END
syslog_detect_backend()
{
    # If user already explicitly set prefered default, just use that.
    edebug "$(lval EBASH_SYSLOG_BACKEND)"
    if [[ -n "${EBASH_SYSLOG_BACKEND:-}" ]]; then
        echo "${EBASH_SYSLOG_BACKEND}"
        return 0
    fi

    if command_exists systemctl && systemctl is-active --quiet systemd-journald &>/dev/null && logger --help | grep -q -- "--journald"; then
        EBASH_SYSLOG_BACKEND="journald"
    else
        EBASH_SYSLOG_BACKEND="syslog"
    fi

    edebug "Auto detected $(lval EBASH_SYSLOG_BACKEND)"
    echo "${EBASH_SYSLOG_BACKEND}"
}

opt_usage syslog <<'END'
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
END
syslog()
{
    $(opt_parse \
        ":backend b        | Syslog backend (e.g. journald, syslog)"                                                   \
        ":priority p=info  | Priority to use (emerg panic alert crit err warning notice info debug)."                  \
        "+syslog_details   | Embed details into syslog message with syslog backend."                                   \
        "message           | Message to send to syslog backend."                                                       \
        "@entries          | Structured key/value details to include in syslog message."                               \
    )

    # Auto detected backend if necessary and verify it is supported.
    if [[ -z "${backend}" ]]; then
        backend=$(syslog_detect_backend)
    fi
    assert_match "${backend}" "(journald|syslog)"

    # Verify priority level is valid.
    if [[ -z ${__EBASH_SYSLOG_PRIORITIES[$priority]:-} ]]; then
        die "Invalid $(lval priority supported=__EBASH_SYSLOG_PRIORITIES)"
    fi

    # Grab numerical priority
    priority=${__EBASH_SYSLOG_PRIORITIES[$priority]}
    argcheck priority

    # Include default details
    declare -A details=(
        [CODE_FILE]="${BASH_SOURCE[1]##*/}"
        [CODE_FUNC]="${FUNCNAME[1]:-}"
        [CODE_LINE]="${BASH_LINENO[0]:-}"
        [MESSAGE]="${message}"
        [PRIORITY]="${priority}"
        [SYSLOG_IDENTIFIER]="${0##*/}"
        [TID]="${BASHPID}"
    )

    expand_vars --uppercase --no-quotes details "${entries[@]:-}"
    edebug "$(lval backend details)"

    # Forward the message and details into the desired backend. For journald it natively supports structured logging so
    # we can just stream them right into journald over STDIN.
    #
    # Otherwise, if the backend is syslog, then we optionally append the details to the message and forward it along to
    # syslog through logger.
    if [[ "${backend}" == "journald" ]]; then
        for key in $(array_indexes_sort details); do
            echo "${key}=${details[$key]}"
        done | logger --journald
    elif [[ "${syslog_details}" -eq 1 ]]; then
        unset details[MESSAGE]
        unset details[PRIORITY]
        logger --priority "${priority}" "${message} $(lval details | sed -e 's|details=||')"
    else
        logger --priority "${priority}" "${message}"
    fi
}
