#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# ELOCK: Cross-platform file locking
#
# This module provides advisory file locking that works on both Linux and macOS:
#
# - Linux: Uses flock(1) for efficient kernel-level locking. Locks are automatically released when the process exits
#   or the file descriptor is closed. Locks are inherited by subshells and can be unlocked from within them.
#
# - Darwin/macOS: Uses mkdir-based spinlocking as flock is not available. The lock is represented by a directory
#   named "${fname}.lock". This approach is atomic but has some limitations:
#   * Locks are NOT automatically released on process exit - you must call eunlock explicitly
#   * Lock state is tracked per-process in __EBASH_ELOCK_FDMAP, so subshells cannot unlock parent's locks
#   * Uses a brief sleep (0.01s) spinlock when waiting for a contested lock
#
#-----------------------------------------------------------------------------------------------------------------------

declare -A __EBASH_ELOCK_FDMAP

opt_usage elock <<'END'
`elock` creates a file-system level lockfile associated with a given filename. This is an advisory lock only and
requires all callers to use `elock` and `eunlock` in order to protect the file.

On Linux, this uses flock(1) for efficient kernel-level locking. On Darwin/macOS, this uses mkdir-based spinlocking
as a cross-platform fallback.

These locks are exclusive. These locks are NOT recursive - if you already own the lock and try to acquire it again,
it will return an error immediately to avoid hanging.

If the file doesn't exist, it is created.
END

opt_usage eunlock <<'END'
`eunlock` unlocks a previously locked file and releases the associated resources (file descriptor on Linux, lock
directory on Darwin). Returns an error if the file is not currently locked by this process.
END

opt_usage elock_get_fd <<'END'
`elock_get_fd` gets the file descriptor (if any) that our process has associated with a given on-disk lockfile.
On Darwin, returns "1" (a placeholder) since mkdir-based locking doesn't use file descriptors.
Returns 1 (failure) if the file is not locked by this process.
END

opt_usage elock_locked <<'END'
`elock_locked` checks if a file is currently locked (by any process, not just this one).
END

opt_usage elock_unlocked <<'END'
`elock_unlocked` checks if a file is not currently locked.
END

#-----------------------------------------------------------------------------------------------------------------------
#
# LINUX: flock-based implementation
#
#-----------------------------------------------------------------------------------------------------------------------

if [[ ${EBASH_OS} == "Linux" ]]; then

    elock()
    {
        [[ $# -eq 1 ]] || { eerror "elock requires exactly 1 argument"; return 1; }
        local fname="$1"

        # Create file if it doesn't exist
        [[ -e ${fname} ]] || touch "${fname}"

        # Check if we already have a file descriptor for this lockfile
        local fd="${__EBASH_ELOCK_FDMAP[$fname]:-}"
        if [[ -n ${fd} ]]; then
            if elock_locked "${fname}"; then
                eerror "elock: ${fname} already locked"
                return 1
            fi

            ewarn "elock: Purging stale lock entry ${fname} fd=${fd}"
            eunlock "${fname}"
        fi

        # Open an auto-assigned file descriptor with the associated file
        edebug "Locking ${fname}"
        exec {fd}<"${fname}"

        if flock --exclusive ${fd}; then
            edebug "Successfully locked ${fname} fd=${fd}"
            __EBASH_ELOCK_FDMAP[$fname]=${fd}
            return 0
        else
            edebug "Failed to lock ${fname} fd=${fd}"
            exec {fd}<&-
            return 1
        fi
    }

    eunlock()
    {
        [[ $# -eq 1 ]] || { eerror "eunlock requires exactly 1 argument"; return 1; }
        local fname="$1"

        local fd="${__EBASH_ELOCK_FDMAP[$fname]:-}"
        if [[ -z ${fd} ]]; then
            eerror "eunlock: ${fname} not locked"
            return 1
        fi

        edebug "Unlocking ${fname} fd=${fd}"
        flock --unlock ${fd}
        eval "exec ${fd}>&-"
        unset "__EBASH_ELOCK_FDMAP[$fname]"
    }

    elock_get_fd()
    {
        [[ $# -eq 1 ]] || { eerror "elock_get_fd requires exactly 1 argument"; return 1; }
        local fd="${__EBASH_ELOCK_FDMAP[$1]:-}"
        if [[ -z "${fd}" ]]; then
            return 1
        else
            echo "${fd}"
            return 0
        fi
    }

    elock_locked()
    {
        [[ $# -eq 1 ]] || { eerror "elock_locked requires exactly 1 argument"; return 1; }
        local fname="$1"

        # If the file doesn't exist then it can't be locked
        [[ -e ${fname} ]] || return 1

        # Try to acquire lock non-blocking; if we can, it wasn't locked
        local fd
        exec {fd}<"${fname}"
        if flock --exclusive --nonblock ${fd}; then
            flock --unlock ${fd}
            exec {fd}<&-
            return 1
        else
            exec {fd}<&-
            return 0
        fi
    }

#-----------------------------------------------------------------------------------------------------------------------
#
# DARWIN: mkdir-based spinlock implementation
#
# mkdir is atomic on all POSIX systems, making it suitable for locking. The lock is represented by a directory
# named "${fname}.lock" - if the directory exists, the file is locked.
#
# Limitations compared to flock:
# - No automatic cleanup on process exit (must call eunlock explicitly or use trap)
# - Lock state tracked in process-local __EBASH_ELOCK_FDMAP (subshells can see lock exists but can't unlock)
# - Brief spinlock sleep when contended (0.01s)
#
#-----------------------------------------------------------------------------------------------------------------------

elif [[ ${EBASH_OS} == "Darwin" ]]; then

    elock()
    {
        [[ $# -eq 1 ]] || { eerror "elock requires exactly 1 argument"; return 1; }
        local fname="$1"
        local lockdir="${fname}.lock"

        # Create file if it doesn't exist (for compatibility with Linux behavior)
        [[ -e ${fname} ]] || touch "${fname}"

        # Check if we already hold this lock
        if [[ -n "${__EBASH_ELOCK_FDMAP[$fname]:-}" ]]; then
            if elock_locked "${fname}"; then
                eerror "elock: ${fname} already locked"
                return 1
            fi

            ewarn "elock: Purging stale lock entry ${fname}"
            eunlock "${fname}"
        fi

        edebug "Locking ${fname}"

        # Spinlock using mkdir (atomic on all POSIX platforms)
        while true; do
            if mkdir "${lockdir}" 2>/dev/null; then
                edebug "Successfully locked ${fname}"
                __EBASH_ELOCK_FDMAP[$fname]=1
                return 0
            fi
            # Brief sleep to avoid busy-waiting (0.01s = 10ms)
            sleep 0.01
        done
    }

    eunlock()
    {
        [[ $# -eq 1 ]] || { eerror "eunlock requires exactly 1 argument"; return 1; }
        local fname="$1"
        local lockdir="${fname}.lock"

        if [[ -z "${__EBASH_ELOCK_FDMAP[$fname]:-}" ]]; then
            eerror "eunlock: ${fname} not locked"
            return 1
        fi

        edebug "Unlocking ${fname}"
        rmdir "${lockdir}" 2>/dev/null || true
        unset "__EBASH_ELOCK_FDMAP[$fname]"
    }

    elock_get_fd()
    {
        [[ $# -eq 1 ]] || { eerror "elock_get_fd requires exactly 1 argument"; return 1; }
        # Return "1" as placeholder since mkdir-based locking doesn't use file descriptors
        if [[ -n "${__EBASH_ELOCK_FDMAP[$1]:-}" ]]; then
            echo "1"
            return 0
        else
            return 1
        fi
    }

    elock_locked()
    {
        [[ $# -eq 1 ]] || { eerror "elock_locked requires exactly 1 argument"; return 1; }
        [[ -d "${1}.lock" ]]
    }

fi

#-----------------------------------------------------------------------------------------------------------------------
#
# Shared implementation (works on all platforms)
#
#-----------------------------------------------------------------------------------------------------------------------

elock_unlocked()
{
    ! elock_locked "$@"
}
