#!/bin/bash
# 
# Copyright 2011-2014, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# TRAPS / DIE / STACKTRACE 
#-----------------------------------------------------------------------------

stacktrace()
{
    local frame=1

    while caller ${frame}; do
        ((frame++));
    done
}

export DIE_IN_PROGRESS=0

die()
{
    [[ ${DIE_IN_PROGRESS} -eq 1 ]] && exit 1
    DIE_IN_PROGRESS=1
    eprogress_kill

    echo ""
    eerror "$@"

    ifs_save; ifs_nl
    local frames=( $(stacktrace) )

    for f in ${frames[@]}; do
        local line=$(echo ${f} | awk '{print $1}')
        local func=$(echo ${f} | awk '{print $2}')
        local file=$(basename $(echo ${f} | awk '{print $3}'))

        [[ ${file} == "efuncs.sh" && ${func} == "die" ]] && break
        
        printf "$(ecolor red)   :: %-20s | ${func}$(ecolor none)\n" "${file}:${line}" >&2
    done
    ifs_restore
   
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

    local c=$1; argcheck c

    # For the colors see tput(1) and terminfo(5)
    [[ ${c} == "none"     ]] && { echo -en $(tput sgr0);              return 0; }
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
    ## Show timestamps before einfo messages and in ebanner ##
    [[ ${EFUNCS_TIME} -eq 1 ]] || return

    echo -en "[$(date '+%b %d %T')] "
}

ebanner()
{
    echo "" >&2
    local cols=$(tput cols)
    cols=$((cols-2))
    eval "local str=\$(printf -- '-%.0s' {1..${cols}})"
    echo -e "$(ecolor magenta)+${str}+" >&2
    echo -e "|" >&2

    ifs_save; ifs_nl
    for line in $@; do
        echo -e "| $line" >&2
    done
    ifs_restore
    
    echo -e "|" >&2
    local stamp=$(etimestamp)
    [[ -n ${stamp} ]] && { echo -e "| Time=${stamp}" >&2; echo -e "|" >&2; }
    echo -e "+${str}+$(ecolor none)" >&2
}

eprefix()
{
    local prefix=$(etimestamp)
    [[ -z ${prefix} ]] && prefix=" * "
    echo -en "${prefix}"
}

edebug()
{
    [[ -n ${EDEBUG} ]] && echo "$(ecolor dimblue)    - ${@}$(ecolor none)" >&2
    return 0
}

einfo()
{
    echo -e "$(ecolor green)$(eprefix)$@ $(ecolor none)" >&2
}

einfon()
{
    echo -en "$(ecolor green)$(eprefix)$@ $(ecolor none)" >&2
}

einfos()
{
    echo -e "$(ecolor cyan)   >> $@ $(ecolor none)" >&2
}

ewarn()
{
    echo -e "$(ecolor yellow)$(eprefix)$@ $(ecolor none)" >&2
}

ewarns()
{
    echo -e "$(ecolor yellow)   >> $@ $(ecolor none)" >&2
}

eerror()
{
    echo -e "$(ecolor red)!! $@ !! $(ecolor none)" >&2
}

# etable("col1|col2|col3", "r1c1|r1c2|r1c3"...)
etable()
{
    columns=$1
    lengths=()
    for line in "$@"; do
        ifs_save; ifs_set "|"; parts=(${line}); ifs_restore
        idx=0
        for p in "${parts[@]}"; do
            mlen=${#p}
            [[ ${mlen} -gt ${lengths[$idx]} ]] && lengths[$idx]=${mlen}
            idx=$((idx+1))
        done
    done

    divider="+"
    ifs_save; ifs_set "|"; parts=(${columns}); ifs_restore
    idx=0
    for p in "${parts[@]}"; do
        len=$((lengths[$idx]+2))
        s=$(printf "%${len}s+")
        divider+=$(echo -n "${s// /-}")
        idx=$((idx+1))
    done

    printf "%s\n" ${divider}

    lnum=0
    for line in "$@"; do
        IFS="|"; parts=(${line}); IFS=" "
        idx=0
        printf "|"
        for p in "${parts[@]}"; do
            pad=$((lengths[$idx]-${#p}+1))
            printf " %s%${pad}s|" "${p}" " "
            idx=$((idx+1))
        done
        printf "\n"
        lnum=$((lnum+1))
        if [[ ${lnum} -eq 1 || ${lnum} -eq $# ]]; then
            printf "%s\n" ${divider}
        else
            printf "%s\n" ${divider//+/|}
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
    local msg="$1"; argcheck msg
    local opt="$2"; argcheck opt
    local secret="$3"
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
    local msg="$1"; argcheck msg
    eprompt_with_options "${msg}" "Yes,No"
}

trim()
{
    echo "$1" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//'
}

strip()
{
    echo ${1//[[:space:]]}
}

compress_spaces()
{
    local output=$(echo -en "$@" | tr -s "[:space:]" " ")
    echo -en "${output}"
}

eend()
{
    local rc=${1:-0} #sets rc to first arg if present otherwise defaults to 0

    if [[ ${rc} -eq 0 ]]; then
        echo -e "$(ecolor blue)[$(ecolor green) ok $(ecolor blue)]$(ecolor none)" >&2
    else
        echo -e "$(ecolor blue)[$(ecolor red) !! $(ecolor blue)]$(ecolor none)" >&2
    fi
}

ekill()
{
    local pid=${1}
    local signal=${2:-TERM}
    kill -${signal} ${pid}
    wait  ${pid}
}

ekilltree()
{
    local pid=$1
    local signal=${2:-TERM}
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

        # If we're terminating just return immediately instead of resetting for next loop
        [[ ${done} -eq 1 ]] && { echo -en "\b" >&2; return; }

        echo -en "\b\b\b\b\b\b\b\b\b\b\b\b" >&2
    done
}

export __EPROGRESS_PID=-1
eprogress()
{
    [[ -n $@ ]] && einfon "$@"

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    [[ ${EPROGRESS:-1} -eq 0 ]] && return

    do_eprogress&
    __EPROGRESS_PID=$!    
}

eprogress_kill()
{
    local rc=${1:-0}
    local signal=${2:-TERM}

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    [[ ${EPROGRESS:-1} -eq 0 ]] && { eend ${rc}; return; }

    if [[ ${__EPROGRESS_PID} -ne -1 ]] ; then
        ekill ${__EPROGRESS_PID} ${signal} &>/dev/null
        __EPROGRESS_PID=-1
        eend ${rc}
    fi
}

#-----------------------------------------------------------------------------
# LOGGING
#-----------------------------------------------------------------------------

# Log a list of variable in 'tag=value' form similar to our C++ logging idiom.
# This function is variadic (takes variable number of arguments) and will log
# the tag=value for each of them. If multiple arguments are given, they will 
# be separated by a space, as in: 'tag=value tag2=value tag3=value3'
#
# The global variable LVAL_DELIM controls what delimter is used around the
# value portion. By default this is an empty string so that each value is not
# delimited. But you can set this to anything you like to more easily delimit
# the value portion. A few special symmetrical delimiters are recognized so 
# if you give one of these it will use the corresponding closing symbols:
# [ ]
# { }
# ( )
# < >
lval()
{
    # Setup delimiters
    local ldelim="${LVAL_DELIM}"
    local rdelim="${LVAL_DELIM}"
    [[ ${ldelim} == "[" ]] && rdelim="]"
    [[ ${ldelim} == "{" ]] && rdelim="}"
    [[ ${ldelim} == "(" ]] && rdelim=")"
    [[ ${ldelim} == "<" ]] && rdelim=">"

    local idx=0
    for arg in $@; do
        local val="${!arg}"
        [[ ${idx} -gt 0 ]] && echo -n " "
        echo -n "${arg}=${ldelim}${val}${rdelim}"
        idx=$((idx+1))
    done
}

# lval with [ ] delimiters
lvalbr()
{
    LVAL_DELIM="[" lval $@
}

# lval with { } delimiters
lvalcb()
{
    LVAL_DELIM="{" lval $@
}

# lval with ( ) delimiters
lvalp()
{
    LVAL_DELIM="(" lval $@
}

# lval with "" delimiters
lvalq()
{
    LVAL_DELIM='"' lval $@
}

# lval with '' delimiters
lvalsq()
{
    LVAL_DELIM="'" lval $@
}

#-----------------------------------------------------------------------------
# MISC PARSING FUNCTIONS
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

ifs_save()
{
    export IFS_SAVE=${IFS}
}

ifs_restore()
{
    export IFS=${IFS_SAVE}
}

ifs_nl()
{
    export IFS="
"
}

ifs_space()
{
    export IFS=" "
}

ifs_set()
{
    export IFS="${1}"
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

valid_ip()
{
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        ifs_save; ifs_set '.'; ip=($ip); ifs_restore
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

hostname_to_ip()
{
    local hostname=$1
    argcheck hostname

    local output hostrc ip
    output=$(host ${hostname})
    hostrc=$?
    edebug "hostname_to_ip hostname=${hostname} output=${output}"
    [[ ${hostrc} -eq 0 ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    ip=$(echo ${output} | awk '{print $4}')

    valid_ip ${ip} || { ewarn "Resolved ${hostname} into invalid ip address ${ip}." ; return 1 ; }

    echo ${ip}
    return 0
}

fully_qualify_hostname()
{
    local hostname=$1
    argcheck hostname

    local output hostrc fqhostname
    output=$(host ${hostname})
    hostrc=$?
    edebug "fully_qualify_hostname: hostname=${hostname} output=${output}"
    [[ ${hostrc} -eq 0 ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }
    fqhostname=$(echo ${output} | awk '{print $1}')

    [[ ${fqhostname} =~ ${hostname} ]] || { ewarn "Invalid fully qualified name ${fqhostname} from ${hostname}." ; return 1 ; }

    echo ${fqhostname}
    return 0
}

getipaddress()
{
    local iface=$1; argcheck 'iface'; 
    local ip=$(strip $(/sbin/ifconfig ${iface} | grep -o 'inet addr:\S*' | cut -d: -f2))
    echo -n "${ip}"
}

getnetmask()
{    local iface=$1; argcheck 'iface'; 
    local netmask=$(strip $(/sbin/ifconfig ${iface} | grep -o 'Mask:\S*' | cut -d: -f2))
    echo -n "${netmask}"
}

getbroadcast()
{
    local iface=$1; argcheck 'iface'; 
    local bcast=$(strip $(/sbin/ifconfig ${iface} | grep -o 'Bcast::\S*' | cut -d: -f2))
    echo -n "${bcast}"
}

# Gets the default gateway that is currently in use
getgateway()
{
    local gw=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
    echo -n "${gw}"
}

# Compute the subnet given the current IPAddress (ip) and Netmask (nm)
getsubnet()
{
    local ip=$1; argcheck 'ip'
    local nm=$2; argcheck 'nm'

    IFS=. read -r i1 i2 i3 i4 <<< "${ip}"
    IFS=. read -r m1 m2 m3 m4 <<< "${nm}"

    printf "%d.%d.%d.%d" "$((i1 & m1))" "$(($i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

#-----------------------------------------------------------------------------
# MISC FS HELPERS
#-----------------------------------------------------------------------------
esource()
{
    source $@ || die "Failed to source $@"
}

epushd()
{
    pushd $1 >/dev/null || die "pushd $1 failed"
}

epopd()
{
    popd $1 >/dev/null    || die "popd failed"
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
    local mode="$1"; argcheck mode
    shift
    local owner="$1"; argcheck owner
    shift

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
    local src=$1
    local dst=$2

    emkdir $dst
    ersync "${src}/" "${dst}/"
    erm ${src}
}

etouch()
{
    [[ -z "$@" ]] && die "Missing argument(s)"
    touch "$@" || die "touch $@ failed"
}

# Unmount (if mounted) and remove directory (if it exists) then create it anew
efreshdir()
{
    local mnt=${1}

    eunmount_recursive ${mnt}
    erm ${mnt}
    emkdir ${mnt}
}

# Copies the given file to *.bak if it doesn't already exist
ebackup()
{
    local src=$1

    [[ -e "${src}" && ! -e "${src}.bak" ]] && ecp "${src}" "${src}.bak"
}

erestore()
{
    local src=$1
    
    [[ -e "${src}.bak" ]] && emv "${src}.bak" "${src}"
}

etar()
{
    # Disable all tar warnings which are expected with unknown file types, sockets, etc.
    local args="--warning=none"

    # Auto detect compression program based on extension but substitutde in pbzip2 for bzip and pigz for gzip
    if [[ $(echo "$@" | egrep -- "\.bz2|\.tz2|\.tbz2|\.tbz") ]]; then
        args+=" --use-compress-program=pbzip2"
    elif [[ $(echo "$@" | egrep -- "\.gz|\.tgz|\.taz") ]]; then
        args+=" --use-compress-program=pigz"
    else
        args+=" --auto-compress"
    fi

    eprogress
    ecmd tar ${args} $@
    eprogress_kill $?
}

esed()
{
    local fname=$1; argcheck fname; shift;
    local cmd="sed -i"
    for exp in "${@}"; do
        cmd+=" -e $'${exp}'"
    done

    cmd+=" $'${fname}'"
    eval "${cmd}" || die "${cmd} failed"
}

#-----------------------------------------------------------------------------                                    
# MOUNT / UMOUNT UTILS
#-----------------------------------------------------------------------------                                    

emounted()
{
    [[ $(strip "${1}") == "" ]] && return 1
    grep --color=never --silent $(readlink -f ${1}) /proc/mounts /etc/mtab &>/dev/null && return 0
    return 1
}

# Is SOMETHING in this list mounted?
emounted_list()
{
    for m in $@; do
        emounted ${m} && return 0
    done

    return 1
}

emount()
{
    einfos "Mounting $@"
    eval "mount $@" || die "mount $@ failed"
}

eunmount()
{
    emounted_list $@ || return
    
    einfos "Unmounting ${@}"
    
    for m in $@; do
        emounted ${m} || continue
        local rdev=$(readlink -f ${m})
        eval "umount ${rdev} &>/dev/null" || eval "umount -fl ${rdev} &>/dev/null" || die "umount ${m} (${rdev}) failed"
    done
}

eunmount_recursive()
{
    emounted_list $@ || return
    
    einfo "Recursively unmounting ${@}"

    for m in $@; do
        local rdev=$(readlink -f ${m})
        ifs_save; ifs_nl
        for p in $(cat /proc/mounts /etc/mtab | grep -P "(^| )${rdev}[/ ]" | awk '{print $2}' | sort -ur); do
            edebug "Unmounting ${p}"
            eunmount ${p}
        done
        ifs_restore
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
# MISC HELPERS
#-----------------------------------------------------------------------------

# Check to ensure all the provided arguments are non-empty
argcheck()
{
    for arg in $@; do
        eval "local val=\$${arg}"
        [[ -z "${val}" ]] && die "Missing argument '${arg}'"
    done
}

# save_function is used to safe off the contents of a previously declared
# function into ${1}_real to aid in overridding a function or altering
# it's behavior.
save_function()
{
    local orig=$(declare -f $1)
    local new="${1}_real${orig#$1}"
    eval "${new}"
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
    local func=$1; argcheck func
    local body=$2; argcheck body

    ## Don't save the function off it already exists to avoid infinite recursion
    declare -f "${func}_real" >/dev/null || save_function ${func}
    eval "$func() ${body}"
    eval "declare -rf ${func}"
}

ecmd()
{
    local cmd="$@"
    eval "${cmd}" || die "Failed to execute [$cmd]"
}

ecmd_try()
{
    local cmd="$@"
    eval "${cmd}" || { rc=$?; ewarn "Failed to execute [$cmd]"; return $rc; }
}

numcores()
{
    [[ -e /proc/cpuinfo ]] || die "/proc/cpuinfo does not exist"

    echo $(cat /proc/cpuinfo | grep "processor" | wc -l)
}

efetch_try()
{
    local url="${1}"
    local dst="${2}"; [[ -z ${dst} ]] && dst="."
    argcheck url dst
    [[ -d ${dst} ]] && dst+="/$(basename ${url})"

    eprogress "Fetching $(lvalbr url dst)"
    
    local timecond=""
    [[ -f ${dst} ]] && timecond="--time-cond ${dst}"

    curl "${url}" ${timecond} --output "${dst}" --location --fail --silent --show-error
    local rc=$?
    eprogress_kill $rc
    [[ ${rc} -eq 0 ]] || { eerror "Failed to fetch $(lvalbr url)"; return $rc; }

    return 0
}

efetch()
{
    efetch_try $@ || die
}

efetch_with_md5_try()
{
    local rc=0
    local url="${1}"
    local dst="${2}"; [[ -z ${dst} ]] && dst="."
    argcheck url dst
    [[ -d ${dst} ]] && dst+="/$(basename ${url})"
    local md5="${dst}.md5"

    # Fetch the md5 before the payload as we don't need to bother fetching payload if md5 is missing
    efetch_try "${url}.md5" "${md5}" && efetch_try "${url}" "${dst}" || rc=1

    ## Verify MD5 -- DELETE any corrupted images
    if [[ ${rc} -eq 0 ]]; then
        einfos "Verifying MD5 $(lvalbr dst md5)"
        epushd $(dirname ${dst})
        
        # If the requested destination was different than what was originally in the MD5 it will fail.
        # Or if the md5sum file was generated with a different path in it it will fail. This just
        # sanititizes it to have the current working directory and the name of the file we downloaded to.
        md5_raw=$(grep -v "#" "${md5}" | awk '{print $1}')
        echo "${md5_raw} $(basename ${dst})" > "${md5}"
        
        # Now we can perform the check
        md5sum --check $(basename ${md5}) >/dev/null
        rc=$?
        epopd
    fi

    if [[ ${rc} -ne 0 ]]; then
        edebug "Removing $(lvalbr dst md5)"
        erm "${dst}"
        erm "${md5}"
    fi  

    [[ ${rc} -eq 0 ]] || return $rc

    einfos "Successfully downloaded $(lvalbr url dst)"

    return 0
}

efetch_with_md5()
{
    efetch_with_md5_try $@ || die
}

netselect()
{
    local hosts=$@; argcheck hosts
    eprogress "Finding host with lowest latency from [${hosts}]"

    declare -a results;

    for h in ${hosts}; do
        local entry=$(trap_and_die; ping -c10 -w5 -q $h 2>/dev/null | \
            awk '/^PING / {host=$2}
                 /packet loss/ {loss=$6}
                 /min\/avg\/max/ {
                    split($4,stats,"/")
                    printf("%s|%f|%f|%s|%f", host, stats[2], stats[4], loss, (stats[2] * stats[4]) * (loss + 1))
                }')

        results=("${results[@]}" "${entry}")
    done

    declare -a sorted=($(printf '%s\n' "${results[@]}" | sort -t\| -k5 -n))
    declare -a rows=("Server|Latency|Jitter|Loss|Score")
    ifs_save; ifs_set "|";
    while read server latency jitter loss score; do
        rows=("${rows[@]}" "${server}|${latency}|${jitter}|${loss}|${score}")
    done << EOF
${sorted[@]}
EOF
    ifs_restore
    eprogress_kill

    ## SHOW ALL RESULTS ##
    einfos "All results:"
    etable ${rows[@]} >&2

    local best=$(echo "${sorted[0]}" | cut -d\| -f1)
    einfos "Best host=[${best}]"

    echo -en "${best}"
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
