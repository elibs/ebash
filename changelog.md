# Bashutils 1.3

    - Pulled option parsing functionality out of declare_args and created a new
      declare_opts function.  Its implementation supports both short and long
      options (and "golfing" short options).  It detects errors on the command
      line that would've previously been ignored such as passing an unsupported
      option to a command.  This is not backward compatible, though.  Calling
      code must change to use declare_opts if it wants to read options (e.g. -g
      or -f),  but declare_args still handles positional arguments as it always
      did.

    - Fixed a bug that caused die not to signal its parent when aborting.  It
      is through this mechanism that we intend to catch errors that happen in
      command substitution shells, so this may unearth some errors that were
      previously undetected.  If you want to disable this for a particular
      shell, you can call disable_die_parent in it.

    - New functions to assist in ascertaining your position in the process
      hierarchy.  Process_tree already existed, but process_children,
      process_parent, and process_ancestors are new.

    - ekill now supports an option (--kill-after) to send the initial signal,
      plus send sigkill later if the process doesn't die, and similar
      functionality has been added to other functions that kill such as
      ekilltree.

    - Rather than depth-first iteration, ekilltree now kills the children of a
      process all at the same time.

    - Die now only kills itself via the terminating signal it caught when that
      signal is one of the TTY signals.  Doing that on other signals such as
      sigterm can cause bash not to execute exit traps.

    - Chroot_kill now defaults to sigterm rather than sigkill.

    - Exceptions, unhandled errors, and caught signals now report the pid of
      the running process and the command running at the time of occurrence.

    - Renamed all internal "global" variables to begin with "\_\_BU\_".  It's
      often shorter than what we were previously using which is nice, but the
      big thing here is that we can tell people to not use those.

# Bashutils 1.2

    - Removed the option parsing functionality from declare_args and let its
      single purpose be handling positional arguments.

    - Added declare_opts to do option parsing.  To use it, you'll typically
      call declare_opts prior to declare_args in any function that you want to
      handle options.  Declare_opts supports both short and long options and is
      friendlier to callers of functions that use it.  For instance, you don't
      have to use an equal sign to specify a value for an option (although you
      still may)


# Bashutils 1.1

    - Added tryrc function to aid in running code that you expect might fail,
      but for which you don't want to use a whole try/catch block.

    - Reworked the way traps work.  Now all intended cleanup will be in the
      EXIT trap, which is called after any per-signal handler is called.  If
      you don't specify which signal when you call trap_add, this will continue
      to "just work"

    - Substantially reduced the number of cases where code inside bashutils
      would accidentally ignore errors.

    - Block signals during critical portions of die and the exit trap so that
      cleanup occurs even in the face of multiple things being cleaned up at
      once.

    - Added functions for dealing with signal names, numbers, etc (signame,
      signum, sigexitcode)

    - New cgroups support.  This requires that the OS already be set up to
      support cgroups (e.g. install cgroup-lite on ubuntu) and most cgroup
      commands require you to be root to run them

    - New elogfile and elogrotate functions make it easy to have your script
      log to a file (possibly in addition to the terminal) and to keep those
      log files tidy.

    - Added a new etimeout function that can run arbitrary commands (including
      functions!), forcing them to run within a certain amount of time.

    - Substantially improved eretry, including better timeout functionality.

    - Added a few functions for dealing with lock files (e.g. see elock,
      eunlock)

    - Added assert functions that are most useful in tests, but can be used
      anywhere.

    - Enhanced etest to detect leaked processes and cause test failure in those
      cases.  Added etestmsg to make logging easier to etest.  Several other
      smaller improvements.

    - Added ibu tool that provides an interactive prompt in a bash shell that
      has pre-loaded all of bashutils.

    - Added functions in daemon.sh that can help manage processes that are
      intended to be daemons.  Particularly useful for keeping daemons running
      inside a chroot, but can also be convenient elsewhere.

    - Substantial hardening and new tests in jenkins.sh.

    - Bashutils now explicitly chooses a locale (en_US.utf8)


# Bashutils 1.0

    - Start using bash's built-in functionality to detect errors and explode if
      one occurs.  (Note: this is implemented via error traps, which work
      mostly as you'd expect with set -e except that the option doesn't show up
      if you check bash's list of options)

    - Start using bash's built-in functionality to detect uninitialized
      variables.

    - Added ETRACE variable.  If you set it to a space-separated list, you'll
      get trace output every time a command is executed that matches an item in
      the list by function name or file name.  The output is more readable than
      that of set -x, and the fact that it's based on a match means its more
      feasible to use it in long scripts.  It's like set -x, only better.
