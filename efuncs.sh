#!/bin/bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# GLOBAL EFUNCS SETTINGS
#-----------------------------------------------------------------------------
set -o pipefail
set -o nounset
set -o functrace
set -o errtrace
shopt -s expand_aliases
shopt -s checkwinsize

#-----------------------------------------------------------------------------
# DEBUGGING
#-----------------------------------------------------------------------------

alias enable_trace='[[ -n ${ETRACE:-} && ${ETRACE:-} != "0" ]] && trap etrace DEBUG || trap - DEBUG'

etrace()
{
    [[ ${ETRACE} == "" || ${ETRACE} == "0" ]] && return 0 || true

    # If ETRACE=1 then it's enabled globally
    if [[ ${ETRACE} != "1" ]]; then
        local _etrace_enabled_tmp=""
        local _etrace_enabled=0

        for _etrace_enabled_tmp in ${ETRACE}; do
            [[ ${BASH_SOURCE[1]:-} =~ ${_etrace_enabled_tmp}
                || ${FUNCNAME[1]:-} =~ ${_etrace_enabled_tmp} ]] && { _etrace_enabled=1; break; }
        done

        [[ ${_etrace_enabled} -eq 1 ]] || return 0
    fi

    echo "$(ecolor dimyellow)[$(basename ${BASH_SOURCE[1]:-} 2>/dev/null || true):${BASH_LINENO[0]:-}:${FUNCNAME[1]:-}:${BASHPID}]$(ecolor none) ${BASH_COMMAND}" >&2
}

edebug_enabled()
{
    [[ ${EDEBUG:=}  == "1" || ${ETRACE:=}  == "1" ]] && return 0
    [[ ${EDEBUG:-0} == "0" && ${ETRACE:-0} == "0" ]] && return 1

    $(declare_args ?_edebug_enabled_caller)

    if [[ -z ${_edebug_enabled_caller} ]]; then
        _edebug_enabled_caller=( $(caller 0) )
        [[ ${_edebug_enabled_caller[1]} == "edebug" || ${_edebug_enabled_caller[1]} == "edebug_out" || ${_edebug_enabled_caller[1]} == "tryrc" ]] \
            && _edebug_enabled_caller=( $(caller 1) )
    fi

    local _edebug_enabled_tmp
    for _edebug_enabled_tmp in ${EDEBUG} ${ETRACE} ; do
        [[ "${_edebug_enabled_caller[@]:1}" =~ ${_edebug_enabled_tmp} ]] && return 0
    done

    return 1
}

edebug_disabled()
{
    ! edebug_enabled
}

edebug()
{
    # Take intput either from arguments or if no arguments were provided take input from
    # standard input.
    local msg=""
    if [[ $# -gt 0 ]]; then
        msg="${@}"
    else
        msg="$(cat)"
    fi
    
    # If debugging isn't enabled then simply return without writing anything.
    # NOTE: We can't return at the top of this function in the event the caller has
    # piped output into edebug. We have to consume their output so that they don't
    # get an error or block.
    edebug_enabled || return 0

    # Force caller to be in edebug output because it's helpful and if you
    # turned on edebug, you probably want to know anyway
    EMSG_PREFIX="${EMSG_PREFIX:-} caller" emsg "dimblue" "" "DEBUG" "${msg}"
}

edebug_out()
{
    edebug_enabled && echo -n "/dev/stderr" || echo -n "/dev/null"
}

#-----------------------------------------------------------------------------
# TRY / CATCH
#-----------------------------------------------------------------------------

DIE_MSG_KILLED="\"[Killed]\""
DIE_MSG_CAUGHT="\"[ExceptionCaught]\""
DIE_MSG_UNHERR="\"[UnhandledError]\""

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
__EFUNCS_DIE_ON_ERROR_TRAP_STACK=()
alias try="
    __EFUNCS_DIE_ON_ERROR_TRAP=\"\$(trap -p ERR | sed -e 's|trap -- ||' -e 's| ERR||' -e \"s|^'||\" -e \"s|'$||\" || true)\"
    : \${__EFUNCS_DIE_ON_ERROR_TRAP:=-}
    __EFUNCS_DIE_ON_ERROR_TRAP_STACK+=( \"\${__EFUNCS_DIE_ON_ERROR_TRAP}\" )
    nodie_on_error
    (
        enable_trace
        die_on_abort
        trap 'die -c=grey19 -r=\$? ${DIE_MSG_CAUGHT} &> >(edebug)' ERR
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
    __EFUNCS_TRY_CATCH_RC=\$?
    __EFUNCS_DIE_ON_ERROR_TRAP=\"\${__EFUNCS_DIE_ON_ERROR_TRAP_STACK[@]:(-1)}\"
    unset __EFUNCS_DIE_ON_ERROR_TRAP_STACK[\${#__EFUNCS_DIE_ON_ERROR_TRAP_STACK[@]}-1]
    trap \"\${__EFUNCS_DIE_ON_ERROR_TRAP}\" ERR
    ( exit \${__EFUNCS_TRY_CATCH_RC} ) || "

# Throw is just a simple wrapper around exit but it looks a little nicer inside
# a 'try' block to see 'throw' instead of 'exit'.
throw()
{
    exit $1
}

# die_on_error is a simple alias to register our trap handler for ERR. It is
# extremely important that we use this mechanism instead of the expected
# 'set -e' so that we have control over how the process exit is handled by
# calling our own internal 'die' handler. This allows us to either exit or
# kill the entire process tree as needed.
#
# NOTE: This is extremely unobvious, but setting a trap on ERR implicitly
# enables 'set -e'.
alias die_on_error='export __EFUNCS_DIE_ON_ERROR_ENABLED=1; trap "die ${DIE_MSG_UNHERR}" ERR'

# Disable calling die on ERROR.
alias nodie_on_error="export __EFUNCS_DIE_ON_ERROR_ENABLED=0; trap - ERR"

# Check if die_on_error is enabled. Returns success (0) if enabled and failure
# (1) otherwise.
die_on_error_enabled()
{
    trap -p | grep -q ERR
}

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
    $(declare_args)

    # Note grab file descriptors for the current process, not the one inside
    # the command substitution ls here.
    local pid=$BASHPID
    local fds=( $(ls /proc/${pid}/fd/ | grep -vP '^(0|1|2|255)$' | tr '\n' ' ') )

    local fd
    for fd in "${fds[@]}"; do
        eval "exec $fd>&-"
    done
}

# Helper method to read from a pipe until we see EOF.
pipe_read()
{
    $(declare_args pipe)
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

# Helper method to read from a pipe until we see EOF and then also 
# intelligently quote the output in a way that can be reused as shell input
# via "printf %q". This will allow us to safely eval the input without fear
# of anything being exectued.
#
# NOTE: This method will echo "" instead of using printf if the output is an
#       empty string to avoid causing various test failures where we'd
#       expect an empty string ("") instead of a string with literl quotes
#       in it ("''").
pipe_read_quote()
{
    $(declare_args pipe)
    local output=$(pipe_read ${pipe})
    if [[ -n ${output} ]]; then
        printf %q "$(printf "%q" "${output}")"
    else
        echo -n ""
    fi
}

# tryrc is a convenience wrapper around try/catch that makes it really easy to
# execute a given command and capture the command's return code, stdout and stderr
# into local variables. We created this idiom because if you handle the failure 
# of a command in any way then bash effectively disables set -e that command
# invocation REGARDLESS OF DEPTH. "Handling the failure" includes putting it in
# a while or until loop, part of an if/else statement or part of a command 
# executed in a && or ||.
#
# Consider a function call chain such as:
#
# foo->bar->zap
#
# and you want to get the return value from foo, you might (wrongly) think you
# could safely use this and safely bypass set -e explosion:
#
# foo || rc=$?
#
# The problem is bash effectively disables "set -e" for this command when used
# in this context. That means even if zap encounteres an unhandled error die()
# will NOT get implicitly called (explicit calls to die would still get called
# of course).
# 
# Here's the insidious documentation from 'man bash' regarding this obscene
# behavior:
#
# "The ERR trap is not executed if the failed command is part of the command
#  list immediately following a while or until keyword, part of the test in
#  an if statement, part of a command executed in a && or ||  list  except 
#  the command following the final && or ||, any command in a pipeline but
#  the last, or if the command's return value is being inverted using !."
#
# What's not obvious from that statement is that this applies to the entire
# expression including any functions it may call not just the top-level 
# expression that had an error. Ick.
#
# Thus we created tryrc to allow safely capturing the return code, stdout
# and stderr of a function call WITHOUT bypassing set -e safety!
#
# This is invoked using the "eval command invocation string" idiom so that it
# is invoked in the caller's envionment. For example: $(tryrc some-command)
#
# OPTIONS:
# -r=VAR The variable to assign the return code to (OPTIONAL, defaults to 'rc').
# -o=VAR The variable to assign STDOUT to (OPTIONAL). If not provided STDOUT
#        will go to /dev/stdout as normal. This is BUFFERED and not displayed
#        until the call completes.
# -e=VAR The variable to assign STDERR to (OPTIONAL). If not provided STDERR
#        will go to /dev/stderr as normal. This is NOT BUFFERED and will display
#        to /dev/stderr in real-time.
# -g     Make variables global even if called in a local context.
tryrc()
{
    $(declare_args)
    local cmd=("$@")
    local rc_out=$(opt_get r "rc")
    local stdout_out=$(opt_get o)
    local stderr_out=$(opt_get e)
    local global=$(opt_get g 0)

    # Determine flags to pass into declare
    local dflags=""
    opt_false g || dflags="-g"

    # Temporary directory to hold stdout and stderr
    local tmpdir=$(mktemp -d /tmp/tryrc-XXXXXXXX)
    trap_add "rm -rf ${tmpdir}"

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
    echo eval "declare ${dflags} ${rc_out}=1;"
    [[ -n ${stdout_out} ]] && echo eval "declare ${dflags} ${stdout_out}="";"
    [[ -n ${stderr_out} ]] && echo eval "declare ${dflags} ${stderr_out}="";"

    # Execute actual command in try/catch so that any fatal errors in the command
    # properly terminate execution of the command then capture off the return code
    # in the catch block. Send all stdout and stderr to respective pipes which will
    # be read in by the above background processes.
    local rc=0
    try
    {
        if [[ -n "${cmd[@]:-}" ]]; then

            # Redirect subshell's STDOUT and STDERR to requested locations
            exec >${stdout_file}
            [[ -n ${stderr_out} ]] && exec 2>${stderr_file}

            # Run command
            "${cmd[@]}"
        fi
    }
    catch
    {
        rc=$?
    }

    # Emit commands to assign return code 
    echo eval "declare ${dflags} ${rc_out}=${rc};"

    # Emit commands to assign stdout but ONLY if a stdout file was actually created.
    # This is because the file is only created on first write. And we don't want this
    # to fail if the command didn't write any stdout. This is also SAFE because we
    # initialize stdout_out and stderr_out above to empty strings.
    if [[ -s ${stdout_file} ]]; then
        local stdout="$(pipe_read_quote ${stdout_file})"
        if [[ -n ${stdout_out} ]]; then
            echo eval "declare ${dflags} ${stdout_out}=${stdout};"
        else
            echo eval "echo ${stdout} >&1;"
        fi
    fi

    # Emit commands to assign stderr
    if [[ -n ${stderr_out} && -s ${stderr_file} ]]; then
        local stderr="$(pipe_read_quote ${stderr_file})"
        echo eval "declare ${dflags} ${stderr_out}=${stderr};"
    fi

    # Remote temporary directory
    rm -rf ${tmpdir}
}

#-----------------------------------------------------------------------------
# TRAPS / DIE / STACKTRACE
#-----------------------------------------------------------------------------

# Print stacktrace to stdout. Each frame of the stacktrace is separated by a
# newline. Allows you to optionally pass in a starting frame to start the
# stacktrace at. 0 is the top of the stack and counts up. See also stacktrace
# and error_stacktrace.
#
# OPTIONS:
# -f=N Frame number to start at.
stacktrace()
{
    $(declare_args)
    local frame=$(opt_get f 0)

    while caller ${frame}; do
        (( frame+=1 ))
    done
}

# Populate an array with the frames of the current stacktrace. Allows you
# to optionally pass in a starting frame to start the stacktrace at. 0 is
# the top of the stack and counts up. See also stacktrace and eerror_stacktrace
#
# OPTIONS:
# -f=N Frame number to start at (defaults to 1 to skip lower level stacktrace
#      frame that this function calls.)
stacktrace_array()
{
    $(declare_args array)
    local frame=$(opt_get f 1)
    array_init_nl ${array} "$(stacktrace -f=${frame})"
}

# Print the trap command associated with a given signal (if any). This
# essentially parses trap -p in order to extract the command from that
# trap for use in other functions such as call_die_traps and trap_add.
trap_get()
{
    $(declare_args sig)

    # Normalize the signal description (which might be a name or a number) into
    # the form trap produces
    sig="$(signame -s "${sig}")"

    local existing=$(trap -p "${sig}")
    existing=${existing##trap -- \'}
    existing=${existing%%\' ${sig}}

    echo -n "${existing}"
}

die()
{
    # Disable traps for any signal during most of die.  We'll reset the traps
    # to existing state prior to exiting so that the exit trap will honor them.
    local saved_traps=$(trap)
    trap "" ${DIE_SIGNALS[@]}

    if [[ ${__EFUNCS_DIE_IN_PROGRESS:=0} -ne 0 ]] ; then
        exit ${__EFUNCS_DIE_IN_PROGRESS}
    else
        $(declare_args)
        __EFUNCS_DIE_IN_PROGRESS=$(opt_get r 1)
        : ${__EFUNCS_DIE_BY_SIGNAL:=$(opt_get s)}
    fi

    local color=$(opt_get c "red")

    # Show error message immediately.
    echo "" >&2
    eerror_internal -c="${color}" "${@}"

    # Call eerror_stacktrace but skip top three frames to skip over the frames
    # containing stacktrace_array, eerror_stacktrace and die itself. Also skip
    # over the initial error message since we already displayed it.
    eerror_stacktrace -c="${color}" -f=3 -s

    # Restore saved signals
    eval "${saved_traps}"

    # If we're in a subshell signal our parent SIGTERM and then exit. This will
    # allow the parent process to gracefully perform any cleanup before the
    # process ultimately exits.
    if [[ $$ != ${BASHPID} ]]; then
        
        # Capture off our BASHPID into a local variable so we can use it in subsequent
        # commands which cannot use BASHPID directly because they are in subshells and
        # the value of BASHPID would be altered by their context. 
        # WARNING: Do NOT use PPID instead of the $(ps) command because PPID is the
        #          parent of $$ not necessarily the parent of ${BASHPID}!
        local pid=${BASHPID}
        ekill -s=SIGTERM $(ps -o pid --no-headers --ppid ${pid})
        ekilltree -s=SIGTERM ${pid}

        # When a process dies as the result of a signal, the proper thing to do
        # is not to exit but to kill self with that same signal.  See
        # http://www.cons.org/cracauer/sigint.html and
        # http://mywiki.wooledge.org/SignalTrap
        #
        if [[ -n "${__EFUNCS_DIE_BY_SIGNAL}" ]] ; then
            trap - ${__EFUNCS_DIE_BY_SIGNAL}
            kill -${__EFUNCS_DIE_BY_SIGNAL} ${BASHPID}
        else
            exit ${__EFUNCS_DIE_IN_PROGRESS}
        fi
    else
        if declare -f die_handler &>/dev/null; then
            die_handler -c="${color}" -r=${__EFUNCS_DIE_IN_PROGRESS} "${@}"
            __EFUNCS_DIE_IN_PROGRESS=0
        else
            ekilltree -s=SIGTERM $$
            exit ${__EFUNCS_DIE_IN_PROGRESS}
        fi
    fi
}

# Appends a command to a trap. By default this will use the default list of
# signals: ${DIE_SIGNALS[@]}, ERR and EXIT so that this trap gets called
# by default for any signal that would cause termination. If that's not the
# desired behavior then simply pass in an explicit list of signals to trap.
#
# Options:
# $1: body of trap to be appended
# $@: Optional list of signals to trap (or default to DIE_SIGNALS and EXIT).
#
# NOTE: Do not put single quotes inside the body of the trap or else we can't
#       reliably extract the trap and eval it later.
trap_add()
{
    $(declare_args cmd)
    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( EXIT )
    
    # Fail if new cmd has single quotes in it.
    if [[ ${cmd} =~ "'" ]]; then
        eerror "trap commands cannot contain single quotes."
        return 1
    fi

    edebug "Adding trap $(lval cmd signals)"

    local sig
    for sig in "${signals[@]}"; do
        sig=$(signame -s ${sig})

        # If we're at the same shell level as a previous trap_add invocation,
        # then append to the existing trap. Otherwise if we're changing shell
        # levels, optionally use die() as base trap if DIE_ON_ERROR or
        # ABORT_ON_ERROR are enabled.
        local existing=""
        if [[ ${__EFUNCS_TRAP_ADD_SHELL_LEVEL:-} == ${BASH_SUBSHELL} ]]; then
            existing="$(trap_get ${sig})"
        else
            __EFUNCS_TRAP_ADD_SHELL_LEVEL=${BASH_SUBSHELL}

            # Clear any existing trap since we're in a subshell
            trap - "${sig}"

            # See if we need to turn on die or not
            if [[ ${sig} == "ERR" && ${__EFUNCS_DIE_ON_ERROR_ENABLED:-} -eq 1 ]]; then
                existing="die \"${DIE_MSG_UNHERR}\""

            elif [[ ${sig} != "EXIT" && ${__EFUNCS_DIE_ON_ABORT_ENABLED:-} -eq 1 ]]; then
                existing="die \"${DIE_MSG_KILLED}\""
            fi
        fi

        trap -- "$(printf '%s; %s' "${cmd}" "${existing}")" "${sig}"
    done
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
    export __EFUNCS_DIE_ON_ABORT_ENABLED=1

    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( ${DIE_SIGNALS[@]} )

    local signal
    for signal in "${signals[@]}" ; do
        local signal_name=$(signame -s ${signal})
        trap "die -s=${signal_name} \"[\${BASHPID} caught ${signal_name}]\"" ${signal}
    done
}

# Disable default traps for all DIE_SIGNALS.
nodie_on_abort()
{
    export __EFUNCS_DIE_ON_ABORT_ENABLED=0

    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( ${DIE_SIGNALS[@]} )
    trap - ${signals[@]}
}

#-----------------------------------------------------------------------------
# FANCY I/O ROUTINES
#-----------------------------------------------------------------------------

# Check if we are "interactive" or not. For our purposes, we are interactive
# if STDERR is attached to a terminal or not. This is checked via the bash
# idiom "[[ -t 2 ]]" where "2" is STDERR. But we can override this default
# check with the global variable EINTERACTIVE=1.
einteractive()
{
    [[ ${EINTERACTIVE:-0} -eq 1 ]] && return 0
    [[ -t 2 ]]
}

tput()
{
    if [[ "$@" == "cols" && -n ${COLUMNS:-} ]]; then
        echo -n "${COLUMNS}"
        return 0
    fi

    TERM=screen-256color /usr/bin/tput $@
}

ecolor_code()
{
   case $1 in

        # Primary
        black)            echo 0     ;;
        red)              echo 1     ;;
        green)            echo 2     ;;
        yellow)           echo 3     ;;
        blue)             echo 4     ;;
        magenta)          echo 5     ;;
        cyan)             echo 6     ;;
        white)            echo 7     ;;

        # Derivatives
        grey0)            echo 16     ;;
        navyblue)         echo 17     ;;
        darkgreen)        echo 22     ;;
        deepskyblue)      echo 24     ;;
        dodgerblue)       echo 26     ;;
        springgreen)      echo 35     ;;
        darkturqouise)    echo 44     ;;
        turquoise)        echo 45     ;;
        blueviolet)       echo 57     ;;
        orange)           echo 58     ;;
        slateblue)        echo 62     ;;
        paleturquoise)    echo 66     ;;
        steelblue)        echo 67     ;;
        cornflowerblue)   echo 69     ;;
        aquamarine)       echo 79     ;;
        darkred)          echo 88     ;;
        darkmagenta)      echo 90     ;;
        plum)             echo 96     ;;
        wheat)            echo 101    ;;
        lightslategrey)   echo 103    ;;
        darkseagreen)     echo 108    ;;
        darkviolet)       echo 128    ;;
        darkorange)       echo 130    ;;
        hotpink)          echo 132    ;;
        mediumorchid)     echo 134    ;;
        lightsalmon)      echo 137    ;;
        gold)             echo 142    ;;
        darkkhaki)        echo 143    ;;
        indianred)        echo 167    ;;
        orchid)           echo 170    ;;
        violet)           echo 177    ;;
        tan)              echo 180    ;;
        lightyellow)      echo 185    ;;
        honeydew)         echo 194    ;;
        salmon)           echo 209    ;;
        pink)             echo 218    ;;
        thistle)          echo 225    ;;

        # Lots of grey
        grey100)          echo 231    ;;
        grey3)            echo 232    ;;
        grey7)            echo 233    ;;
        grey11)           echo 234    ;;
        grey15)           echo 235    ;;
        grey19)           echo 236    ;;
        grey23)           echo 237    ;;
        grey27)           echo 238    ;;
        grey30)           echo 239    ;;
        grey35)           echo 240    ;;
        grey39)           echo 241    ;;
        grey42)           echo 242    ;;
        grey46)           echo 243    ;;
        grey50)           echo 244    ;;
        grey54)           echo 245    ;;
        grey58)           echo 246    ;;
        grey62)           echo 247    ;;
        grey66)           echo 248    ;;
        grey70)           echo 249    ;;
        grey74)           echo 250    ;;
        grey78)           echo 251    ;;
        grey82)           echo 252    ;;
        grey85)           echo 253    ;;
        grey89)           echo 254    ;;
        grey93)           echo 255    ;;

        # Unknown color code
        *)                die "Unknown color: $1" ;;
   esac

   return 0
}

ecolor()
{
    ## If EFUNCS_COLOR is empty then set it based on if STDERR is attached to a console
    local efuncs_color=${EFUNCS_COLOR:=}
    [[ -z ${efuncs_color} ]] && einteractive && efuncs_color=1
    [[ ${efuncs_color} -eq 1 ]] || return 0

    # Reset
    local c=$1
    local reset_re="\breset|none|off\b"
    [[ ${c} =~ ${reset_re} ]] && { echo -en "\033[m"; return 0; }

    local dimre="^dim"
    if [[ ${c} =~ ${dimre} ]]; then
        c=${c#dim}
    else
        tput bold
    fi

    tput setaf $(ecolor_code ${c})
}

eclear()
{
    tput clear >&2
}

etimestamp()
{
    echo -en "$(date '+%b %d %T')"
}

# Display a very prominent banner with a provided message which may be multi-line
# and an optional timestamp as well as the ability to provide any number of extra
# arguments which will be included in the banner in a pretty printed tag=value
# format. All of this is implemented with print_value to give consistency in how
# we log and present information.
ebanner()
{
    local cols lines entries

    echo "" >&2
    cols=$(tput cols)
    cols=$((cols-2))
    eval "local str=\$(printf -- '-%.0s' {1..${cols}})"
    echo -e "$(ecolor magenta)+${str}+" >&2
    echo -e "|" >&2

    # Print the first message honoring any newlines
    array_init_nl lines "${1}"; shift
    for line in "${lines[@]}"; do
        echo -e "| ${line}" >&2
    done

    # Timestamp
    [[ ${EFUNCS_TIME:=0} -eq 1 ]] && local stamp="[$(etimestamp)]" || local stamp=""
    [[ -n ${stamp} ]] && { echo -e "|\n| Time=${stamp}" >&2; }

    # Iterate over all other arguments and stick them into an associative array
    # If a custom key was requested via "key=value" format then use the provided
    # key and lookup value via print_value.
    declare -A __details

    local entries=("${@}")
    for k in "${entries[@]:-}"; do
        [[ -z ${k} ]] && continue

        local _ktag="${k%%=*}";
        : ${_ktag:=${k}}
        local _kval="${k#*=}";
        _ktag=${_ktag#+}
        __details[${_ktag}]=$(print_value ${_kval})

    done

    # Now output all the details (if any)
    if [[ -n ${__details[@]:-} ]]; then
        echo -e "|" >&2

        # Sort the keys and store into an array
        local keys
        keys=( $(for key in ${!__details[@]}; do echo "${key}"; done | sort) )

        # Figure out the longest key
        local longest=0
        for key in ${keys[@]}; do
            local len=${#key}
            (( len > longest )) && longest=$len
        done

        # Iterate over the keys of the associative array and print out the values
        for key in ${keys[@]}; do
            local pad=$((longest-${#key}+1))
            printf "| • %s%${pad}s :: %s\n" ${key} " " "${__details[$key]}" >&2
        done
    fi

    # Close the banner
    echo -e "|" >&2
    echo -e "+${str}+$(ecolor none)" >&2
}

emsg()
{
    # Only take known prefix settings
    local emsg_prefix=$(echo ${EMSG_PREFIX:=} | egrep -o "(time|times|level|caller|all)" || true)

    [[ ${EFUNCS_TIME:=0} -eq 1 ]] && emsg_prefix+=time

    local color=$(ecolor $1)
    local nocolor=$(ecolor none)
    local symbol=${2:-}
    local level=$3
    shift 3

    # Local args to hold the color and regexs for each field
    for field in time level caller msg; do
        local ${field}_color=${nocolor}
        eval "local ${field}_re='\ball|${field}\b'"
    done

    # Determine color values for each field used below.
    : ${EMSG_COLOR:="time level caller"}
    [[ ${EMSG_COLOR} =~ ${time_re}   ]] && time_color=${color}
    [[ ${EMSG_COLOR} =~ ${level_re}  ]] && level_color=${color}
    [[ ${EMSG_COLOR} =~ ${caller_re} ]] && caller_color=${color}

    # Build up the prefix for the log message. Each of these may optionally be in color or not. This is
    # controlled via EMSG_COLOR which is a list of fields to color. By default this is set to all fields.
    # The following fields are supported:
    # (1) time    : Timetamp
    # (2) level   : Log Level
    # (3) caller  : file:line:method
    local delim="${nocolor}|"
    local prefix=""

    if [[ ${level} =~ INFOS|WARNS && ${emsg_prefix} == "time" ]]; then
        :
    else
        local times_re="\ball|times\b"
        [[ ${level} =~ INFOS|WARNS && ${emsg_prefix} =~ ${times_re} || ${emsg_prefix} =~ ${time_re} ]] && prefix+="${time_color}$(etimestamp)"
        [[ ${emsg_prefix} =~ ${level_re}  ]] && prefix+="${delim}${level_color}$(printf "%s"  ${level%%S})"
        [[ ${emsg_prefix} =~ ${caller_re} ]] && prefix+="${delim}${caller_color}$(printf "%-10s" $(basename 2>/dev/null $(caller 1 | awk '{print $3, $1, $2}' | tr ' ' ':')) || true)"
    fi

    # Strip of extra leading delimiter if present
    prefix="${prefix#${delim}}"

    # If it's still empty put in the default
    if [[ -z ${prefix} ]] ; then
        prefix="${symbol}"
    else
        prefix="${color}[${prefix}${color}]"
        [[ ${level} =~ DEBUG|INFOS|WARNS ]] && prefix+=${symbol:2}
    fi

    # Color Policy
    if [[ ${EMSG_COLOR} =~ ${msg_re} || ${level} =~ DEBUG|WARN|ERROR ]] ; then
        echo -e "${color}${prefix} $@${nocolor}" >&2
    else
        echo -e "${color}${prefix}${nocolor} $@" >&2
    fi

    return 0
}

einfo()
{
    emsg "green" ">>" "INFO" "$@"
}

einfos()
{
    emsg "green" "   -" "INFOS" "$@"
}

ewarn()
{
    emsg "yellow" ">>" "WARN" "$@"
}

ewarns()
{
    emsg "yellow" "   -" "WARNS" "$@"
}

eerror_internal()
{
    $(declare_args)
    local color=$(opt_get c "red")
    emsg "${color}" ">>" "ERROR" "$@"
}

eerror()
{
    eerror_internal "$@"
}

# Print an error stacktrace to stderr.  This is like stacktrace only it pretty prints
# the entire stacktrace as a bright red error message with the funct and file:line
# number nicely formatted for easily display of fatal errors.
#
# Allows you to optionally pass in a starting frame to start the stacktrace at. 0 is
# the top of the stack and counts up. See also stacktrace and eerror_stacktrace.
#
# OPTIONS:
# -f=N
#   Frame number to start at (defaults to 2 to skip the top frames with
#   eerror_stacktrace and stacktrace_array).
#
# -s=(0|1)
#   Skip the initial error message (e.g. b/c the caller already displayed it).
#
# -c=(color)
#   Use the specified color for output messages.  Defaults to red.  Supports
#   any color that is supported by ecolor.
#
eerror_stacktrace()
{
    $(declare_args)
    local frame=$(opt_get f 2)
    local skip=$(opt_get s 0)
    local color=$(opt_get c "red")

    if [[ ${skip} -eq 0 ]]; then 
        echo "" >&2
        eerror_internal -c=${color} "$@"
    fi

    local frames=() frame
    stacktrace_array -f=${frame} frames

    array_empty frames ||
    for frame in "${frames[@]}"; do
        local line=$(echo ${frame} | awk '{print $1}')
        local func=$(echo ${frame} | awk '{print $2}')
        local file=$(basename $(echo ${frame} | awk '{print $3}'))

        [[ ${file} == "efuncs.sh" && ${func} == ${FUNCNAME} ]] && break

        printf "$(ecolor ${color})   :: %-20s | ${func}$(ecolor none)\n" "${file}:${line}" >&2
    done
}

# etable("col1|col2|col3", "r1c1|r1c2|r1c3"...)
etable()
{
    $(declare_args columns)
    local lengths=()
    local parts=()
    local idx=0

    for line in "${columns}" "$@"; do
        array_init parts "${line}" "|"
        idx=0
        for p in "${parts[@]}"; do
            mlen=${#p}
            [[ ${mlen} -gt ${lengths[$idx]:-} ]] && lengths[$idx]=${mlen}
            idx=$((idx+1))
        done
    done

    divider="+"
    array_init parts "${columns}" "|"
    idx=0
    for p in "${parts[@]}"; do
        len=$((lengths[$idx]+2))
        s=$(printf "%${len}s+")
        divider+=$(echo -n "${s// /-}")
        idx=$((idx+1))
    done

    printf "%s\n" ${divider}

    lnum=0
    for line in "${columns}" "$@"; do
        array_init parts "${line}" "|"
        idx=0
        printf "|"
        for p in "${parts[@]}"; do
            pad=$((lengths[$idx]-${#p}+1))
            printf " %s%${pad}s|" "${p}" " "
            idx=$((idx+1))
        done
        printf $'\n'
        lnum=$((lnum+1))
        if [[ ${lnum} -eq 1 || ${lnum} -eq $(( $# + 1 )) ]]; then
            printf "%s\n" ${divider}
        else
            [[ ${ETABLE_ROW_LINES:-1} -eq 1 ]] && printf "%s\n" ${divider//+/|}
        fi
    done
}

eprompt()
{
    echo -en "$(ecolor white) * $@: $(ecolor none)" >&2
    local result=""

    read result < /dev/stdin

    echo -en "${result}"
}

# eprompt_with_options allows the caller to specify what options are valid
# responses to the provided question. The caller can also optionally provide
# a list of "secret" options which will not be displayed in the prompt to the
# user but will be accepted as a valid response.
eprompt_with_options()
{
    $(declare_args msg opt ?secret)
    local valid="$(echo ${opt},${secret} | tr ',' '\n' | sort --ignore-case --unique)"
    msg+=" (${opt})"

    ## Keep reading input until a valid response is given
    while true; do
        response=$(die_on_abort; eprompt "${msg}")
        matches=( $(echo "${valid}" | grep -io "^${response}\S*" || true) )
        edebug "$(lval response opt secret matches valid)"
        [[ ${#matches[@]} -eq 1 ]] && { echo -en "${matches[0]}"; return 0; }

        eerror "Invalid response=[${response}] -- use a unique prefix from options=[${opt}]"
    done
}

epromptyn()
{
    $(declare_args msg)
    eprompt_with_options "${msg}" "Yes,No"
}

trim()
{
    echo "$1" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//'
}

compress_spaces()
{
    local output=$(echo -en "$@" | tr -s "[:space:]" " ")
    echo -en "${output}"
}

eend()
{
    local rc=${1:-0}

    if einteractive; then
        # Terminal magic that:
        #    1) Gets the number of columns on the screen, minus 6 because that's
        #       how many we're about to output
        #    2) Moves up a line
        #    3) Moves right the number of columns from #1
        local columns=$(tput cols)
        local startcol=$(( columns - 6 ))
        [[ ${startcol} -gt 0 ]] && echo -en "$(tput cuu1)$(tput cuf ${startcol} 2>/dev/null)" >&2
    fi

    if [[ ${rc} -eq 0 ]]; then
        echo -e "$(ecolor blue)[$(ecolor green) ok $(ecolor blue)]$(ecolor none)" >&2
    else
        echo -e "$(ecolor blue)[$(ecolor red) !! $(ecolor blue)]$(ecolor none)" >&2
    fi
}

spinout()
{
    local char="$1"
    echo -n -e "\b${char}" >&2
    sleep 0.10
}

do_eprogress()
{
    # Automatically detect if we should use ticker based on if we are interactive or not.
    if ! einteractive; then
        while true; do
            echo -n "." >&2
            sleep 1
        done
        return 0
    fi

    # Sentinal for breaking out of the loop on signal from eprogress_kill
    local done=0
    trap "done=1" ${DIE_SIGNALS[@]}

    local start=${SECONDS}
    while [[ ${done} -ne 1 ]]; do
        local now="${SECONDS}"
        local diff=$(( ${now} - ${start} ))

        echo -en "$(ecolor white)" >&2
        printf " [%02d:%02d:%02d]  " $(( ${diff} / 3600 )) $(( (${diff} % 3600) / 60 )) $(( ${diff} % 60 )) >&2
        echo -en "$(ecolor none)"  >&2

        spinout "/"
        spinout "-"
        spinout "\\"
        spinout "|"
        spinout "/"
        spinout "-"
        spinout "\\"
        spinout "|"

        # If we're terminating delete whatever character was lost displayed and print a blank space over it
        # then return immediately instead of resetting for next loop
        [[ ${done} -eq 1 ]] && { echo -en "\b " >&2; return 0; }

        echo -en "\b\b\b\b\b\b\b\b\b\b\b\b\b" >&2
    done
}

eprogress()
{
    echo -en "$(emsg "green" ">>" "INFO" "$@" 2>&1)" >&2

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    [[ ${EPROGRESS:-1} -eq 0 ]] && return 0

    # Prepend this new eprogress pid to the front of our list of eprogress PIDs
    # Add a trap to ensure we kill this backgrounded process in the event we
    # die before calling eprogress_kill.
    ( close_fds ; do_eprogress ) &
    __EPROGRESS_PIDS+=( $! )
    trap_add "eprogress_kill -r=1 $!"
}

# Kill the most recent eprogress in the event multiple ones are queued up.
# Can optionally pass in a specific list of eprogress pids to kill.
#
# Options:
# -r Return code to use (defaults to 0)
# -a Kill all eprogress pids.
eprogress_kill()
{
    $(declare_args)
    local rc=$(opt_get r 0)

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    if [[ ${EPROGRESS:-1} -eq 0 ]] ; then
        einteractive && echo "" >&2
        eend ${rc}
        return 0
    fi

    # If given a list of pids, kill each one. Otherwise kill most recent.
    # If there's nothing to kill just return.
    local pids=()
    if [[ $# -gt 0 ]]; then
        pids=( ${@} )
    elif array_not_empty __EPROGRESS_PIDS; then 
        if opt_true a; then
            pids=( "${__EPROGRESS_PIDS[@]}" )
        else
            pids=( "${__EPROGRESS_PIDS[-1]}" )
        fi
    else
        return 0
    fi

    # Kill requested eprogress pids
    local pid
    for pid in ${pids[@]}; do

        # Don't kill the pid if it's not running or it's not an eprogress pid.
        # This catches potentially disasterous errors where someone would do
        # "eprogress_kill ${rc}" when they really meant "eprogress_kill -r=${rc}"
        if process_not_running ${pid} || ! array_contains __EPROGRESS_PIDS ${pid}; then
            continue
        fi

        # Kill process and wait for it to complete
        ekill ${pid}
        wait ${pid} &>/dev/null || true
        array_remove __EPROGRESS_PIDS ${pid}
        
        # Output
        einteractive && echo "" >&2
        eend ${rc}
    done

    return 0
}

#-----------------------------------------------------------------------------
# SIGNAL FUNCTIONS
#-----------------------------------------------------------------------------

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

# Given a signal name or number, echo the signal number associated with it.
# 
# Options:
#   -s: Get the form that (usually) includes SIG.  For real signals this is
#       something like SIGKILL, SIGINT.  But bash treats its pseudo-signals
#       differently, so EXIT, ERR, and DEBUG all leave off the SIG.
#
signame()
{
    $(declare_args)
    local prefix=""
    if opt_true s ; then
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


#-----------------------------------------------------------------------------
# PROCESS FUNCTIONS
#-----------------------------------------------------------------------------

# Check if a given process is running. Returns success (0) if the process is
# running and failure (1) otherwise.
process_running()
{
    $(declare_args pid)
    kill -0 ${pid} &>/dev/null
}

# Check if a given process is NOT running. Returns success (0) if the process
# is not running and failure (1) otherwise.
process_not_running()
{
    $(declare_args pid)
    ! kill -0 ${pid} &>/dev/null
}

# Generate a depth first recursive listing of entire process tree beneath a given PID.
# If the pid does not exist this will produce an empty string.
process_tree()
{
    $(declare_args pid)

    process_not_running "${pid}" && return 0

    for child in $(ps -o pid --no-headers --ppid ${pid} || true); do
        process_tree ${child}
    done

    echo -n "${pid} "
}

# Kill all pids provided as arguments to this function using the specified signal.
# This function is best effort only. It makes every effort to kill all the specified
# pids but ignores any errors while calling kill. This is largely due to the fact
# that processes can exit before we get a chance to kill them. If you really care
# about processes being gone consider using process_not_running or cgroups.
#
# Options:
# -s=SIGNAL The signal to send to the pids (defaults to SIGTERM).
ekill()
{
    $(declare_args)

    # Determine what signal to send to the processes
    local signal=$(opt_get s SIGTERM)

    # Kill all requested PIDs using requested signal.
    kill -${signal} ${@} &>/dev/null || true
}

# Kill entire process tree for each provided pid by doing a depth first search to find
# all the descendents of each pid and kill all leaf nodes in the process tree first.
# Then it walks back up and kills the parent pids as it traverses back up the tree.
# Like ekill(), this function is best effort only. If you want more robust guarantees
# consider process_not_running or cgroups.
#
# Options:
# -s=SIGNAL 
#       The signal to send to the pids (defaults to SIGTERM).
# -x="pids"
#       Pids to exclude from killing.  $$ and $BASHPID are _ALWAYS_ excluded
#       from killing.
#
ekilltree()
{
    $(declare_args)

    # Determine what signal to send to the processes
    local signal=$(opt_get s SIGTERM)
    local excluded="$$ $BASHPID $(opt_get x)"

    local pid
    for pid in ${@}; do 
        edebug "Killing process tree $(lval pid signal)"
        
        for child in $(ps -o pid --no-headers --ppid ${pid} || true); do
            edebug "Killing $(lval child)"
            ekilltree -x="${excluded}" -s=${signal} ${child}
        done

        if echo "${excluded}" | grep -wq ${pid} ; then
            edebug "Skipping $(lval excluded pid)"
        else
            ekill -s=${signal} ${pid}
        fi
    done
}

#-----------------------------------------------------------------------------
# LOGGING
#-----------------------------------------------------------------------------

# Print the value for the corresponding variable using a slightly modified
# version of what is returned by declare -p. This is the lower level function
# called by lval in order to easily print tag=value for the provided arguments
# to lval. The type of the variable will dictate the delimiter used around the
# value portion. Wherever possible this is meant to generally mimic how the
# types are declared and defined.
#
# Specifically:
#
# - Strings: delimited by double quotes.
# - Arrays and associative arrays: Delimited by ( ).
# - Packs: You must preceed the pack name with a plus sign (i.e. +pack)
#
# Examples:
# String: "value1"
# Arrays: ("value1" "value2 with spaces" "another")
# Associative Arrays: ([key1]="value1" [key2]="value2 with spaces" )
print_value()
{
    local __input=${1:-}
    [[ -z ${__input} ]] && return 0

    # Special handling for packs, as long as their name is specified with a
    # plus character in front of it
    if [[ "${__input:0:1}" == '+' ]] ; then
        pack_print "${__input:1}"
        return 0
    fi

    local decl=$(declare -p ${__input} 2>/dev/null || true)
    local val=$(echo "${decl}")
    val=${val#*=}

    # Deal with properly declared variables which are empty
    [[ -z ${val} ]] && val='""'

    # Special handling for arrays and associative arrays
    regex="declare -[aA]"
    [[ ${decl} =~ ${regex} ]] && { val=$(declare -p ${__input} | sed -e "s/[^=]*='(\(.*\))'/(\1)/" -e "s/[[[:digit:]]\+]=//g"); }

    echo -n "${val}"
}

# Log a list of variable in tag="value" form similar to our C++ logging idiom.
# This function is variadic (takes variable number of arguments) and will log
# the tag="value" for each of them. If multiple arguments are given, they will
# be separated by a space, as in: tag="value" tag2="value" tag3="value3"
#
# This is implemented via calling print_value on each entry in the argument
# list. The one other really handy thing this does is understand our C++
# LVAL2 idiom where you want to log something with a _different_ key. So
# you can say nice things like:
#
# $(lval PWD=$(pwd) VARS=myuglylocalvariablename)
lval()
{
    local __lval_pre=""
    for __arg in "${@}"; do

        # Tag provided?
        local __arg_tag=${__arg%%=*}; [[ -z ${__arg_tag} ]] && __arg_tag=${__arg}
        local __arg_val=${__arg#*=}
        __arg_tag=${__arg_tag#+}
        __arg_val=$(print_value "${__arg_val}")

        echo -n "${__lval_pre}${__arg_tag}=${__arg_val}"
        __lval_pre=" "
    done
}

#-----------------------------------------------------------------------------
# NETWORKING FUNCTIONS
#-----------------------------------------------------------------------------
valid_ip()
{
    $(declare_args ip)
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        array_init ip "${ip}" "."
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

hostname_to_ip()
{
    $(declare_args hostname)

    local output hostrc ip
    output="$(host ${hostname} | grep ' has address ' || true)"
    hostrc=$?
    edebug "hostname_to_ip $(lval hostname output)"
    [[ ${hostrc} -eq 0 ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    ip=$(echo ${output} | awk '{print $4}')

    valid_ip ${ip} || { ewarn "Resolved ${hostname} into invalid ip address ${ip}." ; return 1 ; }

    echo ${ip}
    return 0
}

fully_qualify_hostname()
{
    local hostname=${1,,}
    argcheck hostname

    local output hostrc fqhostname
    output=$(host ${hostname})
    hostrc=$?
    edebug "fully_qualify_hostname: hostname=${hostname} output=${output}"
    [[ ${hostrc} -eq 0 ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }
    fqhostname=$(echo ${output} | awk '{print $1}')
    fqhostname=${fqhostname,,}

    [[ ${fqhostname} =~ ${hostname} ]] || { ewarn "Invalid fully qualified name ${fqhostname} from ${hostname}." ; return 1 ; }

    echo ${fqhostname}
    return 0
}

getipaddress()
{
    $(declare_args iface)
    local ip=$(/sbin/ifconfig ${iface} | grep -o 'inet addr:\S*' | cut -d: -f2 || true)
    echo -n "${ip//[[:space:]]}"
}

getnetmask()
{
    $(declare_args iface)
    local netmask=$(/sbin/ifconfig ${iface} | grep -o 'Mask:\S*' | cut -d: -f2 || true)
    echo -n "${netmask//[[:space:]]}"
}

getbroadcast()
{
    $(declare_args iface)
    local bcast=$(/sbin/ifconfig ${iface} | grep -o 'Bcast::\S*' | cut -d: -f2 || true)
    echo -n "${bcast//[[:space:]]}"
}

# Gets the default gateway that is currently in use
getgateway()
{
    local gw=$(route -n | grep 'UG[ \t]' | awk '{print $2}' || true)
    echo -n "${gw//[[:space:]]}"
}

# Compute the subnet given the current IPAddress (ip) and Netmask (nm)
getsubnet()
{
    $(declare_args ip nm)

    IFS=. read -r i1 i2 i3 i4 <<< "${ip}"
    IFS=. read -r m1 m2 m3 m4 <<< "${nm}"

    printf "%d.%d.%d.%d" "$((i1 & m1))" "$(($i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

# Get list of network interfaces
get_network_interfaces()
{
    ls -1 /sys/class/net | egrep -v '(bonding_masters|Bond)' | tr '\n' ' ' || true
}

# Get list network interfaces with specified "Supported Ports" query.
get_network_interfaces_with_port()
{
    local query="$1"
    local ifname port
    local results=()

    for ifname in $(get_network_interfaces); do
        port=$(ethtool ${ifname} | grep "Supported ports:" || true)
        [[ ${port} =~ "${query}" ]] && results+=( ${ifname} )
    done

    echo -n "${results[@]}"
}

# Get list of 1G network interfaces
get_network_interfaces_1g()
{
    get_network_interfaces_with_port "TP"
}

# Get list of 10G network interfaces
get_network_interfaces_10g()
{
    get_network_interfaces_with_port "FIBRE"
}

# Get the permanent MAC address for given ifname.
# NOTE: Do NOT use ethtool -P for this as that doesn't reliably
#       work on all cards since the firmware has to support it properly.
get_permanent_mac_address()
{
    $(declare_args ifname)

    if [[ -e /sys/class/net/${ifname}/master ]]; then
        sed -n "/Slave Interface: ${ifname}/,/^$/p" /proc/net/bonding/$(basename $(readlink -f /sys/class/net/${ifname}/master)) \
            | grep "Permanent HW addr" \
            | sed -e "s/Permanent HW addr: //"
    else
        cat /sys/class/net/${ifname}/address
    fi
}

# Get the PCI device location for a given ifname
# NOTE: This is only useful for physical devices, such as eth0, eth1, etc.
get_network_pci_device()
{
    $(declare_args ifname)

    (cd /sys/class/net/${ifname}/device; basename $(pwd -P))
}

# Export ethernet device names in the form ETH_1G_0=eth0, etc.
export_network_interface_names()
{
    local idx=0
    local ifname

    for ifname in $(get_network_interfaces_10g); do
        eval "ETH_10G_${idx}=${ifname}"
        (( idx+=1 ))
    done

    idx=0
    for ifname in $(get_network_interfaces_1g); do
        eval "ETH_1G_${idx}=${ifname}"
        (( idx+=1 ))
    done
}

# Get a list of the active network ports on this machine. The result is returned as an array of packs stored in the
# variable passed to the function.
#
# Options:
#  -l Only include listening ports
#
# For example:
# declare -A ports
# get_listening_ports ports
# einfo $(lval +ports[5])
# >> ports[5]=([proto]="tcp" [recvq]="0" [sendq]="0" [local_addr]="0.0.0.0" [local_port]="22" [remote_addr]="0.0.0.0" [remote_port]="0" [state]="LISTEN" [pid]="9278" [prog]="sshd" )
# einfo $(lval +ports[42])
# ports[42]=([proto]="tcp" [recvq]="0" [sendq]="0" [local_addr]="172.17.5.208" [local_port]="48899" [remote_addr]="173.194.115.70" [remote_port]="443" [state]="ESTABLISHED" [pid]="28073" [prog]="chrome" )
#
get_network_ports()
{
    $(declare_args __ports_list)

    local idx=0
    local first=1
    while read line; do

        # Expected netstat format:
        #  Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
        #  tcp        0      0 10.30.65.166:4013       0.0.0.0:*               LISTEN      42004/sfapp
        #  tcp        0      0 10.30.65.166:4014       0.0.0.0:*               LISTEN      42002/sfapp
        #  tcp        0      0 10.30.65.166:8080       0.0.0.0:*               LISTEN      42013/sfapp
        #  tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      19221/sshd
        #  tcp        0      0 0.0.0.0:442             0.0.0.0:*               LISTEN      13159/sfconfig
        #  tcp        0      0 172.30.65.166:2222      192.168.138.137:35198   ESTABLISHED 6112/sshd: root@not
        # ...
        #  udp        0      0 0.0.0.0:123             0.0.0.0:*                           45883/ntpd
        #  udp        0      0 0.0.0.0:161             0.0.0.0:*                           39714/snmpd
        #  udp        0      0 0.0.0.0:514             0.0.0.0:*                           39746/rsyslogd
        #
        # If netstat cannot determine the program that is listening on that port (not enough permissions) it will substitute a "-":
        #  tcp        0      0 0.0.0.0:902             0.0.0.0:*               LISTEN      -
        #  udp        0      0 0.0.0.0:43481           0.0.0.0:*                           -
        #

        # Compare first line to make sure fields are what we expect
        if [[ ${first} -eq 1 ]]; then
            local expected_fields="Proto Recv-Q Send-Q Local Address Foreign Address State PID/Program name"
            assert_eq "${expected_fields}" "${line}"
            first=0
            continue
        fi

        # Convert the line into an array for easy access to the fields
        # Replace * with 0 so that we don't get a glob pattern and end up with an array full of filenames from the local directory
        local fields
        array_init fields "$(echo ${line} | tr '*' '0')" " :/"

        # Skip this line if this is not TCP or UDP
        [[ ${fields[0]} =~ (tcp|udp) ]] || continue

        # Skip this line if the -l flag was passed in and this is not a listening port
        opt_true "l" && [[ ${fields[0]} == "tcp" && ! ${fields[7]} =~ "LISTEN" ]] && continue

        # If there is a - in the line, then netstat could not determine the program listening on this port.
        # Remove the - and add empty strings for the last two fields (PID and program name)
        if [[ ${line} =~ "-" ]]; then
            array_remove fields "-"
            fields+=("")
            fields+=("")
        fi

        # If this is a UDP port, insert an empty string into the "state" field
        if [[ ${fields[0]} == "udp" ]]; then
            fields[9]=${fields[8]}
            fields[8]=${fields[7]}
            fields[7]=""
        fi

        pack_set ${__ports_list}[${idx}] \
            proto=${fields[0]} \
            recvq=${fields[1]} \
            sendq=${fields[2]} \
            local_addr=${fields[3]} \
            local_port=${fields[4]} \
            remote_addr=${fields[5]} \
            remote_port=${fields[6]} \
            state=${fields[7]} \
            pid=${fields[8]} \
            prog=${fields[9]}

        (( idx += 1 ))

    done <<< "$(netstat --all --program --numeric --protocol=inet 2>/dev/null | sed '1d' | tr -s ' ')"
}

#-----------------------------------------------------------------------------
# FILESYSTEM HELPERS
#-----------------------------------------------------------------------------

pushd()
{
    builtin pushd "${@}" >/dev/null
}

popd()
{
    builtin popd "${@}" >/dev/null
}

# chmod + chown
echmodown()
{
    [[ $# -ge 3 ]] || die "echmodown requires 3 or more parameters. Called with $# parameters (chmodown $@)."
    $(declare_args mode owner)

    chmod ${mode} $@
    chown ${owner} $@
}

# Unmount (if mounted) and remove directory (if it exists) then create it anew
efreshdir()
{
    $(declare_args mnt)

    eunmount_recursive ${mnt}
    rm -rf ${mnt}
    mkdir -p ${mnt}
}

# Copies the given file to *.bak if it doesn't already exist
ebackup()
{
    $(declare_args src)

    [[ -e "${src}" && ! -e "${src}.bak" ]] && cp -arL "${src}" "${src}.bak" || true
}

erestore()
{
    $(declare_args src)

    [[ -e "${src}.bak" ]] && mv "${src}.bak" "${src}"
}

# elogrotate rotates all the log files with a given basename similar to what
# happens with logrotate. It will always touch an empty non-versioned file
# just log logrotate.
#
# For example, if you pass in the pathname '/var/log/foo' and ask to keep a
# max of 5, it will do the following:
#   /var/log/foo.4 -> /var/log/foo.5
#   /var/log/foo.3 -> /var/log/foo.4
#   /var/log/foo.2 -> /var/log/foo.3
#   /var/log/foo.1 -> /var/log/foo.2
#   /var/log/foo   -> /var/log/foo.1
#   touch /var/log/foo
#
# OPTIONS
# -c=NUM
#   Maximum count of logs to keep (defaults to 5).
#
# -s=SIZE
#   Rotate logfiles if the size of most recent file is greater than SIZE.
#   SIZE can be expressed using syntax accepted by find(1) --size option.
#   Specifically, you add a suffix to denote the units:
#   c for bytes
#   w for two-byte words
#   k for kilobytes
#   M for Megabytes
#   G for gigabytes
#
elogrotate()
{
    $(declare_args name)
    local count=$(opt_get c 5)
    local size=$(opt_get s 0)
    
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

# elogfile provides the ability to duplicate the calling processes STDOUT
# and STDERR and send them both to a list of files while simultaneously displaying
# them to the console. Using this method is much preferred over manually doing this
# with tee and named pipe redirection as we take special care to ensure STDOUT and
# STDERR pipes are kept separate to avoid problems with logfiles getting truncated.
#
# OPTIONS
#
# -e=(0|1)
#   Redirect STDERR (defaults to 1)
#
# -o=(0|1)
#   Redirect STDOUT (defaults to 1)
#
# -r=NUM
#   Rotate logfile via elogrotate and keep maximum of NUM logs (defaults to 0
#   which is disabled).
#
# -s=SIZE
#   Rotate logfiles via elogrotate if the size of most recent file is greater
#   than SIZE. SIZE can be expressed using syntax accepted by find(1) --size
#   option. Specifically, you add a suffix to denote the units:
#   c for bytes, w for two-byte words, k for kilobytes, M for Megabytes, and
#   G for gigabytes.
#
# -t=(0|1)
#   Tail the output (defaults to 1)
#
# -m=(0|1)
#   Merge STDOUT and STDERR output streams into a single stream on STDOUT.
#
elogfile()
{
    $(declare_args)

    local stdout=$(opt_get o 1)
    local stderr=$(opt_get e 1)
    local dotail=$(opt_get t 1)
    local rotate=$(opt_get r 0)
    local rotate_size=$(opt_get s 0)
    local merge=$(opt_get m 0)
    edebug "$(lval stdout stderr dotail rotate_count rotate_size merge)"

    # Return if nothing to do
    if [[ ${stdout} -eq 0 && ${stderr} -eq 0 ]] || [[ -z "$*" ]]; then
        return 0
    fi

    # Rotate logs as necessary but only if they are regular files
    if [[ ${rotate} -gt 0 ]]; then
        local name
        for name in "${@}"; do
            [[ -f $(readlink -f "${name}") ]] || continue
            elogrotate -c=${rotate} -s=${rotate_size} "${name}"
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
    local tmpdir=$(mktemp -d /tmp/elogfile-XXXXXXXX)
    trap_add "rm -rf ${tmpdir}"
    local pid_pipe="${tmpdir}/pids"
    mkfifo "${pid_pipe}"
 
    # Internal function to avoid code duplication in setting up the pipes
    # and redirection for stdout and stderr.
    elogfile_redirect()
    {
        $(declare_args name)

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
            close_fds
            ( 

                # If we are in a cgroup, move the tee process out of that
                # cgroup so that we do not kill the tee.  It will nicely
                # terminate on its own once the process dies.
                if [[ ${EUID} -eq 0 && -n "$(cgroup_current)" ]] ; then
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

                if [[ ${dotail} -eq 1 ]]; then
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

# etar is a wrapper around the normal 'tar' command with a few enhancements:
# - Suppress all the normal noisy warnings that are almost never of interest to us.
# - Automatically detect fastest compression program by default. If this isn't desired
#   then pass in --use-compress-program=<PROG>. Unlike normal tar, this will big the
#   last one in the command line instead of giving back a fatal error due to multiple
#   compression programs.
etar()
{
    # Disable all tar warnings which are expected with unknown file types, sockets, etc.
    local args=("--warning=none")

    # Provided an explicit compression program wasn't provided via "-I/--use-compress-program"
    # then automatically determine the compression program to use based on file
    # suffix... but substitute in pbzip2 for bzip and pigz for gzip
    local match=$(echo "$@" | egrep '(-I|--use-compress-program)' || true)
    if [[ -z ${match} ]]; then

        local prog=""
        if [[ -n $(echo "$@" | egrep "\.bz2|\.tz2|\.tbz2|\.tbz" || true) ]]; then
            prog="pbzip2"
        elif [[ -n $(echo "$@" | egrep "\.gz|\.tgz|\.taz" || true) ]]; then
            prog="pigz"
        fi

        # If the program we selected is available set that as the compression program
        # otherwise fallback to auto-compress and let tar pick for us.
        if [[ -n ${prog} && -n $(which ${prog} 2>/dev/null || true) ]]; then
            args+=("--use-compress-program=${prog}")
        else
            args+=("--auto-compress")
        fi
    fi

    tar "${args[@]}" "${@}"
}

# Wrapper around computing the md5sum of a file to output just the filename
# instead of the full path to the filename. This is a departure from normal
# md5sum for good reason. If you download an md5 file with a path embedded into
# it then the md5sum can only be validated if you put it in the exact same path.
# This function will die on failure.
emd5sum()
{
    $(declare_args path)

    local dname=$(dirname  "${path}")
    local fname=$(basename "${path}")

    pushd "${dname}"
    md5sum "${fname}"
    popd
}

# Wrapper around checking an md5sum file by pushd into the directory that contains
# the md5 file so that paths to the file don't affect the md5sum check. This
# assumes that the md5 file is a sibling next to the source file with the suffix
# 'md5'. This method will die on failure.
emd5sum_check()
{
    $(declare_args path)

    local fname=$(basename "${path}")
    local dname=$(dirname  "${path}")

    pushd "${dname}"
    md5sum -c "${fname}.md5" | edebug
    popd
}

# Output checksum information for the given file to STDOUT. Specifically output
# the following:
#
# Filename=foo
# MD5=864ec6157c1eea88acfef44d0f34d219
# Size=2192793069
# SHA1=75490a32967169452c10c937784163126c4e9753
# SHA256=8297aefe5bb7319ab5827169fce2e664fe9cd7b88c9b31c40658ab55fcae3bfe
#
# Options:
#
# -p=PathToPrivateKey:  In addition to above checksums also output Base64 encoded
#    PGPSignature. The reason it is Base64 encoded is to properly deal with the
#    required header and footers before the actual signature body.
#
# -k=keyphrase: Optional keyphrase for the PGP Private Key
emetadata()
{
    $(declare_args path)
    [[ -e ${path} ]] || die "${path} does not exist"

    echo "Filename=$(basename ${path})"
    echo "Size=$(stat --printf="%s" "${path}")"

    # Now output MD5, SHA1, and SHA256
    local ctype
    for ctype in MD5 SHA1 SHA256; do
        echo "${ctype}=$(${ctype,,}sum "${path}" | awk '{print $1}')"
    done

    # If PGP signature is NOT requested we can simply return
    local privatekey=""
    privatekey=$(opt_get p)
    [[ -n ${privatekey} ]] || return 0

    # Import that into temporary secret keyring
    local keyring="" keyring_command=""
    keyring=$(mktemp /tmp/emetadata-keyring-XXXX)
    keyring_command="--no-default-keyring --secret-keyring ${keyring}"
    trap_add "rm -f ${keyring}"
    gpg ${keyring_command} --import ${privatekey} |& edebug

    # Get optional keyphrase
    local keyphrase="" keyphrase_command=""
    keyphrase=$(opt_get k)
    [[ -z ${keyphrase} ]] || keyphrase_command="--batch --passphrase ${keyphrase}"

    # Output PGPSignature encoded in base64
    echo "PGPKey=$(basename ${privatekey})"
    echo "PGPSignature=$(gpg --no-tty --yes ${keyring_command} --sign --detach-sign --armor ${keyphrase_command} --output - ${path} 2>/dev/null | base64 --wrap 0)"
}

# Validate an exiting source file against a companion *.meta file which contains
# various checksum fields. The list of checksums is optional but at present the
# supported fields we inspect are: Filename, Size, MD5, SHA1, SHA256, PGPSignature.
# 
# For each of the above fields, if they are present in the .meta file, validate 
# it against the source file. If any of them fail this function returns non-zero.
# If NO validators are present in the info file, this function returns non-zero.
#
# Options:
# -q=(0|1) Quiet mode (default=0)
# -p=PathToPublicKey: Use provided PGP Public Key for PGP validation (if PGPSignature
#                     is present in .meta file).
emetadata_check()
{
    $(declare_args path)
    local meta="${path}.meta"
    [[ -e ${path} ]] || die "${path} does not exist"
    [[ -e ${meta} ]] || die "${meta} does not exist"

    fail()
    {
        emsg "red" "   -" "ERROR" "$@"
        exit 1
    }

    local metapack="" digests=() validated=() expect="" actual="" ctype="" rc=0
    pack_set metapack $(cat "${meta}")
    local publickey=$(opt_get p)
    local pgpsignature=$(pack_get metapack PGPSignature | base64 --decode)

    # Figure out what digests we're going to validate
    for ctype in Size MD5 SHA1 SHA256; do
        pack_contains metapack "${ctype}" && digests+=( "${ctype}" )
    done
    [[ -n ${publickey} && -n ${pgpsignature} ]] && digests+=( "PGP" )

    opt_true "q" || eprogress "Verifying integrity of $(lval path metadata=digests)"
    pack_print metapack |& edebug
    local pids=()

    # Validate size
    if pack_contains metapack "Size"; then
        (
            expect=$(pack_get metapack Size)
            actual=$(stat --printf="%s" "${path}")
            [[ ${expect} -eq ${actual} ]] || fail "Size mismatch: $(lval path expect actual)"
        ) &

        pids+=( $! )
    fi

    # Now validated MD5, SHA1, and SHA256 (if present)
    for ctype in MD5 SHA1 SHA256; do
        if pack_contains metapack "${ctype}"; then
            (
                expect=$(pack_get metapack ${ctype})
                actual=$(${ctype,,}sum ${path} | awk '{print $1}')
                [[ ${expect} == ${actual} ]] || fail "${ctype} mismatch: $(lval path expect actual)"
            ) &

            pids+=( $! )
        fi
    done

    # If Public Key was provied and PGPSignature is present validate PGP signature
    if [[ -n ${publickey} && -n ${pgpsignature} ]]; then
        (
            local keyring=$(mktemp /tmp/emetadata-keyring-XXXX)
            trap_add "rm -f ${keyring}"
            gpg --no-default-keyring --secret-keyring ${keyring} --import ${publickey} |& edebug
            echo "${pgpsignature}" | gpg --verify - "${path}" |& edebug || fail "PGP verification failure: $(lval path)"
        ) &

        pids+=( $! )
    fi

    # Wait for all pids
    wait ${pids[@]} && rc=0 || rc=$?
    opt_true "q" || eprogress_kill -r=${rc}
    return ${rc}
}

#-----------------------------------------------------------------------------
# MOUNT / UMOUNT UTILS
#-----------------------------------------------------------------------------

# Helper method to take care of resolving a given path or mount point to its
# realpath as well as remove any errant '\040(deleted)' which may be suffixed
# on the path. This can happen if a device's source mount point is deleted
# while the destination path is still mounted.
emount_realpath()
{
    $(declare_args path)
    path="${path//\\040\(deleted\)/}"
    echo -n "$(readlink -m ${path} 2>/dev/null || true)"
}

# Echo the emount regex for a given path
emount_regex()
{
    $(declare_args path)
    echo -n "(^| )${path}(\\\\040\\(deleted\\))* "
}

# Echo the number of times a given directory is mounted.
emount_count()
{
    $(declare_args path)
    path=$(emount_realpath ${path})
    local num_mounts=$(grep --count --perl-regexp "$(emount_regex ${path})" /proc/mounts || true)
    echo -n ${num_mounts}
}

emounted()
{
    $(declare_args path)
    path=$(emount_realpath ${path})
    [[ -z ${path} ]] && { edebug "Unable to resolve $(lval path) to check if mounted"; return 1; }

    [[ $(emount_count "${path}") -gt 0 ]]
}

# Bind mount $1 over the top of $2.  Ebindmount works to ensure that all of
# your mounts are private so that we don't see different behavior between
# systemd machines (where shared mounts are the default) and everywhere else
# (where private mounts are the default)
#
# Source and destination MUST be the first two parameters of this function.
# You may specify any other mount options after them.
#
ebindmount()
{
    $(declare_args src dest)

    # The make-private commands are best effort.  We'll try to mark them as
    # private so that nothing, for example, inside a chroot can mess up the
    # machine outside that chroot.
    mount --make-rprivate "${src}"  |& edebug || true
    emount --rbind "${@}" "${src}" "${dest}"
    mount --make-rprivate "${dest}" |& edebug || true
}

emount()
{
    einfos "Mounting $@"
    mount "${@}"
}

eunmount()
{
    local mnt
    for mnt in $@; do
        emounted ${mnt} || continue
        local rdev=$(emount_realpath ${mnt})
        argcheck rdev

        einfos "Unmounting ${mnt}"
        umount -l "${rdev}"
    done
}

# Recursively find all mount points beneath a given root.
# This is like findmnt with a few additional enhancements:
# (1) Automatically recusrive
# (2) findmnt doesn't find mount points beneath a non-root directory
efindmnt()
{
    $(declare_args path)
    path=$(emount_realpath ${path})

    # First check if the requested path itself is mounted
    emounted "${path}" && echo "${path}" || true

    # Now look for anything beneath that directory
    grep --perl-regexp "(^| )${path}[/ ]" /proc/mounts | awk '{print $2}' | sed '/^$/d' || true
}

eunmount_recursive()
{
    local mnt
    for mnt in "${@}"; do
        local rdev=$(emount_realpath "${mnt}")
        argcheck rdev

        while true; do

            # If this path is directly mounted or anything BENEATH it is mounted then proceed
            local matches="$(efindmnt ${mnt} | sort -ur)"
            [[ -n ${matches} ]] || break

            local nmatches=$(echo "${matches}" | wc -l)
            einfo "Recursively unmounting ${mnt} (${nmatches})"
            local match
            for match in "${matches}"; do
                eunmount "${match//${rdev}/${mnt}}"
            done
        done
    done
}

#-----------------------------------------------------------------------------
# DISTRO-SPECIFIC
#-----------------------------------------------------------------------------

edistro()
{
    lsb_release -is
}

isubuntu()
{
    [[ "Ubuntu" == $(edistro) ]]
}

isgentoo()
{
    [[ "Gentoo" == $(edistro) ]]
}

#-----------------------------------------------------------------------------
# COMPARISON FUNCTIONS
#-----------------------------------------------------------------------------

# Generic comparison function using awk which doesn't suffer from bash stupidity
# with regards to having to do use separate comparison operators for integers and
# strings and even worse being completely incapable of comparing floats.
compare()
{
    $(declare_args ?lh op ?rh)

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

#-----------------------------------------------------------------------------
# ARGUMENT HELPERS
#-----------------------------------------------------------------------------

# Check to ensure all the provided arguments are non-empty
argcheck()
{
    local _argcheck_arg
    for _argcheck_arg in $@; do
        [[ -z "${!_argcheck_arg:-}" ]] && die "Missing argument '${_argcheck_arg}'" || true
    done
}

# declare_args takes a list of names and declares a variable for each name from
# the positional arguments in the CALLER's context. It also implicitly looks for
# any options which may have been passed into the called function in the initial
# arguments and stores them into an internal pack for later inspection.
#
# Options Rules:
# (0) Will repeatedily parse first argument and shift so long as first arg contains
#     options.
# (1) Only single character arguments are supported
# (2) Options may be grouped if they do not take arguments (e.g. -abc == -a -b -c)
# (3) Options may take arguments by using an equal sign (e.g. -a=foobar -b="x y z")
#
# All options will get exported into an internal pack named after the caller's
# function. If the caller's function name is 'foo' then the internal pack is named
# '_foo_options'. Instead of interacting with this pack direclty simply use the
# helper methods: opt_true, opt_false, opt_get.
#
# We want all code generated by this function to be invoked in the caller's
# environment instead of within this function. BUT, we don't want to have to use
# clumsy eval $(declare_args...). So instead we use "eval command invocation string"
# which the caller executes via:
#
# $(declare_args a b)
#
# This gets turned into:
#
# "declare a=$1; shift; argcheck a1; declare b=$2; shift; argcheck b; "
#
# There are various special meta characters that can precede the variable name
# that act as instructions to declare_args. Specifically:
#
# ?  The named argument is OPTIONAL. If it's empty do NOT call argcheck.
#
# _  The argument is anonymous and we should not not assign the value to anything.
#    NOTE: The argument must be exactly '_' not just prefixed with '_'. Thus if
#    the argument is literally '_' it will be anonymous but if it is '_a' it is
#    NOT an anonymous variable.
#
# OPTIONS:
# -n: Do not parse options at all
# -l: Emit local variables with 'local' scope qualifier (default)
# -g: Emit global variables with no scope qualifier
# -e: Emit exported variables with 'export' keyword
#
# WARNING: DO NOT CALL EDEBUG INSIDE THIS FUNCTION OR YOU WILL CAUSE INFINITE RECURSION!!
declare_args()
{
    local _declare_args_parse_options=1
    local _declare_args_qualifier="local"
    local _declare_args_optional=0
    local _declare_args_variable=""
    local _declare_args_cmd=""

    # Check the internal declare_args options. We cannot at present reuse the code
    # below which parses options as that's baked into the internal implementation
    # of delcare_args itself and cannot at present be extracted usefully.
    # This is a MUCH more limited version of option parsing.
    if [[ $# -gt 0 && ${1:0:1} == "-" ]]; then
        [[ $1 =~ "n" ]] && _declare_args_parse_options=0
        [[ $1 =~ "l" ]] && _declare_args_qualifier="local"
        [[ $1 =~ "g" ]] && _declare_args_qualifier=""
        [[ $1 =~ "e" ]] && _declare_args_qualifier="export"
        shift
    fi

    # Look at the first argument and see if it starts with a '-'. If so, then grab each
    # character in the first argument and store them into an array so caller can check
    # if particular flags were passed in or not.
    # NOTE: We always declare the _options pack in the caller's environment so code
    #       doesn't have to handle any error cases where it's not defined.
    local _declare_args_caller _declare_args_options
    _declare_args_caller=( $(caller 0) )
    _declare_args_options="_${_declare_args_caller[1]}_options"
    _declare_args_cmd+="declare ${_declare_args_options}='';"
    if [[ ${_declare_args_parse_options} -eq 1 ]]; then
        _declare_args_cmd+="
        while [[ \$# -gt 0 && \${1:0:1} == '-' ]]; do
            [[ \${1:1} =~ '=' ]]
                && pack_set ${_declare_args_options} \"\${1:1}\"
                || pack_set ${_declare_args_options} \$(echo \"\${1:1}\" | grep -o . | sed 's|$|=1|' | tr '\n' ' '; true);
        shift;
        done;"
    fi

    while [[ $# -gt 0 ]]; do
        # If the variable name is "_" then don't bother assigning it to anything
        [[ $1 == "_" ]] && _declare_args_cmd+="shift; " && { shift; continue; }

        # Check if the argument is optional or not as indicated by a leading '?'.
        # If the leading '?' is present then REMOVE It so that code after it can
        # correctly use the key name as the variable to assign it to.
        [[ ${1:0:1} == "?" ]] && _declare_args_optional=1 || _declare_args_optional=0
        _declare_args_variable="${1#\?}"

        # Declare the variable and then call argcheck if required
        _declare_args_cmd+="${_declare_args_qualifier} ${_declare_args_variable}=\${1:-}; shift &>/dev/null || true; "
        [[ ${_declare_args_optional} -eq 0 ]] && _declare_args_cmd+="argcheck ${_declare_args_variable}; "

        shift
    done

    echo "eval ${_declare_args_cmd}"
}

# Helper method to print the options after calling declare_args.
opt_print()
{
    local _caller=( $(caller 0) )
    pack_print _${_caller[1]}_options
}

# Helper method to be used after declare_args to check if a given option is true (1).
opt_true()
{
    local _caller=( $(caller 0) )
    [[ "$(pack_get _${_caller[1]}_options ${1})" -eq 1 ]]
}

# Helper method to be used after declare_args to check if a given option is false (0).
opt_false()
{
    local _caller=( $(caller 0) )
    [[ "$(pack_get _${_caller[1]}_options ${1})" -eq 0 ]]
}

# Helper method to be used after declare_args to extract the value of an option.
# Unlike opt_get this one allows you to specify a default value to be used in
# the event the requested option was not provided.
opt_get()
{
    $(declare_args key ?default)
    local _caller=( $(caller 0) )
    local _value=$(pack_get _${_caller[1]}_options ${key})
    : ${_value:=${default}}

    echo -n "${_value}"
}

#-----------------------------------------------------------------------------
# MISC HELPERS
#-----------------------------------------------------------------------------

# save_function is used to safe off the contents of a previously declared
# function into ${1}_real to aid in overridding a function or altering
# it's behavior.
save_function()
{
    local orig=$(declare -f $1)
    local new="${1}_real${orig#$1}"
    eval "${new}" &>/dev/null
}

# override_function is a more powerful version of save_function in that it will
# still save off the contents of a previously declared function into ${1}_real
# but it will also define a new function with the provided body ${2} and
# mark this new function as readonly so that it cannot be overridden later.
# If you call override_function multiple times we have to ensure it's idempotent.
# The danger here is in calling save_function multiple tiems as it may cause
# infinite recursion. So this guards against saving off the same function multiple
# times.
override_function()
{
    $(declare_args func body)

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

# Internal only efetch function which fetches an individual file using curl.
# This will show an eprogress ticker and then kill the ticker with either
# success or failure indicated. The return value is then returned to the
# caller for handling.
efetch_internal()
{
    $(declare_args url dst)
    local timecond=""
    [[ -f ${dst} ]] && timecond="--time-cond ${dst}"

    eprogress "Fetching $(lval url dst)"
    $(tryrc curl "${url}" ${timecond} --output "${dst}" --location --fail --silent --show-error --insecure)
    eprogress_kill -r=${rc}

    return ${rc}
}

# Fetch a provided URL to an optional destination path via efetch_internal. 
# This function can also optionally validate the fetched data against various
# companion files which contain metadata for file fetching. If validation is
# requested and the validation fails then all temporary files fetched are
# removed.
#
# Options:
# -m=(0|1) Fetch companion .md5 file and validate fetched file's MD5 matches.
# -M=(0|1) Fetch companion .meta file and validate metadata fields using emetadata_check.
# -q=(0|1) Quiet mode (disable eprogress and other info messages)
efetch()
{
    $(declare_args url ?dst)
    : ${dst:=/tmp}
    [[ -d ${dst} ]] && dst+="/$(basename ${url})"
    
    # Companion files we may fetch
    local md5="${dst}.md5"
    local meta="${dst}.meta"

    try
    {
        # Optionally suppress all output from this subshell
        opt_true "q" && exec &>/dev/null

        ## If requested, fetch MD5 file
        if opt_true "m"; then

            efetch_internal "${url}.md5" "${md5}"
            efetch_internal "${url}"     "${dst}"

            # Verify MD5
            einfos "Verifying MD5 $(lval dst md5)"

            local dst_dname=$(dirname  "${dst}")
            local dst_fname=$(basename "${dst}")
            local md5_dname=$(dirname  "${md5}")
            local md5_fname=$(basename "${md5}")

            cd "${dst_dname}"

            # If the requested destination was different than what was originally in the MD5 it will fail.
            # Or if the md5sum file was generated with a different path in it it will fail. This just
            # sanititizes it to have the current working directory and the name of the file we downloaded to.
            sed -i "s|\(^[^#]\+\s\+\)\S\+|\1${dst_fname}|" "${md5_fname}"

            # Now we can perform the check
            md5sum --check "${md5_fname}" >/dev/null

        ## If requested fetch *.meta file and validate using contained fields
        elif opt_true "M"; then

            efetch_internal "${url}.meta" "${meta}"
            efetch_internal "${url}"      "${dst}"
            emetadata_check "${dst}"
        
        ## BASIC file fetching only
        else
            efetch_internal "${url}" "${dst}"
        fi
    
        einfos "Successfully fetched $(lval url dst)"
    }
    catch
    {
        local rc=$?
        edebug "Removing $(lval dst md5 meta rc)"
        rm -rf "${dst}" "${md5}" "${meta}"
        return ${rc}
    }
}

netselect()
{
    local hosts=$@; argcheck hosts
    eprogress "Finding host with lowest latency from [${hosts}]"

    declare -a results sorted rows

    for h in ${hosts}; do
        local entry=$(die_on_abort; ping -c10 -w5 -q $h 2>/dev/null | \
            awk '/^PING / {host=$2}
                 /packet loss/ {loss=$6}
                 /min\/avg\/max/ {
                    split($4,stats,"/")
                    printf("%s|%f|%f|%s|%f", host, stats[2], stats[4], loss, (stats[2] * stats[4]) * (loss + 1))
                }')

        results+=("${entry}")
    done

    array_init_nl sorted "$(printf '%s\n' "${results[@]}" | sort -t\| -k5 -n)"
    array_init_nl rows "Server|Latency|Jitter|Loss|Score"

    for entry in ${sorted[@]} ; do
        array_init parts "${entry}" "|"
        array_add_nl rows "${parts[0]}|${parts[1]}|${parts[2]}|${parts[3]}|${parts[4]}"
    done

    eprogress_kill

    ## SHOW ALL RESULTS ##
    einfos "All results:"
    etable ${rows[@]} >&2

    local best=$(echo "${sorted[0]}" | cut -d\| -f1)
    einfos "Best host=[${best}]"

    echo -en "${best}"
}

# etimeout executes arbitrary shell commands for you, enforcing a timeout around the
# command.  If the command eventually completes successfully etimeout will return 0.
# Otherwise if it is prematurely terminated via the requested SIGNAL it will return
# 124 to match behavior with the vanilla timeout(1) command. If the process fails to
# exit after receiving requested signal it will send SIGKILL to the process. If this
# happens the return code of etimeout will still be 124 since we rely on that return
# code to indicate that a process timedout and was prematurely terminated.
#
# This function is similar in purpose to the vanilla timeout(1) command only this
# one is more powerful since it can call any arbitrary shell command including
# bash functions or eval'd strings.
#
# OPTIONS:
# -s SIGNAL=<signal name or number>     e.g. SIGNAL=2 or SIGNAL=TERM
#   When ${TIMEOUT} seconds have passed since running the command, this will be
#   the signal to send to the process to make it stop.  The default is TERM.
#   [NOTE: KILL will _also_ be sent two seconds after the timeout if the first
#   signal doesn't do its job]
#
# -t TIMEOUT (REQUIRED). After this duration, command will be killed if it hasn't
#   exited. If it's a simple number, the duration will be a number in seconds.  You
#   may also specify suffixes in the same format the timeout command accepts them.
#   For instance, you might specify 5m or 1h or 2d for 5 minutes, 1 hour, or 2
#   days, respectively.
#
# All direct parameters to etimeout are assumed to be the command to execute, and
# etimeout is careful to retain your quoting.
etimeout()
{
    # Parse options
    $(declare_args)
    local _etimeout_signal=$(opt_get s SIGTERM)
    local _etimeout_timeout=$(opt_get t "")
    argcheck _etimeout_timeout

    # Background the command to be run
    local start=${SECONDS}
    local cmd=("${@}")

    # If no command to execute just return success immediately
    if [[ -z "${cmd[@]:-}" ]]; then
        return 0
    fi

    # Launch command in the background and store off its pid.
    local rc=""
    "${cmd[@]}" &
    local pid=$!
    edebug "Executing $(lval cmd timeout=_etimeout_timeout signal=_etimeout_signal pid)"
 
    # Start watchdog process to kill process if it times out
    (
        die_on_abort
        close_fds

        # Sleep for the requested timeout. If process_tree is empty 
        # then it exited on its own and we don't have to kill it.
        sleep ${_etimeout_timeout}
        local pre_pids=( $(process_tree ${pid}) )
        array_empty pre_pids && exit 0

        # Process did not exit on it's own. Send it the intial requested
        # signal. If its process tree is empty then exit with 1.
        ekilltree -s=${_etimeout_signal} ${pid}
        sleep 2

        # If there are ANY processes in the original pid list still running OR
        # new processes in the process tree then blast a SIGKILL to all the pids
        # and exit with 1.
        local post_pids=( $(process_tree ${pid}) )
        array_empty post_pids && exit 1
        ekill -s=SIGKILL ${pre_pids[@]} ${post_pids[@]}
        exit 1

    ) &>/dev/null &

    # Wait for pid which will either be KILLED by watcher or complete normally.
    local watcher=$!
    wait ${pid}                     &>/dev/null && rc=0 || rc=$?
    ekilltree -s=SIGKILL ${watcher} &>/dev/null
    wait ${watcher}                 &>/dev/null && watcher_rc=0 || watcher_rc=$?
    local stop=${SECONDS}
    local seconds=$(( ${stop} - ${start} ))
    
    # If the process timedout return 124 to match timeout behavior.
    if [[ ${watcher_rc} -eq 1 ]]; then
        edebug "Timeout $(lval cmd rc seconds timeout=_etimeout_timeout signal=_etimeout_signal pid)"
        return 124
    else
        return ${rc}
    fi
}

# eretry executes arbitrary shell commands for you wrapped in a call to etimeout
# and retrying up to a specified count. If the command eventually completes
# successfully eretry will return 0. If the command never completes successfully
# but continues to fail every time the return code from eretry will be the failing
# command's return code. If the command is prematurely terminated via etimeout the
# return code from eretry will be 124.
#
# OPTIONS:
#
# -d DELAY. Amount of time to delay (sleep) after failed attempts before retrying.
#   Note that this value can accept sub-second values, just as the sleep command does.
#
# -e <space separated list of numbers>
#   Any of the exit codes specified in this list will cause eretry to stop
#   retrying. If eretry receives one of these codes, it will immediately stop
#   retrying and return that exit code.  By default, only a zero return code
#   will cause eretry to stop.  If you specify -e, you should consider whether
#   you want to include 0 in the list.
#
# -r RETRIES
#   Command will be attempted RETRIES times total. If no options are provided to
#   eretry it will use a default retry limit of 5.
#
# -s SIGNAL=<signal name or number>     e.g. SIGNAL=2 or SIGNAL=TERM
#   When ${TIMEOUT} seconds have passed since running the command, this will be
#   the signal to send to the process to make it stop.  The default is TERM.
#   [NOTE: KILL will _also_ be sent two seconds after the timeout if the first
#   signal doesn't do its job]
#
# -t TIMEOUT. After this duration, command will be killed (and retried if that's the
#   right thing to do).  If unspecified, commands may run as long as they like
#   and eretry will simply wait for them to finish. Uses sleep(1) time
#   syntax.
#
# -T TIMEOUT. Total timeout for entire eretry operation.
#   This -T flag is different than -t in that -T applies to the entire eretry
#   operation including all iterations and retry attempts and timeouts of each
#   individual command. Uses sleep(1) time syntax.
#
# -w SECONDS
#   A warning will be generated on (or slightly after) every SECONDS while the
#   command keeps failing.
#
# All direct parameters to eretry are assumed to be the command to execute, and
# eretry is careful to retain your quoting.
eretry()
{
    # Parse options
    $(declare_args)
    local _eretry_delay=$(opt_get d 0)
    local _eretry_exit_codes=$(opt_get e 0)
    local _eretry_retries=$(opt_get r "")
    local _eretry_signal=$(opt_get s SIGTERM)
    local _eretry_timeout_total=$(opt_get T "")
    local _eretry_timeout=$(opt_get t ${_eretry_timeout_total:-infinity})
    local _eretry_warn=$(opt_get w "")

    # If no total timeout or retry limit was specified then default to prior behavior with a max retry of 5.
    if [[ -z ${_eretry_timeout_total} && -z ${_eretry_retries} ]]; then
        _eretry_retries=5
    elif [[ -z ${_eretry_retries} ]]; then
        _eretry_retries="infinity"
    fi

    # If a total timeout was specified then wrap call to eretry_internal with etimeout
    if [[ -n ${_eretry_timeout_total} ]]; then
        etimeout -t=${_eretry_timeout_total} -s=${_eretry_signal} eretry_internal "${@}"
    else
        eretry_internal "${@}"
    fi
}

# Internal method called by eretry so that we can wrap the call to eretry_internal with a call
# to etimeout in order to provide upper bound on entire invocation.
eretry_internal()
{
    # Command
    local cmd=("${@}")
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
        [[ ${_eretry_retries} != "infinity" && ${attempt} -ge ${_eretry_retries} ]] && break || (( attempt+=1 ))
        
        edebug "Executing $(lval cmd rc stdout) retries=(${attempt}/${_eretry_retries})"

        # Run the command through timeout wrapped in tryrc so we can throw away the stdout 
        # on any errors. The reason for this is any caller who cares about the output of
        # eretry might see part of the output if the process times out. If we just keep
        # emitting that output they'd be getting repeated output from failed attempts
        # which could be completely invalid output (e.g. truncated XML, Json, etc).
        stdout=""
        $(tryrc -o=stdout etimeout -t=${_eretry_timeout} -s=${_eretry_signal} "${cmd[@]}")
        
        # Append list of exit codes we've seen
        exit_codes+=(${rc})

        # Break if the process exited with white listed exit code.
        if echo "${_eretry_exit_codes}" | grep -wq "${rc}"; then
            edebug "Command exited with white listed $(lval rc _eretry_exit_codes cmd) retries=(${attempt}/${_eretry_retries})"
            break
        fi

        # Show warning if requested
        if [[ -n ${_eretry_warn} ]] && (( SECONDS - warn_seconds > _eretry_warn )); then
            ewarn "Failed $(lval cmd timeout=_eretry_timeout exit_codes) retries=(${attempt}/${_eretry_retries})" 
            warn_seconds=${SECONDS}
        fi

        # Don't use "-ne" here since delay can have embedded units
        if [[ ${_eretry_delay} != "0" ]] ; then
            edebug "Sleeping $(lval _eretry_delay)" 
            sleep ${_eretry_delay}
        fi
    done

    [[ ${rc} -eq 0 ]] || ewarn "Failed $(lval cmd timeout=_eretry_timeout exit_codes) retries=(${attempt}/${_eretry_retries})" 

    # Emit stdout
    echo -n "${stdout}"

    # Return final return code
    return ${rc}
}

# setvars takes a template file with optional variables inside the file which
# are surrounded on both sides by two underscores.  It will replace the variable
# (and surrounding underscores) with a value you specify in the environment.
#
# For example, if the input file looks like this:
#   Hi __NAME__, my name is __OTHERNAME__.
# And you call setvars like this
#   NAME=Bill OTHERNAME=Ted setvars intputfile
# The inputfile will be modified IN PLACE to contain:
#   Hi Bill, my name is Ted.
#
# SETVARS_ALLOW_EMPTY=(0|1)
#   By default, empty values are NOT allowed. Meaning that if the provided key
#   evaluates to an empty string, it will NOT replace the __key__ in the file.
#   if you require that functionality, simply use SETVARS_ALLOW_EMPTY=1 and it
#   will happily allow you to replace __key__ with an empty string.
#
#   After all variables have been expanded in the provided file, a final check
#   is performed to see if all variables were set properly. It will return 0 if
#   all variables have been successfully set and 1 otherwise.
#
# SETVARS_WARN=(0|1)
#   To aid in debugging this will display a warning on any unset variables.
#
# OPTIONAL CALLBACK:
#   You may provided an optional callback as the second parameter to this function.
#   The callback will be called with the key and the value it obtained from the
#   environment (if any). The callback is then free to make whatever modifications
#   or filtering it desires and then echo the new value to stdout. This value
#   will then be used by setvars as the replacement value.
setvars()
{
    $(declare_args filename ?callback)
    edebug "Setting variables $(lval filename callback)"
    [[ -f ${filename} ]] || die "$(lval filename) does not exist"

    # If this file is a binary file skip it
    file ${filename} | grep -q ELF && continue || true

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

#-----------------------------------------------------------------------------
# LOCKFILES
#-----------------------------------------------------------------------------

declare -A __ELOCK_FDMAP

# elock is a wrapper around flock(1) to create a file-system level lockfile
# associated with a given filename. This is an advisory lock only and requires
# all callers to use elock/eunlock in order to protect the file. This method
# is easier to use than calling flock directly since it will automatically
# open a file descriptor to associate with the lockfile and store that off in
# an associative array for later use.
#
# These locks are exclusive. In the future we may support a -s option to pass
# into flock to make them shared but at present we don't need that behavior.
#
# These locks are NOT recursive. Which means if you already own the lock and
# you try to acquire the lock again it will return an error immediately to
# avoid hanging.
#
# The file descriptor associated with the lockfile is what keeps the lock
# alive. This means you need to either explicitly call eunlock to unlock the
# file and close the file descriptor OR simply put it in a subshell and it
# will automatically be closed and freed up when the subshell exits.
#
# Lockfiles are inherited by subshells. Specifically, a subshell will see the
# file locked and has the ability to unlock that file. This may seem odd since
# subshells normally cannot modify parent's state. But in this case it is
# in-kernel state being modified for the process which the parent and subshell
# share. The one catch here is that our internal state variable __ELOCK_FDMAP
# will become out of sync when this happens because a call to unlock inside
# a subshell will unlock it but cannot remove from our parent's FDMAP. All of
# these functions deal with this possibility properly by not considering the
# FDMAP authoritative. Instead, rely on flock for error handling where possible
# and even if we have a value in our map check if it's locked or not before
# failing any operations.
#
# To match flock behavior, if the file doesn't exist it is created.
#
elock()
{
    $(declare_args fname)
    
    # Create file if it doesn't exist
    [[ -e ${fname} ]] || touch ${fname} 
 
    # Check if we already have a file descriptor for this lockfile. If we do
    # don't fail immediately but check if that file is actually locked. If so
    # return an error to avoid causing deadlock. If it's not locked, purge the
    # stale entry with a warning.
    local fd=$(elock_get_fd "${fname}" || true)
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
        __ELOCK_FDMAP[$fname]=${fd}
        return 0
    else
        edebug "Failed to lock $(lval fname fd)"
        exec ${fd}<&-
        return 1
    fi
}

# eunlock is the logical analogue to elock. It's still essentially a wrapper 
# around "flock -u" to unlock a previously locked file. This will ensure the
# lock file is in our associative array and if not return an error. Then it
# will simply call into flock to unlock the file. If successful, it will 
# close remove the file descriptor from our file descriptor associative array.
eunlock()
{
    $(declare_args fname)
 
    local fd=$(elock_get_fd "${fname}" || true)
    if [[ -z ${fd} ]]; then
        eerror "$(lval fname) not locked"
        return 1
    fi
    
    edebug "Unlocking $(lval fname fd)"
    flock --unlock ${fd}
    eval "exec ${fd}>&-"
    unset __ELOCK_FDMAP[$fname]
}

# Get the file descriptor (if any) that our process has associated with a given
# on-disk lockfile. This is largely for convenience inside elock and eunlock
# to avoid some code duplication but could also be used externally if needed.
#
elock_get_fd()
{
    $(declare_args fname)
    local fd="${__ELOCK_FDMAP[$fname]:-}"
    if [[ -z "${fd}" ]]; then
        return 1
    else
        echo -n "${fd}"
        return 0
    fi
}


# Check if a file is locked via elock. This simply looks for the file inside
# our associative array because flock doesn't provide a native way to check
# if we have a file locked or not.
elock_locked()
{
    $(declare_args fname)

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

# Check if a file is not locked via elock. This simply loosk for the file inside
# our associative array because flock doesn't provide a native way to check
# if we have a file locked or not.
elock_unlocked()
{
    ! elock_locked $@
}

#-----------------------------------------------------------------------------
# ARRAYS
#-----------------------------------------------------------------------------

# array_init will split a string on any characters you specify, placing the
# results in an array for you.
#
#  $1: name of array to assign to (i.e. "array")
#  $2: string to be split
#  $3: (optional) character(s) to be used as delimiters.
array_init()
{
    $(declare_args __array ?__string ?__delim)

    # If nothing was provided to split on just return immediately
    [[ -z ${__string} ]] && { eval "${__array}=()"; return 0; } || true

    # Default bash IFS is space, tab, newline, so this will default to that
    : ${__delim:=$' \t\n'}

    IFS="${__delim}" eval "${__array}=(\${__string})"
}

# This function works like array_init, but always specifies that the delimiter
# be a newline.
array_init_nl()
{
    [[ $# -eq 2 ]] || die "array_init_nl requires exactly two parameters"
    array_init "$1" "$2" $'\n'
}

# Initialize an array from a Json array. This will essentially just strip
# of the brackets from around the Json array and then remove the internal
# quotes on each value since they are unecessary in bash.
array_init_json()
{
    [[ $# -ne 2 ]] && die "array_init_json requires exactly two parameters"
    array_init "$1" "$(echo "${2}" | sed -e 's|^\[\s*||' -e 's|\s*\]$||' -e 's|",\s*"|","|g' -e 's|"||g')" ","
}

# Print the size of any array.  Yes, you can also do this with ${#array[@]}.
# But this functions makes for symmertry with pack (i.e. pack_size).
array_size()
{
    $(declare_args __array)

    # Treat unset variables as being an empty array, because when you tell
    # bash to create an empty array it doesn't really allow you to
    # distinguish that from an unset variable.  (i.e. it doesn't show you
    # the variable until you put something in it)
    local value=$(eval "echo \${${__array}[*]:-}")
    if [[ -z "${value}" ]]; then
        echo 0
    else
        eval "echo \${#${__array}[@]}"
    fi

    return 0
}

# Return true (0) if an array is empty and false (1) otherwise
array_empty()
{
    $(declare_args __array)
    [[ $(array_size ${__array}) -eq 0 ]]
}

# Returns true (0) if an array is not empty and false (1) otherwise
array_not_empty()
{
    $(declare_args __array)
    [[ $(array_size ${__array}) -ne 0 ]]
}

# array_add will split a given input string on requested delimiters and add them
# to the given array (which may or may not already exist).
#
# $1: name of the array to add the new elements to
# $2: string to be split
# $3: (optional) character(s) to be used as delimiters.
array_add()
{
    $(declare_args __array ?__string ?__delim)

    # If nothing was provided to split on just return immediately
    [[ -z ${__string} ]] && return 0

    # Default bash IFS is space, tab, newline, so this will default to that
    : ${__delim:=$' \t\n'}

    # Parse the input given the delimiter and append to the array.
    IFS="${__delim}" eval "${__array}+=(\${__string})"
}

# Identical to array_add only hard codes the delimter to be a newline.
array_add_nl()
{
    [[ $# -ne 2 ]] && die "array_add_nl requires exactly two parameters"
    array_add "$1" "$2" $'\n'
}

# array_remove will remove the given value(s) from an array, if present.
#
# OPTIONS:
# -a=(0|1) Remove all instances (defaults to only removing the first instance)
array_remove()
{
    $(declare_args __array)

    # Return immediately if if array is not set or no values were given to be
    # removed. The reason we don't error out on an unset array is because
    # bash doesn't save arrays with no members.  For instance A=() unsets array A...
    [[ -v ${__array} && $# -gt 0 ]] || return 0
    
    # Remove all instances or only the first?
    local remove_all=$(opt_get a 0)

    local value
    for value in "${@}"; do

        local idx
        for idx in $(array_indexes ${__array}); do
            eval "local entry=\${${__array}[$idx]}"
            [[ "${entry}" == "${value}" ]] || continue

            unset ${__array}[$idx]

            [[ ${remove_all} -eq 1 ]] || return 0
        done
    done
}

# Bash arrays may have non-contiguous indexes.  For instance, you can unset an
# ARRAY[index] to remove an item from the array and bash does not shuffle the
# indexes.
#
# If you need to iterate over the indexes of an array (rather than simply
# iterating over the items), you can call array_indexes on the array and it
# will echo all of the indexes that exist in the array.
#
array_indexes()
{
    $(declare_args __array_indexes_array)
    eval "echo \${!${__array_indexes_array}[@]}"
}

# array_contains will check if an array contains a given value or not. This
# will return success (0) if it contains the requested element and failure (1)
# if it does not.
#
# $1: name of the array to search
# $2: value to check for existance in the array
array_contains()
{
    $(declare_args __array __value)

    local idx=0
    for idx in $(array_indexes ${__array}); do
        eval "local entry=\${${__array}[$idx]}"
        [[ "${entry}" == "${__value}" ]] && return 0
    done

    return 1
}

# array_join will join an array into one flat string with the provided delimeter
# between each element in the resulting string.
#
# $1: name of the array to join
# $2: (optional) delimiter
array_join()
{
    $(declare_args __array ?__delim)

    # If the array is empty return empty string
    array_empty ${__array} && { echo -n ""; return 0; } || true

    # Default bash IFS is space, tab, newline, so this will default to that
    : ${__delim:=$' \t\n'}

    # Otherwise use IFS to join the array. This must be in a subshell so that
    # the change to IFS doesn't persist after this function call.
    ( IFS="${__delim}"; eval "echo -n \"\${${__array}[*]}\"" )
}

# Identical to array_join only it hardcodes the dilimter to a newline.
array_join_nl()
{
    [[ $# -ne 1 ]] && die "array_join_nl requires exactly one parameter"
    array_join "$1" $'\n'
}

# array_quote creates a single flat string representation of an array with
# an extra level of proper bash quoting around everything so it's suitable
# to be eval'd.
array_quote()
{
    $(declare_args __array)

    local __output=()
    local __entry=""

    local idx=0
    for (( idx=0; idx < $(array_size ${__array}); idx++ )); do
        eval "local entry=\${${__array}[$idx]}"
        __output+=( "$(printf %q "${entry}")" )
    done

    echo -n "${__output[@]}"
}

# Sort an array in-place.
#
# OPTIONS:
# -u Make resulting array unique.
# -V Perform a natural (version) sort.
array_sort()
{
    $(declare_args __array)
    local flags=()

    opt_true "u" && flags+=("--unique")
    opt_true "V" && flags+=("--version-sort")

    local idx=0
    readarray -t ${__array} < <(
        for (( idx=0; idx < $(array_size ${__array}); idx++ )); do
            eval "echo \${${__array}[$idx]}"
        done | sort ${flags[@]:-}
    )
}

#-----------------------------------------------------------------------------
# PACK
#-----------------------------------------------------------------------------
#
# Consider a "pack" to be a "new" data type for bash.  It stores a set of
# key/value pairs in an arbitrary format inside a normal bash (string)
# variable.  This is much like an associative array, but has a few differences
#
#   1) You can store packs INSIDE associative arrays (example in unit tests)
#   2) It treats keys case insensitively (which may not be a benefit in your
#      case, but there it is)
#   3) The "keys" in a pack may not contain an equal sign, nor may they contain
#      whitespace"
#   4) Packed values cannot contain newlines.
#
#

#
# For a (new or existing) variable whose contents are formatted as a pack, set
# one or more keys to values.  For example, the following will create a new
# variable packvar that will contain three keys (alpha, beta, n) with
# associated values (a, b, 7)
#
#  pack_set packvar alpha=a beta=b n=7
#
pack_set()
{
    local _pack_set_pack=$1 ; shift

    for _pack_set_arg in "${@}" ; do
        local _pack_set_key="${_pack_set_arg%%=*}"
        local _pack_set_val="${_pack_set_arg#*=}"

        pack_set_internal ${_pack_set_pack} "${_pack_set_key}" "${_pack_set_val}"
    done
}

#
# Much like pack_set, and takes arguments of the same form.  The difference is
# that pack_update will create no new keys -- it will only update keys that
# already exist.
#
pack_update()
{
    local _pack_update_pack=$1 ; shift

    for _pack_update_arg in "${@}" ; do
        local _pack_update_key="${_pack_update_arg%%=*}"
        local _pack_update_val="${_pack_update_arg#*=}"

        pack_keys ${_pack_update_pack} | grep -aPq "\b${_pack_update_key}\b" \
            && pack_set_internal ${_pack_update_pack} "${_pack_update_key}" "${_pack_update_val}" \
            || true
    done
}

pack_set_internal()
{
    local _pack_pack_set_internal=$1
    local _tag=$2
    local _val="$3"

    argcheck _tag
    [[ ${_tag} =~ = ]] && die "bashutils internal error: tag ${_tag} cannot contain equal sign"
    [[ $(echo "${_val}" | wc -l) -gt 1 ]] && die "packed values cannot hold newlines"

    local _removeOld="$(echo -n "${!1:-}" | _unpack | grep -av '^'${_tag}'=' || true)"
    local _addNew="$(echo "${_removeOld}" ; echo -n "${_tag}=${_val}")"
    local _packed=$(echo "${_addNew}" | _pack)

    printf -v ${1} "${_packed}"
}

#
# Get the last value assigned to a particular key in this pack.
#
pack_get()
{
    local _pack_pack_get=$1
    local _tag=$2

    argcheck _pack_pack_get _tag

    local _unpacked="$(echo -n "${!_pack_pack_get:-}" | _unpack)"
    local _found="$(echo -n "${_unpacked}" | grep -a "^${_tag}=" || true)"
    echo "${_found#*=}"
}

pack_contains()
{
    [[ -n $(pack_get $@) ]]
}

#
# Copy a packed value from one variable to another.  Either variable may be
# part of an associative array, if you're so inclined.
#
# Examples:
#   pack_copy A B
#   pack_copy B A["alpha"]
#   pack_copy A["alpha"] B[1]
#
pack_copy()
{
    argcheck 1 2
    eval "${2}=\"\${!1}\""
}

#
# Call provided callback function on each entry in the pack. The callback function
# should take two arguments, and it will be called once for each item in the
# pack and passed the key as the first value and its value as the second value.
#
pack_iterate()
{
    local _func=$1
    local _pack_pack_iterate=$2
    argcheck _func _pack_pack_iterate

    local _unpacked="$(echo -n "${!_pack_pack_iterate}" | _unpack)"
    local _lines ; array_init_nl _lines "${_unpacked}"

    for _line in "${_lines[@]}" ; do

        local _key="${_line%%=*}"
        local _val="${_line#*=}"

        ${_func} "${_key}" "${_val}"

    done
}

# Spews bash commands that, when executed will declare a series of variables
# in the caller's environment for each and every item in the pack. This uses
# the "eval command invocation string" which the caller then executes in order
# to manifest the commands. For instance, if your pack contains keys a and b
# with respective values 1 and 2, you can create locals a=1 and b=2 by running:
#
#   $(pack_import pack)
#
# If you don't want the pack's entire contents, but only a limited subset, you
# may specify them.  For instance, in the same example scenario, the following
# will create a local a=1, but not a local for b.
#
#  $(pack_import pack a)
#
# OPTIONS:
# -l: Emit local variables with 'local' scope qualifier (default)
# -g: Emit global variables with no scope qualifier
# -e: Emit exported variables with 'export' keyword
pack_import()
{
    $(declare_args _pack_import_pack)
    local _pack_import_keys=("${@}")
    [[ $(array_size _pack_import_keys) -eq 0 ]] && _pack_import_keys=($(pack_keys ${_pack_import_pack}))

    # Determine requested scope for the variables
    local _pack_import_scope="local"
    opt_true "l" && _pack_import_scope="local"
    opt_true "g" && _pack_import_scope=""
    opt_true "e" && _pack_import_scope="export"

    local _pack_import_cmd=""
    for _pack_import_key in "${_pack_import_keys[@]}" ; do
        local _pack_import_val=$(pack_get ${_pack_import_pack} ${_pack_import_key})
        _pack_import_cmd+="$_pack_import_scope $_pack_import_key=\"${_pack_import_val}\"; "
    done

    echo "eval "${_pack_import_cmd}""
}

#
# Assigns values into a pack by extracting them from the caller environment.
# For instance, if you have locals a=1 and b=2 and run the following:
#
#    pack_export pack a b
#
# You will be left with the same pack as if you instead said:
#
#   pack_set pack a=${a} b=${b}
#
pack_export()
{
    local _pack_export_pack=$1 ; shift

    local _pack_export_args=()
    for _pack_export_arg in "${@}" ; do
        _pack_export_args+=("${_pack_export_arg}=${!_pack_export_arg:-}")
    done

    pack_set "${_pack_export_pack}" "${_pack_export_args[@]}"
}

pack_size()
{
    [[ -z ${1} ]] && die "pack_size requires a pack to be specified as \$1"
    echo -n "${!1}" | _unpack | wc -l
}

#
# Echo a whitespace-separated list of the keys in the specified pack to stdout.
#
pack_keys()
{
    [[ -z ${1} ]] && die "pack_keys requires a pack to be specified as \$1"
    echo "${!1:-}" | _unpack | sed 's/=.*$//'
}

# Note: To support working with print_value, pack_print does NOT print a
# newline at the end of its output
pack_print()
{
    local _pack_pack_print=$1
    argcheck _pack_pack_print

    echo -n '('
    pack_iterate _pack_print_item ${_pack_pack_print}
    echo -n ')'
}

_pack_print_item()
{
    echo -n "[$1]=\"$2\" "
}

_unpack()
{
    # NOTE: BSD base64 is really chatty and this is the reason we discard its
    # error output
    base64 -d 2>/dev/null | tr '\0' '\n'
}

_pack()
{
    # NOTE: BSD base64 is really chatty and this is the reason we discard its
    # error output
    grep -av '^$' | tr '\n' '\0' | base64 2>/dev/null
}

#-----------------------------------------------------------------------------
# STRING MANIPULATION
#-----------------------------------------------------------------------------

# Convert a given input string into "upper snake case". This is generally most
# useful when converting a "CamelCase" string although it will work just as
# well on non-camel case input. Essentially it looks for all upper case letters
# and puts an underscore before it, then uppercase the entire input string.
#
# For example:
#
# sliceDriveSize => SLICE_DRIVE_SIZE
# slicedrivesize => SLICEDRIVESIZE
#
# It has some special handling for some common corner cases where the normal
# camel case idiom isn't well followed. The best example for this is around
# units (e.g. MB, GB). Consider "sliceDriveSizeGB" where SLICE_DRIVE_SIZE_GB
# is preferable to SLICE_DRIVE_SIZE_G_B.
#
# The current list of translation corner cases this handles:
# KB, MB, GB, TB
to_upper_snake_case()
{
    $(declare_args input)

    echo "${input}"         \
        | sed -e 's|KB|Kb|' \
              -e 's|MB|Mb|' \
              -e 's|GB|Gb|' \
              -e 's|TB|Tb|' \
        | perl -ne 'print uc(join("_", split(/(?=[A-Z])/)))'
}

#-----------------------------------------------------------------------------
# JSON
#-----------------------------------------------------------------------------

# Convert each argument, in turn, to json in an appropriate way and drop them
# all in a single json blob.
#
to_json()
{
    echo -n "{"
    local _notfirst="" _arg
    for _arg in "${@}" ; do
        [[ -n ${_notfirst} ]] && echo -n ","

        local _arg_noqual=$(discard_qualifiers ${_arg})
        echo -n "$(json_escape ${_arg_noqual}):"
        if is_pack ${_arg} ; then
            pack_to_json ${_arg}

        elif is_array ${_arg} ; then
            array_to_json ${_arg}

        elif is_associative_array ${_arg} ; then
            associative_array_to_json ${_arg}

        else
            json_escape "$(eval echo -n \${${_arg}})"
        fi

        _notfirst=true
    done
    echo -n "}"
}

# Convert an array specified by name (i.e ARRAY not ${ARRAY} or ${ARRAY[@]})
# into a json array containing the same data.
#
array_to_json()
{
    # This will store a copy of the specified array's contents into __array
    $(declare_args __array)
    eval "local __array=(\"\${${__array}[@]}\")"

    echo -n "["
    local i notfirst=""
    for i in "${__array[@]}" ; do
        [[ -n ${notfirst} ]] && echo -n ","
        echo -n $(json_escape "$i")
        notfirst=true
    done

    echo -n "]"
}

associative_array_to_json()
{
    echo -n "{"
    local _notfirst="" _key
    edebug "1=$1"
    for _key in $(eval echo -n "\${!$1[@]}") ; do
        edebug $(lval _key)
        [[ -n ${_notfirst} ]] && echo -n ","

        echo -n $(json_escape ${_key})
        echo -n ':'
        echo -n $(json_escape "$(eval echo -n \${$1[$_key]})")

        _notfirst=true
    done
    echo -n "}"
}

# Convert a single pack into a json blob where the keys are the same as the
# keys from the pack (and so are the values)
#
pack_to_json()
{
    [[ -z ${1} ]] && die "pack_to_json requires a pack to be specified as \$1"

    local _pack _key _notfirst=""
    _pack=$(discard_qualifiers $1)
    echo -n "{"
    for _key in $(pack_keys ${_pack}) ; do
        [[ -n ${_notfirst} ]] && echo -n ","
        echo -n '"'${_key}'":'"$(json_escape "$(pack_get ${_pack} ${_key})")"
        _notfirst=true
    done
    echo -n "}"
}

# Escape an arbitrary string (specified as $1) so that it is quoted and safe to
# put inside json.
#
json_escape()
{
    echo -n "$1" \
        | python -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
}

# Import all of the key:value pairs from a non-nested Json object directly into
# the caller's environment as proper bash variables. Similar to a lot of other
# methods inside bashutils, this uses the "eval command invocation string" idom.
# So, the proper calling convention for this is:
#
# $(json_import)
#
# By default this function operates on stdin. Alternatively you can change it to
# operate on a file via -f. To use via STDIN use one of these idioms:
#
# $(json_import <<< ${json})
# $(curl ... | $(json_import)
#
# OPTIONS:
# -l: Emit local variables with 'local' scope qualifier (default)
# -g: Emit global variables with no scope qualifier
# -e: Emit exported variables with 'export' keyword
# -f: Parse the contents of provided file instead of stdin (e.g. -f=MyFile)
# -u: Convert all keys into upper snake case.
# -p: Prefix all keys with provided required prefix (e.g. -p=FOO)
# -q: Use JQ style query expression on given JSON before parsing.
# -x: Whitespace sparated list of keys to exclude while importing. If using multiple
#     keys use quotes around them: -x "foo bar"
json_import()
{
    $(declare_args)

    # Determine requested scope for the variables
    local _json_import_qualifier="local"
    opt_true "l" && _json_import_qualifier="local"
    opt_true "g" && _json_import_qualifier=""
    opt_true "e" && _json_import_qualifier="export"

    # Lookup optional prefix to use
    local _json_import_prefix="$(opt_get p)"

    # Lookup optional jq query to use
    local _json_import_query="$(opt_get q)"
    : ${_json_import_query:=.}

    # Lookup optional filename to use. If no filename was given then we're operating on STDIN.
    # In either case read into a local variable so we can parse it repeatedly in this function.
    local _json_import_filename="$(opt_get f)"
    : ${_json_import_filename:=-}
    local _json_import_data=$(cat ${_json_import_filename} | jq -r "${_json_import_query}")

    # Check if explicit keys are requested. If not, slurp all keys in from provided data.
    local _json_import_keys=("${@:-}")
    [[ ${#_json_import_keys} -eq 0 ]] && array_init_json _json_import_keys "$(jq -c -r keys <<< ${_json_import_data})"

    # Get list of optional keys to exclude
    local _json_import_keys_excluded
    array_init _json_import_keys_excluded "$(opt_get x)"

    # Debugging
    edebug $(lval _json_import_prefix _json_import_query _json_import_filename _json_import_data _json_import_keys _json_import_keys_excluded)

    local cmd key val
    for key in "${_json_import_keys[@]}"; do
        array_contains _json_import_keys_excluded ${key} && continue

        local val=$(jq -r .${key} <<< ${_json_import_data})
        edebug $(lval key val)
        opt_true "u" && key=$(to_upper_snake_case "${key}")

        cmd+="${_json_import_qualifier} ${_json_import_prefix}${key}=\"${val}\";"
    done

    echo -n "eval ${cmd}"
}

#-----------------------------------------------------------------------------
# Type detection
#-----------------------------------------------------------------------------

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
    [[ "${1:0:1}" == '+' ]]
}

discard_qualifiers()
{
    echo "${1##+}"
}

#-----------------------------------------------------------------------------
# ASSERTS
#-----------------------------------------------------------------------------

# Executes a command (simply type the command after assert as if you were
# running it without assert) and calls die if that command returns a bad exit
# code.
# 
# For example:
#    assert [[ 0 -eq 1 ]]
#
# There's a subtlety here that I don't think can easily be fixed given bash's
# semantics.  All of the arguments get evaluated prior to assert ever seeing
# them.  So it doesn't know what variables you passed in to an expression, just
# what the expression was.  This is pretty handy in cases like this one:
#
#   a=1
#   b=2
#   assert [[ ${a} -eq ${b} ]]
#
# because assert will tell you that the command that it executed was 
#
#     [[ 1 -eq 2 ]]
#
# There it seems ideal.  But if you have an empty variable, things get a bit
# annoying.  For instance, this command will blow up because inside assert bash
# will try to evaluate [[ -z ]] without any arguments to -z.  (Note -- it still
# blows up, just not in quite the way you'd expect)
#
#    empty=""
#    assert [[ -z ${empty} ]]
#
# To make this particular case easier to deal with, we also have assert_empty
# which you could use like this:
#
#    assert_empty empty
#
assert()
{
    local cmd=( "${@}" )
    
    $(tryrc -r=__assert_rc eval "${cmd[@]}")
    [[ ${__assert_rc} -eq 0 ]] || die "assert failed (${__assert_rc}) :: ${cmd[@]}"
}

assert_true()
{
    assert "${@}"
}

assert_false()
{
    local cmd=( "${@}" )

    $(tryrc -r=__assert_false_rc eval "${cmd[@]}")
    [[ ${__assert_false_rc} -ne 0 ]] || die "assert_false failed :: ! $(lval cmd)"
}

assert_op()
{
    compare "${@}" || "assert_op failed :: ${@}"
}

assert_eq()
{
    $(declare_args ?lh ?rh ?msg)
    [[ "${lh}" == "${rh}" ]] || die "assert_eq failed [${msg:-}] :: $(lval lh rh)"
}

assert_ne()
{
    $(declare_args ?lh ?rh ?msg)
    [[ ! "${lh}" == "${rh}" ]] || die "assert_ne failed [${msg:-}] :: $(lval lh rh)"
}

assert_match()
{
    $(declare_args ?lh ?rh ?msg)
    [[ "${lh}" =~ "${rh}" ]] || die "assert_match failed [${msg:-}] :: $(lval lh rh)"
}

assert_not_match()
{
    $(declare_args ?lh ?rh ?msg)
    [[ ! "${lh}" =~ "${rh}" ]] || die "assert_not_match failed [${msg:-}] :: $(lval lh rh)"
}

assert_zero()
{
    [[ ${1:-0} -eq 0 ]] || die "assert_zero received $1 instead of zero."
}

assert_not_zero()
{
    [[ ${1:-1} -ne 0 ]] || die "assert_not_zero received ${1}."
}

assert_empty()
{
    local _arg
    for _arg in $@; do
        [[ "${!_arg:-""}" == "" ]] || die "assert_empty received $(lval _arg)"
    done
}

assert_not_empty()
{
    local _arg
    for _arg in $@; do
        [[ "${!_arg}" != "" ]] || die "assert_not_empty received $(lval _arg)"
    done
}

assert_exists()
{
    local name
    for name in "${@}"; do
        [[ -e "${name}" ]] || die "'${name}' does not exist"
    done
}

assert_not_exists()
{
    local name
    for name in "${@}"; do
        [[ ! -e "${name}" ]] || die "'${name}' exists"
    done
}

# Default traps
die_on_abort
die_on_error
enable_trace

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------

return 0
