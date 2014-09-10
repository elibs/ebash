#!/bin/bash
# 
# Copyright 2011-2013, SolidFire, Inc. All rights reserved.
#

# Automatically export all functions/variables
set -a

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

DIE_IN_PROGRESS=0

die()
{
    [[ ${DIE_IN_PROGRESS} -eq 1 ]] && exit 1
    DIE_IN_PROGRESS=1

    echo ""
    eerror "$@"

    IFS="
"
    local frames=( $(stacktrace) )

    for f in ${frames[@]}; do
        local line=$(echo ${f} | awk '{print $1}')
        local func=$(echo ${f} | awk '{print $2}')
        local file=$(basename $(echo ${f} | awk '{print $3}'))

        [[ ${file} == "efuncs.sh" && ${func} == "die" ]] && break
        
        printf "$(ecolor red)   :: %-20s | ${func}$(ecolor none)\n" "${file}:${line}" >&2
    done

    ifs_restore
    [[ ${EFUNCS_FATAL:=1} == 1 ]] && { trap - EXIT ;  kill 0 ; }
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

# Default trap
trap_add 'die [killed]' HUP INT QUIT BUS PIPE TERM

#-----------------------------------------------------------------------------
# FANCY I/O ROUTINES
#-----------------------------------------------------------------------------

## If EFUNCS_COLOR is empty then set it based on if stdout is a terminal or not ##
[[ -t 1 ]] && INTERACTIVE=1 || INTERACTIVE=0

tput()
{
    TERM=${TERM:-xterm} /usr/bin/tput $@
}

ecolor()
{
    [[ -z ${EFUNCS_COLOR} && ${INTERACTIVE} -eq 1 ]] && EFUNCS_COLOR=1
    [[ ${EFUNCS_COLOR} -eq 1 ]] || return 0

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

einfo_prefix()
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
    echo -e "$(ecolor green)$(einfo_prefix)$@ $(ecolor none)" >&2
}

einfon()
{
    echo -en "$(ecolor green)$(einfo_prefix)$@ $(ecolor none)" >&2
}

einfos()
{
    echo -e "$(ecolor cyan)   >> $@ $(ecolor none)" >&2
}

ewarn()
{
    echo -e "$(ecolor yellow) * $@ $(ecolor none)" >&2
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

eprompt_timeout()
{
    local timeout=$1 ; shift; [[ -z "${timeout}" ]] && die "Missing timeout value"
    local default=$1 ; shift; [[ -z "${default}" ]] && die "Missing default value"
    
    echo -en "$(ecolor white) * $@: $(ecolor none)" >&2
    local result=""

    read result -t ${timeout} < /dev/stdin || result="${default}"
    
    echo -en "${result}"
}

epromptyn()
{
    while true; do
        response=$(eprompt "$@ (Y/N)" | tr '[:lower:]' '[:upper:]')
        if [[ ${response} == "Y" || ${response} == "N" ]]; then
            echo -en "${response}"
            return
        fi

        eerror "Invalid response ($response) -- please enter Y or N"
    done
}

epromptyn_timeout()
{
    local timeout=$1 ; shift; [[ -z "${timeout}" ]] && die "Missing timeout value"
    local default=$1 ; shift; [[ -z "${default}" ]] && die "Missing default value"

    while true; do
        local response=$(eprompt_timeout "${timeout}" "${default}" "$@ (Y/N)" | tr '[:lower:]' '[:upper:]')
        if [[ ${response} == "Y" || ${response} == "N" ]]; then
            echo -en "${response}"
            return
        fi

        eerror "Invalid response ($response) -- please enter Y or N"
    done
}

trim()
{
    echo "$1" | sed 's|^[ \t]\+||'
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

    if [[ "${rc}" == "0" ]]; then
        echo -e "$(ecolor blue)[$(ecolor green) ok $(ecolor blue)]$(ecolor none)" >&2
    else
        echo -e "$(ecolor blue)[$(ecolor red) !! $(ecolor blue)]$(ecolor none)" >&2
    fi
}

ekill()
{
    kill ${1} >/dev/null 2>&1 || die "Failed to kill ${1}"
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

    local start=$(date +"%s")
    while true; do 
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

        echo -n -e "\b\b\b\b\b\b\b\b\b\b\b\b" >&2
    done
}

__EPROGRESS_PID=-1
eprogress()
{
    einfon "$@"
    do_eprogress&
    __EPROGRESS_PID=$!    
}

eprogress_kill()
{
    local rc="${1}"; [[ -z "${rc}" ]] && rc="0"
    if (( ${__EPROGRESS_PID} != -1 )) ; then
        ekill ${__EPROGRESS_PID} &>/dev/null
        wait  ${__EPROGRESS_PID} &>/dev/null
        __EPROGRESS_PID=-1
        eend ${rc}
    fi
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
    # Auto detect compression program based on extension but substitutde in pbzip2 for bzip and pigz for gzip
    local args="--checkpoint=1000 --checkpoint-action=dot"

    if [[ $(echo "$@" | egrep -- "\.bz2|\.tz2|\.tbz2|\.tbz") ]]; then
        args+=" --use-compress-program=pbzip2"
    elif [[ $(echo "$@" | egrep -- "\.gz|\.tgz|\.taz") ]]; then
        args+=" --use-compress-program=pigz"
    else
        args+=" --auto-compress"
    fi

    eval "tar ${args} $@" || die "[tar ${args} $@] failed"
    
    eend
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
        for p in $(cat /proc/mounts /etc/mtab | grep -P "(^| )${rdev}" | awk '{print $2}' | sort -ur); do
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

# Check to ensure an argument is non-zero
argcheck()
{
    local tag=$1 ; [[ -z "${tag}" ]] && die "Missing argument 'tag'"
    eval "local val=\$${tag}"
    [[ -z "${val}" ]] && die "Missing argument '${tag}'"
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
override_function()
{
    local func=$1; shift; argcheck func
    local body=$2; shift; argcheck body

    save_function ${func}; shift
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

etouch()
{
    ecmd "touch $@"
}

numcores()
{
    [[ -e /proc/cpuinfo ]] || die "/proc/cpuinfo does not exist"

    echo $(cat /proc/cpuinfo | grep "processor" | wc -l)
}

efetch_try()
{
    local dest=~/Downloads
    [[ ! -e ${dest} ]] && dest=/tmp
    dest+="/$(basename ${1})"

    eprogress "Fetching [${1}] to [${dest}]"
    
    local timecond=""
    [[ -f ${dest} ]] && timecond="--time-cond ${dest}"

    curl "${1}" ${timecond} --output "${dest}" --location --fail --silent --show-error
    local rc=$?
    eprogress_kill $rc
    [[ ${rc} -eq 0 ]] || { ewarn "Failed to fetch [${1}]"; return $rc; }

    echo -n "${dest}"
}

efetch()
{
    local fetched=""
    fetched=$(efetch_try $1) || die "Failed to fetch [${1}]"
    echo -n "${fetched}"
}

efetch_with_md5_try()
{
    local url="${1}"; argcheck url

    # Do not do both the declaration and assignment at same time or we fail to detect errors properly
    local rc=0
    local md5=""
    local img=""
    
    # Fetch the md5 before the payload as we don't need to bother fetching payload if md5 is missing
    md5=$(efetch_try "${url}.md5") && img=$(efetch_try "${url}") || rc=1

    ## Verify MD5 -- DELETE any corrupted images
    if [[ ${rc} -eq 0 ]]; then
        argcheck img; argcheck md5

        einfos "Verifying MD5 of [${img}] against [${md5}]"
        epushd $(dirname ${img})
        md5sum --check ${md5} >/dev/null
        rc=$?
        epopd
    fi

    if [[ ${rc} -ne 0 ]]; then
        ewarns "Removing ${md5} and ${img}"
        [[ -n "${md5}" ]] && erm "${md5}" && md5=""
        [[ -n "${img}" ]] && erm "${img}" && img=""
    fi  

    [[ ${rc} -eq 0 ]] || return $rc

    einfos "Successfully downloaded [${img}]"
    echo -n "${img}"
}

efetch_with_md5()
{
    local fetched=""
    fetched=$(efetch_with_md5_try $1) || die "Failed to fetch [${1}] with md5"
    echo -n "${fetched}"
}

enslookup()
{
    [[ $(nslookup -fail $1 | grep SERVFAIL | wc -l) ]] && echo -en "${1}" || echo -en "${2}"
}

netselect()
{
    local hosts=$@; argcheck hosts
    eprogress "Finding host with lowest latency from [${hosts}]"

    declare -a results;

    for h in ${hosts}; do
        local entry=$(ping -c10 -w5 -q $h 2>/dev/null | \
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
