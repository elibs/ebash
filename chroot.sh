#!/bin/bash
# 
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# PULL IN DEPENDENT PACKAGES
#-----------------------------------------------------------------------------
source "${BASHUTILS}/efuncs.sh"   || { echo "Failed to find efuncs.sh" ; exit 1; }
$(esource ${BASHUTILS}/dpkg.sh)

#-----------------------------------------------------------------------------                                    
# CORE CHROOT FUNCTIONS
#-----------------------------------------------------------------------------                                    
CHROOT_MOUNTS=( /dev /dev/pts /proc /sys )

chroot_mount()
{
    argcheck CHROOT
    einfo "Mounting $(lval CHROOT CHROOT_MOUNTS)"

    for m in ${CHROOT_MOUNTS[@]}; do 
        emkdir ${CHROOT}${m}
        ebindmount ${m} ${CHROOT}${m}
    done

    ecmd grep -v rootfs "${CHROOT}/proc/mounts" | sort -u > "${CHROOT}/etc/mtab"
}

chroot_unmount()
{
    argcheck CHROOT
    einfo "Unmounting $(lval CHROOT CHROOT_MOUNTS)"
   
    local mounts=()
    array_init_nl mounts "$(echo ${CHROOT_MOUNTS[@]} | sed 's| |\n|g' | sort -r)"
    for m in ${mounts[@]}; do
        eunmount ${CHROOT}${m}
    done
}

chroot_prompt()
{
    $(declare_args ?name)
    argcheck CHROOT

    # If no name given use basename of CHROOT
    : ${name:=CHROOT-$(basename ${CHROOT})}

    # Determine what shell to generate chroot prompt for
    local shell="$(opt_get s)"
    : ${shell:=${SHELL}}
    local shellrc="${HOME}/.$(basename ${shell})rc"
    local shellrc_prompt="${shellrc}.prompt"

    # Check if already sourcing promptrc
    grep -q "${shellrc_prompt}" ${CHROOT}${shellrc} && { edebug "Already sourcing promptrc in ${shellrc}"; return 0; }

    edebug "Creating chroot_prompt $(lval shell shellrc shellrc_prompt)"

    # ZSH just HAS to be different
    if [[ ${shell} =~ zsh ]]; then
        echo "prompt off"
        echo "PS1=\"%F{green}%n@%M %F{blue}%d%f\\n\$ \""
        echo "PS1=\"%F{red}[${name}]%f \$PS1\""
    else
        echo "PS1=\"\[$(ecolor green)\]\u@\h \[$(ecolor blue)\]\w$(ecolor none)\\n\$ \""
        echo "PS1=\"\[$(ecolor red)\][${name}] \$PS1\""
    fi > ${CHROOT}${shellrc_prompt}

    echo ". ${shellrc_prompt}" >> ${CHROOT}${shellrc}
}

chroot_shell()
{
    $(declare_args ?name)
    argcheck CHROOT

    # Setup CHROOT prompt
    chroot_prompt ${name}

    # Mount then enter chroot. Do it all in a subshell so that we ensure we properly
    # unmount when we're finished.
    ( chroot_mount && chroot ${CHROOT} ${CHROOT_ENV}; chroot_unmount; )
}

chroot_cmd()
{
    argcheck CHROOT
    
    einfos $@
    chroot ${CHROOT} ${CHROOT_ENV} -c "$*"
    [[ $? -eq 0 ]] || die "Failed to execute [$*]"
}

chroot_cmd_try()
{
    argcheck CHROOT
    
    einfos $@
    chroot ${CHROOT} ${CHROOT_ENV} -c "$*"
    [[ $? -eq 0 ]] || ewarns "Failed to execute [$*]"
}

# Send a signal to processes inside _this_ CHROOT (designated by ${CHROOT})
# that match the given regex.  [note: regex support is identical to pgrep]
#
#    $1: Optional pgrep pattern that match the processes you'd like to signal.
#        If no pattern is specified, ALL proceses in the chroot will be
#        signalled.
#    $2: Optional signal name or number.  Defaults to SIGKILL(9)
# 
chroot_kill()
{
    argcheck CHROOT

    local pids signal

    signal=${2:-KILL}

    [[ -n $1 ]] && { pids=$(pgrep "${1}") ; edebug "Sending signal ${signal} to chroot processes matching \"${1}\"." ; }
    [[ -z $1 ]] && { pids=$(ps -eo "%p")  ; edebug "Sending signal ${signal} to all chroot processes." ; }

    for pid in ${pids}; do
        local link=$(readlink "/proc/${pid}/root")
        
        # Skip processes started in NO chroot or ANOTHER chroot
        [[ -z ${link} || ${link} != ${CHROOT} ]] && continue

        # Kill this process
        einfos "Killing ${pid} [$(ps -p ${pid} -o comm=)]"
        ekilltree ${pid} ${signal}
    done
}

# Cleanly exit a chroot by:
# (1) Kill any processes started inside chroot (chroot_kill)
# (1) Unmount chroot bind mounted directories  (chroot_unmount)
# (2) Recursively unmount anything else mounted beneath the chroot
chroot_exit()
{
    chroot_kill
    chroot_unmount
    eunmount_recursive ${CHROOT}
    erm ${CHROOT}/etc/mtab
}

#-----------------------------------------------------------------------------                                    
# APT-CHROOT FUNCTIONS
#-----------------------------------------------------------------------------                                    

## APT SETTINGS ##
CHROOT_APT="aptitude -f -y"
CHROOT_ENV="/usr/bin/env USER=root SUDO_USER=root HOME=/root DEBIAN_FRONTEND=noninteractive /bin/bash"

chroot_apt_update()
{
    chroot_cmd apt-get update >/dev/null
}

chroot_apt_clean()
{
    chroot_cmd apt-get clean >/dev/null
    chroot_cmd apt-get autoclean >/dev/null
}

chroot_install_with_apt_get()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "Installing $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "apt-get -f -qq -y --force-yes install $*"
    [[ $? -eq 0 ]] || die "Failed to install [$*]"
}

# Check if all the packages listed can be installed
chroot_install_check()
{
    # BUG: https://bugs.launchpad.net/ubuntu/+source/aptitude/+bug/919216
    # 'aptitude install' silently fails with success if a bogus package is given whereas 'aptitude show'
    # gives back a proper error code. So first do a check with aptitude show first.
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} show $(echo $* | sed -e 's/\(>=\|<=\)/=/g')" >/dev/null || return 1
}

# Internal chroot_install method which will do a post-install check to ensure the package was installed
chroot_install_internal()
{
    # Check if all packages are installable
    chroot_install_check $* || return 1
    
    # Do actual install
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} install $(echo $* | sed -e 's/\(>=\|<=\)/=/g')" || return 1

    # Post-install validation because ubuntu is entirely stupid and apt-get and aptitude can return
    # success even though the package is not installed successfully
    for p in $@; do
        
        local pn=${p}
        local pv=""
        local op=""

        if [[ ${p} =~ ([^>=<>]*)(>=|<=|<<|>>|=)(.*) ]]; then
            pn="${BASH_REMATCH[1]}"
            op="${BASH_REMATCH[2]}"
            pv="${BASH_REMATCH[3]}"
        fi

        # Actually installed
        local actual=$(trap_and_die; chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg-query -W -f='\${Package}|\${Version}' ${pn}" || { ewarn "Failed to install [${pn}]"; return 1; })
        local apn="${actual}"; apn=${apn%|*}
        local apv="${actual}"; apv=${apv#*|}
        
        [[ ${pn} == ${apn} ]] || { ewarn "Mismatched package name wanted=[${pn}] actual=[${apn}]"; return 1; }
    
        ## No explicit version check -- continue
        [[ -z "${op}" || -z "${pv}" ]] && continue

        dpkg_compare_versions "${apv}" "${op}" "${pv}" || { ewarn "Version mismatch: wanted=[${pn}-${pv}] actual=[${apn}-${apv}] op=[${op}]"; return 1; }
    
    done

    return 0
}

chroot_install()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "Installing $@"

    chroot_install_check $*    || die "Failed to resolve requested package list"
    chroot_install_internal $* || die "Failed to install [$@]"
}

chroot_install_try()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return

    einfos "Installing $@"
   
    chroot_install_check $@    || { ewarns "Failed to resolve [$@]"; return 1; }
    chroot_install_internal $@ || { ewarns "Failed to install [$@]"; return 1; } 
}

chroot_install_retry()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "Installing $@"

    chroot_install_check $* || die "Failed to resolve requested package list"

    # Try to install up to 5 times. This deals with unconfigured packages that can only be fully installed
    # on a second installation. 
    local max=5
    for (( i=0; i<${max}; ++i )); do
        chroot_install_internal $* \
            && { [[ $i > 0 ]] && ewarns "Successfully installed packages (tries=${i}/${max})"; return; }
        ewarns "Failed to install packages (tries=${i}/${max}) -- retrying..."
    done

    die "Failed to install [$@]"
}

chroot_uninstall()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "Uninstalling $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} remove --purge $*" || die "Failed to remove [$*]"
}

chroot_dpkg()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "dpkg $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg $*" || die "Failed to run dpkg [$*]"
}

chroot_apt()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "${CHROOT_APT} $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} $*" || die "Failed to run apt-get [$*]"
}

chroot_apt_try()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return
    
    einfos "${CHROOT_APT} $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} $*" || ewarns "Failed to run apt-get [$*]"
}

chroot_listpkgs()
{
    argcheck CHROOT
    output=$(trap_and_die; chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg-query -W") || die "Failed to execute [$*]"
    echo -en "${output}"
}

chroot_uninstall_filter()
{
    argcheck CHROOT
    local filter=$@
    pkgs=$(trap_and_die; chroot_listpkgs)
    chroot_uninstall $(eval "echo \"${pkgs}\" | ${filter} | awk '{print \$1}'")
}

chroot_apt_setup()
{
    $(declare_args CHROOT UBUNTU_RELEASE RELEASE HOST UBUNTU_ARCH)

    ## Set up DPKG options so we don't get prompted for anything
    einfo "Setting up dpkg.cfg"
    echo 'force-confdef'          > ${CHROOT}/etc/dpkg/dpkg.cfg
    echo 'force-confold'         >> ${CHROOT}/etc/dpkg/dpkg.cfg
    echo 'no-debsig'             >> ${CHROOT}/etc/dpkg/dpkg.cfg
    echo 'log /var/log/dpkg.log' >> ${CHROOT}/etc/dpkg/dpkg.cfg

    einfo "Setting up sources.list"
	cat > "${CHROOT}/etc/apt/sources.list" <<-EOF
	deb [arch=${UBUNTU_ARCH}] http://${HOST}/${RELEASE}/ubuntu/ ${UBUNTU_RELEASE} main restricted universe multiverse
	deb [arch=${UBUNTU_ARCH}] http://${HOST}/${RELEASE}/ubuntu/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse
	deb [arch=${UBUNTU_ARCH}] http://${HOST}/${RELEASE}/security-ubuntu ${UBUNTU_RELEASE}-security main restricted universe multiverse
	EOF

    ## APT Update
    ## In case a prior run failed let's clean up any prior dpkg and apt-get failures
    einfo "Initial configure/update"
    chroot_dpkg --configure -a
    chroot_cmd apt-get -f -y --force-yes install
    chroot_apt_update
    
    # Install Aptitude since we use that for everything in chroot
    einfo "Installing minimial package set"
    chroot_install_with_apt_get apt aptitude
    chroot_install curl vim wget

    # Install keys
    einfo "Adding trusted keys"
    for keyname in solidfire_signing_key.pub dell_openmanage_key.pub gcc_ppa_repo.pub; do
        einfos ${keyname}

        chroot_cmd wget -q http://${HOST}/${keyname} -O /tmp/${keyname} &>/dev/null
        chroot_cmd apt-key add /tmp/${keyname}                          &>/dev/null
        chroot_cmd rm -f /tmp/${keyname}                                &>/dev/null
    done

    # Add SolidFire entries after adding SolidFire APT public keys then
    einfo "Updating sources.list"
	cat >> "${CHROOT}/etc/apt/sources.list" <<-EOF
	deb [arch=${UBUNTU_ARCH}] http://${HOST}/solidfire ${UBUNTU_RELEASE} main
	deb [arch=${UBUNTU_ARCH}] http://${HOST}/omsa/repo/ /
	EOF

    # In case any packages didn't fully install (APT...)
    einfo "Final configure/update"
    chroot_dpkg --configure -a
    chroot_cmd apt-get -f -y --force-yes install
    chroot_apt_update
}

chroot_setup()
{
    ## Mount chroot and run all commands in subshell in case anything fails
    ## Also note the arguments are NOT local variables as want any functions call 
    ## Below to use these settings.
    (

    $(declare_args CHROOT UBUNTU_RELEASE RELEASE HOST UBUNTU_ARCH)

    [[ ${NOBANNER} -eq 1 ]] || ebanner "Setting up chroot [${CHROOT}]"
   
    # Because of how we mount things while building up our chroot sometimes
    # /etc/resolv.conf will be bind mounted into ${CHROOT}. When that happens
    # calling 'cp' will fail b/c they refer to the same inodes. So we need
    # to explicitly check for that here.
    local src="/etc/resolv.conf"
    local dst="${CHROOT}/etc/resolv.conf"
    [[ "$(stat --format=%d.%i ${src})" != "$(stat --format=%d.%i ${dst})" ]] && ecp ${src} ${dst}

    ## MOUNT
    chroot_mount

    ## LOCALES/TIMEZONE
    einfo "Configuring locale and timezone"
    local LANG="en_US.UTF-8"
    local TZ="Etc/UTC"
    echo "LANG=\"${LANG}\"" > "${CHROOT}/etc/default/locale" || die "Failed to set /etc/default/locale"
    chroot_cmd locale-gen ${LANG}
    chroot_cmd /usr/sbin/update-locale
    echo "${TZ}" > "${CHROOT}/etc/timezone"                  || die "Failed to set /etc/timezone"
    chroot_install_with_apt_get tzdata
    chroot_cmd dpkg-reconfigure tzdata
    
    ## SETUP
    chroot_apt_setup ${CHROOT} ${UBUNTU_RELEASE} ${RELEASE} ${HOST} ${UBUNTU_ARCH}

    ## CLEANUP
    chroot_apt_clean
    chroot_unmount

    [[ ${NOBANNER} -eq 1 ]] || ebanner "Finished setting up chroot [${CHROOT}]"
    echo ""

    ) || { chroot_unmount; die "chroot_setup failed"; }
}

#-----------------------------------------------------------------------------
# CHROOT_DAEMON FUCNTIONS
#-----------------------------------------------------------------------------

chroot_daemon_start()
{
    # Parse required arguments. Any remaining options will be passed to the daemon.
    $(declare_args exe)
    argcheck CHROOT

    # Determine pretty name to display from optional -n
    local name="$(opt_get n)"
    : ${name:=$(basename ${exe})}

    # Determmine optional pidfile
    local pidfile="$(opt_get p)"
    : ${pidfile:=/var/run/$(basename ${exe})}

    ## Info
    einfo "Starting ${name}"
    edebug "Starting $(lval CHROOT name exe pidfile) args=${@}"

    # Construct a subprocess which bind mounds chroot mount points then executes
    # requested daemon. After the daemon complets automatically unmount chroot.
    ( chroot_mount && chroot_cmd_try ${exe} "${@}"; chroot_unmount ) &>$(edebug_out) &

    # Get the PID of the process we just created and store into requested pid file.
    local pid=$!
    emkdir $(dirname ${pidfile})
    echo "${pid}" > "${pidfile}"

    # Give the daemon a second to startup and then check its status. If it blows
    # up immediately we'll catch the error immediately and be able to let the
    # caller know that startup failed.
    sleep 1
    chroot_daemon_status -n="${name}" -p="${pidfile}" &>$(edebug_out) \
        || die "Failed to start chroot daemon $(lval name exe pidfile)"
   
    eend 0
    return 0
}

chroot_daemon_stop()
{
    # Parse required arguments.
    $(declare_args exe)
    argcheck CHROOT

    # Determine pretty name to display from optional -n
    local name="$(opt_get n)"
    : ${name:=$(basename ${exe})}

    # Determmine optional pidfile
    local pidfile="$(opt_get p)"
    : ${pidfile:=/var/run/$(basename ${exe})}

    # Determine optional signal to use
    local signal="$(opt_get s)"
    : ${signal:=TERM}

    # Info
    einfo "Stopping ${name}"
    edebug "Stopping $(lval CHROOT name exe pidfile signal)"

    # If it's not running just return (with failure)
    chroot_daemon_status -n="${name}" -p="${pidfile}" &>$(edebug_out) \
        || { eend 1; ewarns "Already stopped"; eend 1; return 0; }

    # If it is running stop it with optional signal
    local pid=$(cat ${pidfile} 2>/dev/null)
    ekilltree ${pid} ${signal}
    erm ${pidfile}
    eend 0
}

chroot_daemon_status()
{
    # Parse required arguments
    $(declare_args)
    argcheck CHROOT

    # pidfile is required
    local pidfile=$(opt_get p)
    argcheck pidfile

    # Determine pretty name to display from optional -n
    local name=$(opt_get n)
    : ${name:=$(basename ${pidfile})}

    einfo "Checking ${name}"
    edebug "Checking $(lval CHROOT name pidfile)"

    # Check pidfile
    [[ -e ${pidfile} ]] || { eend 1; ewarns "Not Running (no pidfile)"; return 1; }
    local pid=$(cat ${pidfile} 2>/dev/null)
    [[ -z ${pid}     ]] && { eend 1; ewarns "Not Running (no pid)"; return 1; } 
   
    # Send a signal to process to see if it's running
    kill -0 ${pid} &>/dev/null || { eend 1; ewarns "Not Running"; return 1; }

    # OK -- It's running
    eend 0
    return 0
}

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
# MKCHROOT
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
mkchroot()
{
    $(declare_args CHROOT UBUNTU_RELEASE RELEASE HOST UBUNTU_ARCH)
    ebanner "Making chroot" CHROOT UBUNTU_RELEASE RELEASE HOST UBUNTU_ARCH

    ## Make sure that debootstrap is installed
    which debootstrap > /dev/null || die "debootstrap must be installed"

    ## Setup chroot
    emkdir ${CHROOT}

    #-----------------------------------------------------------------------------                                    
    # DEBOOTSTRAP IMAGE
    #-----------------------------------------------------------------------------                                    
    local CHROOT_IMAGE="chroot_${UBUNTU_RELEASE}.tgz"
    einfo "Creating $(lval CHROOT UBUNTU_RELEASE RELEASE HOST UBUNTU_ARCH)"

    local LSB_RELEASE=$(cat /etc/lsb-release | grep "CODENAME" | awk -F= '{print $2}')
    local GPG_FLAG="--no-check-gpg"
    [[ ${LSB_RELEASE} == "lucid" ]] && GPG_FLAG=""

    # Try to download to /var/distbox/downloads if it exists. If it doesn't then fallback to /tmp
    local dst="/tmp"
    [[ -d "/var/distbox" ]] && dst="/var/distbox/downloads"
    emkdir "${dst}"

    efetch_with_md5_try "http://${HOST}/images/${CHROOT_IMAGE}" "${dst}/${CHROOT_IMAGE}"
    if [[ $? -eq 0 ]]; then
        debootstrap ${GPG_FLAG} --arch ${UBUNTU_ARCH} --unpack-tarball="${dst}/${CHROOT_IMAGE}" ${UBUNTU_RELEASE} ${CHROOT} http://${HOST}/${RELEASE}-ubuntu
    else
        debootstrap ${GPG_FLAG} --arch ${UBUNTU_ARCH} ${UBUNTU_RELEASE} ${CHROOT} http://${HOST}/${RELEASE}-ubuntu
    fi

    #-----------------------------------------------------------------------------        
    # MODIFY CHROOT IMAGE
    #-----------------------------------------------------------------------------
    NOBANNER=1 chroot_setup ${CHROOT} ${UBUNTU_RELEASE} ${RELEASE} ${HOST} ${UBUNTU_ARCH}

    ebanner "Finished making chroot [${CHROOT}]"
    echo ""
    
    # DONE
    return 0
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
