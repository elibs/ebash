#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#---------------------------------------------------------------------------------------------------
#
# File Descriptors
#
#---------------------------------------------------------------------------------------------------

opt_usage get_stream_fd <<'END'
Convert stream names (e.g. 'stdout') to cannonical file descriptor numbers:

- **stdin**: 0
- **stdout**: 1
- **stderr**: 2

Any other names will result in an error.
END
get_stream_fd()
{
    case "$1" in
        stdin ) echo "0"; return 0 ;;
        stdout) echo "1"; return 0 ;;
        stderr) echo "2"; return 0 ;;

        *) die "Unsupported stream=$1"
    esac
}

opt_usage close_fds <<'END'
Close file descriptors that are currently open. This can be important because child processes inherit all of their
parent's file descriptors, but frequently don't need access to them. Sometimes the fact that those descriptors are
still open can even cause problems (e.g. if a FIFO has more writers than expected, its reader may not get the EOF it is
expecting.)

This function closes all open file descriptors EXCEPT stdin (0), stdout (1), and stderr (2). Technically, you can close
those on your own if you want via syntax like this:

```shell
exec 0>&- 1>&- 2>&-
```

But practically speaking, it's likely to cause problems. For instance, hangs or errors when something tries to write to
or read from one of those. It's a better idea to do this intead if you really don't want your stdin/stdout/stderr
inherited:

```shell
exec 0</dev/null 1>/dev/null 2>/dev/null
```

We also never close fd 255. Bash considers that its own. For instance, sometimes that's open to the script you're
currently executing.
END
close_fds()
{
    # Note grab file descriptors for the current process, not the one inside the command substitution ls here.
    local pid=$BASHPID

    # occasionally there are no file descriptors, therefore we need '|| true'
    local fds=()
    fds=( $(ls $(fd_path)/ | grep -vP '^(0|1|2|255)$' | tr '\n' ' ' || true) )
    array_empty fds && return 0

    local fd
    for fd in "${fds[@]}"; do
        eval "exec $fd>&-"
    done
}

opt_usage fd_path <<'END'
Get the full path in procfs for a given file descriptor.
END
fd_path()
{
    if [[ ${EBASH_OS} == Linux ]] ; then
        echo /proc/self/fd

    elif [[ ${EBASH_OS} == Darwin ]] ; then
        echo /dev/fd

    else
        die "Unsupported OS $(lval EBASH_OS)"
    fi
}
