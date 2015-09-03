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

    echo "$(ecolor dimyellow)[$(basename ${BASH_SOURCE[1]:-} 2>/dev/null || true):${BASH_LINENO[0]:-}:${FUNCNAME[1]:-}]$(ecolor none) ${BASH_COMMAND}" >&2
}

edebug_enabled()
{
    [[ ${EDEBUG:=} == "1" ]] && return 0
    [[ ${EDEBUG} == "" || ${EDEBUG} == "0" ]] && return 1

    $(declare_args ?_edebug_enabled_caller)

    if [[ -z ${_edebug_enabled_caller} ]]; then
        _edebug_enabled_caller=( $(caller 0) )
        [[ ${_edebug_enabled_caller[1]} == "edebug" || ${_edebug_enabled_caller[1]} == "edebug_out" ]] \
            && _edebug_enabled_caller=( $(caller 1) )
    fi

    local _edebug_enabled_tmp
    for _edebug_enabled_tmp in ${EDEBUG} ; do
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
    edebug_enabled || return 0
    echo -e "$(emsg 'dimblue' '   -' 'DEBUG' "$@")" >&2
}

edebug_out()
{
    edebug_enabled && echo -n "/dev/stderr" || echo -n "/dev/null"
}

#-----------------------------------------------------------------------------
# TRY / CATCH
#-----------------------------------------------------------------------------

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
        trap '__EFUNCS_DIE_ON_ERROR_RC=\$? ; eerror_stacktrace \"exception caught\" &>\$(edebug_out) ; exit \$__EFUNCS_DIE_ON_ERROR_RC' ERR
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
alias die_on_error='trap "die [UnhandledError]" ERR'

# Disable calling die on ERROR.
alias nodie_on_error="trap - ERR"

# Check if die_on_error is enabled. Returns success (0) if enabled and failure
# (1) otherwise.
die_on_error_enabled()
{
    trap -p | grep ERR &>$(edebug_out)
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
    local frame
    frame=$(opt_get f 0)

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
    local frame
    frame=$(opt_get f 1)
    array_init_nl ${array} "$(stacktrace -f=${frame})"
}

die()
{
    [[ ${__EFUNCS_DIE_IN_PROGRESS:=0} -eq 1 ]] && exit 1 || true
    __EFUNCS_DIE_IN_PROGRESS=1
    eprogress_killall

    # Clear ERR and DEBUG traps to avoid tracing die code.
    trap - ERR
    trap - DEBUG

    # Call eerror_stacktrace but skip top three frames to skip over
    # the frames containing stacktrace_array, eerror_stacktrace and
    # die itself.
    eerror_stacktrace -f=3 "${@}"

    # Now kill our entire process tree with SIGKILL.
    # NOTE: Use BASHPID so that we kill our current instance of bash.
    # This is different than $$ only if we're in a subshell.
    ekilltree -s=SIGKILL $$
    exit 1
}

# appends a command to a trap
#
# - 1st arg:  code to add
# - remaining args:  names of traps to modify
#
trap_add()
{
    trap_add_cmd=$1; shift || die "${FUNCNAME} usage error"
    for trap_add_name in "$@"; do
        trap -- "$(
            # helper fn to get existing trap command from output
            # of trap -p
            extract_trap_cmd() { printf '%s\n' "${3:-}"; }
            # print the new trap command
            printf '%s; ' "${trap_add_cmd}"
            # print existing trap command with newline
            eval "extract_trap_cmd $(trap -p "${trap_add_name}")"
        )" "${trap_add_name}" \
            || die "unable to add to trap ${trap_add_name}"
    done
}

# set the trace attribute for the above function.  this is
# required to modify DEBUG or RETURN traps because functions don't
# inherit them unless the trace attribute is set
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
die_signals=( SIGHUP    SIGINT   SIGQUIT   SIGILL   SIGABRT   SIGFPE   SIGKILL
              SIGSEGV   SIGPIPE  SIGALRM   SIGTERM  SIGUSR1   SIGUSR2  SIGBUS
              SIGIO     SIGPROF  SIGSYS    SIGTRAP  SIGVTALRM SIGXCPU  SIGXFSZ
            )

# Enable default traps for all die_signals to call die().
die_on_abort()
{
    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( "${die_signals[@]}" )
    trap 'die [killed]' ${signals[@]}
}

# Disable default traps for all die_signals.
nodie_on_abort()
{
    local signals=( "${@}" )
    [[ ${#signals[@]} -gt 0 ]] || signals=( "${die_signals[@]}" )
    trap - ${signals[@]}
}

# Default traps
die_on_abort
die_on_error
enable_trace

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

    local bold
    bold="$(tput bold)"
    local dimre="^dim"
    if [[ ${c} =~ ${dimre} ]]; then
        c=${c#dim}
        bold=""
    fi

    echo -en ${bold}$(tput setaf $(ecolor_code ${c}))
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
        local keys=( $(for key in ${!__details[@]}; do echo "${key}"; done | sort) )

        # Figure out the longest key
        local longest=0
        for key in ${keys[@]}; do
            local len=${#key}
            (( len > longest )) && longest=$len
        done

        # Iterate over the keys of the associative array and print out the values
        for key in ${keys[@]}; do
            local pad
            pad=$((longest-${#key}+1))
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
    local emsg_prefix
    emsg_prefix=$(echo ${EMSG_PREFIX:=} | egrep -o "(time|times|level|caller|all)" || true)

    $(declare_args color ?symbol level)
    [[ ${EFUNCS_TIME:=0} -eq 1 ]] && emsg_prefix+=time

    # Local args to hold the color and regexs for each field
    for field in time level caller msg; do
        eval "local ${field}_color=$(ecolor none)"
        eval "local ${field}_re='\ball|${field}\b'"
    done

    # Determine color values for each field used below.
    : ${EMSG_COLOR:="time level caller"}
    [[ ${EMSG_COLOR} =~ ${time_re}   ]] && time_color=$(ecolor ${color})
    [[ ${EMSG_COLOR} =~ ${level_re}  ]] && level_color=$(ecolor ${color})
    [[ ${EMSG_COLOR} =~ ${caller_re} ]] && caller_color=$(ecolor ${color})

    # Build up the prefix for the log message. Each of these may optionally be in color or not. This is
    # controlled vai EMSG_COLOR which is a list of fields to color. By default this is set to all fields.
    # The following fields are supported:
    # (1) time    : Timetamp
    # (2) level   : Log Level
    # (3) caller  : file:line:method
    local delim
    delim="$(ecolor none)|"
    local prefix=""

    if [[ ${level} =~ INFOS|WARNS && ${emsg_prefix} == "time" ]]; then
        :
    else
        local times_re="\ball|times\b"
        [[ ${level} =~ INFOS|WARNS && ${emsg_prefix} =~ ${times_re} || ${emsg_prefix} =~ ${time_re} ]] && prefix+="${time_color}$(etimestamp)"
        [[ ${emsg_prefix} =~ ${level_re}  ]] && prefix+="${delim}${level_color}$(printf "%s"  ${level%%S})"
        [[ ${emsg_prefix} =~ ${caller_re} ]] && prefix+="${delim}${caller_color}$(printf "%-10s" $(basename 2>/dev/null $(caller 1 | awk '{print $3, $1, $2}' | tr ' ' ':')))"
    fi

    # Strip of extra leading delimiter if present
    prefix="${prefix#${delim}}"

    # If it's still empty put in the default
    [[ -z ${prefix} ]] && prefix="${symbol}" || { prefix="$(ecolor ${color})[${prefix}$(ecolor ${color})]"; [[ ${level} =~ DEBUG|INFOS|WARNS ]] && prefix+=${symbol:2}; }

    # Color Policy
    [[ ${EMSG_COLOR} =~ ${msg_re} || ${level} =~ DEBUG|WARN|ERROR ]]   \
        && echo -en "$(ecolor ${color})${prefix} $@$(ecolor none)" >&2 \
        || echo -en "$(ecolor ${color})${prefix}$(ecolor none) $@" >&2
}

einfo()
{
    echo -e  "$(emsg 'green' '>>' 'INFO' "$@")" >&2
}

einfos()
{
    echo -e "$(emsg 'green' '   -' 'INFOS' "$@")" >&2
}

ewarn()
{
    echo -e "$(emsg 'yellow' '>>' 'WARN' "$@")" >&2
}

ewarns()
{
    echo -e "$(emsg 'yellow' '   -' 'WARNS' "$@")" >&2
}

eerror()
{
    echo -e "$(emsg 'red' '>>' 'ERROR' "$@")" >&2
}

# Print an error stacktrace to stderr.  This is like stacktrace only it pretty prints
# the entire stacktrace as a bright red error message with the funct and file:line
# number nicely formatted for easily display of fatal errors.
#
# Allows you to optionally pass in a starting frame to start the stacktrace at. 0 is
# the top of the stack and counts up. See also stacktrace and eerror_stacktrace.
#
# OPTIONS:
# -f=N Frame number to start at (defaults to 2 to skip the top frames with
#      eerror_stacktrace and stacktrace_array).
eerror_stacktrace()
{
    $(declare_args)
    local frame
    frame=$(opt_get f 2)

    echo "" >&2
    eerror "$@"

    local frames=()
    stacktrace_array -f=${frame} frames

    array_empty frames ||
    for f in "${frames[@]}"; do
        local line func file
        line=$(echo ${f} | awk '{print $1}')
        func=$(echo ${f} | awk '{print $2}')
        file=$(basename $(echo ${f} | awk '{print $3}'))

        [[ ${file} == "efuncs.sh" && ${func} == ${FUNCNAME} ]] && break

        printf "$(ecolor red)   :: %-20s | ${func}$(ecolor none)\n" "${file}:${line}" >&2
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
    local valid
    valid="$(echo ${opt},${secret} | tr ',' '\n' | sort --ignore-case --unique)"
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
    local output
    output=$(echo -en "$@" | tr -s "[:space:]" " ")
    echo -en "${output}"
}

eend()
{
    local rc=${1:-0} #sets rc to first arg if present otherwise defaults to 0

    if einteractive; then
        # Terminal magic that:
        #    1) Gets the number of columns on the screen, minus 6 because that's
        #       how many we're about to output
        #    2) Moves up a line
        #    3) Moves right the number of columns from #1
        local columns=${COLUMNS:-$(tput cols)}
        local startcol
        startcol=$(( columns - 6 ))
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
    trap "done=1" SIGINT SIGTERM

    local start
    start=$(date +"%s")
    while [[ ${done} -ne 1 ]]; do
        local now diff
        now=$(date +"%s")
        diff=$(( ${now} - ${start} ))

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

export __EPROGRESS_PIDS=""
eprogress()
{
    echo -en "$(emsg 'green' '>>' 'INFO' "$@")" >&2

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    [[ ${EPROGRESS:-1} -eq 0 ]] && return 0

    ## Prepend this new eprogress pid to the front of our list of eprogress PIDs
    do_eprogress &
    export __EPROGRESS_PIDS="$! ${__EPROGRESS_PIDS}"
}

# Kill the most recent eprogress in the event multiple ones are queued up.
eprogress_kill()
{
    local rc=${1:-0}
    local signal=${2:-TERM}

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    if [[ ${EPROGRESS:-1} -eq 0 ]] ; then
        einteractive && echo "" >&2
        eend ${rc}
        return 0
    fi

    # Get the most recent pid
    local pids=()
    array_init pids "${__EPROGRESS_PIDS}"
    if [[ $(array_size pids) -gt 0 ]]; then
        ekill -s=${signal} ${pids[0]}
        wait ${pids[0]} &>/dev/null || true

        export __EPROGRESS_PIDS="${pids[@]:1}"
        einteractive && echo "" >&2
        eend ${rc}
    fi

    return 0
}

# Kill all eprogress pids
eprogress_killall()
{
    while [[ -n ${__EPROGRESS_PIDS} ]]; do
        eprogress_kill 1
    done
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

# Kill all pids provided as arguments to this function using the specified signal.
# This function makes every effort to kill all the specified pids. If there are any
# errors this function will return non-zero (corresponding to the number of pids
# that could not be killed successfully).
#
# Options:
# -s=SIGNAL The signal to send to the pids (defaults to SIGTERM).
ekill()
{
    $(declare_args)

    # Determine what signal to send to the processes
    local signal
    signal=$(opt_get s SIGTERM)
    local errors=0

    # Iterate over all provided PIDs and kill each one. If any of the PIDS do not
    # exist just skip it instead of trying (and failing) to kill it since we're
    # already in the desired state if the process is killed already.
    for pid in ${@}; do

        # If process doesn't exist just return instead of trying (and failing) to kill it
        process_running ${pid} || continue

        # The process is still running. Now kill it. So long as the process does NOT
        # exist after sending it the specified signal this function will return
        # success.
        local cmd
        cmd="$(ps -p ${pid} -o comm= || true)"
        edebug "Killing $(lval pid signal cmd)"

        # The process is still running. Now kill it. So long as the process does NOT
        # exist after sending it the specified signal this function will return success.
        edebug "        Killing ${pid} with -${signal}"
        kill -${signal} ${pid} &>$(edebug_out) || (( errors+=1 ))
        edebug "        Number of errors encountered (ekill): ${errors}"
    done

    [[ ${errors} -eq 0 ]]
}

# Kill entire process tree for each provided pid by doing a depth first search to find
# all the descendents of each pid and kill all leaf nodes in the process tree first.
# Then it walks back up and kills the parent pids as it traverses back up the tree.
# This method makes every effort to kill all the requested pids. If there are any errors
# then the method will return non-zero at the end (which will correspond to the number
# of pids that could not be killed successfully).
#
# Options:
# -s=SIGNAL The signal to send to the pids (defaults to SIGTERM).
ekilltree()
{
    $(declare_args)

    # Determine what signal to send to the processes
    local signal
    signal=$(opt_get s SIGTERM)
    local errors=0

    local pid
    for pid in ${@}; do
        edebug "    Killing process tree of ${pid} [$(ps -p ${pid} -o comm= || true)] with ${signal}"
        for child in $(ps -o pid --no-headers --ppid ${pid} || true); do
            edebug "    Found child ${child}, of ${pid}"
            ekilltree -s=${signal} ${child} || (( errors+=1 ))
        done

        edebug "    Attempting to kill ${pid}"
        ekill -s=${signal} ${pid} || (( errors+=1 ))
        edebug "    Number of errors encountered (ekilltree): ${errors}"
    done

    [[ ${errors} -eq 0 ]]
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

    local decl
    decl=$(declare -p ${__input} 2>/dev/null || true)
    local val
    val=$(echo "${decl}")
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
    local ip
    ip=$(/sbin/ifconfig ${iface} | grep -o 'inet addr:\S*' | cut -d: -f2 || true)
    echo -n "${ip//[[:space:]]}"
}

getnetmask()
{
    $(declare_args iface)
    local netmask
    netmask=$(/sbin/ifconfig ${iface} | grep -o 'Mask:\S*' | cut -d: -f2 || true)
    echo -n "${netmask//[[:space:]]}"
}

getbroadcast()
{
    $(declare_args iface)
    local bcast
    bcast=$(/sbin/ifconfig ${iface} | grep -o 'Bcast::\S*' | cut -d: -f2 || true)
    echo -n "${bcast//[[:space:]]}"
}

# Gets the default gateway that is currently in use
getgateway()
{
    local gw
    gw=$(route -n | grep 'UG[ \t]' | awk '{print $2}' || true)
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

#-----------------------------------------------------------------------------
# FILESYSTEM HELPERS
#-----------------------------------------------------------------------------

# esource allows you to source multiple files at a time with proper error
# checking after each file sourcing. If any of the files cannot be sourced
# either because the file cannot be found or it contains invalid bash syntax,
# esource will call die. This still internally calls 'source' so all the
# rules still apply with regard to how the files are found via PATH, etc.
#
# NOTE: As it turns out, bash's 'source' function can behave very differently
# if called within a function versus called normally in global scope. The most
# important distinction here is if the sourced file contains any "declare"
# statements if these are invoked in function scope they are **LOCAL** variables
# rather than global variables as the caller would expect with "source".
#
# To workaround this problem, we have to make sure this is called in the caller's
# native environment rather than invoked immediately within this function call.
# But to avoid forcing the caller to use nasty eval syntax we can actually be a
# bit more clever and embed the call to eval into the command esource eventually
# invokes. This is called an "eval command invocation string" and is invoked in
# the caller's envionment as in $(esource ...).
esource()
{
    [[ $# -eq 0 ]] && return 0

    local cmd=""
    for file in "${@}" ; do
        cmd+='source "'${file}'" &>$(edebug_out) || die "Failed to source '${file}'"; '
    done

    echo -n "eval "${cmd}""
}

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
# -m=NUM Maximum number of logs to keep (defaults to 5)
elogrotate()
{
    $(declare_args name)
    local max
    max=$(opt_get m 5)

    local log_idx next
    for (( log_idx=${max}; log_idx > 0; log_idx-- )); do
        next=$(( log_idx+1 ))
        mv -f ${name}.${log_idx} ${name}.${next} &>$(edebug_out) || true
    done

    # Move non-versioned one over and create empty new file
    mv -f ${name} ${name}.1 &>$(edebug_out) || true
    mkdir -p $(dirname ${name})
    touch ${name}

    # Remove any log files greater than our retention count
    ( find $(dirname ${name}) -name "${name}*" 2>$(edebug_out) || true) | sort --version-sort | awk "NR>${max}" | xargs rm -f
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
    local match
    match=$(echo "$@" | egrep '(-I|--use-compress-program)' || true)
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

    local dname fname
    dname=$(dirname  "${path}")
    fname=$(basename "${path}")

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

    local fname dname
    fname=$(basename "${path}")
    dname=$(dirname  "${path}")

    pushd "${dname}"
    md5sum -c "${fname}.md5" >$(edebug_out)
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
echecksum()
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
    keyring=$(mktemp /tmp/echecksum-keyring-XXXX)
    keyring_command="--no-default-keyring --secret-keyring ${keyring}"
    trap_add "rm -f ${keyring}" ${die_signals[@]} ERR EXIT
    gpg --quiet ${keyring_command} --import ${privatekey}

    # Get optional keyphrase
    local keyphrase="" keyphrase_command=""
    keyphrase=$(opt_get k)
    [[ -z ${keyphrase} ]] || keyphrase_command="--batch --passphrase ${keyphrase}"

    # Output PGPSignature encoded in base64
    echo "PGPKey=$(basename ${privatekey})"
    echo "PGPSignature=$(gpg --quiet --no-tty --yes ${keyring_command} --sign --detach-sign --armor ${keyphrase_command} --output - ${path} | base64 --wrap 0)"
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
echecksum_check()
{
    $(declare_args path)
    local meta="${path}.meta"
    [[ -e ${path} ]] || die "${path} does not exist"
    [[ -e ${meta} ]] || die "${meta} does not exist"

    # If we're in quiet mode send all STDOUT and STDERR to edebug
    local redirect=""
    opt_true "q" && redirect="$(edebug_out)" || redirect="/dev/stderr"

    {
        local metapack="" validated=() expect="" actual="" ctype="" publickey="" keyring="" pgpsignature=""
        
        einfo "Verifying integrity of $(lval path meta)"
        pack_set metapack $(cat "${meta}")
        pack_print metapack &>$(edebug_out)

        if pack_contains metapack "Size"; then
            
            einfos "Size"
            expect=$(pack_get metapack Size)
            actual=$(stat --printf="%s" "${path}")
            [[ ${expect} -eq ${actual} ]] || { ewarn "Size mismatch: $(lval path expect actual)"; return 1; }
            validated+=( "Size" )
            eend
        fi

        # Now validated MD5, SHA1, and SHA256 (if present)
        for ctype in MD5 SHA1 SHA256; do
            if pack_contains metapack "${ctype}"; then
                
                einfos "${ctype}"
                expect=$(pack_get metapack ${ctype})
                actual=$(${ctype,,}sum ${path} | awk '{print $1}')
                [[ ${expect} == ${actual} ]] || { ewarn "${ctype} mismatch: $(lval path expect actual)"; return 2; }
                validated+=( ${ctype} )
                eend
            fi
        done

        # If Public Key was provied and PGPSignature is present validate PGP signature
        publickey=$(opt_get p)
        pgpsignature=$(pack_get metapack PGPSignature | base64 --decode)
        if [[ -n ${publickey} && -n ${pgpsignature} ]]; then
          
            einfos "PGPSignature"

            # Import PGP Public Key
            keyring=$(mktemp /tmp/echecksum-keyring-XXXX)
            trap_add "rm -f ${keyring}" ${die_signals[@]} ERR EXIT
            gpg --quiet --no-default-keyring --secret-keyring ${keyring} --import ${publickey}

            # Now we can validate the signature
            echo "${pgpsignature}" | gpg --verify - "${path}" || { ewarn "PGP signature verification failure: $(lval path)"; return 3; }
            validated+=( "PGPSignature" )
            
            eend
        fi

        # If we didn't validate anything then that's an error
        ! array_empty validated || { ewarn "Failed to validate $(lval path)"; return 4; }

    } &>${redirect}
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
    local num_mounts
    num_mounts=$(grep --count --perl-regexp "$(emount_regex ${path})" /proc/mounts || true)
    echo -n ${num_mounts}
}

emounted()
{
    $(declare_args path)
    path=$(emount_realpath ${path})
    [[ -z ${path} ]] && { edebug "Unable to resolve $(lval path) to check if mounted"; return 1; }

    (
        local output="" rc=0
        output=$(grep --perl-regexp "$(emount_regex ${path})" /proc/mounts)
        rc=$?

        [[ -n ${output} ]] && output="\n${output}"
        edebug "Checking if $(lval path) is mounted:${output}"

        [[ ${rc} -eq 0 ]] \
            && { edebug "$(lval path) is mounted ($(emount_count ${path}))";     return 0; } \
            || { edebug "$(lval path) is NOT mounted ($(emount_count ${path}))"; return 1; }
    )
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
    mount --make-rprivate "${src}" &>$(edebug_out)  || true
    emount --rbind "${@}" "${src}" "${dest}"
    mount --make-rprivate "${dest}" &>$(edebug_out) || true
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
        local rdev
        rdev=$(emount_realpath ${mnt})
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
    for mnt in $@; do
        local rdev
        rdev=$(emount_realpath ${mnt})
        argcheck rdev

        while [[ true ]]; do

            # If this path is directly mounted or anything BENEATH it is mounted then proceed
            local matches
            matches="$(efindmnt ${mnt} | sort -ur)"
            edebug "$(lval mnt rdev matches)"
            [[ -z ${matches} ]] && break

            local nmatches
            nmatches=$(echo "${matches}" | wc -l)
            einfo "Recursively unmounting ${mnt} (${nmatches})"
            local match
            for match in "${matches}"; do
                eunmount ${match//${rdev}/${mnt}}
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
# Similar to what we do in esource, we want all code generated by this function
# to be invoked in the caller's environment instead of within this function.
# BUT, we don't want to have to use clumsy eval $(declare_args...). So instead we
# employ the same trick of emitting a 'eval command invocation string' which the
# caller executes via:
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
    local _declare_args_caller=( $(caller 0) )
    local _declare_args_options="_${_declare_args_caller[1]}_options"
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
    [[ $(pack_get _${_caller[1]}_options ${1}) -eq 1 ]]
}

# Helper method to be used after declare_args to check if a given option is false (0).
opt_false()
{
    local _caller=( $(caller 0) )
    [[ $(pack_get _${_caller[1]}_options ${1}) -eq 0 ]]
}

# Helper method to be used after declare_args to extract the value of an option.
# Unlike opt_get this one allows you to specify a default value to be used in
# the event the requested option was not provided.
opt_get()
{
    $(declare_args key ?default)
    local _caller _value
    _caller=( $(caller 0) )
    _value=$(pack_get _${_caller[1]}_options ${key})
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
    local orig
    orig=$(declare -f $1)
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
    local actual
    actual="$(declare -pf ${func} 2>/dev/null || true)"
    [[ ${expected} == ${actual} ]] && return 0 || true

    eval "${expected}"
    eval "declare -rf ${func}"
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

    local rc=0
    eprogress "Fetching $(lval url dst)"
    curl "${url}" ${timecond} --output "${dst}" --location --fail --silent --show-error --insecure && rc=0 || rc=$?
    eprogress_kill ${rc}

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
# -M=(0|1) Fetch companion .meta file and validate metadata fields using echecksum_check.
# -q=(0|1) Quiet mode (disable eprogress and other info messages)
efetch()
{
    $(declare_args url ?dst)
    : ${dst:=/tmp}
    [[ -d ${dst} ]] && dst+="/$(basename ${url})"
    
    # Companion files we may fetch
    local md5="${dst}.md5"
    local meta="${dst}.meta"

    # If we're in quiet mode send all STDOUT and STDERR to edebug
    local redirect=""
    opt_true "q" && redirect="$(edebug_out)" || redirect="/dev/stderr"

    try
    {
        ## If requested, fetch MD5 file
        if opt_true "m"; then

            efetch_internal "${url}.md5" "${md5}"
            efetch_internal "${url}"     "${dst}"

            # Verify MD5
            einfos "Verifying MD5 $(lval dst md5)"

            local dst_dname dst_fname md5_dname md5_fname
            dst_dname=$(dirname  "${dst}")
            dst_fname=$(basename "${dst}")
            md5_dname=$(dirname  "${md5}")
            md5_fname=$(basename "${md5}")

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
            echecksum_check "${dst}"
        
        ## BASIC file fetching only
        else
            efetch_internal "${url}" "${dst}"
        fi
    } &>${redirect}
    catch
    {
        local rc=$?
        edebug "Removing $(lval dst md5 meta rc)"
        rm -rf "${dst}" "${md5}" "${meta}"
        return ${rc}
    }

    einfos "Successfully fetched $(lval url dst)" &>${redirect}
}

netselect()
{
    local hosts=$@; argcheck hosts
    eprogress "Finding host with lowest latency from [${hosts}]"

    declare -a results sorted rows

    for h in ${hosts}; do
        local entry
        entry=$(die_on_abort; ping -c10 -w5 -q $h 2>/dev/null | \
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

    local best
    best=$(echo "${sorted[0]}" | cut -d\| -f1)
    einfos "Best host=[${best}]"

    echo -en "${best}"
}

# eretry executes arbitrary shell commands for you, enforcing a timeout in
# seconds and retrying up to a specified count.  If the command is successful,
# retries stop.  If not, eretry will "die".
#
# If the command eventually completes successfully eretry will return 0. Otherwise
# if it is prematurely terminated via the requested SIGNAL it will return 124 to match
# earlier behavior with timeout based implementations. If the process fails to exit
# after receiving requested signal it will send SIGKILL to the process. If this
# happens the return code of eretry will be 137 (128+SIGKILL).
#
# OPTIONS:
# -t TIMEOUT. After this duration, command will be killed (and retried if that's the
#   right thing to do).  If unspecified, commands may run as long as they like
#   and eretry will simply wait for them to finish.
#
#   If it's a simple number, the duration will be a number in seconds.  You may
#   also specify suffixes in the same format the timeout command accepts them.
#   For instance, you might specify 5m or 1h or 2d for 5 minutes, 1 hour, or 2
#   days, respectively.
#
# -d DELAY. Amount of time to delay (sleep) after failed attempts before retrying.
#   Note that this value can accept sub-second values, just as the sleep command does.
#
# -s SIGNAL=<signal name or number>     e.g. SIGNAL=2 or SIGNAL=TERM
#   When ${TIMEOUT} seconds have passed since running the command, this will be
#   the signal to send to the process to make it stop.  The default is TERM.
#   [NOTE: KILL will _also_ be sent two seconds after the timeout if the first
#   signal doesn't do its job]
#
# -r RETRIES=<number>
#   Command will be attempted <number> times total.
#
# -w WARN=<number>
#   A warning will be generated every time <number> of retries have been
#   attemped and failed.
#
# All direct parameters to eretry are assumed to be the command to execute, and
# eretry is careful to retain your quoting.
#
eretry()
{
    # Parse options
    $(declare_args)
    local _eretry_timeout _eretry_delay _eretry_signal _eretry_retries _eretry_warn
    _eretry_timeout=$(opt_get t "")
    _eretry_delay=$(opt_get d 0)
    _eretry_signal=$(opt_get s SIGTERM)
    _eretry_retries=$(opt_get r 5)
    _eretry_warn=$(opt_get w 0)
    [[ ${_eretry_retries} -le 0 ]] && _eretry_retries=1

    # Convert signal name to number so we can use it's numerical value
    if [[ ! ${_eretry_signal} =~ ^[[:digit:]]$ ]]; then
        _eretry_signal=$(kill -l ${_eretry_signal})
    fi

    # Command
    local cmd=("${@}")

    # Tries
    local attempt=0
    local rc=""
    local exit_codes=()
    for (( attempt=0 ; attempt < _eretry_retries; attempt++ )) ; do

        if [[ -n ${_eretry_timeout} ]] ; then

            "${cmd[@]}" &
            local pid=$!

            # Start watchdog process to kill it if it timesout
            (
                nodie_on_error
                die_on_abort
                sleep ${_eretry_timeout}
                kill -0 ${pid} || exit 0

                kill -${_eretry_signal} ${pid}
                sleep 2
                kill -0 ${pid} || exit ${_eretry_signal}
                kill -KILL ${pid}
            ) &

            # Wait for the pid which will either be KILLED by the watcher
            # or completel normally.
            local watcher=$!
            wait ${pid} && rc=0 || rc=$?
            kill -9 ${watcher} &>/dev/null || true
            wait ${watcher}    &>/dev/null || true

            # If the process timedout return 124 to match timeout behavior.
            local timeout_rc
            timeout_rc=$(( 128 + ${_eretry_signal} ))
            [[ ${rc} -eq ${timeout_rc} ]] && rc=124

        else
            "${cmd[@]}" && rc=0 || rc=$?
        fi
        exit_codes+=(${rc})

        [[ ${rc} -eq 0 ]] && break

        [[ ${_eretry_warn} -ne 0 ]] && (( (attempt+1) % _eretry_warn == 0 && (attempt+1) < _eretry_retries )) \
            && ewarn "Command has failed $((attempt+1)) times. Retrying: $(lval cmd retries=_eretry_retries timeout=_eretry_timeout exit_codes)"

        [[ ${_eretry_delay} -ne 0 ]] && { edebug "Sleeping $(lval _eretry_delay)" ; sleep ${_eretry_delay} ; }
    done

    [[ ${rc} -eq 0 ]] || ewarn "Command failed $(lval cmd retries=_eretry_retries timeout=_eretry_timeout exit_codes)"

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
        local -a notset=( $(grep -o '__\S\+__' ${filename} | sort --unique | tr '\n' ' ') )
        [[ ${SETVARS_WARN:-1}  -eq 1 ]] && ewarn "Failed to set all variables in $(lval filename notset)"
        return 1
    fi

    return 0
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
    set +u
    eval "echo \${#${__array}[@]}"
    set -u
}

# Return true (0) if an array is empty and false (1) otherwise
array_empty()
{
    $(declare_args __array)
    [[ $(array_size ${__array}) -eq 0 ]]
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

    local __array_remove_to_remove=("${@}")

    # Simply bail if the array is not set, because bash doesn't really save
    # arrays with no members.  For instance A=() unsets array A...
    [[ -v ${__array} ]] || { edebug "array_remove skipping empty array $(lval __array)" ; return 0; }

    # Remove all instances or only the first?
    local remove_all
    remove_all=$(opt_get a 0)

    local value
    for value in "${__array_remove_to_remove[@]}"; do

        local idx
        for idx in $(array_indexes ${__array}) ; do
            eval "local entry=\${${__array}[$idx]:-}"
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
    for (( idx=0; idx < $(array_size ${__array}); idx++ )); do
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
    [[ $(array_size __array) -eq 0 ]] && { echo -n ""; return 0; } || true

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

    local _removeOld _addNew _packed
    _removeOld="$(echo -n "${!1:-}" | _unpack | grep -av '^'${_tag}'=' || true)"
    _addNew="$(echo "${_removeOld}" ; echo -n "${_tag}=${_val}")"
    _packed=$(echo "${_addNew}" | _pack)

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

    local _unpacked _found
    _unpacked="$(echo -n "${!_pack_pack_get:-}" | _unpack)"
    _found="$(echo -n "${_unpacked}" | grep -a "^${_tag}=" || true)"
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

    local _unpacked _lines _line
    _unpacked="$(echo -n "${!_pack_pack_iterate}" | _unpack)"
    array_init_nl _lines "${_unpacked}"

    for _line in "${_lines[@]}" ; do

        local _key="${_line%%=*}"
        local _val="${_line#*=}"

        ${_func} "${_key}" "${_val}"

    done
}

# Spews bash commands that, when executed will declare a series of variables
# in the caller's environment for each and every item in the pack. This uses
# the same tactic as esource and declare_args by emitting an "eval command
# invocation string" which the caller then executes in order to manifest the
# commands. For instance, if your pack contains keys a and b with respective
# values 1 and 2, you can create locals a=1 and b=2 by running:
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
        local _pack_import_val
        _pack_import_val=$(pack_get ${_pack_import_pack} ${_pack_import_key})
        _pack_import_cmd+="$_pack_import_scope $_pack_import_key=${_pack_import_val}; "
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

        local _arg_noqual
        _arg_noqual=$(discard_qualifiers ${_arg})
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
# methods inside bashutils, this uses the 'eval command invocation string' idom.
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

    local _json_import_prefix _json_import_query _json_import_filename _json_import_data _json_import_keys

    # Lookup optional prefix to use
    _json_import_prefix="$(opt_get p)"

    # Lookup optional jq query to use
    _json_import_query="$(opt_get q)"
    : ${_json_import_query:=.}

    # Lookup optional filename to use. If no filename was given then we're operating on STDIN.
    # In either case read into a local variable so we can parse it repeatedly in this function.
    _json_import_filename="$(opt_get f)"
    : ${_json_import_filename:=-}
    _json_import_data=$(cat ${_json_import_filename} | jq -r "${_json_import_query}")

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

        local val
        val=$(jq -r .${key} <<< ${_json_import_data})
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
# SOURCING
#-----------------------------------------------------------------------------
return 0
