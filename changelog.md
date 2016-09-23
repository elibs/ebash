# Bashutils 1.3

    - New configuration file reading and writing tools for INI-style
      configuration files.  (see share/conf.sh for more info)

    - Added pkg subsystem with tools for installing and uninstalling
      packages as well as determining whether they're installed in a safe
      way across Linux distros.

    - Added --file option to eprogress

    - Added --hexdump option to assert_eq

    - Added -n option to einfo, ewarn, edebug that prevents them from
      generating a newline at the end of the message.  Note that this must
      be held in the first argument to the einfo/ewarn/edebug function.
    
    - Corrected substantial defects in the existing assert functions and
      added unit tests for them.

    - assert_empty and assert_not_empty now accept strings and blows up if
      any of the strings do not meet their criteria.  Previously they
      expected the name of a variable.  Assert_var_empty and
      assert_var_not_empty have been added to handle that use case.

    - Created a new opt_parse function that contains all of the argument
      handling functionality that `declare_args` used to while also being
      explicit instead of implicit about option handling.  Supports both short
      and long options.  Supports "golfing" of short options (i.e. -e -x and
      -ex are equivalent).  Detects errors on the command line of calling code
      that would've previously been ignored such as passing an unsupported
      option to a command.

    - New opt_forward function that helps forward options passed into one other
      functions that accept the same options. Useful when you have an
      "internal" function that handles most of the work that is done by a slim
      calling function.

    - Removed declare_args in favor of opt_parse.  It is syntax-compatible as
      long as you didn't use options.  When using options, they must now be
      specified but we prefer this as it is more explicit.

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

    - The daemon utilities no longer support a post_start hook but do support a
      post_mount hook.  That ability exists mostly to aid in testing the daemon
      utilities, but perhaps it is also useful elsewhere.  Better logging
      should be produced by the daemon bashutils functions into the daemon's
      log file if you request one.

    - Chroot_kill now defaults to sigterm rather than sigkill.

    - Exceptions, unhandled errors, and caught signals now report the pid of
      the running process and the command running at the time of occurrence.

    - Renamed all internal "global" variables to begin with "\_\_BU\_".  It's
      often shorter than what we were previously using which is nice, but the
      big thing here is that we can tell people to not use those.

    - Etest now runs under Mac OS, given appropriate GNU toolchains installed
      with names prefixed with "g" (which seems to be the default for both
      homebrew and macports).

    - Ecolor now allows for 0 or more arguments which can be modifiers or
      foreground colors. No longer support "dimCOLOR".  Instead use "dim
      color". Ecolor now also supports setting background color by prefixing
      the color name with "b:"

    - Ecolor caches its output so that it doesn't have to spawn tput processes
      repeatedly to get codes.  This approximately halves the time each einfo
      takes vs bashutils 1.2.

    - lval: Changed leading character to indicate that a variable is a pack
      from + to % to be more similar to perl's hashes and to avoid using the
      plus sign differently in lval and opt_parse.

    - trap: A new trap function designed to shadow bash's trap builtin works
      around the way bash discards inherited ERR and DEBUG traps when you
      create a new trap.

    - netselect now supports options to make it quiet and to specify how many
      times to test each host.  When only given a single host, netselect works
      much faster.

    - Fix a netselect bug that caused it to return a different name than one of
      those hosts specified when ping output looks different (for instance,
      when it has an aliased name in DNS).

    - New "bashutils" binary that can run bashutils functions as an external
      command as well as many other binaries designed for calling bashutils
      functions (e.g. daemon, cgroup, chroot, eunmount, ewarn)

    - Move .sh files into a share directory and binaries into a bin directory.
      Typical expectations are that BASHUTILS points to the share directory so
      that you can source ${BASHUTILS}/share as you always did.  BASHUTILS_HOME
      should point to the parent directory that holds all of the bashutils
      stuff.

    - Readme and unit tests are now included in the package.

    - Revamp overlayfs module to to perform all parsing of the various mount 
      layers into a single overlayfs_layers function. This uses a pack to more
      easily and consistently access various mount points and sources of the
      mount points throughout overlayfs code.

    - Modified overlayfs_tree to dump contents top-down instead of bottom-up.
      This means the uppermost layer is printed first to indicate it's a
      read-through layer cake filesystem.

    - Add new overlayfs_commit function to commit all pending changes in the
      overlayfs write later back down into the lowest read-only layer and then
      unmount the overlayfs mount. The intention of this function is that you should
      call it when you're completely done with an overlayfs and you want its
      changes to persist back to the original archive.

    - Pulled a lot of code out of efuncs in favor of keeping the files
      small and focused.  For instance, messaging code moved to emsg.sh,
      array code to array.sh, etc.  The proper thing to do is to continue
      to source only bashutils.sh.  The rest are really just internals.

    - New reexec function that can re-execute the current script with the
      same arguments under sudo, in a mount namespace, or both.

    - The daemon functions will now close stdout and stderr when a logfile
      is specified but leave them open if not.

    - Added os detection functions (os, os_distro, os_release)

    - Added array parsing into opt_parse using new type character '&'.  This
      allows you to specify an option multiple times and they will all get
      accumulated into a single array.

# Bashutils 1.2

    - Created new general purpose abstract archive module. This provides common
      functions for creating, extracting, listing, mounting, unmounting and
      converting ISOs, squashfs images, and all supported tar file formats.

    - Created new OverlayFS module. This provides a very clean interface for
      dealing with the many different overlayfs versions that we interact with.
      Provides great tools for mounting, unmounting, listing, saving and
      printing out tree representation.

    - Consolidated eunmount_recursive, eunmount_rm and eunmount into a 
      single function with flags to control its behavior. This single function
      can now optionally unmount recursively and also optionally remove the
      mount point (recursively) if desired. It also has the ability to continue
      unmounting while something is mounted beneath the mount point.

    - Add multi-character support to array_join. Can now also optionally include
      the delimiter before or after (or both) all joined elements.

    - Add a config file, and configurable colors for the common functions.
      Common color variables include COLOR_INFO, COLOR_DEBUG, COLOR_WARN, and
      COLOR_ERROR, however there are also others available, and this list may be
      extended in the future.

    - Prompts and progress tickers are now shown in bold using the default
      terminal foreground color.

    - Added configuration to allow forge to package bashutils.

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

    - Fixed bug on calling exit without specifying an exit code.


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
