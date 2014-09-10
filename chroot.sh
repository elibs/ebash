#!/bin/bash
# 
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# PULL IN DEPENDENT PACKAGES
#-----------------------------------------------------------------------------
source "${BASHUTILS_PATH}/efuncs.sh"   || { echo "Failed to find efuncs.sh" ; exit 1; }
source "${BASHUTILS_PATH}/dpkg.sh"     || die "Failed to source dpkg.sh"

#-----------------------------------------------------------------------------                                    
# CORE CHROOT FUNCTIONS
#-----------------------------------------------------------------------------                                    
CHROOT_MOUNTS="/dev /dev/pts /proc /sys"

chroot_mount()
{
    argcheck CHROOT

    local first=1
 
    for m in ${CHROOT_MOUNTS}; do 
        emounted "${CHROOT}${m}" && continue

        [[ ${first} -eq 1 ]] && { einfo "Mounting chroot [${CHROOT}]"; first=0; }
        emkdir ${CHROOT}${m}
        emount --bind ${m} ${CHROOT}${m}
    done

    ecmd "grep -v rootfs ${CHROOT}/proc/mounts | sort -u > ${CHROOT}/etc/mtab"
}

chroot_unmount()
{
    argcheck CHROOT
    local first=1

    ifs_save; ifs_nl
    for m in $(echo ${CHROOT_MOUNTS} | sed 's| |\n|g' | sort -r); do
        emounted "${CHROOT}${m}" || continue

        [[ ${first} -eq 1 ]] && { einfo "Unmounting chroot [${CHROOT}]"; first=0; }
        eunmount ${CHROOT}${m}
    done
    ifs_restore

    erm ${CHROOT}/etc/mtab
}

chroot_shell()
{
    argcheck CHROOT
    
    chroot ${CHROOT} ${CHROOT_ENV}
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

# Kill provided list of PID inside the CHROOT. This function checks the given PIDs 
# to ensure they were actually started inside the CHROOT and will skip them if not.
# If NO PIDs are provided, this will ==> KILL ALL PROCESS <== started inside the CHROOT.
chroot_kill()
{
    argcheck CHROOT

    einfo "Killing chroot [${CHROOT}] PIDS=[$*]"

    local pids="$*"
    [[ $# -eq 0 ]] && { ewarns "No pids provided -- killing all chroot processes"; pids=$(ps -eo "%p"); }

    for pid in ${pids}; do
        local link=$(readlink "/proc/${pid}/root")
        
        # Skip processes started in NO chroot or ANOTHER chroot
        [[ -z ${link} || ${link} != ${CHROOT} ]] && continue

        # Kill this process
        einfos "Killing ${pid} [$(ps -p ${pid} -o comm=)]"
        kill -9 ${pid} 
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
    [[ $(strip "$@") == "" ]] && return
    
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
		local actual=$(chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg-query -W -f='\${Package}|\${Version}' ${pn}" || { ewarn "Failed to install [${pn}]"; return 1; })
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
    [[ $(strip "$@") == "" ]] && return
    
    einfos "Installing $@"

    chroot_install_check $*    || die "Failed to resolve requested package list"
    chroot_install_internal $* || die "Failed to install [$@]"
}

chroot_install_try()
{
    argcheck CHROOT
    [[ $(strip "$@") == "" ]] && return

    einfos "Installing $@"
   
    chroot_install_check $@    || { ewarns "Failed to resolve [$@]"; return 1; }
    chroot_install_internal $@ || { ewarns "Failed to install [$@]"; return 1; } 
}

chroot_install_retry()
{
    argcheck CHROOT
    [[ $(strip "$@") == "" ]] && return
    
    einfos "Installing $@"

    chroot_install_check $* || die "Failed to resolve requested package list"

    # Try to install up to 5 times. This deals with unconfigured packages that can only be fully installed
    # on a second installation. 
    local max=5
    for (( i=0; i<${max}; ++i )); do
        chroot_install_internal $* \
            && { [[ $i > 0 ]] && ewarns "Successfully installed packages (tries=${i}/${max})"; return; }
        eerror "Failed to install packages (tries=${i}/${max}) -- retrying..."
    done

    die "Failed to install [$@]"
}

chroot_uninstall()
{
    argcheck CHROOT
    [[ $(strip "$@") == "" ]] && return
    
    einfos "Uninstalling $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} remove --purge $*" || die "Failed to remove [$*]"
}

chroot_dpkg()
{
    argcheck CHROOT
    [[ $(strip "$@") == "" ]] && return
    
    einfos "dpkg $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg $*" || die "Failed to run dpkg [$*]"
}

chroot_apt()
{
    argcheck CHROOT
    [[ $(strip "$@") == "" ]] && return
    
    einfos "${CHROOT_APT} $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} $*" || die "Failed to run apt-get [$*]"
}

chroot_apt_try()
{
    argcheck CHROOT
    [[ $(strip "$@") == "" ]] && return
    
    einfos "${CHROOT_APT} $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} $*" || ewarns "Failed to run apt-get [$*]"
}

chroot_listpkgs()
{
    argcheck CHROOT
    output=$(chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg-query -W") || die "Failed to execute [$*]"
    echo -en "${output}"
}

chroot_uninstall_filter()
{
    argcheck CHROOT
    local filter=$@
    pkgs=$(chroot_listpkgs)
    chroot_uninstall $(eval "echo \"${pkgs}\" | ${filter} | awk '{print \$1}'")
}

chroot_apt_setup()
{
    local CHROOT=$1;         argcheck CHROOT
    local UBUNTU_RELEASE=$2; argcheck UBUNTU_RELEASE
    local RELEASE=$3;        argcheck RELEASE
    local HOST=$4;           argcheck HOST
    local UBUNTU_ARCH=$5;    argcheck UBUNTU_ARCH

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
        chroot_cmd rm -f /tmp/${keyname}chroot_cmd                      &>/dev/null
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

    CHROOT=$1;         argcheck CHROOT
    UBUNTU_RELEASE=$2; argcheck UBUNTU_RELEASE
    RELEASE=$3;        argcheck RELEASE
    HOST=$4;           argcheck HOST
    UBUNTU_ARCH=$5;    argcheck UBUNTU_ARCH

    [[ ${NOBANNER} -eq 1 ]] || ebanner "Setting up chroot [${CHROOT}]"
    
    # resolv.conf
    echo "search users.solidfire.net lab.solidfire.net vwc.solidfire.net" >> ${CHROOT}/etc/resolv.conf

    ## MOUNT
    chroot_mount

    ## LOCALES/TIMEZONE
    einfo "Configuring locale and timezone"
    local LANG="en_US.UTF-8"
    local TZ="America/Denver"
    echo "LANG=\"${LANG}\"" > "${CHROOT}/etc/default/locale" || die "Failed to set /etc/default/locale"
    chroot_cmd locale-gen ${LANG}
    chroot_cmd /usr/sbin/update-locale
    echo "${TZ}" > "${CHROOT}/etc/timezone"                  || die "Failed to set /etc/timezone"
    chroot_install_with_apt_get tzdata
    chroot_cmd dpkg-reconfigure tzdata
    
    ## SETUP
    chroot_apt_setup $@

    ## CLEANUP
    chroot_apt_clean
    chroot_unmount

    [[ ${NOBANNER} -eq 1 ]] || ebanner "Finished setting up chroot [${CHROOT}]"
    echo ""

    ) || { chroot_unmount; die "chroot_setup failed"; }
}

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
# MKCHROOT
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
mkchroot()
{
    local CHROOT=$1;         argcheck CHROOT
    local UBUNTU_RELEASE=$2; argcheck UBUNTU_RELEASE
    local RELEASE=$3;        argcheck RELEASE
    local HOST=$4;           argcheck HOST
    local UBUNTU_ARCH=$5;    argcheck UBUNTU_ARCH

    ebanner "Making chroot [${CHROOT}]"

    ## Make sure that debootstrap is installed
    which debootstrap > /dev/null || die "debootstrap must be installed"

    ## Setup chroot
    emkdir ${CHROOT}

    #-----------------------------------------------------------------------------                                    
    # DEBOOTSTRAP IMAGE
    #-----------------------------------------------------------------------------                                    
    local CHROOT_IMAGE="chroot_${UBUNTU_RELEASE}.tgz"
    einfo "Creating CHROOT=[${CHROOT}] UBUNTU_RELEASE=[${UBUNTU_RELEASE}] RELEASE=[${RELEASE}] HOST=[${HOST}] UBUNTU_ARCH=[${UBUNTU_ARCH}]"

    local LSB_RELEASE=$(cat /etc/lsb-release | grep "CODENAME" | awk -F= '{print $2}')
    local GPG_FLAG="--no-check-gpg"
    [[ ${LSB_RELEASE} == "lucid" ]] && GPG_FLAG=""

    local fetched=""
    fetched=$(efetch_with_md5_try "http://${HOST}/images/${CHROOT_IMAGE}")
    if [[ $? -eq 0 ]]; then
        debootstrap ${GPG_FLAG} --arch ${UBUNTU_ARCH} --unpack-tarball="${fetched}" ${UBUNTU_RELEASE} ${CHROOT} http://${HOST}/${RELEASE}-ubuntu
    else
        debootstrap ${GPG_FLAG} --arch ${UBUNTU_ARCH} ${UBUNTU_RELEASE} ${CHROOT} http://${HOST}/${RELEASE}-ubuntu
    fi

    #-----------------------------------------------------------------------------        
    # MODIFY CHROOT IMAGE
    #-----------------------------------------------------------------------------
    NOBANNER=1 chroot_setup $@

    ebanner "Finished making chroot [${CHROOT}]"
    echo ""
    
    # DONE
    return 0
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
