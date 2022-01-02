#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

[[ ${EBASH_OS} == "Linux" ]] || return 0

declare -A __EBASH_ELOCK_FDMAP

opt_usage elock <<'END'
`elock` is a wrapper around [flock](https://man7.org/linux/man-pages/man1/flock.1.html) to create a file-system level
lockfile associated with a given filename. This is an advisory lock only and requires all callers to use `elock` and
`eunlock` in order to protect the file. This method is easier to use than calling flock directly since it will
automatically open a file descriptor to associate with the lockfile and store that off in an associative array for later
use.

These locks are exclusive. In the future we may support a -s option to pass into `flock` to make them shared but at
present we don't need that behavior.

These locks are NOT recursive. Which means if you already own the lock and you try to acquire the lock again it will
return an error immediately to avoid hanging.

The file descriptor associated with the lockfile is what keeps the lock alive. This means you need to either explicitly
call `eunlock` to unlock the file and close the file descriptor OR simply put it in a subshell and it will automatically
be closed and freed up when the subshell exits.

Lockfiles are inherited by subshells. Specifically, a subshell will see the file locked and has the ability to unlock
that file. This may seem odd since subshells normally cannot modify parent's state. But in this case it is in-kernel
state being modified for the process which the parent and subshell share. The one catch here is that our internal state
variable `__EBASH_ELOCK_FDMAP` will become out of sync when this happens because a call to unlock inside a subshell will
unlock it but cannot remove from our parent's `FDMAP`. All of these functions deal with this possibility properly by not
considering the `FDMAP` authoritative. Instead, rely on `flock` for error handling where possible and even if we have a
value in our map check if it's locked or not before failing any operations.

To match `flock` behavior, if the file doesn't exist it is created.
END
elock()
{
    $(opt_parse fname)

    # Create file if it doesn't exist
    [[ -e ${fname} ]] || touch ${fname}

    # Check if we already have a file descriptor for this lockfile. If we do don't fail immediately but check if that
    # file is actually locked. If so return an error to avoid causing deadlock. If it's not locked, purge the stale
    # entry with a warning.
    local fd
    fd=$(elock_get_fd "${fname}" || true)
    if [[ -n ${fd} ]]; then

        if elock_locked "${fname}"; then
            eerror "$(lval fname) already locked"
            return 1
        fi

        ewarn "Purging stale lock entry $(lval fname fd)"
        eunlock ${fname}
    fi

    # Open an auto-assigned file descriptor with the associated file
    edebug "Locking $(lval fname)"
    local fd
    exec {fd}<${fname}

    if flock --exclusive ${fd}; then
        edebug "Successfully locked $(lval fname fd)"
        __EBASH_ELOCK_FDMAP[$fname]=${fd}
        return 0
    else
        edebug "Failed to lock $(lval fname fd)"
        exec ${fd}<&-
        return 1
    fi
}

opt_usage eunlock <<'END'
`eunlock` is the logical analogue to `elock`. It's still essentially a wrapper around `flock -u` to unlock a previously
locked file. This will ensure the lock file is in our associative array and if not return an error. Then it will simply
call into `flock` to unlock the file. If successful, it will close remove the file descriptor from our file descriptor
associative array.
END
eunlock()
{
    $(opt_parse fname)

    local fd
    fd=$(elock_get_fd "${fname}" || true)
    if [[ -z ${fd} ]]; then
        eerror "$(lval fname) not locked"
        return 1
    fi

    edebug "Unlocking $(lval fname fd)"
    flock --unlock ${fd}
    eval "exec ${fd}>&-"
    unset __EBASH_ELOCK_FDMAP[$fname]
}

opt_usage elock_get_fd <<'END'
`elock_get_fd` gets the file descriptor (if any) that our process has associated with a given on-disk lockfile. This is
largely for convenience inside `elock` and `eunlock` to avoid some code duplication but could also be used externally if
needed.
END
elock_get_fd()
{
    $(opt_parse fname)
    local fd="${__EBASH_ELOCK_FDMAP[$fname]:-}"
    if [[ -z "${fd}" ]]; then
        return 1
    else
        echo -n "${fd}"
        return 0
    fi
}


opt_usage elock_locked <<'END'
`elock_locked` checks if a file is locked via `elock`. This simply looks for the file inside our associative array
because `flock` doesn't provide a native way to check if we have a file locked or not.
END
elock_locked()
{
    $(opt_parse fname)

    # If the file doesn't exist then we can't check if it's locked
    [[ -e ${fname} ]] || return 1

    local fd
    exec {fd}<${fname}
    if flock --exclusive --nonblock ${fd}; then
        flock --unlock ${fd}
        return 1
    else
        return 0
    fi
}

opt_usage elock_unlocked <<'END'
`elock_unlocked` checks if a file is not locked via `elock`. This simply looks for the file inside our associative array
because `flock` doesn't provide a native way to check if we have a file locked or not.
END
elock_unlocked()
{
    ! elock_locked "${@}"
}
