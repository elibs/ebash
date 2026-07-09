# Module elock


## func elock

`elock` creates a file-system level lockfile associated with a given filename. This is an advisory lock only and
requires all callers to use `elock` and `eunlock` in order to protect the file.

On Linux, this uses flock(1) for efficient kernel-level locking. On Darwin/macOS, this uses mkdir-based spinlocking
as a cross-platform fallback.

These locks are exclusive. These locks are NOT recursive - if you already own the lock and try to acquire it again,
it will return an error immediately to avoid hanging.

If the file doesn't exist, it is created.

## func elock_get_fd

`elock_get_fd` gets the file descriptor (if any) that our process has associated with a given on-disk lockfile.
On Darwin, returns "1" (a placeholder) since mkdir-based locking doesn't use file descriptors.
Returns 1 (failure) if the file is not locked by this process.

## func elock_locked

`elock_locked` checks if a file is currently locked (by any process, not just this one).

## func elock_unlocked

`elock_unlocked` checks if a file is not currently locked.

## func eunlock

`eunlock` unlocks a previously locked file and releases the associated resources (file descriptor on Linux, lock
directory on Darwin). Returns an error if the file is not currently locked by this process.
