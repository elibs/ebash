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

# Default backend to use. If this is not explicitly set then ebash will automatically detect what backend to use. It
# will first see if systemd is installed and systemd-journald is running if if so will set set this "journald".
# Otherwise it will set this to "syslog" which is supported on OSX and all legacy Linux distributions.
: ${EBASH_SYSLOG_BACKEND:=""}

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

opt_usage syslog <<'END'
syslog provides a simple interface for logging a message to the system logger with full support for structured logging.
The structured details provided to this function are passed as an optional list of "KEY KEY=VALUE ..." entries identical
to ebanner and underlying expand_vars function. The KEY and VALUE are automatically intpolated if they are variables.

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
    # Automatically detect what backend to use. If systemctl exists and systemd-journald is running, then default to using
    # journald as the backend. Otherwise default to vanilla syslog. This can of course be globally set by the application
    # or explicitly provided at the logging call site.
    if [[ -z "${EBASH_SYSLOG_BACKEND}" ]]; then
        if command_exists systemctl && systemctl is-active --quiet systemd-journald; then
            EBASH_SYSLOG_BACKEND="journald"
        else
            EBASH_SYSLOG_BACKEND="syslog"
        fi
    fi

    $(opt_parse \
        ":backend b=${EBASH_SYSLOG_BACKEND} | Syslog backend (e.g. journald, syslog)"                                  \
        ":priority=info                     | Priority to use (emerg panic alert crit err warning notice info debug)." \
        "+syslog_details                    | Embed details into syslog message with syslog backend."                  \
        "message                            | Message to send to syslog backend."                                      \
        "@entries                           | Structured key/value details to include in syslog message."              \
    )

    # Verify supported backend
    assert_match "${backend}" "(journald|syslog)"

    # Verify priority level is valid.
    if ! [[ -v __EBASH_SYSLOG_PRIORITIES[$priority] ]]; then
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

    expand_vars --uppercase --no-quotes details "${entries[@]}"
    edebug "syslog: $(lval details)"

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
