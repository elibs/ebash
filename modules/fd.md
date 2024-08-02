# Module fd


## func close_fds

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

## func fd_path

Get the full path in procfs for a given file descriptor.

## func get_stream_fd

Convert stream names (e.g. 'stdout') to cannonical file descriptor numbers:

- **stdin**: 0
- **stdout**: 1
- **stderr**: 2

Any other names will result in an error.
