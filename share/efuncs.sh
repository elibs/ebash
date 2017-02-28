#!/bin/bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

#---------------------------------------------------------------------------------------------------
# GLOBAL EFUNCS SETTINGS
#---------------------------------------------------------------------------------------------------
set -o pipefail
set -o nounset
set -o functrace
set -o errtrace
shopt -s expand_aliases
shopt -s checkwinsize
shopt -s extglob

alias enable_trace='[[ -n ${ETRACE:-} && ${ETRACE:-} != "0" ]] && trap etrace DEBUG || trap - DEBUG'

#---------------------------------------------------------------------------------------------------
# TRY / CATCH
#---------------------------------------------------------------------------------------------------

DIE_MSG_KILLED='[Killed]'
DIE_MSG_CAUGHT='[ExceptionCaught pid=$BASHPID cmd=$(string_truncate -e 60 ${BASH_COMMAND})]'
DIE_MSG_UNHERR='[UnhandledError pid=$BASHPID cmd=$(string_truncate -e 60 ${BASH_COMMAND})]'


# The below aliases allow us to support rich error handling through the use
# of the try/catch idom typically found in higher level languages. Essentially
# the 'try' alias creates a subshell and then turns on implicit error handling
# through "die_on_error" (which essentially just enables 'set -e'). Since this
# runs in a subshell with fatal error handling enabled, the subshell will
# immediately exit on failure. The catch block which immediately follows the
# try block captures the exit status of the subshell and if it's not '0' it
# will invoke the catch block to handle the error.
#
# One clever trick employed here is to keep track of what level of the try/catch
# stack we are in so that the parent's ERR trap won't get triggered and cause
# the process to exit. Because we WANT the try subshell to exit and allow the
# failure to be handled inside the catch block.
__BU_DIE_ON_ERROR_TRAP_STACK=()
alias try="
    __BU_DIE_ON_ERROR_TRAP=\"\$(trap -p ERR | sed -e 's|trap -- ||' -e 's| ERR||' -e \"s|^'||\" -e \"s|'$||\" || true)\"
    : \${__BU_DIE_ON_ERROR_TRAP:=-}
    __BU_DIE_ON_ERROR_TRAP_STACK+=( \"\${__BU_DIE_ON_ERROR_TRAP}\" )
    nodie_on_error
    (
        __BU_INSIDE_TRY=1
        declare __BU_DISABLE_DIE_PARENT_PID=\${BASHPID}
        enable_trace
        die_on_abort
        trap 'die -r=\$? ${DIE_MSG_CAUGHT}' ERR
    "


# Catch block attached to a preceeding try block. This is a rather complex
# alias and it's probably not readily obvious why it jumps through the hoops
# it is jumping through but trust me they are all important. A few important
# notes about this alias:
#
# (1) Note that the ");" ends the preceeding subshell created by the "try"
#     block. Which means that a try block on it's own will be invalid syntax
#     to try to force try/catch to always be used properly.
#
# (2) All of the "|| true" stuff in this alias is extremely important. Without
#     it the implicit error handling will kick in and the process will be
#     terminated immediately instead of allowing the catch() block to handle
#     the error.
#
# (3) It's often really convenient for the catch block to know what the error
#     code was inside the try block. But that's actually kinda of hard to get
#     right. So here we capture the error code, and then we employ a curious
#     "( exit $rc; ) ||" to create a NEW subshell which exits with the original
#     try block's status. If it was 0 this will do nothing. Otherwise it will
#     call the catch block handling code. If we didn't care about the nesting
#     levels this wouldn't be necessary and we could just simplify the catch
#     alias to "); ||". But knowing the nesting level is really important.
#
# (4) The dangling "||" here requries the caller to put something after the
#     catch block which sufficiently handles the error or the code won't be
#     valid.
alias catch=" );
    __BU_TRY_CATCH_RC=\$?
    __BU_DIE_ON_ERROR_TRAP=\"\${__BU_DIE_ON_ERROR_TRAP_STACK[@]:(-1)}\"
    unset __BU_DIE_ON_ERROR_TRAP_STACK[\${#__BU_DIE_ON_ERROR_TRAP_STACK[@]}-1]
    trap \"\${__BU_DIE_ON_ERROR_TRAP}\" ERR
    ( exit \${__BU_TRY_CATCH_RC} ) || "

# Throw is just a simple wrapper around exit but it looks a little nicer inside
# a 'try' block to see 'throw' instead of 'exit'.
throw()
{
    exit $1
}

# Returns true (0) if the current code is executing inside a try/catch block
# and false otherwise.
#
inside_try()
{
    [[ ${__BU_INSIDE_TRY:-0} -eq 1 ]]
}

# die_on_error registers a trap handler for ERR. It is extremely important that
# we use this mechanism instead of the expected 'set -e' so that we have
# control over how the process exit is handled by calling our own internal
# 'die' handler. This allows us to either exit or kill the entire process tree
# as needed.
#
# NOTE: This is extremely unobvious, but setting a trap on ERR implicitly
# enables 'set -e'.
die_on_error()
{
    trap "die ${DIE_MSG_UNHERR}" ERR
}

# disable the bashutils ERR trap handler.  Calling this is akin to calling 'set
# +e'.  Bashutils will no longer detect errors for you in this shell.
#
nodie_on_error()
{
    trap - ERR
}

# Prevent an error or other die call in the _current_ shell from killing its
# parent.  By default with bashutils, errors propagate to the parent by sending
# the parent a sigterm.
#
# You might want to use this in shells that you put in the background if you
# don't want an error in them to cause you to be notified via sigterm.
#
alias disable_die_parent="declare __BU_DISABLE_DIE_PARENT_PID=\${BASHPID}"

# Convert stream names (e.g. 'stdout') to cannonical file descriptor numbers:
#
# stdin=0
# stdout=1
# stderr=2
#
# Any other names will result in an error.
get_stream_fd()
{
    case "$1" in
        stdin ) echo "0"; return 0 ;;
        stdout) echo "1"; return 0 ;;
        stderr) echo "2"; return 0 ;;

        *) die "Unsupported stream=$1"
    esac
}

# Close file descriptors that are currently open.  This can be important
# because child processes inherit all of their parent's file descriptors, but
# frequently don't need access to them.  Sometimes the fact that those
# descriptors are still open can even cause problems (e.g. if a FIFO has more
# writers than expected, its reader may not get the EOF it is expecting.)
#
# This function closes all open file descriptors EXCEPT stdin (0),
# stdout (1), and stderr (2).  Technically, you can close those on your own if
# you want via syntax like this:
#    exec 0>&- 1>&- 2>&-
#
# But practically speaking, it's likely to cause problems.  For instance, hangs
# or errors when something tries to write to or read from one of those.  It's a
# better idea to do this intead if you really don't want your
# stdin/stdout/stderr inherited:
#
#   exec 0</dev/null 1>/dev/null 2>/dev/null
#
# We also never close fd 255.  Bash considers that its own.  For instance,
# sometimes that's open to the script you're currently executing.
#
close_fds()
{
    # Note grab file descriptors for the current process, not the one inside
    # the command substitution ls here.
    local pid=$BASHPID
    local fds=( $(ls $(fd_path)/ | grep -vP '^(0|1|2|255)$' | tr '\n' ' ') )

    array_empty fds && return 0

    local fd
    for fd in "${fds[@]}"; do
        eval "exec $fd>&-"
    done
}

fd_path()
{
    if [[ ${__BU_OS} == Linux ]] ; then
        echo /proc/self/fd

    elif [[ ${__BU_OS} == Darwin ]] ; then
        echo /dev/fd

    else
        die "Unsupported OS $(lval __BU_OS)"
    fi
}

opt_usage pipe_read "Helper method to read from a pipe until we see EOF."
pipe_read()
{
    $(opt_parse "pipe")
    local line
    
    # Read returns an error when it reaches EOF. But we still want to emit that
    # last line. So if we failed to read due to EOF but saw a partial line we
    # still want to echo it.
    #
    # NOTE: IFS='' and "-r" flag are critical here to ensure we don't lose
    # whitespace or try to interpret anything.
    while IFS= read -r line || [[ -n "${line}" ]]; do
        echo "${line}"
    done <${pipe}
}

opt_usage pipe_read_quote <<'END'
Helper method to read from a pipe until we see EOF and then also intelligently quote the output in a
way that can be reused as shell input via "printf %q". This will allow us to safely eval the input
without fear of anything being exectued.

NOTE: This method will echo "" instead of using printf if the output is an empty string to avoid
causing various test failures where we'd expect an empty string ("") instead of a string with literl
quotes in it ("''").
END
pipe_read_quote()
{
    $(opt_parse "pipe")
    local output=$(pipe_read ${pipe})
    if [[ -n ${output} ]]; then
        printf %q "$(printf "%q" "${output}")"
    else
        echo -n ""
    fi
}

opt_usage tryrc <<'END'
Tryrc is a convenience wrapper around try/catch that makes it really easy to execute a given command
and capture the command's return code, stdout and stderr into local variables. We created this idiom
because if you handle the failure of a command in any way then bash effectively disables set -e that
command invocation REGARDLESS OF DEPTH. "Handling the failure" includes putting it in a while or
until loop, part of an if/else statement or part of a command executed in a && or ||.

Consider a function call chain such as:

    foo->bar->zap

and you want to get the return value from foo, you might (wrongly) think you could safely use this
and safely bypass set -e explosion:

    foo || rc=$?

The problem is bash effectively disables "set -e" for this command when used in this context. That
means even if zap encounteres an unhandled error die() will NOT get implicitly called (explicit
calls to die would still get called of course).

Here's the insidious documentation from 'man bash' regarding this obscene behavior:

    "The ERR trap is not executed if the failed command is part of the command list immediately
    following a while or until keyword, part of the test in an if statement, part of a command
    executed in a && or ||  list  except the command following the final && or ||, any command in a
    pipeline but the last, or if the command's return value is being inverted using !."

What's not obvious from that statement is that this applies to the entire expression including any
functions it may call not just the top-level expression that had an error. Ick.

Thus we created tryrc to allow safely capturing the return code, stdout and stderr of a function
call WITHOUT bypassing set -e safety!

This is invoked using the "eval command invocation string" idiom so that it is invoked in the
caller's envionment. For example: $(tryrc some-command)
END
tryrc()
{
    $(opt_parse \
        ":rc r=rc  | Variable to assign the return code to." \
        ":stdout o | Write stdout to the specified variable rather than letting it go to stdout." \
        ":stderr e | Write stderr to the specified variable rather than letting it go to stderr." \
        "+global g | Make variables created global rather than local" \
        "@cmd      | Command to run, along with any arguments.")

    # Determine flags to pass into declare
    local dflags=""
    [[ ${global} -eq 1 ]] && dflags="-g"

    # Temporary directory to hold stdout and stderr
    local tmpdir=$(mktemp --tmpdir --directory tryrc-XXXXXX)
    trap_add "rm --recursive --force ${tmpdir}"

    # Create temporary file for stdout and stderr
    local stdout_file="${tmpdir}/stdout" stderr_file="${tmpdir}/stderr"

    # We're creating an "eval command string" inside the command substitution
    # that the caller is supposed to wrap around tryrc.
    #
    # Command substitution really can only run one big command.  In other
    # words, everything after the first command inside it is passed as an
    # argument to the first command.  But you can separate multiple commands by
    # semicolons inside an eval, so we put an eval around the entire output of
    # tryrc.
    #
    # Later you'll see we also put eval around the inside commands.  We
    # basically quote everything twice and then make up for it by eval-ing
    # everything twice in order to convince everything to keep whitespace as it
    # is.
    echo eval

    # Need to first make sure we've emitted code to set our output variables in the
    # event we are interrupted
    echo eval "declare ${dflags} ${rc}=1;"
    [[ -n ${stdout} ]] && echo eval "declare ${dflags} ${stdout}="";"
    [[ -n ${stderr} ]] && echo eval "declare ${dflags} ${stderr}="";"

    # Execute actual command in try/catch so that any fatal errors in the command
    # properly terminate execution of the command then capture off the return code
    # in the catch block. Send all stdout and stderr to respective pipes which will
    # be read in by the above background processes.
    local actual_rc=0
    try
    {
        if [[ -n "${cmd[@]:-}" ]]; then

            # Redirect subshell's STDOUT and STDERR to requested locations
            exec >${stdout_file}
            [[ -n ${stderr} ]] && exec 2>${stderr_file}

            # Run command
            quote_eval "${cmd[@]}"
        fi
    }
    catch
    {
        actual_rc=$?
    }

    # Emit commands to assign return code 
    echo eval "declare ${dflags} ${rc}=${actual_rc};"

    # Emit commands to assign stdout but ONLY if a stdout file was actually created.
    # This is because the file is only created on first write. And we don't want this
    # to fail if the command didn't write any stdout. This is also SAFE because we
    # initialize stdout and stderr above to empty strings.
    if [[ -s ${stdout_file} ]]; then
        local actual_stdout="$(pipe_read_quote ${stdout_file})"
        if [[ -n ${stdout} ]]; then
            echo eval "declare ${dflags} ${stdout}=${actual_stdout};"
        else
            echo eval "echo ${actual_stdout} >&1;"
        fi
    fi

    # Emit commands to assign stderr
    if [[ -n ${stderr} && -s ${stderr_file} ]]; then
        local actual_stderr="$(pipe_read_quote ${stderr_file})"
        echo eval "declare ${dflags} ${stderr}=${actual_stderr};"
    fi

    # Remote temporary directory
    rm --recursive --force ${tmpdir}
}

#---------------------------------------------------------------------------------------------------
# TRAPS / DIE / STACKTRACE
#---------------------------------------------------------------------------------------------------

opt_usage stacktrace <<'END'
Print stacktrace to stdout. Each frame of the stacktrace is separated by a newline. Allows you to
optionally pass in a starting frame to start the stacktrace at. 0 is the top of the stack and counts
up. See also stacktrace and error_stacktrace.
END
stacktrace()
{
    $(opt_parse ":frame f=0 | Frame number to start at if not the current one")

    while caller ${frame}; do
        (( frame+=1 ))
    done
}

opt_usage stacktrace_array <<'END'
Populate an array with the frames of the current stacktrace. Allows you to optionally pass in a
starting frame to start the stacktrace at. 0 is the top of the stack and counts up. See also
stacktrace and eerror_stacktrace
END
stacktrace_array()
{
    $(opt_parse \
        ":frame f=1 | Frame number to start at" \
        "array")

    array_init_nl ${array} "$(stacktrace -f=${frame})"
}

opt_usage trap_get <<'END'
Print the trap command associated with a given signal (if any). This essentially parses trap -p in
order to extract the command from that trap for use in other functions such as call_die_traps and
trap_add.
END
trap_get()
{
    $(opt_parse "sig | Signal name to print traps for.")

    # Normalize the signal description (which might be a name or a number) into
    # the form trap produces
    sig="$(signame -s "${sig}")"

    local existing=$(trap -p "${sig}")
    existing=${existing##trap -- \'}
    existing=${existing%%\' ${sig}}

    echo -n "${existing}"
}

# Replace normal exit function with our own internal exit function so we can
# detect abnormal exit conditions through an EXIT trap which we setup to ensure
# die() is called on exit if it didn't go through our own internal exit mechanism.
# 
# The primary use case for this trickery is to detect and catch unset variables.
# With "set -u" turned on, bash immediately exits the program -- NOT by calling
# bash exit function but by calling the C exit(2) function. The problem is that 
# even though it exits, it does NOT call the ERR trap. Thus die() doesn't get 
# invoked even though there was a fatal error causing abnormal termination. We
# can catch this scenario by setting up an EXIT trap and invoking die() if exit
# was invoked outside of our internal exit function.
#
# The other advantage to this approach is that if someone calls exit directly
# inside bash code sourcing bashutils in order to gracefully exit they probably
# do NOT want to see a stacktrace and have die() get invoked. This mechanism
# will ensure that works properly b/c they will go through our internal exit
# function and that will bypass die().
#
exit()
{
    local exit_code=$?
    # Mark that this was an internal exit so that in our die mechanism we
    # won't call die if it already went through our internal exit function.
    __BU_INTERNAL_EXIT=1
    builtin exit ${1:-${exit_code}}
}

opt_usage die <<'END'
die is our central error handling function for all bashutils code which is called on any unhandled
error or via the ERR trap. It is responsible for printing a stacktrace to STDERR indicating the
source of the fatal error and then killing our process tree and finally signalling our parent
process that we died via SIGTERM. With this careful setup, we do not need to do any error checking
in our bash scripts. Instead we rely on the ERR trap getting invoked for any unhandled error which
will call die(). At that point we take extra care to ensure that process and all its children exit
with error.

You may call die and tell it what message to print upon death if you'd like to produce a descriptive
error message.
END
die()
{
    # Capture off our BASHPID into a local variable so we can use it in subsequent
    # commands which cannot use BASHPID directly because they are in subshells and
    # the value of BASHPID would be altered by their context. 
    # WARNING: Do NOT use PPID instead of the $(ps) command because PPID is the
    #          parent of $$ not necessarily the parent of ${BASHPID}!
    local pid=${BASHPID}
    local parent=$(process_parent ${pid})

    # Disable traps for any signal during most of die.  We'll reset the traps
    # to existing state prior to exiting so that the exit trap will honor them.
    disable_signals

    if [[ ${__BU_DIE_IN_PROGRESS:=0} -ne 0 ]] ; then
        exit ${__BU_DIE_IN_PROGRESS}
    fi
    
    $(opt_parse \
        ":return_code rc r=1 | Return code that die will eventually exit with." \
        ":signal s           | Signal that caused this die to occur." \
        ":color c            | DEPRECATED OPTION -- no longer has any effect." \
        ":frames f=3         | Number of stack frames to skip." \
        "@message            | Message to display.")

    __BU_DIE_IN_PROGRESS=${return_code}
    : ${__BU_DIE_BY_SIGNAL:=${signal}}

    if inside_try ; then
        # Don't print a stack trace for errors that were caught
        true

    else
        echo "" >&2
        eerror_internal   -c="${COLOR_ERROR}" "${message[*]:-}"
        eerror_stacktrace -c="${COLOR_ERROR}" -f=${frames} -s
    fi

    reenable_signals

    # If we're in a subshell signal our parent SIGTERM and then exit. This will
    # allow the parent process to gracefully perform any cleanup before the
    # process ultimately exits.
    if [[ $$ != ${BASHPID} ]]; then
        
        # Kill the parent shell.  This is how we detect failures inside command
        # substituion shells.  Bash would typically ignore them, but this
        # causes the shell calling the command substitution to fail and call die.
        #
        # Note: The shell that makes up the "try" body of a try/catch is
        # special.  We don't want to kill the try, we want to let the catch
        # handle things.
        #
        if [[ ${__BU_DISABLE_DIE_PARENT_PID:-0} != ${pid} ]] ; then
            edebug "Sending kill to parent $(lval parent pid __BU_DISABLE_DIE_PARENT_PID)"
            ekill -s=SIGTERM ${parent}
        fi

        # Then kill all children of the current process (but not the current process)
        edebug "Killing children of ${pid}"
        ekilltree -s=SIGTERM -k=2s -x=${pid} ${pid}

        # Last, finish up the current process. 
        if [[ -n "${__BU_DIE_BY_SIGNAL}" ]] ; then
            # When a process dies as the result of a SIGINT or other tty
            # signals, the proper thing to do is not to exit but to kill self
            # with that same signal.
            # 
            # See http://www.cons.org/cracauer/sigint.html and
            # http://mywiki.wooledge.org/SignalTrap
            #
            if array_contains TTY_SIGNALS "${__BU_DIE_BY_SIGNAL}" ; then
                trap - ${__BU_DIE_BY_SIGNAL}
                ekill -s=${__BU_DIE_BY_SIGNAL} ${BASHPID}
            else
                exit $(sigexitcode "${__BU_DIE_BY_SIGNAL}")
            fi
        else
            exit ${__BU_DIE_IN_PROGRESS}
        fi
    else
        if declare -f die_handler &>/dev/null; then
            die_handler -r=${__BU_DIE_IN_PROGRESS} "${@}"
            __BU_DIE_IN_PROGRESS=0
        else
            ekilltree -s=SIGTERM -k=2s $$
            exit ${__BU_DIE_IN_PROGRESS}
        fi
    fi
}

# Save off the current state of signal-based traps and disable them.  You may
# be interested in doing this if you're very concerned that a short bit of code
# should not be interrupted by a signal.  Be _SURE_ to call renable signals
# when you're done.
#
disable_signals()
{
    declare -Ag _BASHUTILS_SAVED_TRAPS
    _BASHUTILS_SAVED_TRAPS[$BASHPID]=$(trap -p "${DIE_SIGNALS[@]}")
    trap "" "${DIE_SIGNALS[@]}"
}

reenable_signals()
{
    eval "${_BASHUTILS_SAVED_TRAPS[$BASHPID]}"
}

opt_usage trap_add <<'END'
Appends a command to a trap. By default this will use the default list of signals:
${DIE_SIGNALS[@]}, ERR and EXIT so that this trap gets called by default for any signal that would
cause termination. If that's not the desired behavior then simply pass in an explicit list of
signals to trap.
END
trap_add()
{
    $(opt_parse \
        "?cmd     | Command to be added to the trap, quoted to be one argument." \
        "@signals | Signals (or pseudo-signals) that should invoke the trap.  Default is EXIT.")

    array_not_empty signals || signals=( "EXIT" )

    local sig
    for sig in "${signals[@]}"; do
        sig=$(signame -s ${sig})

        # If we're at the same shell level where we have set any trap, then
        # it's safe to append to the existing trap.  If we haven't set any trap
        # in this shell level, bash will show us the parent shell's traps
        # instead and we don't want to copy those into this shell.
        local existing=""
        if [[ ${__BU_TRAP_LEVEL:-0} -eq ${BASH_SUBSHELL} ]]; then
            existing="$(trap_get ${sig})"

            # Strip off our bashutils internal cleanup from the trap, because
            # we'll add it back in later.
            existing=${existing%%; _bashutils_on_exit_end}
            existing=${existing##_bashutils_on_exit_start; }

            # __BU_TRAP_LEVEL is owned and updated by our trap() function.
            # It'll update it soon.
        fi

        local complete_trap
        [[ ${sig} == "EXIT" ]] && complete_trap+="_bashutils_on_exit_start; "
        [[ -n "${cmd}"      ]] && complete_trap+="${cmd}; "
        [[ -n "${existing}" ]] && complete_trap+="${existing}; "
        [[ ${sig} == "EXIT" ]] && complete_trap+="_bashutils_on_exit_end"
        trap -- "${complete_trap}" "${sig}"

    done
}


# Bashutils asks bash to let the ERR and DEBUG traps be inherited from shell to
# subshell by setting appropriate shell options.  Unfortunately, its method of
# enforcing that inheritance is somewhat limited.  It only lasts until someone
# sets any other trap.  At that point, the inhertied trap is erased.
#
# To workaround this behavior, bashutils overrides "trap" such that it will do
# the normal work that you expect trap to do, but it will also make sure that
# the ERR and DEBUG traps are truly inherited from shell to shell and persist
# regardless of whether other traps are created.
#
trap()
{
    # If trap received any options, don't do anything special.  Only -l and -p
    # are supported by bash's trap and they don't affect the current set of
    # traps.
    if [[ "$1" == "--" || "$1" != -* ]] ; then

        # __BU_TRAP_LEVEL is the ${BASH_SUBSHELL} value that was used the last time
        # trap was called.  BASH_SUBSHELL is incremented for each nested subshell.
        # At the top level, that is 0
        if [[ ${__BU_TRAP_LEVEL:=0} -lt ${BASH_SUBSHELL} ]] ; then

            local trapsToSave="$(builtin trap -p ERR DEBUG)"

            # Call "builtin trap" rather than "trap" because we don't want to
            # recurse infinitely.  Note, the backslashes before the hyphens in
            # this pattern are superfluous to bash, but they make vim's syntax
            # highlighting much happier.
            trapsToSave="${trapsToSave//trap --/builtin trap \-\-}"

            # Call the trap builtin to set those ERR and DEBUG traps first
            eval "${trapsToSave}"

            __BU_TRAP_LEVEL=${BASH_SUBSHELL}
        fi

    fi

    builtin trap "${@}"
}


_bashutils_on_exit_start()
{
    # Save off the exit code the fist time the exit trap is called -- it can be
    # reinvoked multiple times in the process of the shell going down.
    #
    local exit_code=$?
    if [[ ! -v __BU_EXIT_CODE ]] ; then
        # Store off the exit code. This is used at the end of the exit trap inside _bashutils_on_exit_end.
        __BU_EXIT_CODE=${exit_code}
        disable_signals
    fi
}

_bashutils_on_exit_end()
{
    reenable_signals

    # If we're exiting with non-zero exit code, make sure that it occurred
    # through our custom exit function.  The only reason we currently believe
    # that it will _not_ go through that path is if bash dies due to an unset
    # variable.
    #
    # Then we execute die to try to make it more clear where things went crazy.
    if [[ ${__BU_INTERNAL_EXIT:-0} != "1" && ${__BU_EXIT_CODE:-} != "0" ]]; then
        eval "die ${DIE_MSG_UNHERR}"
    fi
}

# Set the trace attribute for trap_add function. This is required to modify
# DEBUG or RETURN traps because functions don't inherit them unless the trace
# attribute is set.
declare -f -t trap_add

# List of signals which will cause die() to be called. These signals are the ones
# which by default bash uses to cause a program to terminate or abort. It may seem
# odd to register traps for things like SIGKILL since you can't IGNORE signals like
# that. However, you can still register a trap instead of the default handler bash
# uses and do something BEFORE you are terminated. If you don't register new traps
# for these signals then you get really annoying error messages whenever a process
# is killed or aborted.
#
# NOTE: We use this list below in die_on_abort and nodie_on_abort which we call
# shortly below this as our global default traps. Additionally, it is very important
# to call die_on_abort at the start of any command substitution which you want to be
# interruptible.
DIE_SIGNALS=( SIGHUP    SIGINT   SIGQUIT   SIGILL   SIGABRT   SIGFPE   SIGKILL
              SIGSEGV   SIGPIPE  SIGALRM   SIGTERM  SIGUSR1   SIGUSR2  SIGBUS
              SIGIO     SIGPROF  SIGSYS    SIGTRAP  SIGVTALRM SIGXCPU  SIGXFSZ
            )

# These signals are typically generated by the TTY when the person at the
# terminal hits a key.  Typical terminals have them configured to be SIGINT on
# Ctrl-C, SIGQUIT on Ctrl-\, and SIGTSTP on Ctrl-Z.
#
# The funny thing about the way the TTY sends the signals is that they go to
# the whole process group at once, rather than just, say, the foreground
# process.
#
TTY_SIGNALS=( SIGINT SIGQUIT SIGTSTP )

# Enable default traps for all DIE_SIGNALS to call die().
die_on_abort()
{
    export __BU_DIE_ON_ABORT_ENABLED=1

    local signal
    for signal in "${DIE_SIGNALS[@]}" ; do
        trap "die -s=${signal} \"[Caught ${signal} pid=\${BASHPID} cmd=\$(string_truncate -e 60 \${BASH_COMMAND})\"]" ${signal}
    done
}

# Disable default traps for all DIE_SIGNALS.
nodie_on_abort()
{
    export __BU_DIE_ON_ABORT_ENABLED=0

    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( ${DIE_SIGNALS[@]} )
    trap - ${signals[@]}
}

reexec()
{
    # If opt_parse has already been called in the main script, we want to preserve the options that it removed from $@
    # as it worked. Luckily, it saves those off and we can read them from __BU_FULL_ARGS.
    #
    # Determining if __BU_FULL_ARGS contains anything is difficult for a couple reasons.  One is that we want to be
    # compatible with bash 4.2, 4.3, and 4.4 and each behaves differently with respect to emtpy arrays and set -u.  See
    # array_size in array.sh for more info on that.  We'd normally use array_size, but it calls opt_parse which
    # helpfullly overwrites __BU_FULL_ARGS for us. Here, we sidestep the issue by presuming that opt_parse will have
    # done nothing to $@ unless it contains at least one characters, so we'll only do anything if __BU_FULL_ARGS
    # contains at least one character in any one slot in the array.
    #
    if [[ -n "${__BU_FULL_ARGS[*]:-}" ]] ; then
        __BU_REEXEC_CMD=( "${__BU_REEXEC_CMD[0]}" "${__BU_FULL_ARGS[@]}" )
    fi

    $(opt_parse \
        "+sudo     | Ensure this process is root, and use sudo to become root if not." \
        "+mount_ns | Create a new mount namespace to run in.")

    array_not_empty __BU_REEXEC_CMD || die "reexec must be called via its eponymous alias."

    # If sudo was requested and the caller is not already root then exec sudo. Take special care to
    # pass through the TMPDIR variable since glibc silently deletes it from the environment of any
    # suid binary such as sudo. If TMPDIR isn't set, then set it to /tmp which is what would normally
    # happen if the variable wasn't set.
    if [[ ${sudo} -eq 1 && $(id -u) != 0 ]] ; then
        exec sudo TMPDIR=${TMPDIR:-/tmp} -E -- "${__BU_REEXEC_CMD[@]}"
    fi

    if [[ ${mount_ns} -eq 1 && ${__BU_REEXEC_MOUNT_NS:-} != ${BASHPID} ]] ; then
        export __BU_REEXEC_MOUNT_NS=${BASHPID}
        exec unshare -m -- "${__BU_REEXEC_CMD[@]}"
    fi
    unset __BU_REEXEC_CMD
}
alias reexec='declare -a __BU_REEXEC_CMD=("$0" "$@") ; reexec'

#---------------------------------------------------------------------------------------------------
# SIGNAL FUNCTIONS
#---------------------------------------------------------------------------------------------------

# Given a name or number, echo the signal name associated with it.
#
signum()
{
    if [[ "$1" =~ ^[[:digit:]]$ ]] ; then
        echo "$1"

    # For a complete list of bash pseudo-signals, see help trap (this is the
    # complete list at time of writing)
    elif [[ "$1" == "EXIT" || "$1" == "ERR" || "$1" == "DEBUG" || "$1" == "RETURN" ]] ; then
        die "Bash pseudo signal $1 does not have a signal number."

    else
        kill -l "$1"
    fi
    return 0
}

opt_usage signame <<'END'
Given a signal name or number, echo the signal number associated with it.

With the --include-sig option, SIG will be part of the name for signals where that is appropriate.
For instance, SIGTERM or SIGABRT rather than TERM or ABRT.  Note that bash pseudo signals never use
SIG.  This function treats those appropriately (i.e. even with --include sig will return EXIT rather
than SIGEXIT)
END
signame()
{
    $(opt_parse \
        "+include_sig s | Get the form of the signal name that includes SIG.")

    local prefix=""
    if [[ ${include_sig} -eq 1 ]] ; then
        prefix="SIG"
    fi

    if [[ "$1" =~ ^[[:digit:]]+$ ]] ; then
        echo "${prefix}$(kill -l "$1")"

    elif [[ "${1^^}" == "EXIT" || "${1^^}" == "SIGEXIT" ]]; then
        echo "EXIT"

    elif [[ "${1^^}" == "ERR" || "${1^^}" == "SIGERR" ]]; then
        echo "ERR"

    elif [[ "${1^^}" == "DEBUG" || "${1^^}" == "SIGDEBUG" ]]; then
        echo "DEBUG"

    else
        # Find the associated number, and then get the name that bash believes
        # is associated with that number
        echo "${prefix}$(kill -l "$(kill -l "$1")")"
    fi
    return 0
}

# Given a signal name or number, echo the exit code that a bash process
# would produce if it died due to the specified signal.
sigexitcode()
{
    echo "$(( 128 + $(signum $1) ))"
    return 0
}


#---------------------------------------------------------------------------------------------------
# FILESYSTEM HELPERS
#---------------------------------------------------------------------------------------------------

# Variable containing documentation for what we call the "path mapping syntax" idiom. This variable
# can then be used in the docstrings for functions which make use of path mapping syntax without
# having to repeat the documentation (and hence become stale) or refer to another function and be
# less usable.
PATH_MAPPING_SYNTAX_DOC="This function uses the 'path mapping syntax' idiom. Path mapping syntax is a generic idiom used to
map one path to another using a colon to delimit source and destination paths. This is a convenient
idiom often used by functions which need to have a source file and use it in an alternative location
inside the function. For example, '/var/log/kern.log:kern.log' specifies a source file of
'/var/log/kern.log' and a destination file of 'kern.log'. 
    
The path mapping syntax also supports referring to the contents of a directory rather than the
directory itself using scp like syntax. For example, if you wanted to refer to the contents of
/var/log instead of the directory /var/log, you would say '/var/log/.'. The trailing '/.' indicates
the contents of the directory should be used rather than the directory itself. You can also map the
contents of that directory into an alternative destination path using '/var/log/.:logs'."

# Wrapper around pushd to suppress its noisy output.
pushd()
{
    builtin pushd "${@}" >/dev/null
}

# Wrapper around popd to suppress its noisy output.
popd()
{
    builtin popd "${@}" >/dev/null
}

# chmod + chown
echmodown()
{
    [[ $# -ge 3 ]] || die "echmodown requires 3 or more parameters. Called with $# parameters (chmodown $@)."
    $(opt_parse mode owner)

    chmod ${mode} $@
    chown ${owner} $@
}

# Recursively unmount the named directories and remove them (if they exist) then create new ones.
# NOTE: Unlike earlier implementations, this handles multiple arguments properly.
efreshdir()
{
    local mnt
    for mnt in "${@}"; do
        
        [[ -z "${mnt}" ]] && continue

        eunmount -a -r -d "${mnt}"
        mkdir -p ${mnt}
    
    done
}

opt_usage ebackup "Copies the given file to *.bak if it doesn't already exist"
ebackup()
{
    $(opt_parse src)

    [[ -e "${src}" && ! -e "${src}.bak" ]] && cp -arL "${src}" "${src}.bak" || true
}

erestore()
{
    $(opt_parse src)

    [[ -e "${src}.bak" ]] && mv "${src}.bak" "${src}"
}

opt_usage elogrotate <<'END'
elogrotate rotates all the log files with a given basename similar to what happens with logrotate.
It will always touch an empty non-versioned file just log logrotate.

For example, if you pass in the pathname '/var/log/foo' and ask to keep a max of 5, it will do the
following:

    /var/log/foo.4 -> /var/log/foo.5
    /var/log/foo.3 -> /var/log/foo.4
    /var/log/foo.2 -> /var/log/foo.3
    /var/log/foo.1 -> /var/log/foo.2
    /var/log/foo   -> /var/log/foo.1
    touch /var/log/foo
END
elogrotate()
{
    $(opt_parse \
        ":count c=5 | Maximum number of logs to keep" \
        ":size s=0  | If specified, rotate logs at this specified size rather than each call to
                      elogrotate.  You can use these units: c -- bytes, w -- two-byte words, k --
                      kilobytes, m -- Megabytes, G -- gigabytes" \
        "name       | Base name to use for the logfile.")

    # Ensure we don't try to rotate non-files
    [[ -f $(readlink -f "${name}") ]] 

    # Find log files by exactly this name that are of the size that should be rotated
    local files="$(find "$(dirname "${name}")" -maxdepth 1          \
                   -type f                                          \
                   -a -name "$(basename "${name}")"                 \
                   -a \( -size ${size} -o -size +${size} \) )"

    edebug "$(lval name files count size)"

    # If log file exists and is smaller than size threshold just return
    if [[ -z "${files}"  ]]; then
        return 0
    fi

    local log_idx next
    for (( log_idx=${count}; log_idx > 0; log_idx-- )); do
        next=$(( log_idx+1 ))
        [[ -e ${name}.${log_idx} ]] && mv -f ${name}.${log_idx} ${name}.${next}
    done

    # Move non-versioned one over and create empty new file
    [[ -e ${name} ]] && mv -f ${name} ${name}.1
    mkdir -p $(dirname ${name})
    touch ${name}

    # Remove any log files greater than our retention count
    find "$(dirname "${name}")" -maxdepth 1                 \
               -type f -name "$(basename "${name}")"        \
            -o -type f -name "$(basename "${name}").[0-9]*" \
        | sort --version-sort | awk "NR>${count}" | xargs rm -f
}

opt_usage elogfile <<'END'
elogfile provides the ability to duplicate the calling processes STDOUT and STDERR and send them
both to a list of files while simultaneously displaying them to the console. Using this function is
much preferred over manually doing this with tee and named pipe redirection as we take special care
to ensure STDOUT and STDERR pipes are kept separate to avoid problems with logfiles getting
truncated.
END
elogfile()
{
    $(opt_parse \
        "+stderr e=1       | Whether to redirect stderr to the logfile." \
        "+stdout o=1       | Whether to redirect stdout to the logfile." \
        ":rotate_count r=0 | When rotating log files, keep this number of log files." \
        ":rotate_size s=0  | Rotate log files when they reach this size. Units as accepted by find." \
        "+tail t=1         | Whether to continue to display output on local stdout and stderr." \
        "+merge m          | Whether to merge stdout and stderr into a single stream on stdout.")

    edebug "$(lval stdout stderr tail rotate_count rotate_size merge)"

    # Return if nothing to do
    if [[ ${stdout} -eq 0 && ${stderr} -eq 0 ]] || [[ -z "$*" ]]; then
        return 0
    fi

    # Rotate logs as necessary but only if they are regular files
    if [[ ${rotate_count} -gt 0 ]]; then
        local name
        for name in "${@}"; do
            [[ -f $(readlink -f "${name}") ]] || continue
            elogrotate -c=${rotate_count} -s=${rotate_size} "${name}"
        done
    fi

    # Setup EINTERACTIVE so our output formats properly even though stderr
    # won't be connected to a console anymore.
    if [[ ! -v EINTERACTIVE ]]; then
        [[ -t 2 ]] && export EINTERACTIVE=1 || export EINTERACTIVE=0
    fi

    # Export COLUMNS properly so that eend and eprogress output properly
    # even though stderr won't be connected to a console anymore.
    if [[ ! -v COLUMNS ]]; then
        export COLUMNS=$(tput cols)
    fi

    # Temporary directory to hold our FIFOs
    local tmpdir=$(mktemp --tmpdir --directory elogfile-XXXXXX)
    trap_add "rm --recursive --force ${tmpdir}"
    local pid_pipe="${tmpdir}/pids"
    mkfifo "${pid_pipe}"
 
    # Internal function to avoid code duplication in setting up the pipes
    # and redirection for stdout and stderr.
    elogfile_redirect()
    {
        $(opt_parse name)

        # If we're not redirecting the requested stream then just return success
        [[ ${!name} -eq 1 ]] || return 0

        # Create pipe
        local pipe="${tmpdir}/${name}"
        mkfifo "${pipe}"
        edebug "$(lval name pipe)"

        # Double fork so that the process doing the tee won't be one of our children
        # processes anymore. The purose of this is to ensure when we kill our process
        # tree that we won't kill the tee process. If we allowed tee to get killed
        # then any future output would HANG indefinitely because there wouldn't be
        # a reader attached to the pipe. Without a reader attached to the pipe all
        # writes block indefinitely. Since this is blocking in the kernel the process
        # essentially becomes unkillable once in this state.
        (
            disable_die_parent
            close_fds
            ( 
                # If we are in a cgroup, move the tee process out of that
                # cgroup so that we do not kill the tee.  It will nicely
                # terminate on its own once the process dies.
                if cgroup_supported && [[ ${EUID} -eq 0 && -n "$(cgroup_current)" ]] ; then
                    edebug "Moving tee process out of cgroup"
                    cgroup_move "/" ${BASHPID}
                fi

                # Ignore signals that came from the TTY for these special
                # processes.
                #
                # This will keep them alive long enough to display our error
                # output and such.  SIGPIPE will take care of them, and the
                # kill -9 below will make double sure.
                #
                trap "" ${TTY_SIGNALS[@]}
                echo "${BASHPID}" >${pid_pipe}

                # Past this point, we hand control to the tee processes which
                # we expect to die in their own time.  We no longer want to be
                # notified if something goes wrong (such as the tee being
                # killed)
                nodie_on_error

                if [[ ${tail} -eq 1 ]]; then
                    tee -a "${@}" <${pipe} >&$(get_stream_fd ${name}) 2>/dev/null
                else
                    tee -a "${@}" <${pipe} >/dev/null 2>&1
                fi
            ) &
        ) &

        # Grab the pid of the backgrounded pipe process and setup a trap to ensure
        # we kill it when we exit for any reason.
        local pid=$(cat ${pid_pipe})
        trap_add "kill -9 ${pid} 2>/dev/null || true"

        # Finally re-exec so that our output stream(s) are redirected to the pipe.
        # NOTE: If we're merging stdout+stderr we redirect both streams into the pipe
        if [[ ${merge} -eq 1 ]]; then
            eval "exec &>${pipe}"
        else
            eval "exec $(get_stream_fd ${name})>${pipe}"
        fi
    }

    # Redirect stdout and stderr as requested to the provided list of files.
    if [[ ${merge} -eq 1 ]]; then
        elogfile_redirect stdout "${@}"
    else
        elogfile_redirect stdout "${@}"
        elogfile_redirect stderr "${@}"
    fi
}

opt_usage emd5sum <<'END'
Wrapper around computing the md5sum of a file to output just the filename instead of the full path
to the filename. This is a departure from normal md5sum for good reason. If you download an md5 file
with a path embedded into it then the md5sum can only be validated if you put it in the exact same
path. This function will die on failure.
END
emd5sum()
{
    $(opt_parse path)

    local dname=$(dirname  "${path}")
    local fname=$(basename "${path}")

    pushd "${dname}"
    md5sum "${fname}"
    popd
}

opt_usage emd5sum_check <<'END'
Wrapper around checking an md5sum file by pushd into the directory that contains the md5 file so
that paths to the file don't affect the md5sum check. This assumes that the md5 file is a sibling
next to the source file with the suffix 'md5'. This method will die on failure.
END
emd5sum_check()
{
    $(opt_parse path)

    local fname=$(basename "${path}")
    local dname=$(dirname  "${path}")

    pushd "${dname}"
    md5sum -c "${fname}.md5" | edebug
    popd
}

opt_usage emetadata <<'END'
Output checksum information for the given file to STDOUT. Specifically output
the following:

    Filename=foo
    MD5=864ec6157c1eea88acfef44d0f34d219
    Size=2192793069
    SHA1=75490a32967169452c10c937784163126c4e9753
    SHA256=8297aefe5bb7319ab5827169fce2e664fe9cd7b88c9b31c40658ab55fcae3bfe
END
emetadata()
{
    $(opt_parse \
        ":private_key p | Also check the PGP signature based on this private key." \
        ":keyphrase k   | The keyphrase to use for the specified private key." \
        "path")
    [[ -e ${path} ]] || die "${path} does not exist"

    echo "Filename=$(basename ${path})"
    echo "Size=$(stat --printf="%s" "${path}")"

    # Now output MD5, SHA256, SHA512
    local ctype
    for ctype in MD5 SHA256 SHA512; do
        echo "${ctype}=$(eval ${ctype,,}sum "${path}" | awk '{print $1}')"
    done

    # If PGP signature is NOT requested we can simply return
    [[ -n ${private_key} ]] || return 0

    # Needs to be in /tmp rather than using $TMPDIR because gpg creates a socket in this directory and the complete
    # path can't be longer than 108 characters. gpg also expands relative paths, so no getting around it that way.
    local gpg_home=$(mktemp --directory /tmp/gpghome-XXXXXX)
    trap_add "rm -rf ${gpg_home}"

    # If using GPG 2.1 or higher, start our own gpg-agent. Otherwise, GPG will start one and leave it running.
    local gpg_version=$(gpg --version | awk 'NR==1{print $NF}')
    if compare_version "${gpg_version}" ">=" "2.1"; then
        local agent_command="gpg-agent --homedir ${gpg_home} --quiet --daemon --allow-loopback-pinentry"
        ${agent_command}
        trap_add "pkill -f \"${agent_command}\""
    fi

    # Import that into temporary secret keyring
    local keyring="" keyring_command=""
    keyring=$(mktemp --tmpdir emetadata-keyring-XXXXXX)
    trap_add "rm --force ${keyring}"

    keyring_command="--no-default-keyring --secret-keyring ${keyring}"
    if compare_version "${gpg_version}" ">=" "2.1"; then
        keyring_command+=" --pinentry-mode loopback"
    fi
    GPG_AGENT_INFO="" GNUPGHOME="${gpg_home}" gpg ${keyring_command} --batch --import ${private_key} |& edebug

    # Get optional keyphrase
    local keyphrase_command=""
    [[ -z ${keyphrase} ]] || keyphrase_command="--batch --passphrase ${keyphrase}"

    # Output PGPSignature encoded in base64
    echo "PGPKey=$(basename ${private_key})"
    echo "PGPSignature=$(GPG_AGENT_INFO="" GNUPGHOME="${gpg_home}" gpg --no-tty --yes ${keyring_command} --sign --detach-sign --armor ${keyphrase_command} --output - ${path} 2>/dev/null | base64 --wrap 0)"
}

opt_usage emetadata_check <<'END'
Validate an exiting source file against a companion *.meta file which contains various checksum
fields. The list of checksums is optional but at present the supported fields we inspect are:
Filename, Size, MD5, SHA1, SHA256, SHA512, PGPSignature.

For each of the above fields, if they are present in the .meta file, validate it against the source
file. If any of them fail this function returns non-zero. If NO validators are present in the info
file, this function returns non-zero.
END
emetadata_check()
{
    $(opt_parse \
        "+quiet q      | If specified, produce no output.  Return code reflects whether check was good or bad." \
        ":public_key p | Path to a PGP public key that can be used to validate PGPSignature in .meta file."     \
        "path")

    local meta="${path}.meta"
    [[ -e ${path} ]] || die "${path} does not exist"
    [[ -e ${meta} ]] || die "${meta} does not exist"

    fail()
    {
        emsg "${COLOR_ERROR}" "   -" "ERROR" "$@"
        exit 1
    }

    local metapack="" digests=() validated=() expect="" actual="" ctype="" rc=0
    pack_set metapack $(cat "${meta}")
    local pgpsignature=$(pack_get metapack PGPSignature | base64 --decode)

    # Figure out what digests we're going to validate
    for ctype in Size MD5 SHA1 SHA256 SHA512; do
        pack_contains metapack "${ctype}" && digests+=( "${ctype}" )
    done
    [[ -n ${public_key} && -n ${pgpsignature} ]] && digests+=( "PGP" )

    if edebug_enabled; then
        edebug "Verifying integrity of $(lval path metadata=digests)"
        pack_print metapack |& edebug
    fi

    if [[ ${quiet} -eq 0 ]]; then
        einfo "Verifying integrity of $(basename ${path})"
        eprogress --style einfos "$(lval metadata=digests)"
    fi

    # Fail if there were no digest validation fields to check
    if array_empty digests; then
        fail "No digest validation fields found: $(lval path)"
    fi

    # Now validate all digests we found
    local pids=()
    local ctype
    for ctype in ${digests[@]}; do

        expect=$(pack_get metapack ${ctype})

        if [[ ${ctype} == "Size" ]]; then
            actual=$(stat --printf="%s" "${path}")
            [[ ${expect} == ${actual} ]] || fail "Size mismatch: $(lval path expect actual)"
        elif [[ ${ctype} == @(MD5|SHA1|SHA256|SHA512) ]]; then
            actual=$(eval ${ctype,,}sum ${path} | awk '{print $1}')
            [[ ${expect} == ${actual} ]] || fail "${ctype} mismatch: $(lval path expect actual)"
        elif [[ ${ctype} == "PGP" && -n ${public_key} && -n ${pgpsignature} ]]; then
            local keyring=$(mktemp --tmpdir emetadata-keyring-XXXXXX)
            trap_add "rm --force ${keyring}"
            GPG_AGENT_INFO="" gpg --no-default-keyring --secret-keyring ${keyring} --import ${public_key} |& edebug
            GPG_AGENT_INFO="" echo "${pgpsignature}" | gpg --verify - "${path}" |& edebug || fail "PGP verification failure: $(lval path)"
        fi &

         pids+=( $! )
    done

    # Wait for all pids
    wait ${pids[@]} && rc=0 || rc=$?
    [[ ${quiet} -eq 1 ]] || eprogress_kill -r=${rc}
    return ${rc}
}

# Check if a directory is empty
directory_empty()
{
    $(opt_parse dir)
    ! find "${dir}" -mindepth 1 -print -quit | grep -q .
}

# Check if a directory is not empty
directory_not_empty()
{
    $(opt_parse dir)
    find "${dir}" -mindepth 1 -print -quit | grep -q .
}

#---------------------------------------------------------------------------------------------------
# COMPARISON FUNCTIONS
#---------------------------------------------------------------------------------------------------

opt_usage compare <<'END'
Generic comparison function using awk which doesn't suffer from bash stupidity with regards to
having to do use separate comparison operators for integers and strings and even worse being
completely incapable of comparing floats.
END
compare()
{
    $(opt_parse "?lh" "op" "?rh")

    ## =~
    if [[ ${op} == "=~" ]]; then
        [[ ${lh} =~ ${rh} ]] && return 0
        return 1
    fi
    if [[ ${op} == "!~" ]]; then
        [[ ! ${lh} =~ ${rh} ]] && return 0
        return 1
    fi

    ## Escape a few special characters that trip up awk
    lh=${lh//[@()]/_}
    rh=${rh//[@()]/_}
    awk -v lh="${lh}" -v rh="${rh}" "BEGIN { if ( lh ${op} rh ) exit(0) ; else exit(1) ; }" && return 0 || return 1
}

# Specialized comparision helper to properly compare versions
compare_version()
{
    local lh=${1}
    local op=${2}
    local rh=${3}

    ## EQUALS
    [[ ${op} == "!=" ]] && [[ ${lh} != ${rh} ]] && return 0
    [[ ${op} == "==" || ${op} == "<=" || ${op} == ">=" ]] && [[ ${lh} == ${rh} ]] && return 0
    [[ ${op} == "<"  || ${op} == ">" ]] && [[ ${lh} == ${rh} ]] && return 1
    op=${op/<=/<}
    op=${op/>=/>}

    [[ ${op} == "<"  ]] && [[ ${lh} == $(printf "${lh}\n${rh}" | sort -V | head -n1) ]] && return 0
    [[ ${op} == ">"  ]] && [[ ${lh} == $(printf "${lh}\n${rh}" | sort -V | tail -n1) ]] && return 0

    return 1
}

#---------------------------------------------------------------------------------------------------
# ARGUMENT HELPERS
#---------------------------------------------------------------------------------------------------

# Check to ensure all the provided arguments are non-empty
argcheck()
{
    local _argcheck_arg
    for _argcheck_arg in $@; do
        [[ -z "${!_argcheck_arg:-}" ]] && die "Missing argument '${_argcheck_arg}'" || true
    done
}


#---------------------------------------------------------------------------------------------------
# MISC HELPERS
#---------------------------------------------------------------------------------------------------

# save_function is used to safe off the contents of a previously declared
# function into ${1}_real to aid in overridding a function or altering
# it's behavior.
save_function()
{
    local orig=$(declare -f $1)
    local new="${1}_real${orig#$1}"
    eval "${new}" &>/dev/null
}

opt_usage override_function <<'END'
override_function is a more powerful version of save_function in that it will still save off the
contents of a previously declared function into ${1}_real but it will also define a new function
with the provided body ${2} and mark this new function as readonly so that it cannot be overridden
later. If you call override_function multiple times we have to ensure it's idempotent. The danger
here is in calling save_function multiple tiems as it may cause infinite recursion. So this guards
against saving off the same function multiple times.
END
override_function()
{
    $(opt_parse func body)

    # Don't save the function off it already exists to avoid infinite recursion
    declare -f "${func}_real" >/dev/null || save_function ${func}

    # If the function has already been overridden don't fail so long as it's
    # IDENTICAL to what we've already defined it as. This allows more graceful
    # handling of sourcing a file multiple times with an override in it as it'll
    # be identical. Normally the eval below would produce an error with set -e
    # enabled.
    local expected="${func} () ${body}"$'\n'"declare -rf ${func}"
    local actual="$(declare -pf ${func} 2>/dev/null || true)"
    [[ ${expected} == ${actual} ]] && return 0 || true

    eval "${expected}" &>/dev/null
    eval "declare -rf ${func}" &>/dev/null
}

numcores()
{
    [[ -e /proc/cpuinfo ]] || die "/proc/cpuinfo does not exist"

    echo $(cat /proc/cpuinfo | grep "processor" | wc -l)
}

opt_usage efetch_internal <<'END'
Internal only efetch function which fetches an individual file using curl. This will show an
eprogress ticker and then kill the ticker with either success or failure indicated. The return value
is then returned to the caller for handling.
END
efetch_internal()
{
    $(opt_parse url dst)
    local timecond=""
    [[ -f ${dst} ]] && timecond="--time-cond ${dst}"
    
    eprogress "Fetching $(lval url dst)"
    $(tryrc curl "${url}" ${timecond} --create-dirs --output "${dst}.pending" --location --fail --silent --show-error --insecure)
    eprogress_kill -r=${rc}

    if [[ ${rc} -eq 0 ]]; then
        if [[ -e "${dst}.pending" ]]; then
            mv "${dst}.pending" "${dst}"
        else
            # If curl succeeded, but the file wasn't created, then the remote file was an empty file. This was a bug in older
            # versions of curl that was fixed in newer versions. To make the old curl match the new curl behavior, simply
            # touch an empty file if one doesn't exist.
            # See: https://github.com/curl/curl/issues/183
            edebug "Working around old curl bug #183 wherein empty files are not properly created."
            touch "${dst}"
	fi
    elif [[ -e "${dst}.pending" ]]; then
        rm "${dst}.pending"
    fi

    return ${rc}
}

opt_usage efetch <<'END'
Fetch a provided URL to an optional destination path via efetch_internal. This function can also
optionally validate the fetched data against various companion files which contain metadata for file
fetching. If validation is requested and the validation fails then all temporary files fetched are
removed.
END
efetch()
{
    $(opt_parse \
        "+md5 m        | Fetch companion .md5 file and validate fetched file's MD5 matches." \
        "+meta M       | Fetch companion .meta file and validate metadata fields using emetadata_check." \
        "+quiet q      | Quiet mode.  (Disable eprogress and other info messages)" \
        ":public_key p | Path to a PGP public key that can be used to validate PGPSignature in .meta file."     \
        "url           | URL from which efetch should pull data." \
        "dst=/tmp      | Destination directory.")

    [[ -d ${dst} ]] && dst+="/$(basename ${url})"
    
    # Companion files we may fetch
    local md5_file="${dst}.md5"
    local meta_file="${dst}.meta"

    try
    {
        # Optionally suppress all output from this subshell
        [[ ${quiet} -eq 1 ]] && exec &>/dev/null

        ## If requested, fetch MD5 file
        if [[ ${md5} -eq 1 ]] ; then

            efetch_internal "${url}.md5" "${md5_file}"
            efetch_internal "${url}"     "${dst}"

            # Verify MD5
            einfos "Verifying MD5 $(lval dst md5_file)"

            local dst_dname=$(dirname  "${dst}")
            local dst_fname=$(basename "${dst}")
            local md5_dname=$(dirname  "${md5_file}")
            local md5_fname=$(basename "${md5_file}")

            cd "${dst_dname}"

            # If the requested destination was different than what was originally in the MD5 it will fail.
            # Or if the md5sum file was generated with a different path in it it will fail. This just
            # sanititizes it to have the current working directory and the name of the file we downloaded to.
            sed -i "s|\(^[^#]\+\s\+\)\S\+|\1${dst_fname}|" "${md5_fname}"

            # Now we can perform the check
            md5sum --check "${md5_fname}" >/dev/null

        ## If requested fetch *.meta file and validate using contained fields
        elif [[ ${meta} -eq 1 ]]; then

            efetch_internal "${url}.meta" "${meta_file}"
            efetch_internal "${url}"      "${dst}"
            opt_forward emetadata_check quiet public_key -- "${dst}"
        
        ## BASIC file fetching only
        else
            efetch_internal "${url}" "${dst}"
        fi
    
        einfos "Successfully fetched $(lval url dst)"
    }
    catch
    {
        local rc=$?
        edebug "Removing $(lval dst md5_file meta_file rc)"
        rm -rf "${dst}" "${md5_file}" "${meta_file}"
        return ${rc}
    }
}

opt_usage etimeout <<'END'
etimeout
========

`etimeout` will execute an arbitrary bash command for you, but will only let it
use up the amount of time (i.e. the "timeout") you specify.

If the command tries to take longer than that amount of time, it will be killed
and etimeout will return 124.  Otherwise, etimeout will return the value that
your called command returned.

All arguments to `etimeout` (i.e. everything that isn't an option, or
everything after --) is assumed to be part of the command to execute.
`Etimeout` is careful to retain your quoting.
END

etimeout()
{
    $(opt_parse \
        ":signal sig s=TERM | First signal to send if the process doesn't complete in time.  KILL
                              will still be sent later if it's not dead." \
        ":timeout t         | After this duration, command will be killed if it hasn't already
                              completed." \
        "@cmd               | Command and its arguments that should be executed.")

    argcheck timeout

    # Background the command to be run
    local start=${SECONDS}

    # If no command to execute just return success immediately
    if [[ -z "${cmd[@]:-}" ]]; then
        return 0
    fi

    #-------------------------------------------------------------------------
    # COMMAND TO EVAL
    local rc=""
    (
        disable_die_parent
        quote_eval "${cmd[@]}"
        local rc=$?
    ) &
    local pid=$!
    edebug "Executing $(lval cmd timeout signal pid)"
 
    #-------------------------------------------------------------------------
    # WATCHER
    #
    # Launch a background "wathcher" process that is simply waiting for the
    # timeout timer to expire.  If it does, it will kill the original command.
    (
        disable_die_parent
        close_fds

        # Wait for the timeout to elapse
        sleep ${timeout}

        # Upon getting here, we know that either 1) the timeout elapsed or 2)
        # our sleep process was killed.
        #
        # We can check to see if anything is still running, though, because we
        # know the command's PID.  If it's gone, it must've finished and we can exit
        #
        local pre_pids=( $(process_tree ${pid}) )
        if array_empty pre_pids ; then
            exit 0
        else
            # Since it did not exit and we must've completed our timeout sleep,
            # the command must've outlived its usefulness.  Do away with it.
            ekilltree -s=${signal} -k=2s ${pid}

            # Return sentinel 124 value to let the main process know that we
            # encountered a timeout.
            exit 124
        fi

    ) &>/dev/null &

    #-------------------------------------------------------------------------
    # HANDLE RESULTS
    {
        # Now we need to wait for the original process to finish.  We know that
        # it will _either_ finish because it completes normally or because the
        # watcher will kill it.
        #
        # Note that we do _not_ know which.  The return code we get from that
        # process might be its normal rc, or it might be the rc that it got
        # because it was killed by the watcher.
        local watcher=$!
        wait ${pid} && rc=0 || rc=$?

        # Once the above has completed, we know that the watcher is no longer
        # needed, so we can kill it, too.
        ekilltree -s=TERM ${watcher}

        # We need the return code from the watcher process to determine what
        # happened.  If it returned our sentinel value (124), then we know that
        # it determined there was a timeout.  Otherwise, we know that the
        # original command returned on its own.
        wait ${watcher} && watcher_rc=0 || watcher_rc=$?

        local stop=${SECONDS}
        local seconds=$(( ${stop} - ${start} ))

    } &>/dev/null
    
    # Now if we got that sentinel 124 value, we can report the timeout
    if [[ ${watcher_rc} -eq 124 ]] ; then
        edebug "Timeout $(lval cmd rc seconds timeout signal pid)"
        return 124
    else
        # Otherwise, we report the value reported by the original command
        return ${rc}
    fi
}

opt_usage eretry <<'END'
Eretry executes arbitrary shell commands for you wrapped in a call to etimeout
and retrying up to a specified count.

If the command eventually completes successfully eretry will return 0. If the
command never completes successfully but continues to fail every time the
return code from eretry will be the failing command's return code. If the
command is prematurely terminated via etimeout the return code from eretry will
be 124.

All direct parameters to eretry are assumed to be the command to execute, and
eretry is careful to retain your quoting.
END
eretry()
{
    $(opt_parse \
        ":delay d=0              | Amount of time to delay (sleep) after failed attempts before
                                   retrying. Note that this value can accept sub-second values, just
                                   as the sleep command does. This parameter will be passed directly
                                   to sleep, so you can specify any arguments it accepts such as
                                   .01s, 5m, or 3d." \
        ":fatal_exit_codes e=0   | Space-separated list of exit codes.  Any of the exit codes
                                   specified in this list will cause eretry to stop retrying. If
                                   eretry receives one of these codes, it will immediately stop
                                   retrying and return that exit code. By default, only a zero
                                   return code will cause eretry to stop.  If you specify -e, you
                                   should consider whether you want to include 0 in the list." \
        ":retries r              | Command will be attempted this many times total. If no options
                                   are provided to eretry it will use a default retry limit of 5." \
        ":signal sig s=TERM      | When timeout seconds have passed since running the command, this
                                   will be the signal to send to the process to make it stop.  The
                                   default is TERM. [NOTE: KILL will _also_ be sent two seconds
                                   after the timeout if the first signal doesn't do its job]" \
        ":timeout t              | After this duration, command will be killed (and retried if
                                   that's the right thing to do).  If unspecified, commands may run
                                   as long as they like and eretry will simply wait for them to
                                   finish. Uses sleep(1) time syntax." \
        ":max_timeout T=infinity | Total timeout for entire eretry operation. This flag is different
                                   than --timeout in that --max-timeout applies to the entire eretry
                                   operation including all iterations and retry attempts and
                                   timeouts of each individual command. Uses sleep(1) time syntax." \
        ":warn_every w           | A warning will be generated on (or slightly after) every SECONDS
                                   while the command keeps failing." \
        "@cmd                    | Command to run along with any of its own options and arguments.")

    # If unspecified, limit timeout to the same as max_timeout
    : ${timeout:=${max_timeout:-infinity}}


    # If a total timeout was specified then wrap call to eretry_internal with etimeout
    if [[ ${max_timeout} != "infinity" ]]; then
        : ${retries:=infinity}

        etimeout -t=${max_timeout} -s=${signal} --          \
            opt_forward eretry_internal timeout delay fatal_exit_codes signal warn_every retries -- "${cmd[@]}"
    else
        # If no total timeout or retry limit was specified then default to prior
        # behavior with a max retry of 5.
        : ${retries:=5}

        opt_forward eretry_internal timeout delay fatal_exit_codes signal warn_every retries -- "${cmd[@]}"
    fi
}

opt_usage eretry_internal <<'END'
Internal method called by eretry so that we can wrap the call to eretry_internal with a call to
etimeout in order to provide upper bound on entire invocation.
END
eretry_internal()
{
    $(opt_parse \
        ":delay d                | Time to sleep between failed attempts before retrying." \
        ":fatal_exit_codes e     | Space-separated list of exit codes that are fatal (i.e. will result in no retry)." \
        ":retries r              | Command will be attempted once plus this number of retries if it continues to fail." \
        ":signal sig s           | Signal to be send to the command if it takes longer than the timeout." \
        ":timeout t              | If one attempt takes longer than this duration, kill it and retry if appropriate." \
        ":warn_every w           | Generate warning messages after failed attempts when it has been more than this long since the last warning." \
        "@cmd                    | Command to run followed by any of its own options and arguments.")

    argcheck delay fatal_exit_codes retries signal timeout

    # Command
    local attempt=0
    local rc=0
    local exit_codes=()
    local stdout=""
    local warn_seconds="${SECONDS}"

    # If no command to execute just return success immediately
    if [[ -z "${cmd[@]:-}" ]]; then
        return 0
    fi

    while true; do
        [[ ${retries} != "infinity" && ${attempt} -ge ${retries} ]] && break || (( attempt+=1 ))
        
        edebug "Executing $(lval cmd timeout max_timeout) retries=(${attempt}/${retries})"

        # Run the command through timeout wrapped in tryrc so we can throw away the stdout 
        # on any errors. The reason for this is any caller who cares about the output of
        # eretry might see part of the output if the process times out. If we just keep
        # emitting that output they'd be getting repeated output from failed attempts
        # which could be completely invalid output (e.g. truncated XML, Json, etc).
        stdout=""
        $(tryrc -o=stdout etimeout -t=${timeout} -s=${signal} "${cmd[@]}")
        
        # Append list of exit codes we've seen
        exit_codes+=(${rc})

        # Break if the process exited with white listed exit code.
        if echo "${fatal_exit_codes}" | grep -wq "${rc}"; then
            edebug "Command reached terminal exit code.  Ending retries. $(lval rc fatal_exit_codes cmd)"
            break
        fi

        # Show warning if requested
        if [[ -n ${warn_every} ]] && (( SECONDS - warn_seconds > warn_every )); then
            ewarn "Failed $(lval cmd timeout exit_codes) retries=(${attempt}/${retries})" 
            warn_seconds=${SECONDS}
        fi

        # Don't use "-ne" here since delay can have embedded units
        if [[ ${delay} != "0" ]] ; then
            edebug "Sleeping $(lval delay)" 
            sleep ${delay}
        fi
    done

    [[ ${rc} -eq 0 ]] || ewarn "Failed $(lval cmd timeout exit_codes) retries=(${attempt}/${retries})" 

    # Emit stdout
    echo -n "${stdout}"

    # Return final return code
    return ${rc}
}

opt_usage setvars <<'END'
setvars takes a template file with optional variables inside the file which are surrounded on both
sides by two underscores.  It will replace the variable (and surrounding underscores) with a value
you specify in the environment.

For example, if the input file looks like this:
    Hi __NAME__, my name is __OTHERNAME__.

And you call setvars like this
    NAME=Bill OTHERNAME=Ted setvars intputfile

The inputfile will be modified IN PLACE to contain:
    Hi Bill, my name is Ted.

SETVARS_ALLOW_EMPTY=(0|1)
    By default, empty values are NOT allowed. Meaning that if the provided key
    evaluates to an empty string, it will NOT replace the __key__ in the file.
    if you require that functionality, simply use SETVARS_ALLOW_EMPTY=1 and it
    will happily allow you to replace __key__ with an empty string.

    After all variables have been expanded in the provided file, a final check
    is performed to see if all variables were set properly. It will return 0 if
    all variables have been successfully set and 1 otherwise.

SETVARS_WARN=(0|1)
    To aid in debugging this will display a warning on any unset variables.

OPTIONAL CALLBACK:
    You may provided an optional callback as the second parameter to this function.
    The callback will be called with the key and the value it obtained from the
    environment (if any). The callback is then free to make whatever modifications
    or filtering it desires and then echo the new value to stdout. This value
    will then be used by setvars as the replacement value.
END
setvars()
{
    $(opt_parse \
        "filename  | File to modify." \
        "?callback | You may provided an optional callback as the second parameter to this function.
                     The callback will be called with the key and the value it obtained from the
                     environment (if any). The callback is then free to make whatever modifications
                     or filtering it desires and then echo the new value to stdout. This value will
                     then be used by setvars as the replacement value.")

    edebug "Setting variables $(lval filename callback)"
    [[ -f ${filename} ]] || die "$(lval filename) does not exist"

    # If this file is a binary file skip it
    if file ${filename} | grep -q ELF ; then
        edebug "Skipping binary file $(lval filename): $(file ${filename})"
        return 0
    fi

    for arg in $(grep -o "__\S\+__" ${filename} | sort --unique || true); do
        local key="${arg//__/}"
        local val="${!key:-}"

        # Call provided callback if one was provided which by contract should print
        # the new resulting value to be used
        [[ -n ${callback} ]] && val=$(${callback} "${key}" "${val}")

        # If we got an empty value back and empty values aren't allowed then continue.
        # We do NOT call die here as we'll deal with that at the end after we have
        # tried to expand all variables.
        [[ -n ${val} || ${SETVARS_ALLOW_EMPTY:-0} -eq 1 ]] || continue

        edebug "   ${key} => ${val}"

        # Put val into perl's environment and let _perl_ pull it out of that
        # environment.  This has the benefit of causing it to not try to
        # interpret any of it, but to treat it as a raw string
        VAL="${val}" perl -pi -e "s/__${key}__/\$ENV{VAL}/g" "${filename}" || die "Failed to set $(lval key val filename)"
    done

    # Check if anything is left over and return correct return value accordingly.
    if grep -qs "__\S\+__" "${filename}"; then
        local notset=()
        notset=( $(grep -o '__\S\+__' ${filename} | sort --unique | tr '\n' ' ') )
        [[ ${SETVARS_WARN:-1}  -eq 1 ]] && ewarn "Failed to set all variables in $(lval filename notset)"
        return 1
    fi

    return 0
}

opt_usage quote_eval <<'END'
Ever want to evaluate a bash command that is stored in an array?  It's mostly a great way to do
things.  Keeping the various arguments separate in the array means you don't have to worry about
quoting.  Bash keeps the quoting you gave it in the first place.  So the typical way to run such a
command is like this:

    > cmd=(echo "\$\$")
    > "${cmd[@]}"
    $$

As you can see, since the dollar signs were quoted as the command was put into the array, so the
quoting was retained when the command was executed. If you had instead used eval, you wouldn't get
that behavior:

    > cmd=(echo "\$\$")
    > "${cmd[@]}"
    53355

Instead, the argument gets "evaluated" by bash, turning it into the current process id.  So if
you're storing commands in an array, you can see that you typically don't want to use eval.

But there's a wrinkle, of course.  If the first item in your array is the name of an alias, bash
won't expand that alias when using the first syntax. This is because alias expansion happens in a
stage _before_ bash expands the contents of the variable.

So what can you do if you want alias expansion to happen but also want things in the array to be
quoted properly?  Use `quote_array`.  It will ensure that all of the arguments don't get evaluated
by bash, but that the name of the command _does_ go through alias expansion.

    > cmd=(echo "\$\$")
    > quote_eval "${cmd[@]}"
    $$

There, wasn't that simple?
END
quote_eval()
{
    local cmd=("$1")
    shift

    for arg in "${@}" ; do
        cmd+=( "$(printf %q "${arg}")" )
    done

    eval "${cmd[@]}"
}


#---------------------------------------------------------------------------------------------------
# STRING MANIPULATION
#---------------------------------------------------------------------------------------------------

opt_usage to_upper_snake_case <<'END'
Convert a given input string into "upper snake case". This is generally most useful when converting
a "CamelCase" string although it will work just as well on non-camel case input. Essentially it
looks for all upper case letters and puts an underscore before it, then uppercase the entire input
string.

For example:

    sliceDriveSize => SLICE_DRIVE_SIZE
    slicedrivesize => SLICEDRIVESIZE

It has some special handling for some common corner cases where the normal camel case idiom isn't
well followed. The best example for this is around units (e.g. MB, GB). Consider "sliceDriveSizeGB"
where SLICE_DRIVE_SIZE_GB is preferable to SLICE_DRIVE_SIZE_G_B.

The current list of translation corner cases this handles: KB, MB, GB, TB
END
to_upper_snake_case()
{
    $(opt_parse input)

    echo "${input}"         \
        | sed -e 's|KB|Kb|' \
              -e 's|MB|Mb|' \
              -e 's|GB|Gb|' \
              -e 's|TB|Tb|' \
        | perl -ne 'print uc(join("_", split(/(?=[A-Z])/)))'
}

opt_usage to_lower_snake_case <<'END'
Convert a given input string into "lower snake case". This is generally most useful when converting
a "CamelCase" string although it will work just as well on non-camel case input. Essentially it
looks for all upper case letters and puts an underscore before it, then lowercase the entire input
string.

For example:

    sliceDriveSize => slice_drive_size
    slicedrivesize => slicedrivesize

It has some special handling for some common corner cases where the normal camel case idiom isn't
well followed. The best example for this is around units (e.g. MB, GB). Consider "sliceDriveSizeGB"
where slice_drive_size_gb is preferable to slice_drive_size_g_b.

The current list of translation corner cases this handles: KB, MB, GB, TB
END
to_lower_snake_case()
{
    $(opt_parse input)

    echo "${input}"         \
        | sed -e 's|KB|Kb|' \
              -e 's|MB|Mb|' \
              -e 's|GB|Gb|' \
              -e 's|TB|Tb|' \
        | perl -ne 'print lc(join("_", split(/(?=[A-Z])/)))'
}

string_trim()
{
    local text=$*
    text=${text%%+([[:space:]])}
    text=${text##+([[:space:]])}
    printf -- "%s" "${text}"
}

opt_usage string_truncate <<'END'
Truncate a specified string to fit within the specified number of characters. If the ellipsis option
is specified, truncation will result in an ellipses where the removed characters were (and the total
string will still fit within length characters)

Any arguments after the length will be considered part of the text to string_truncate
END
string_truncate()
{
    $(opt_parse \
        "+ellipsis e | If set, an elilipsis (...) will replace any removed text." \
        "length      | Desired maximum length for text." )

    local text=$*

    if [[ ${#text} -gt ${length} && ${ellipsis} -eq 1 ]] ; then
        printf -- "%s" "${text:0:$((length-3))}..."
    else
        printf -- "%s" "${text:0:${length}}"
    fi
}

# Collapse grouped whitespace in the specified string to single spaces.
string_collapse()
{
    local output=$(echo -en "$@" | tr -s "[:space:]" " ")
    echo -en "${output}"
}

opt_usage is_int <<'END'
Returns true if the input string is an integer and false otherwise. May have a leading '-' or '+'
to indicate the number is negative or positive. This does NOT handle floating point numbers. For
that you should instead use is_num.
END
is_int()
{
    [[ "${1}" =~ ^[-+]?[0-9]+$ ]] && return 0 || return 1
}

opt_usage is_num <<'END'
Returns true if the input string is a number and false otherwise. May have a leading '-' or '+'
to indicate the number is negative or positive. Unlike is_integer, this function properly handles
floating point numbers.

is_num at present does not handle fractions or exponents or numbers is other bases (e.g. hex).
But in the future we may add support for these as needed. As such we decided not to limit ourselves
with calling this just is_float.
END
is_num()
{
    [[ "${1}" =~ ^[-+]?[0-9]+\.?[0-9]*$ ]] && return 0 || return 1
}

#---------------------------------------------------------------------------------------------------
# Type detection
#---------------------------------------------------------------------------------------------------

# These functions take a parameter that is a variable NAME and allow you to
# determine information about that variable name.
#
# Detecting packs relies on the bashutils convention of "if the first character
# of the name is a +, consider it a pack)
is_array()
{
    [[ "$(declare -p $1 2>/dev/null)" =~ ^declare\ -a ]]
}

is_associative_array()
{
    [[ "$(declare -p $1 2>/dev/null)" =~ ^declare\ -A ]]
}

is_pack()
{
    [[ "${1:0:1}" == '%' ]]
}

is_function()
{
    if [[ $# != 1 ]] ; then
        die "is_function takes only a single argument but was passed $@"
    fi

    declare -F "$1" &>/dev/null
}

discard_qualifiers()
{
    echo "${1##%}"
}

#---------------------------------------------------------------------------------------------------
# SOURCING
#---------------------------------------------------------------------------------------------------

return 0
