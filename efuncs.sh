#!/bin/bash
# 
# Copyright 2011-2014, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# TRAPS / DIE / STACKTRACE 
#-----------------------------------------------------------------------------

stacktrace()
{
    local frame=${1:-1}

    while caller ${frame}; do
        ((frame++));
    done
}

export DIE_IN_PROGRESS=0

die()
{
    [[ ${DIE_IN_PROGRESS} -eq 1 ]] && exit 1
    DIE_IN_PROGRESS=1
    eprogress_killall

    eerror_stacktrace "${@}"
   
    # If die() is fatal (via EFUNCS_FATAL) go ahead and kill everything in this process tree
    [[ ${EFUNCS_FATAL:-1} -eq 1 ]] && { trap - EXIT ;  kill 0 ; }

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
            extract_trap_cmd() { printf '%s\n' "$3"; }
            # print the new trap command
            printf '%s\n' "${trap_add_cmd}"
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

# Trap specified signals and call die() which will kill the entire
# process tree. Can optionally specify what signals to trap but defaults
# to the key signals we generally want to die on. This is used as our
# default signal handler but it's also very important to put this at the
# start of any command substitution which you want to be interruptible. 
# Otherwise, due to bash quirkiness, signals are ignored in command
# substitution: http://www.tldp.org/LDP/Bash-Beginners-Guide/html/sect_12_01.html.
trap_and_die()
{
    local signals=$@
    [[ -z ${signals[@]} ]] && signals=( HUP INT QUIT BUS PIPE TERM )
    trap 'die [killed]' ${signals[@]}
}

# Default trap
trap_and_die

#-----------------------------------------------------------------------------
# FANCY I/O ROUTINES
#-----------------------------------------------------------------------------

tput()
{
    TERM=${TERM:-xterm} /usr/bin/tput $@
}

ecolor()
{
    ## If EFUNCS_COLOR is empty then set it based on if stderr is a terminal or not ##
    local efuncs_color=${EFUNCS_COLOR}
    [[ -z ${efuncs_color} && -t 2 ]] && efuncs_color=1
    [[ ${efuncs_color} -eq 1 ]] || return 0

    # NOTE: Do NOT use declare_args here to pull c out of the argument list.
    # Otherwise you cause indirect infinite recursion if you enable EDEBUG!!
    local c=$1; argcheck c

    # For the colors see tput(1) and terminfo(5)
    [[ ${c} == "none"     ]] && { echo -en "\033[m";                  return 0; }
    [[ ${c} == "red"      ]] && { echo -en $(tput bold;tput setaf 1); return 0; }
    [[ ${c} == "green"    ]] && { echo -en $(tput bold;tput setaf 2); return 0; }
    [[ ${c} == "yellow"   ]] && { echo -en $(tput bold;tput setaf 3); return 0; }
    [[ ${c} == "fawn"     ]] && { echo -en $(tput setaf 3);           return 0; }
    [[ ${c} == "beige"    ]] && { echo -en $(tput setaf 3);           return 0; }
    [[ ${c} == "dimblue"  ]] && { echo -en $(tput setaf 4);           return 0; }
    [[ ${c} == "blue"     ]] && { echo -en $(tput bold;tput setaf 4); return 0; }
    [[ ${c} == "purple"   ]] && { echo -en $(tput setaf 5);           return 0; }
    [[ ${c} == "magenta"  ]] && { echo -en $(tput bold;tput setaf 5); return 0; }
    [[ ${c} == "cyan"     ]] && { echo -en $(tput bold;tput setaf 6); return 0; }
    [[ ${c} == "gray"     ]] && { echo -en $(tput setaf 7);           return 0; }
    [[ ${c} == "white"    ]] && { echo -en $(tput bold;tput setaf 7); return 0; }
    [[ ${c} == "bell"     ]] && { echo -en $(tput bel);               return 0; }
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
# format. Additionally, for any argument which is an associative array, you can 
# choose if you want it logged as a signale parameter or expanded into tag=value
# within the details section. If you want it logged as a single parameter inside
# the details section just pass it by name as you always would. If instead you want
# the associative array expanded for you into multiple tag=value pairs to be each
# included individually in the details section precede the parameter name with a '!'
# as in !ARRAY.
# 
# All of this is implemented with print_value to give consistency in how we log
# and present information.
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
    array_init_nl lines "${1}" ; shift
    for line in "${lines[@]}"; do
        echo -e "| ${line}" >&2
    done

    # Timestamp
    [[ ${EFUNCS_TIME} -eq 1 ]] && local stamp="[$(etimestamp)]" || local stamp=""
    [[ -n ${stamp} ]] && { echo -e "|\n| Time=${stamp}" >&2; }

    # Iterate over all other arguments and stick them into an associative array
    # If a custom key was requested via "key=value" format then use the provided
    # key and lookup value via print_value.
    declare -A __details;
    
    array_init_nl entries "$*"
    for k in "${entries[@]}"; do

        # Magically expand arrays prefixed with bang operator ('!') to allow
        # more natural logging of elements within an array or an associative
        # array individiaually within the details section instead of all on
        # one line. The implementation of this terrible because bash doesn't
        # actually support natural things like exporting an array or passing
        # an array between functions. Worse, you can't just say something
        # simple like: eval ${!MYARRAY[${key}]} because that would just be
        # too simple. SO... the way this works is to use declare -p to create
        # a new local array to this function from the named one that was passed
        # in and then lookup the requested key in _THAT_ array. Magic.
        if [[ ${k:0:1} == "!" ]]; then
            
            local array_name="${k:1}"
            local code="$(declare -p ${array_name})"
            code=${code/${array_name}/array}
            eval "${code}"

            for akey in ${!array[@]}; do
                __details[${akey}]=$(print_value "${array[$akey]}")
            done
        else
            local _ktag="${k%%=*}"; [[ -z ${_ktag} ]] && _ktag="${k}"
            local _kval="${k#*=}";
            _ktag=${_ktag#+}
            __details[${_ktag}]=$(print_value ${_kval})
        fi
    done
  
    # Now output all the details (if any)
    if [[ ${#__details[@]} -ne 0 ]]; then
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
            local pad=$((longest-${#key}+1))
            printf "| • %s%${pad}s :: %s\n" ${key} " " ${__details[$key]} >&2
        done
    fi

    # Close the banner
    echo -e "|" >&2
    echo -e "+${str}+$(ecolor none)" >&2
}

emsg()
{
    # Only take known prefix settings
    local emsg_prefix=$(echo ${EMSG_PREFIX} | egrep -o "(time|times|level|caller|all)")

    $(declare_args color ?symbol level)
    [[ ${EFUNCS_TIME} -eq 1 ]] && emsg_prefix+=time

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
    local delim="$(ecolor none)|"
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
    [[ ${EMSG_COLOR} =~ ${msg_re} || ${level} =~ DEBUG|WARN|ERROR ]]    \
        && echo -en "$(ecolor ${color})${prefix} $@$(ecolor none) " >&2 \
        || echo -en "$(ecolor ${color})${prefix}$(ecolor none) $@ " >&2
}

edebug_enabled()
{
    [[ ${EDEBUG} == "1" ]] && return 0
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

edebug()
{
    edebug_enabled || return 0
    echo -e "$(emsg 'dimblue' '   -' 'DEBUG' "$@")" >&2
}

edebug_out()
{
    edebug_enabled && echo -n "/dev/stderr" || echo -n "/dev/null"
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

eerror_stacktrace()
{
    local skip_frames=1
    [[ $(caller 0 | awk '{print $2}') == "die" ]] && local skip_frames=2 

    echo "" >&2
    eerror "$@"

    local frames=()
    array_init_nl frames "$(stacktrace ${skip_frames})"

    for f in "${frames[@]}"; do
        local line=$(echo ${f} | awk '{print $1}')
        local func=$(echo ${f} | awk '{print $2}')
        local file=$(basename $(echo ${f} | awk '{print $3}'))

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

    for line in "${columns}" "$@"; do
        array_init parts "${line}" "|"
        idx=0
        for p in "${parts[@]}"; do
            mlen=${#p}
            [[ ${mlen} -gt ${lengths[$idx]} ]] && lengths[$idx]=${mlen}
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
            [[ ${ETABLE_ROW_LINES} != 0 ]] && printf "%s\n" ${divider//+/|}
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
        response=$(trap_and_die; eprompt "${msg}")
        matches=( $(echo "${valid}" | grep -io "^${response}\S*") )
        nmatches=${#matches[@]}
        edebug "Response=[${response}] opt=[${opt}] secret=[${secret}] matches=[${matches[@]}] nmatches=[${#matches[@]}] valid=[${valid//\n/ }]"
        [[ ${nmatches} -eq 1 ]] && { echo -en "${matches[0]}"; return 0; }

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
    local rc=${1:-0} #sets rc to first arg if present otherwise defaults to 0

    if [[ -t 1 ]] ; then
        # Terminal magic that:
        #    1) Gets the number of columns on the screen, minus 6 because that's
        #       how many we're about to output
        #    2) Moves up a line
        #    3) Moves right the number of columns from #1
        local startcol=$(( $(tput cols) - 6 ))
        echo -en "$(tput cuu1)$(tput cuf ${startcol})" >&2
    fi

    if [[ ${rc} -eq 0 ]]; then
        echo -e "$(ecolor blue)[$(ecolor green) ok $(ecolor blue)]$(ecolor none)" >&2
    else
        echo -e "$(ecolor blue)[$(ecolor red) !! $(ecolor blue)]$(ecolor none)" >&2
    fi
}

ekill()
{
    $(declare_args pid ?signal)
    : ${signal:=TERM}

    kill -${signal} ${pid}
    wait  ${pid}
}

ekilltree()
{
    $(declare_args pid ?signal)
    : ${signal:=TERM}

    edebug "Killing process tree of ${pid} [$(ps -p ${pid} -o comm=)] with ${signal}."
    for child in $(ps -o pid --no-headers --ppid ${pid}); do
        ekilltree ${child} ${signal}
    done
    ekill ${pid} ${signal} &>/dev/null
}

spinout()
{
    local char="$1"
    echo -n -e "\b${char}" >&2
    sleep 0.10
}

do_eprogress()
{
    if [[ ! -t 2 ]]; then
        while true; do
            echo -n "." >&2
            sleep 1
        done
        return
    fi

    # Sentinal for breaking out of the loop on signal from eprogress_kill
    local done=0
    trap_add "done=1" SIGINT SIGTERM

    local start=$(date +"%s")
    while [[ ${done} -ne 1 ]]; do 
        local now=$(date +"%s")
        local diff=$(( ${now} - ${start} ))

        echo -en "$(ecolor white)" >&2
        printf "[%02d:%02d:%02d]  " $(( ${diff} / 3600 )) $(( (${diff} % 3600) / 60 )) $(( ${diff} % 60 )) >&2
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
        [[ ${done} -eq 1 ]] && { echo -en "\b " >&2; return; }

        echo -en "\b\b\b\b\b\b\b\b\b\b\b\b" >&2
    done
}

export __EPROGRESS_PIDS=""
eprogress()
{
    echo -en "$(emsg 'green' '>>' 'INFO' "$@")" >&2

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    [[ ${EPROGRESS:-1} -eq 0 ]] && return

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
        [[ -t 1 ]] && echo "" >&2
        eend ${rc}
        return
    fi

    # Get the most recent pid
    local pids=( ${__EPROGRESS_PIDS} )
    if [[ ${#pids} -gt 0 ]]; then
        ekill ${pids[0]} ${signal} &>/dev/null
        export __EPROGRESS_PIDS="${pids[@]:1}"
        [[ -t 1 ]] && echo "" >&2
        eend ${rc}
    fi
}

# Kill all eprogress pids
eprogress_killall()
{
    while [[ -n ${__EPROGRESS_PIDS} ]]; do
        eprogress_kill 1
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
# - Arrays: Delimited by ( ).
# - Associative Arrays: Delimited by { }
# - Packs: You must preceed the pack name with a plus sign (i.e. +pack)
#
# Examples:
# String: "value1"
# Arrays: ("value1" "value2 with spaces" "another")
# Associative Arrays: {[key1]="value1" [key2]="value2 with spaces"}
print_value()
{
    local __input=${1}
    [[ -z ${__input} ]] && return

    # Special handling for packs, as long as their name is specified with a
    # plus character in front of it
    if [[ "${__input:0:1}" == '+' ]] ; then
        pack_print "${__input:1}"
        return
    fi

    # Magically expand things of the form MYARRAY[key] to allow more natural
    # logging of elements within an array or an associative array. The
    # implementation of this terrible because bash doesn't actually support
    # natural things like exporting an array or passing an array between
    # functions. Worse, you can't just say something simple like:
    # eval ${!MYARRAY[${key}]} because that would just be too simple.
    # SO... the way this works is to use declare -p to create a new local
    # array to this function from the named one that was passed in and then
    # lookup the requested key in _THAT_ array. Magic.
    if [[ ${__input} =~ (.*)\[(.*)\] ]] ; then
        local array_name=${BASH_REMATCH[1]}
        local key_name=${BASH_REMATCH[2]}
        local code=$(declare -p ${array_name})
        code=${code/${array_name}/array}
        eval "${code}"

        # FINALLY we can lookup the requested key from our new local array.
        echo -n "\"${array[$key_name]}\""

        return
    fi

    local decl=$(declare -p ${__input} 2>/dev/null)
    local val=$(echo "${decl}")
    val=${val#*=}

    # If decl is empty just print out it's raw value as it's NOT a variable!!
    # This is really important so that you can do simple things like
    # $(print_value /home/marshall) and it'll just pass through that value
    # as is but with the proper formatting and quoting.
    [[ -z ${decl} ]] && val='"'${__input}'"'

    # Deal with properly delcared variables which are empty
    [[ -z ${val} ]] && val='""'

    # Special handling for arrays and associative arrays
    [[ ${decl} =~ "declare -a" ]] && { val=$(declare -p ${__input} | sed -e "s/[^=]*='(\(.*\))'/(\1)/" -e "s/[[[:digit:]]\+]=//g"); }

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
    local idx=0
    for __arg in "${@}"; do
        
        # Tag provided?
        local __arg_tag=${__arg%%=*}; [[ -z ${__arg_tag} ]] && __arg_tag=${__arg}
        local __arg_val=${__arg#*=}
        __arg_tag=${__arg_tag#+}
        __arg_val=$(print_value "${__arg_val}")
        
        [[ ${idx} -gt 0 ]] && echo -n " "
        echo -n "${__arg_tag}=${__arg_val}"
        
        idx=$((idx+1))
    done
}

#-----------------------------------------------------------------------------
# DEPRECATED CONFIG_SET* FUNCTIONS
#-----------------------------------------------------------------------------

parse_tag_value_internal()
{
    local input=$1
    local array=()
    tag=$(echo ${input} | cut -d= -f1)
    val=$(echo ${input} | cut -d= -f2 | tr -d '\"')

    array=( ${tag} ${val} )
    rtr=(${array[@]})
    
    parts=(${rtr[@]})
    echo -n "${parts[1]}"
}

parse_tag_value()
{
    local path=$1
    local tag=$2
    local prefix=$3
    local output=$(cat ${path} | grep "^${tag}=")
    
    if [[ "${output}" != "" ]]; then
        echo -n "${prefix}$(parse_tag_value_internal ${output})"
    fi
}

config_set_value()
{
    local tag=$1 ; argcheck 'tag'; shift
    eval "local val=$(trim \${$tag})" || die
    for cfg in $@; do
        sed -i "s|\${$tag}|${val}|g" "${cfg}" || die "Failed to update ${tag} in ${cfg}"
    done
}

# Check no unexpanded variables in given config file or else die
config_check()
{
    local cfg=$1 ; argcheck 'cfg'; shift
    grep "\${" "${cfg}" -qs && die "Failed to replace all variables in ${cfg}"
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
    output="$(host ${hostname} | grep ' has address ')"
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
    local ip=$(/sbin/ifconfig ${iface} | grep -o 'inet addr:\S*' | cut -d: -f2)
    echo -n "${ip//[[:space:]]}"
}

getnetmask()
{
    $(declare_args iface)
    local netmask=$(/sbin/ifconfig ${iface} | grep -o 'Mask:\S*' | cut -d: -f2)
    echo -n "${netmask//[[:space:]]}"
}

getbroadcast()
{
    $(declare_args iface)
    local bcast=$(/sbin/ifconfig ${iface} | grep -o 'Bcast::\S*' | cut -d: -f2)
    echo -n "${bcast//[[:space:]]}"
}

# Gets the default gateway that is currently in use
getgateway()
{
    local gw=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
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

#-----------------------------------------------------------------------------
# FILESYSTEM HELPERS
#-----------------------------------------------------------------------------

# esource allows you to source multiple files at a time with proper error
# checking after each file sourcing. If any of the files cannot be sourced
# either because the file cannot be found or it contains invalid bash syntax, 
# esource will call die(). This still internally calls 'source' so all the
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
    [[ $# -eq 0 ]] && return

    local cmd=""
    for file in "${@}" ; do
        cmd+='source "'${file}'" &>$(edebug_out) || die "Failed to source '${file}'"; '
    done

    echo -n "eval "${cmd}""
}

epushd()
{
    pushd $1 >/dev/null || die "pushd $1 failed"
}

epopd()
{
    popd $1 >/dev/null  || die "popd $1 failed"
}

emkdir()
{
    eval "mkdir -p $@" || die "emkdir $@ failed"
}

echmod()
{
    eval "chmod $@" || die "echmod $@ failed"
}

echown()
{
    eval "chown $@" || die "echown $@ failed"
}

# chmod + chown
echmodown()
{
    [[ $# -ge 3 ]] || die "echmodown requires 3 or more parameters. Called with $# parameters (chmodown $@)."
    $(declare_args mode owner)

    echmod ${mode} $@
    echown ${owner} $@
}

ecp()
{
    eval "cp -arL $@" || die "ecp $@ failed"
}

ecp_try()
{
    eval "cp -arL $@" || { rc=$?; ewarn "ecp $@ failed"; return $rc; }
}

erm()
{
    eval "rm -rf $@" || die "rm -rf $@ failed"
}

erm_try()
{
    eval "rm -rf $@" || { rc=$?; ewarn "rm -rf $@ failed"; return $rc; }
}

ermdir()
{
    eval "rmdir $@" || die "rmdir $@ failed"
}

emv()
{
    eval "mv $@" || die "emv $@ failed"
}

eln()
{
    eval "ln $@" || die "eln $@ failed"
}

ersync()
{
    local flags="-azl"
    [[ ${V} -eq 1 ]] && flags+="vh"
    eval "rsync ${flags} $@" || die "rsync $@ failed"
}

erename()
{
    $(declare_args src dest)

    emkdir "${dest}"
    ersync "${src}/" "${dest}/"
    erm "${src}"
}

etouch()
{
    [[ -z "$@" ]] && die "Missing argument(s)"
    touch "$@" || die "touch $@ failed"
}

# Unmount (if mounted) and remove directory (if it exists) then create it anew
efreshdir()
{
    $(declare_args mnt)

    eunmount_recursive ${mnt}
    erm ${mnt}
    emkdir ${mnt}
}

# Copies the given file to *.bak if it doesn't already exist
ebackup()
{
    $(declare_args src)
    
    [[ -e "${src}" && ! -e "${src}.bak" ]] && ecp "${src}" "${src}.bak"
}

erestore()
{
    $(declare_args src)
    
    [[ -e "${src}.bak" ]] && emv "${src}.bak" "${src}"
}

etar()
{
    # Disable all tar warnings which are expected with unknown file types, sockets, etc.
    local args=("--warning=none")

    # Auto detect compression program based on extension but substitute in pbzip2 for bzip and pigz for gzip
    if [[ -n $(echo "$@" | egrep -- "\.bz2|\.tz2|\.tbz2|\.tbz") ]]; then
        args+=("--use-compress-program=pbzip2")
    elif [[ -n $(echo "$@" | egrep -- "\.gz|\.tgz|\.taz") ]]; then
        args+=("--use-compress-program=pigz")
    else
        args+=("--auto-compress")
    fi

    ecmd tar "${args[@]}" "${@}"
}

esed()
{
    $(declare_args fname)
    
    local cmd="sed -i"
    for exp in "${@}"; do
        cmd+=" -e $'${exp}'"
    done

    cmd+=" $'${fname}'"
    eval "${cmd}" || die "${cmd} failed"
}

# Wrapper around computing the md5sum of a file to output just the filename
# instead of the full path to the filename. This is a departure from normal
# md5sum for good reason. If you download an md5 file with a path embedded into
# it then the md5sum can only be validated if you put it in the exact same path.
# This function will die() on failure.
emd5sum()
{
    $(declare_args path)
   
    local dname=$(dirname  "${path}")
    local fname=$(basename "${path}")

    epushd "${dname}"
    md5sum "${fname}" || die "Failed to compute md5 $(lval path)"
    epopd
}

# Wrapper around checking an md5sum file by pushd into the directory that contains
# the md5 file so that paths to the file don't affect the md5sum check. This
# assumes that the md5 file is a sibling next to the source file with the suffix
# 'md5'. This method will die() on failure.
emd5sum_check()
{
    $(declare_args path)
    
    local fname=$(basename "${path}")
    local dname=$(dirname  "${path}")

    epushd "${dname}"
    ecmd md5sum -c "${fname}.md5"
    epopd
}

#-----------------------------------------------------------------------------                                    
# MOUNT / UMOUNT UTILS
#-----------------------------------------------------------------------------                                    

# Echo the number of times a given directory is mounted.
emount_count()
{
    $(declare_args path)
    path=$(readlink -m ${path} 2>/dev/null)
    path=${path//[[:space:]]}
    local num_mounts=$(grep --count --perl-regexp "(^| )${path} " /proc/mounts)
    echo -n ${num_mounts}
}

emounted()
{
    $(declare_args path)
    path=$(readlink -m ${path} 2>/dev/null)
    [[ -z ${path} ]] && { edebug "Unable to resolve $(lval path) to check if mounted"; return 1; }

    local output="" rc=0
    output=$(grep --perl-regexp "(^| )${path} " /proc/mounts)
    rc=$?

    edebug "Checking if $(lval path) is mounted:
${output}"

    [[ ${rc} -eq 0 ]] \
        && { edebug "$(lval path) is mounted ($(emount_count ${path}))";     return 0; } \
        || { edebug "$(lval path) is NOT mounted ($(emount_count ${path}))"; return 1; }
}

emount()
{
    einfos "Mounting $@"
    ecmd mount "${@}"
}

eunmount()
{
    local first=1

    for m in $@; do
        emounted ${m} || continue
        
        local rdev=$(readlink -m ${m})
        [[ -z ${rdev} ]] && die

        [[ ${first} -eq 1 ]] && { first=0; einfos "Unmounting ${@}"; }
        ecmd umount -l "${rdev}"
    done
}

eunmount_recursive()
{
    local first=1

    for m in $@; do
        local rdev=$(readlink -m ${m})
        [[ -z ${rdev} ]] && die
        
        for p in $(grep --perl-regexp "(^| )${rdev}[/ ]" /proc/mounts | awk '{print $2}' | sort -ur); do
            [[ ${first} -eq 1 ]] && { first=0; einfo "Recursively unmounting ${@}"; }
            eunmount ${p}
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

    ## Degenerate case where actual and expect are both empty strings
    [[ -z ${lh} && -z ${rh} ]] && return 0
    [[ -z ${lh} && -n ${rh} ]] && return 1
    [[ -n ${lh} && -z ${rh} ]] && return 1

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
        [[ -z "${!_argcheck_arg}" ]] && die "Missing argument '${_argcheck_arg}'"
    done
}

# Internal helper method used by both declare_args and declare_globals that
# takes a list of names and declares a variable for each name from the positional
# arguments in the CALLER's context. Similar to what we do in esource, we want
# to code to be invoked in the caller's environment instead of within this function.
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
# The required first argument to this internal helper method indicates the
# qualifier that should be used for the scope of the variable which is one of:
#
# "local"  Local variables with function scope
# ""       Global variables with file scope
# "export" Global variables with external scope in caller's environment 
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
#
# WARNING: DO NOT CALL EDEBUG INSIDE THIS FUNCTION OR YOU WILL CAUSE INFINITE RECURSION!!
declare_args_internal()
{
    local _declare_args_qualifier=$1
    local _declare_args_optional=0
    local _declare_args_variable=""
    local _declare_args_cmd=""

    while shift; do
        [[ $# -eq 0 ]] && break

        # If the variable name is "_" then don't bother assigning it to anything
        [[ $1 == "_" ]] && _declare_args_cmd+="shift; " && continue

        # Check if the argument is optional or not as indicated by a leading '?'.
        # If the leading '?' is present then REMOVE It so that code after it can
        # correctly use the key name as the variable to assign it to.
        [[ ${1:0:1} == "?" ]] && _declare_args_optional=1 || _declare_args_optional=0
        _declare_args_variable="${1#\?}"

        # Declare the variable and then call argcheck if required
        _declare_args_cmd+="${_declare_args_qualifier} ${_declare_args_variable}=\$1; shift; "
        [[ ${_declare_args_optional} -eq 0 ]] && _declare_args_cmd+="argcheck ${_declare_args_variable}; "
    done
    
    echo "eval ${_declare_args_cmd}"
}

# Public method which just calls into declare_args_internal with "local" keyword.
# See declare_args_internal
declare_args()
{
    declare_args_internal "local" "${@}"
}

# Public method which just calls into declare_args_internal with "" keyword.
# See declare_args_internal.
declare_globals()
{
    declare_args_internal "" "${@}"
}

# Public method which just calls into declare_args_internal with "export" keyword.
# See declare_args_internal.
declare_exports()
{
    declare_args_internal "export" "${@}"
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

    ## Don't save the function off it already exists to avoid infinite recursion
    declare -f "${func}_real" >/dev/null || save_function ${func}
    eval "$func() ${body}"
    eval "declare -rf ${func}"
}

ecmd()
{
    local cmd=("$@")
    edebug "Executing $(lval cmd)"
    "${cmd[@]}" || die "Failed to execute $(lval cmd)"
}

ecmd_try()
{
    local cmd=("$@")
    edebug "Executing $(lval cmd)"
    "${cmd[@]}" || { rc=$?; ewarn "Failed to execute [$cmd]"; return $rc; }
}

numcores()
{
    [[ -e /proc/cpuinfo ]] || die "/proc/cpuinfo does not exist"

    echo $(cat /proc/cpuinfo | grep "processor" | wc -l)
}

efetch_try()
{
    local url="${1}"
    local dst="${2}"; [[ -z ${dst} ]] && dst="/tmp"
    argcheck url dst
    [[ -d ${dst} ]] && dst+="/$(basename ${url})"

    eprogress "Fetching $(lval url dst)"
    
    local timecond=""
    [[ -f ${dst} ]] && timecond="--time-cond ${dst}"

    curl "${url}" ${timecond} --output "${dst}" --location --fail --silent --show-error
    local rc=$?
    eprogress_kill $rc
    [[ ${rc} -eq 0 ]] || { ewarn "Failed to fetch $(lval url)"; return $rc; }

    # For backwards compatibility with older scripts this will echo out the downloaded path
    # if the newer syntax wasn't used
    [[ -z ${2} ]] && echo -n "${dst}"

    return 0
}

efetch()
{
    efetch_try "${@}" || die
}

efetch_with_md5_try()
{
    local rc=0
    local url="${1}"
    local dst="${2}"; [[ -z ${dst} ]] && dst="/tmp"
    argcheck url dst
    [[ -d ${dst} ]] && dst+="/$(basename ${url})"
    local md5="${dst}.md5"

    # Fetch the md5 before the payload as we don't need to bother fetching payload if md5 is missing
    efetch_try "${url}.md5" "${md5}" && efetch_try "${url}" "${dst}" || rc=1

    ## Verify MD5 -- DELETE any corrupted images
    if [[ ${rc} -eq 0 ]]; then
        
        einfos "Verifying MD5 $(lval dst md5)"
    
        local dst_dname=$(dirname  "${dst}")
        local dst_fname=$(basename "${dst}")
        local md5_dname=$(dirname  "${md5}")
        local md5_fname=$(basename "${md5}")

        epushd "${dst_dname}"
        
        # If the requested destination was different than what was originally in the MD5 it will fail.
        # Or if the md5sum file was generated with a different path in it it will fail. This just
        # sanititizes it to have the current working directory and the name of the file we downloaded to.
        local md5_raw=$(grep -v "#" "${md5_fname}" | awk '{print $1}')
        echo "${md5_raw}  ${dst_fname}" > "${md5_fname}"
        
        # Now we can perform the check
        md5sum --check "${md5_fname}" >/dev/null
        rc=$?
        epopd
    fi

    if [[ ${rc} -ne 0 ]]; then
        edebug "Removing $(lval dst md5)"
        erm "${dst}"
        erm "${md5}"
    fi  

    [[ ${rc} -eq 0 ]] || { ewarn "Failed to fetch $(lval url)"; return $rc; }

    einfos "Successfully downloaded $(lval url dst)"

    # For backwards compatibility with older scripts this will echo out the downloaded path
    # if the newer syntax wasn't used
    [[ -z ${2} ]] && echo -n "${dst}"

    return 0
}

efetch_with_md5()
{
    efetch_with_md5_try "${@}" || die
}

netselect()
{
    local hosts=$@; argcheck hosts
    eprogress "Finding host with lowest latency from [${hosts}]"

    declare -a results sorted rows;

    for h in ${hosts}; do
        local entry=$(trap_and_die; ping -c10 -w5 -q $h 2>/dev/null | \
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

    for entry in "${sorted[@]}"; do
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

# eretry executes arbitrary shell commands for you, enforcing a timeout in
# seconds and retrying up to a specified count.  If the command is successful,
# retries stop.  If not, eretry will "die".
#
# If you use EFUNCS_FATAL=0, rather than calling die, eretry will return the
# error code from the last attempt. Commands that timeout will return exit code
# 124, unless they die from sigkill in which case they'll return exit code 137.
#
# TIMEOUT=<duration>
#   After this duration, command will be killed (and retried if that's the
#   right thing to do).  If unspecified, commands may run as long as they like
#   and eretry will simply wait for them to finish.
#
#   If it's a simple number, the duration will be a number in seconds.  You may
#   also specify suffixes in the same format the timeout command accepts them.
#   For instance, you might specify 5m or 1h or 2d for 5 minutes, 1 hour, or 2
#   days, respectively.
#
# SLEEP=<time to pass to sleep command>
#   Amount of time to wait after failed attempts before retrying.  Note that
#   this value can accept sub-second values, just as the sleep command does.
#
# SIGNAL=<signal name or number>     e.g. SIGNAL=2 or SIGNAL=TERM
#   When ${TIMEOUT} seconds have passed since running the command, this will be
#   the signal to send to the process to make it stop.  The default is TERM.
#   [NOTE: KILL will _also_ be sent two seconds after the timeout if the first
#   signal doesn't do its job]
#
# RETRIES=<number>
#   Command will be attempted <number> times total.
#
# WARN_EVERY=<number>
#   A warning will be generated every time <number> of retries have been
#   attemped and failed.
#
# All direct parameters to eretry are assumed to be the command to execute, and
# eretry is careful to retain your quoting.
#
eretry()
{
    local try rc cmd exit_codes

    argcheck RETRIES
    [[ ${RETRIES} -le 0 ]] && RETRIES=1

    SIGNAL=${SIGNAL:-TERM}

    cmd=("${@}")
    argcheck cmd

    rc=1
    exit_codes=()
    for (( try=0 ; try < RETRIES ; try++ )) ; do
        if [[ -n ${TIMEOUT} ]] ; then
            timeout --signal=${SIGNAL} --kill-after=2s ${TIMEOUT} "${@}"
            rc=$?
        else
            edebug "$(lval try rc cmd)"
            "${@}"
            rc=$?
        fi
        exit_codes+=(${rc})

        [[ ${rc} -eq 0 ]] && break

        [[ ${WARN_EVERY} -ne 0 ]] && (( (try+1) % WARN_EVERY == 0 && (try+1) < RETRIES )) \
            && ewarn "Command has failed $((try+1)) times.  Still trying.  $(lval cmd RETRIES TIMEOUT exit_codes)"

        [[ -n ${SLEEP} ]] && { edebug "Sleeping $(lval SLEEP)" ; sleep ${SLEEP} ; }
        edebug "eretry: trying again $(lval rc try cmd)"
    done

    if [[ ${rc} -ne 0 ]] ; then
        # Return last exit code if EFUNCS_FATAL isn't supposed to kill the process
        [[ ${EFUNCS_FATAL:-1} -ne 1 ]] && { ewarn "Command failed $(lval cmd RETRIES TIMEOUT exit_codes)" ; return ${rc} ; }

        # Or go ahead and die if EFUNCS_FATAL is set
        die "eretry: failed $(lval cmd exit_codes)"
    fi
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
# SETVARS_FATAL=(0|1)
#   After all variables have been expanded in the provided file, a final check
#   is performed to see if all variables were set properly. If SETVARS_FATAL is
#   1 (the default) it will call die() and dump the contents of the file to more
#   easily see what values were not set properly. Recall by default die() will
#   cause the process to be killed unless you set EFUNCS_FATAL to 0 in which case
#   it will just exit with a non-zero error code.
#
# SETVARS_WARN=(0|1)
#   Even if SETVARS_FATAL is 0, it's sometimes still useful to see a warning on
#   any unset variables. If SETVARS_WARN is set to 1 it will display a warning
#   in the event it did not call die() due to SETVARS_FATAL being set to 0.
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

    for arg in $(grep -o "__\S\+__" ${filename} | sort --unique); do
        local key="${arg//__/}"
        local val="${!key}"
    
        # Call provided callback if one was provided which by contract should print
        # the new resulting value to be used
        [[ -n ${callback} ]] && val=$(${callback} "${key}" "${val}")

        # If we got an empty value back and empty values aren't allowed then continue.
        # We do NOT call die here as we'll deal with that at the end after we have
        # tried to expand all variables. This way we can properly support SETVARS_WARN
        # and SETVARS_FATAL.
        [[ -n ${val} || ${SETVARS_ALLOW_EMPTY:-0} -eq 1 ]] || continue

        edebug "   ${key} => ${val}"
        
        # Put val into perl's environment and let _perl_ pull it out of that
        # environment.  This has the benefit of causing it to not try to
        # interpret any of it, but to treat it as a raw string
        VAL="${val}" perl -pi -e "s/__${key}__/\$ENV{VAL}/g" "${filename}" || die "Failed to set $(lval key val filename)"
    done

    # Ensure nothing left over if SETVARS_FATAL is true. If SETVARS_WARN is true it will still warn in this case.
    if grep -qs "__\S\+__" "${filename}"; then
        local onerror=""
        [[ ${SETVARS_WARN:-1}  -eq 1 ]] && onerror=ewarn
        [[ ${SETVARS_FATAL:-1} -eq 1 ]] && onerror=die

        local -a notset=( $(grep -o '__\S\+__' ${filename} | sort --unique | tr '\n' ' ') )
        [[ -n ${onerror} ]] && ${onerror} "Failed to set all variables in $(lval filename notset)"
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
    [[ -z ${__string} ]] && { eval "${__array}=()"; return; }

    # Default bash IFS is space, tab, newline, so this will default to that
    [[ -z ${__delim} ]] && __delim=$' \t\n'

    IFS="${__delim}" eval "${__array}=(\${__string})"
}

# This function works like array_init, but always specifies that the delimiter
# be a newline.
array_init_nl()
{
    [[ $# -ne 2 ]] && die "array_init_nl only takes two parameters"
    array_init "$1" "$2" $'\n'
}

# Print the size of any array.  Yes, you can also do this with ${#array[@]}.
# But this functions makes for symmertry with pack (i.e. pack_size).
array_size()
{
    $(declare_args __array)
    eval "echo \${#${__array}[@]}"
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
    [[ -z ${__string} ]] && return

    # Default bash IFS is space, tab, newline, so this will default to that
    [[ -z ${__delim} ]] && __delim=$' \t\n'

    # Parse the input given the delimiter and append to the array.
    IFS="${__delim}" eval "${__array}+=(\${__string})"
}

# Identical to array_add only hard codes the delimter to be a newline.
array_add_nl()
{
    [[ $# -ne 2 ]] && die "array_add_nl only takes two parameters"
    array_add "$1" "$2" $'\n'
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

    for (( idx=0; idx < $(array_size ${__array}); idx++ )); do
        eval "local entry=\${${__array}[$idx]}"
        [[ "${entry}" == "${__value}" ]] && return 0
    done

    return 1
}

array_quote()
{
    $(declare_args __array)

    local __output=()
    local __entry=""

    for (( idx=0; idx < $(array_size ${__array}); idx++ )); do
        eval "local entry=\${${__array}[$idx]}"
        __output+=( "$(printf %q "${entry}")" )
    done

    echo "${__output[@]}"
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
            && pack_set_internal ${_pack_update_pack} "${_pack_update_key}" "${_pack_update_val}" ;
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

    local _removeOld="$(echo -n "${!1}" | _unpack | grep -av '^'${_tag}'=')"
    local _addNew="$(echo "${_removeOld}" ; echo -n "${_tag}=${_val}")"
    local _packed=$(echo "${_addNew}" | _pack)

    edebug "$(lval _pack_pack_set_internal _tag _val)"
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

    local _unpacked="$(echo -n "${!_pack_pack_get}" | _unpack)"
    local _found="$(echo -n "${_unpacked}" | grep -a "^${_tag}=")"
    edebug "$(lval _pack_pack_get _tag _found)"
    echo "${_found#*=}"
    [[ -n ${_found} ]]
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
    [[ -z $1 || -z $2 || -n $3 ]] && die "pack_copy requires two arguments"

    eval "${2}=\"\${!1}\"" 
}

#
# For a given pack, execute a given callback function.  The callback function
# should take two arguments, and it will be called once for each item in the
# pack and passed the key as the first value and its value as the second value.
#
pack_iterate()
{
    local _pack_pack_iterate=$1
    local _func=$2
    argcheck _pack_pack_iterate _func

    local _unpacked="$(echo -n "${!_pack_pack_iterate}" | _unpack)"
    local _lines ; array_init_nl _lines "${_unpacked}"

    edebug "$(lval _pack_pack_iterate _unpacked _lines)"

    for _line in "${_lines[@]}" ; do

        local _key="${_line%%=*}"
        local _val="${_line#*=}"

        ${_func} "${_key}" "${_val}"

    done
}

# Internal helper method used by pack_import and pack_import_global where 
# these two wrappers specify the scope of the imports as the required first
# argument. pack_import provides the scope 'local' and pack_import_global
# uses no scope specifier.
#
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
pack_import_internal()
{
    $(declare_args ?_pack_import_scope _pack_import_pack)
    local _pack_import_keys=("${@}")
    [[ ${#_pack_import_keys} -eq 0 ]] && _pack_import_keys=($(pack_keys ${_pack_import_pack}))

    edebug $(lval _pack_import_keys)

    local _pack_import_cmd=""
    for _pack_import_key in "${_pack_import_keys[@]}" ; do
        local _pack_import_val=$(pack_get ${_pack_import_pack} ${_pack_import_key})
        _pack_import_cmd+="$_pack_import_scope $_pack_import_key=${_pack_import_val}; "
    done

    echo "eval "${_pack_import_cmd}""
}

# Public method which just calls into pack_import_internal with "local" scope keyword.
# See pack_import_internal.
pack_import()
{
    pack_import_internal "local" "${@}"
}

# Public method which just calls into pack_import_internal with "" scope keyword.
# See pack_import_internal.
pack_import_global()
{
    pack_import_internal "" "${@}"
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
    local _pack_export_pack=$1
    shift

    local _pack_export_args=()
    for _pack_export_arg in "${@}" ; do
        _pack_export_args+=("${_pack_export_arg}=${!_pack_export_arg}")
    done

    edebug "$(lval _pack_export_pack _pack_export_args)"
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
    echo "${!1}" | _unpack | sed 's/=.*$//'
}

# Note: To support working with print_value, pack_print does NOT print a
# newline at the end of its output
pack_print()
{
    local _pack_pack_print=$1
    argcheck _pack_pack_print

    echo -n '('
    pack_iterate ${_pack_pack_print} _pack_print_item
    echo -n ')'
}

_pack_print_item()
{
    echo -n "[$1]=$(print_value "$2") "
}

_unpack()
{
    base64 -d -w0 | tr '\0' '\n'
}

_pack()
{
    grep -av '^$' | tr '\n' '\0' | base64 -w0
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
