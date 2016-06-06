#!/bin/bash
#
# Copyright 2011-2016, SolidFire, Inc. All rights reserved.
#

: ${EMSG_PREFIX:=}
: ${EMSG_COLOR:=all}

: ${COLOR_INFO:="bold green"}
: ${COLOR_DEBUG:="blue"}
: ${COLOR_TRACE:="yellow"}
: ${COLOR_WARN:="bold yellow"}
: ${COLOR_ERROR:="bold red"}
: ${COLOR_BRACKET:="bold blue"}
: ${COLOR_BANNER:="bold magenta"}

# Any functions whose names are "==" to this are exempt from ETRACE.  In other
# words, even if ETRACE=1, these functions actions will not be displayed in the
# output.
#
# By default, these are excluded:
#   - Any parts of opt_parse (plus string_trim because opt_parse uses it)
#   - Emsg and other message producing internals (but not the message
#     functions like edebug, einfo)
#   - Internals of die and stack generation (but leaving some parts of die
#     so it's more clear what is happening.)
#   - Signame, which does translations amongst signal names in various styles
#     and signal numbers.
: ${ETRACE_BLACKLIST:=@(opt_parse|opt_parse_setup|opt_parse_options|opt_parse_arguments|opt_parse_find_canonical|argcheck|ecolor|ecolor_internal|ecolor_code|einteractive|emsg|string_trim|print_value|lval|disable_signals|reenable_signals|eerror_internal|eerror_stacktrace|stacktrace|stacktrace_array|signame|array_size|array_empty|array_not_empty)}

etrace()
{
    # This function returns as soon as it can decide that tracing should not
    # happen.  If it makes its way to the end, then it finally does the tracing
    # it must do.

    # Is tracing globally off?
    [[ ${ETRACE} == "" || ${ETRACE} == "0" ]] && return 0 || true


    # Is tracing enabled, but not globally (i.e. now we check function and
    # filenames)
    if [[ ${ETRACE} != "1" ]]; then

        local should_be_enabled=0

        local word
        for word in ${ETRACE}; do
            [[ ${BASH_SOURCE[1]:-} == *"${word}"*
                || ${FUNCNAME[1]:-} == *"${word}"* ]] && { should_be_enabled=1; break; }
        done

        [[ ${should_be_enabled} -eq 1 ]] || return 0
    fi


    # Whether we got here because ETRACE=1 or because a function was
    # specifically chosen, we still leave out blacklisted functions
    if [[ ${FUNCNAME[1]} == ${ETRACE_BLACKLIST} ]] ; then
        return 0
    fi

    {
        ecolor ${COLOR_TRACE}
        echo -n "[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]:-}:${FUNCNAME[1]:-}:${BASHPID}]"
        ecolor none
        echo "${BASH_COMMAND}"
    } >&2
}

edebug_enabled()
{
    [[ -n ${1:-} ]] && die "edebug_enabled does not support arguments."

    [[ ${EDEBUG:=}  == "1" || ${ETRACE:=}  == "1" ]] && return 0
    [[ ${EDEBUG:-0} == "0" && ${ETRACE:-0} == "0" ]] && return 1

    # Walk up the stack and pick the first function that isn't in our list of
    # function names skipped
    local index=1
    local caller=${FUNCNAME[$index]}
    local filename=${BASH_SOURCE[$index]}
    if [[ ${caller} == @(edebug|edebug_out|tryrc) ]] ; then
        (( index += 1 ))
        caller=${FUNCNAME[$index]}
        filename=${BASH_SOURCE[$index]}
    fi

    # If the edebug or etrace strings contain a word that matches the name of
    # the function or filename, then edebug is on.
    local word
    for word in ${EDEBUG:-} ${ETRACE:-} ; do
        [[ "${caller}"   == *"${word}"* ]] && return 0
        [[ "${filename}" == *"${word}"* ]] && return 0
    done

    # Otherwise, it's not.
    return 1
}

edebug_disabled()
{
    ! edebug_enabled
}

edebug()
{
    # Take input either from arguments or if no arguments were provided take input from
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
    EMSG_PREFIX="${EMSG_PREFIX:-} caller" emsg "${COLOR_DEBUG}" "" "DEBUG" "${msg}"
}

edebug_out()
{
    edebug_enabled && echo -n "/dev/stderr" || echo -n "/dev/null"
}

# Check if we are "interactive" or not. For our purposes, we are interactive
# if STDERR is attached to a terminal or not. This is checked via the bash
# idiom "[[ -t 2 ]]" where "2" is STDERR. But we can override this default
# check with the global variable EINTERACTIVE=1.
einteractive()
{
    [[ ${EINTERACTIVE:-0} -eq 1 ]] && return 0
    [[ -t 2 ]]
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

    declare -Ag __BU_COLOR_CACHE
    local index=$*
    if [[ ! -v "__BU_COLOR_CACHE[$index]" ]] ; then
        __BU_COLOR_CACHE[$index]=$(ecolor_internal "${index}")
    fi

    echo -n "${__BU_COLOR_CACHE[$index]}"
}

ecolor_internal()
{
    local c=""
    for c in $@; do
        case ${c} in
            dim)            echo -en "\033[2m"                 ;;
            invert)         tput rev                           ;;
            bold)           tput bold                          ;;
            underline)      tput smul                          ;;
            reset|none|off) echo -en "\033[0m"                 ;;
            b:*)            tput setab $(ecolor_code ${c#b:})  ;;
            *)              tput setaf $(ecolor_code ${c})     ;;
        esac
    done
}

eclear()
{
    tput clear >&2
}

etimestamp()
{
    echo -en "$(date '+%b %d %T.%3N')"
}

# Display a very prominent banner with a provided message which may be multi-line
# and an optional timestamp as well as the ability to provide any number of extra
# arguments which will be included in the banner in a pretty printed tag=value
# format. All of this is implemented with print_value to give consistency in how
# we log and present information.
ebanner()
{
    {
        local cols lines entries

        echo ""
        cols=${COLUMNS:-80}
        cols=$((cols-2))
        eval "local str=\$(printf -- '-%.0s' {1..${cols}})"
        ecolor ${COLOR_BANNER}
        echo -e "+${str}+"
        echo -e "|"

        # Print the first message honoring any newlines
        array_init_nl lines "${1}"; shift
        for line in "${lines[@]}"; do
            echo -e "| ${line}"
        done

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
            echo -e "|"

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
                printf "| • %s%${pad}s :: %s\n" ${key} " " "${__details[$key]}"
            done
        fi

        # Close the banner
        echo -e "|"
        echo -en "+${str}+"
        ecolor none
        echo ""

    } >&2

    return 0
}

emsg()
{
    {
        local color=$1 ; shift
        local header=$1 ; shift
        local level=$1 ; shift
        local msg="$*"

        local informative_header=0
        if [[ ${EMSG_PREFIX} =~ ${BU_WORD_BEGIN}(time|times|level|caller|pid|all)${BU_WORD_END} ]] ; then
            informative_header=1
        fi

        # Print the "informative header" containing things like timestamp, calling
        # function, etc.  We choose which ones to print based on the contents of
        # EMSG_PREFIX and which ones to color based on the value of EMSG_COLOR
        if [[ ${informative_header} == 1 && ${level} != @(INFOS|WARNS) ]] ; then
            ecolor $color
            echo -n "["
            ecolor reset

            local field first_printed=0
            for field in time level caller pid ; do

                # If the field is one selected by EMSG_PREFIX...
                if [[ ${EMSG_PREFIX} =~ ${BU_WORD_BEGIN}(all|${field})${BU_WORD_END} ]] ; then

                    # Separator if this isn't the first field to print
                    [[ ${first_printed} -eq 1 ]] && { ecolor reset ; echo -n "|" ; }

                    # Start color if appropriate
                    [[ ${EMSG_COLOR} =~ ${BU_WORD_BEGIN}(all|${field})${BU_WORD_END} ]] && ecolor $color

                    # Print the individual field
                    case ${field} in
                        time|times)
                            etimestamp
                            ;;
                        level)
                            echo -n "${level}"
                            ;;
                        caller)
                            # First field is filename with path info stripped off
                            echo -n "${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}:${FUNCNAME[2]:-}"
                            ;;
                        pid)
                            echo -n "${BASHPID}"
                            ;;
                        *)
                            die "Internal error."
                            ;;
                    esac

                    first_printed=1
                    ecolor reset
                fi
        
            done

            ecolor $color
            echo -n "] "

        else
            # If not the informative header, just use the message-type-specific
            # header passed as an argument to emsg
            ecolor $color
            echo -n "${header} "
        fi

        # If EMSG_COLOR doesn't say to color the message turn off color before
        # we start printing it
        [[ ! ${EMSG_COLOR} =~ ${BU_WORD_BEGIN}(all|msg)${BU_WORD_END} ]] && ecolor reset

        # Also, only print colored messages for certain levels
        [[ ${level} != @(DEBUG|WARN|WARNS|ERROR) ]] && ecolor reset

        echo -n "${msg}"
        ecolor reset
        echo ""
    } >&2
}

einfo()
{
    emsg "${COLOR_INFO}" ">>" "INFO" "$@"
}

einfos()
{
    emsg "${COLOR_INFO}" "   -" "INFOS" "$@"
}

ewarn()
{
    emsg "${COLOR_WARN}" ">>" "WARN" "$@"
}

ewarns()
{
    emsg "${COLOR_WARN}" "   -" "WARNS" "$@"
}

eerror_internal()
{
    $(opt_parse ":color c=${COLOR_ERROR} | Color to print the message in.")
    emsg "${color}" ">>" "ERROR" "$@"
}

eerror()
{
    emsg "${COLOR_ERROR}" ">>" "ERROR" "$@"
}

opt_usage eerror_stacktrace <<'END'
Print an error stacktrace to stderr.  This is like stacktrace only it pretty prints the entire
stacktrace as a bright red error message with the funct and file:line number nicely formatted for
easily display of fatal errors.

Allows you to optionally pass in a starting frame to start the stacktrace at. 0 is the top of the
stack and counts up. See also stacktrace and eerror_stacktrace.
END
eerror_stacktrace()
{
    $(opt_parse \
        ":frame f=2              | Frame number to start at.  Defaults to 2, which skips this function and its caller." \
        "+skip s                 | Skip the initial error message.  Useful if the caller already displayed it." \
        ":color c=${COLOR_ERROR} | Use the specified color for output messages.")

    if [[ ${skip} -eq 0 ]]; then 
        echo "" >&2
        eerror_internal -c="${color}" "$@"
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
    $(opt_parse "columns")
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
    echo -en "$(ecolor bold) * $@: $(ecolor none)" >&2
    local result=""

    read result < /dev/stdin

    echo -en "${result}"
}

opt_usage eprompt_with_options <<'END'
eprompt_with_options allows the caller to specify what options are valid responses to the provided
question. The caller can also optionally provide a list of "secret" options which will not be
displayed in the prompt to the user but will be accepted as a valid response.
END
eprompt_with_options()
{
    $(opt_parse "msg" "opt" "?secret")
    local valid="$(echo ${opt},${secret} | tr ',' '\n' | sort --ignore-case --unique)"
    msg+=" (${opt})"

    ## Keep reading input until a valid response is given
    while true; do
        response=$(eprompt "${msg}")
        matches=( $(echo "${valid}" | grep -io "^${response}\S*" || true) )
        edebug "$(lval response opt secret matches valid)"
        [[ ${#matches[@]} -eq 1 ]] && { echo -en "${matches[0]}"; return 0; }

        eerror "Invalid response=[${response}] -- use a unique prefix from options=[${opt}]"
    done
}

epromptyn()
{
    $(opt_parse "msg")
    eprompt_with_options "${msg}" "Yes,No"
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
        echo -e "$(ecolor ${COLOR_BRACKET})[$(ecolor ${COLOR_INFO}) ok $(ecolor ${COLOR_BRACKET})]$(ecolor none)" >&2
    else
        echo -e "$(ecolor ${COLOR_BRACKET})[$(ecolor ${COLOR_ERROR}) !! $(ecolor ${COLOR_BRACKET})]$(ecolor none)" >&2
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

        ecolor bold >&2
        printf " [%02d:%02d:%02d]  " $(( ${diff} / 3600 )) $(( (${diff} % 3600) / 60 )) $(( ${diff} % 60 )) >&2
        ecolor none >&2

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
    echo -en "$(emsg "${COLOR_INFO}" ">>" "INFO" "$@" 2>&1)" >&2

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    [[ ${EPROGRESS:-1} -eq 0 ]] && return 0

    # Prepend this new eprogress pid to the front of our list of eprogress PIDs
    # Add a trap to ensure we kill this backgrounded process in the event we
    # die before calling eprogress_kill.
    ( close_fds ; do_eprogress ) &
    __BU_EPROGRESS_PIDS+=( $! )
    trap_add "eprogress_kill -r=1 $!"
}

opt_usage eprogress_kill <<'END'
Kill the most recent eprogress in the event multiple ones are queued up. Can optionally pass in a
specific list of eprogress pids to kill.
END
eprogress_kill()
{
    $(opt_parse \
        ":rc return_code r=0  | Should this eprogress show a mark for success or failure?" \
        "+all a               | If set, kill ALL known eprogress processes, not just the current one")

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
    elif array_not_empty __BU_EPROGRESS_PIDS; then 
        if [[ ${all} -eq 1 ]] ; then
            pids=( "${__BU_EPROGRESS_PIDS[@]}" )
        else
            pids=( "${__BU_EPROGRESS_PIDS[-1]}" )
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
        if process_not_running ${pid} || ! array_contains __BU_EPROGRESS_PIDS ${pid}; then
            continue
        fi

        # Kill process and wait for it to complete
        ekill ${pid} &>/dev/null
        wait ${pid} &>/dev/null || true
        array_remove __BU_EPROGRESS_PIDS ${pid}

        # Output
        einteractive && echo "" >&2
        eend ${rc}
    done

    return 0
}

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
# - Packs: You must preceed the pack name with a percent sign (i.e. %pack)
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
    # '%' character in front of it
    if [[ "${__input:0:1}" == '%' ]] ; then
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
# be separated by a space, as in: tag="value" tag2="value2" tag3="value3"
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
        __arg_tag=${__arg_tag#%}
        __arg_val=$(print_value "${__arg_val}")

        echo -n "${__lval_pre}${__arg_tag}=${__arg_val}"
        __lval_pre=" "
    done
}

return 0