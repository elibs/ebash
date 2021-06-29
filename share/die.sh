#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# DIE
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage die_on_error <<'END'
`die_on_error` registers a trap handler for `ERR`. It is extremely important that we use this mechanism instead of the
expected `set -e` so that we have control over how the process exit is handled by calling our own internal `die`
handler. This allows us to either exit or kill the entire process tree as needed.

> **_NOTE:_** This is extremely unobvious, but setting a trap on `ERR` implicitly enables `set -e`.
END
die_on_error()
{
    trap "die ${DIE_MSG_UNHERR}" ERR
}

opt_usage nodie_on_error <<'END'
`nodie_on_error` disable the ebash `ERR` trap handler. Calling this is akin to calling `set +e`. ebash will no longer
detect errors for you in this shell.
END
nodie_on_error()
{
    trap - ERR
}

opt_usage exit <<'END'
`exit` is a replacement for the builtin `exit` function with our own internal `exit` function so we can detect abnormal
exit conditions through an `EXIT` trap which we setup to ensure `die` is called on exit if it didn't go through our own
internal exit mechanism.

The primary use case for this trickery is to detect and catch unset variables. With `set -u` turned on, bash immediately
exits the program -- NOT by calling bash `exit` function but by calling the C `exit(2)` function. The problem is that
even though it exits, it does NOT call the `ERR` trap. Thus `die` doesn't get invoked even though there was a fatal
error causing abnormal termination. We can catch this scenario by setting up an `EXIT` trap and invoking `die` if exit
was invoked outside of our internal exit function.

The other advantage to this approach is that if someone calls `exit` directly inside bash code sourcing ebash in order to
gracefully exit they probably do NOT want to see a stacktrace and have `die` get invoked. This mechanism will ensure
that works properly because they will go through our internal exit function and that will bypass `die`.
END
exit()
{
    local exit_code=$?
    # Mark that this was an internal exit so that in our die mechanism we won't call die if it already went through our
    # internal exit function.
    __EBASH_INTERNAL_EXIT=1
    builtin exit ${1:-${exit_code}}
}

opt_usage disable_die_stacktrace <<'END'
`disable_die_stacktrace` is a convenience mechanism for disabling stacktraces emitted by `die`. They can be re-enabled
via `enable_die_stacktrace`.
END
disable_die_stacktrace()
{
    __EBASH_DIE_STACKTRACE_ENABLED=0
}

opt_usage enable_die_stacktrace <<'END'
`enable_die_stacktrace` is a convenience mechanism for enabling stacktraces emitted by `die`. They can be disabled via
`disable_die_stacktrace`.
END
enable_die_stacktrace()
{
    __EBASH_DIE_STACKTRACE_ENABLED=1
}

opt_usage die_stacktrace_enabled <<'END'
`die_stacktrace_enabled` returns success (0) if `die` should emit stacktraces and failure (1) otherwise.
END
die_stacktrace_enabled()
{
    [[ ${__EBASH_DIE_STACKTRACE_ENABLED:-1} -eq 1 ]]
}

opt_usage die <<'END'
`die` is our central error handling function for all ebash code which is called on any unhandled error or via the `ERR`
trap. It is responsible for printing a stacktrace to STDERR indicating the source of the fatal error and then killing
our process tree and finally signalling our parent process that we died via `SIGTERM`. With this careful setup, we do
not need to do any error checking in our bash scripts. Instead we rely on the `ERR` trap getting invoked for any
unhandled error which will call `die`. At that point we take extra care to ensure that process and all its children exit
with error.

You may call die and tell it what message to print upon death if you'd like to produce a descriptive error message.
END
die()
{
    # Capture off our BASHPID into a local variable so we can use it in subsequent commands which cannot use BASHPID
    # directly because they are in subshells and the value of BASHPID would be altered by their context.
    #
    # WARNING: Do NOT use PPID instead of the $(ps) command because PPID is the parent of $$ not necessarily the parent
    # of ${BASHPID}!
    local pid=${BASHPID}
    local parent
    parent=$(process_parent ${pid})

    # Disable traps for any signal during most of die. We'll reset the traps to existing state prior to exiting so that
    # the exit trap will honor them.
    disable_signals

    if [[ ${__EBASH_DIE_IN_PROGRESS:=0} -ne 0 ]] ; then
        exit ${__EBASH_DIE_IN_PROGRESS}
    fi

    $(opt_parse \
        ":return_code rc r=1 | Return code that die will eventually exit with." \
        ":signal s           | Signal that caused this die to occur." \
        ":color c            | DEPRECATED OPTION -- no longer has any effect." \
        ":frames f=3         | Number of stack frames to skip." \
        "+nostack n          | Do not print a stacktrace." \
        "@message            | Message to display.")

    __EBASH_DIE_IN_PROGRESS=${return_code}
    : ${__EBASH_DIE_BY_SIGNAL:=${signal}}

    # If we are inside a try/catch, or die() stacktraces have been disabled via disable_die_stacktrace then bypass
    # printing the stacktrace.
    if ! die_stacktrace_enabled || inside_try ; then
        edebug "Skipping die() stacktrace due to die_stacktrace_enabled or inside_try"
        true

    else
        echo "" >&2
        __eerror_internal   -c="${COLOR_ERROR}" "${message[*]:-}"
        if [[ ${nostack} -eq 0 ]] ; then
            eerror_stacktrace -c="${COLOR_ERROR}" -f=${frames} -s
        fi
    fi

    reenable_signals

    # If we're in a subshell signal our parent SIGTERM and then exit. This will allow the parent process to gracefully
    # perform any cleanup before the process ultimately exits.
    if [[ $$ != ${BASHPID} ]]; then

        # Kill the parent shell. This is how we detect failures inside command substituion shells. Bash would
        # typically ignore them, but this causes the shell calling the command substitution to fail and call die.
        #
        # Note: The shell that makes up the "try" body of a try/catch is special. We don't want to kill the try, we
        # want to let the catch handle things.
        if [[ ${__EBASH_DISABLE_DIE_PARENT_PID:-0} != ${pid} ]] ; then
            edebug "Sending kill to parent $(lval parent pid __EBASH_DISABLE_DIE_PARENT_PID)"
            ekill -s=SIGTERM ${parent}
        fi

        # Then kill all children of the current process (but not the current process)
        edebug "Killing children of ${pid}"
        ekilltree -s=SIGTERM -k=2s -x=${pid} ${pid}

        # Last, finish up the current process.
        if [[ -n "${__EBASH_DIE_BY_SIGNAL}" ]] ; then
            # When a process dies as the result of a SIGINT or other tty signals, the proper thing to do is not to exit
            # but to kill self with that same signal.
            #
            # See http://www.cons.org/cracauer/sigint.html and http://mywiki.wooledge.org/SignalTrap
            if array_contains TTY_SIGNALS "${__EBASH_DIE_BY_SIGNAL}" ; then
                trap - ${__EBASH_DIE_BY_SIGNAL}
                ekill -s=${__EBASH_DIE_BY_SIGNAL} ${BASHPID}
            else
                exit $(sigexitcode "${__EBASH_DIE_BY_SIGNAL}")
            fi
        else
            exit ${__EBASH_DIE_IN_PROGRESS}
        fi
    else
        if declare -f die_handler &>/dev/null; then
            die_handler -r=${__EBASH_DIE_IN_PROGRESS} "${@}"
            __EBASH_DIE_IN_PROGRESS=0
        else
            ekilltree -s=SIGTERM -k=2s $$
            exit ${__EBASH_DIE_IN_PROGRESS}
        fi
    fi
}

_ebash_on_exit_start()
{
    # Save off the exit code the first time the exit trap is called -- it can be reinvoked multiple times in the process
    # of the shell going down.
    local exit_code=$?
    if [[ ! -v __EBASH_EXIT_CODE ]] ; then
        # Store off the exit code. This is used at the end of the exit trap inside _ebash_on_exit_end.
        __EBASH_EXIT_CODE=${exit_code}
        disable_signals
    fi
}

_ebash_on_exit_end()
{
    reenable_signals

    # If we're exiting with non-zero exit code, make sure that it occurred through our custom exit function. The only
    # reason we currently believe that it will _not_ go through that path is if bash dies due to an unset variable.
    #
    # Then we execute die to try to make it more clear where things went crazy.
    if [[ ${__EBASH_INTERNAL_EXIT:-0} != "1" && ${__EBASH_EXIT_CODE:-} != "0" ]]; then
        eval "die ${DIE_MSG_UNHERR}"
    fi
}

# List of signals which will cause die() to be called. These signals are the ones which by default bash uses to cause a
# program to terminate or abort. It may seem odd to register traps for things like SIGKILL since you can't IGNORE
# signals like that. However, you can still register a trap instead of the default handler bash uses and do something
# BEFORE you are terminated. If you don't register new traps for these signals then you get really annoying error
# messages whenever a process is killed or aborted.
#
# NOTE: We use this list below in die_on_abort and nodie_on_abort which we call shortly below this as our global default
# traps. Additionally, it is very important to call die_on_abort at the start of any command substitution which you want
# to be interruptible.
DIE_SIGNALS=( SIGHUP    SIGINT   SIGQUIT   SIGILL   SIGABRT   SIGFPE   SIGKILL
              SIGSEGV   SIGPIPE  SIGALRM   SIGTERM  SIGUSR1   SIGUSR2  SIGBUS
              SIGIO     SIGPROF  SIGSYS    SIGTRAP  SIGVTALRM SIGXCPU  SIGXFSZ
            )

# These signals are typically generated by the TTY when the person at the terminal hits a key. Typical terminals have
# them configured to be SIGINT on Ctrl-C, SIGQUIT on Ctrl-\, and SIGTSTP on Ctrl-Z.
#
# The funny thing about the way the TTY sends the signals is that they go to the whole process group at once, rather
# than just, say, the foreground process.
TTY_SIGNALS=( SIGINT SIGQUIT SIGTSTP )

opt_usage die_on_abort <<'END'
Enable default traps for all DIE_SIGNALS to call `die`.
END
die_on_abort()
{
    export __EBASH_DIE_ON_ABORT_ENABLED=1

    local signal
    for signal in "${DIE_SIGNALS[@]}" ; do
        trap "die -s=${signal} \"[Caught ${signal} pid=\${BASHPID} cmd=\$(string_truncate -e \$(tput cols) \${BASH_COMMAND})\"]" ${signal}
    done
}

opt_usage nodie_on_abort <<'END'
Disable default traps for all DIE_SIGNALS.
END
nodie_on_abort()
{
    export __EBASH_DIE_ON_ABORT_ENABLED=0

    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( ${DIE_SIGNALS[@]} )
    trap - "${signals[@]}"
}
