# Bashutils 1.2

    - Removed the option parsing functionality from declare_args and let its
      single purpose be handling positional arguments.

    - Added declare_opts to do option parsing.  To use it, you'll typically
      call declare_opts prior to declare_args in any function that you want to
      handle options.  Declare_opts supports both short and long options and is
      friendlier to callers of functions that use it.  For instance, you don't
      have to use an equal sign to specify a value for an option (although you
      still may)

    - Created new general purpose abstract filesystem module. This provides
      common functions for creating, extracting, listing, mounting, unmounting
      and converting ISOs, squashfs images, and all supported tar file formats.

    - Added OverlayFS support into filesystem module. This provides a very
      clean interface for dealing with the many different overlayfs versions
      that we interact with. Provides great tools for mounting, unmounting,
      listing, saving and printing out tree representation.

    - Consolidated eunmount_recursive, eunmount_rm and eunmount into a 
      single function with flags to control its behavior. This single function
      can now optionally unmount recursively and also optionally remove the
      mount point (recursively) if desired. It also has the ability to continue
      unmounting while something is mounted beneath the mount point.

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
