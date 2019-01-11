#!/bin/bash
#
# Copyright 2012-2018, Marshall McMullen <marshall.mcmullen@gmail.com> 
# Copyright 2012-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

[[ ${__EBASH_OS} != Linux ]] && return 0

#---------------------------------------------------------------------------------------------------
# CORE CHROOT FUNCTIONS
#---------------------------------------------------------------------------------------------------
CHROOT_MOUNTS=( /dev /proc /sys )

chroot_mount()
{
    argcheck CHROOT
    einfo "Mounting $(lval CHROOT CHROOT_MOUNTS)"

    for m in ${CHROOT_MOUNTS[@]}; do
        mkdir -p ${CHROOT}${m}
        ebindmount ${m} ${CHROOT}${m}
    done
}

chroot_unmount()
{
    argcheck CHROOT
    einfo "Unmounting $(lval CHROOT CHROOT_MOUNTS)"

    local mounts=()
    array_init_nl mounts "$(echo ${CHROOT_MOUNTS[@]} | sed 's| |\n|g' | sort -r)"
    for m in "${mounts[@]}" ; do
        eunmount "${CHROOT}${m}"
    done
}

chroot_prompt()
{
    $(opt_parse "?name")
    argcheck CHROOT

    # If no name given use basename of CHROOT
    : ${name:=CHROOT-$(basename ${CHROOT})}

    mkdir -p ${CHROOT}/${HOME}

    # Prompt for zsh
    (
        echo "PS1=\"%F{green}%n@%M %F{blue}%d%f"$'\n'"\$ \""
        echo "PS1=\"%F{red}[${name}]%f \$PS1\""
    ) > ${CHROOT}/${HOME}/.zshrc.prompt

    # Prompt for bash
    (
        echo "PS1=\"\[$(ecolor green)\]\u@\h \[$(ecolor blue)\]\w$(ecolor none)\\n\$ \""
        echo "PS1=\"\[$(ecolor red)\][${name}] \$PS1\""
    ) > ${CHROOT}/${HOME}/.bashrc.prompt

    local shellrc
    for shellrc in .zshrc .bashrc ; do

        local shellrc_prompt=${HOME}/${shellrc}.prompt
        local prompt_source_cmd=". ${shellrc_prompt}"

        # Append the source command to the shellrc if it doesn't already have it
        if ! grep -qF "${prompt_source_cmd}" ${CHROOT}/${HOME}/${shellrc} 2>/dev/null; then
            echo "${prompt_source_cmd}" >> ${CHROOT}/${HOME}/${shellrc}
        else
            edebug "Already sourcing promptrc in ${shellrc}"
        fi
    done
}

chroot_shell()
{
    $(opt_parse "?name")
    argcheck CHROOT

    # Setup CHROOT prompt
    chroot_prompt ${name}

    # Mount then enter chroot. Ensure we setup a trap so that we'll unmount the chroot 
    # regardless of how we leave this function.
    chroot_mount
    trap_add "chroot_unmount"
    # CHROOT_ENV here refers to bash, so we're starting a bash shell here
    chroot ${CHROOT} ${CHROOT_ENV} --login -i || true
}

chroot_cmd()
{
    argcheck CHROOT

    einfos $@
    chroot ${CHROOT} ${CHROOT_ENV} -c "$*"
}

opt_usage chroot_kill <<'END'
Send a signal to processes inside _this_ CHROOT (designated by ${CHROOT}) that match the given
regex.  [note: regex support is identical to pgrep]
END
#
# $1: Optional pgrep pattern that match the processes you'd like to signal.
#        If no pattern is specified, ALL proceses in the chroot will be
#        signalled.
#
chroot_kill()
{
    $(opt_parse \
        ":signal s=TERM   | The signal to send to killed pids." \
        ":kill_after k    | Also send SIGKILL to processes that are still alive after this duration.
                            (Does not block)" \
        "?regex           | Pgrep regex that should match processes you'd like to signal.  If none
                            is specified, all processes in the chroot will be killed.")

    argcheck CHROOT

    local pids=""
    local errors=0
    [[ -n ${regex} ]] && pids=$(pgrep "${regex}" || return 0) || pids=$(ps -eo "%p")
    edebug $(lval regex signal pids)

    local pid link
    for pid in ${pids}; do
        link=$(readlink "/proc/${pid}/root" || true)

        # Skip processes started in NO chroot or ANOTHER chroot
        [[ -z ${link} || ${link} != ${CHROOT} ]] && continue

        # Kill this process
        einfos "Killing ${pid} [$(ps -p ${pid} -o comm=)]"
        ekilltree -s=${signal} --kill-after=${kill_after} ${pid} || (( errors+=1 ))
    done

    [[ ${errors} -eq 0 ]]
}

# Cleanly exit a chroot by:
# (1) Kill any processes started inside chroot (chroot_kill)
# (2) Recursively unmount the chroot and anything mounted underneath it
chroot_exit()
{
    chroot_kill
    eunmount -r ${CHROOT}
}

opt_usage chroot_readlink <<'END'
Read a symlink inside a CHROOT and give full path to the symlink OUTSIDE the chroot. For example, if
inside the CHROOT you have "/a -> /b" then calling chroot_readlink "/a" => "${CHROOT}/b"
END
chroot_readlink()
{
    argcheck CHROOT
    $(opt_parse path)

    echo -n "${CHROOT}$(chroot_cmd readlink -m "${path}" 2>/dev/null)"
}

#---------------------------------------------------------------------------------------------------
# APT-CHROOT FUNCTIONS
#---------------------------------------------------------------------------------------------------

## APT SETTINGS ##
CHROOT_APT="aptitude -f -y"
CHROOT_ENV="/usr/bin/env USER=root SUDO_USER=root HOME=/root DEBIAN_FRONTEND=noninteractive TMPDIR=/tmp /bin/bash"

chroot_apt_update()
{
    chroot_cmd apt-get update 2>/dev/null
}

chroot_apt_clean()
{
    chroot_cmd apt-get clean >/dev/null
    chroot_cmd apt-get autoclean >/dev/null
}

chroot_install_with_apt_get()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return 0

    einfos "Installing $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "apt-get -f -qq -y --force-yes install $*"
}

# Check if all the packages listed can be installed
chroot_install_check()
{
    # BUG: https://bugs.launchpad.net/ubuntu/+source/aptitude/+bug/919216
    # 'aptitude install' silently fails with success if a bogus package is given whereas 'aptitude show'
    # gives back a proper error code. So first do a check with aptitude show first.
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} show $(echo $* | sed -e 's/\(>=\|<=\)/=/g')" |& edebug
}

chroot_install()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return 0

    einfos "Installing $@"

    # Check if all packages are installable
    chroot_install_check $*

    # Do actual install
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} install $(echo $* | sed -e 's/\(>=\|<=\)/=/g')"

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
        local actual apn apv
        actual=$(chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg-query -W -f='\${Package}|\${Version}' ${pn}")
        apn="${actual%|*}"
        apv="${actual#*|}"

        [[ ${pn} == ${apn} ]] || { eerror "Mismatched package name $(lval wanted=pn actual=apn)"; return 1; }

        ## No explicit version check -- continue
        [[ -z "${op}" || -z "${pv}" ]] && continue

        dpkg_compare_versions --chroot ${CHROOT} "${apv}" "${op}" "${pv}" || { eerror "Version mismatch: wanted=[${pn}-${pv}] actual=[${apn}-${apv}] op=[${op}]"; return 1; }
    done
}

chroot_uninstall()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return 0

    einfos "Uninstalling $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} remove --purge $*"
}

chroot_dpkg()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return 0

    einfos "dpkg $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg $*"
}

chroot_apt()
{
    argcheck CHROOT
    [[ $# -eq 0 ]] && return 0

    einfos "${CHROOT_APT} $@"
    chroot ${CHROOT} ${CHROOT_ENV} -c "${CHROOT_APT} $*"
}

chroot_listpkgs()
{
    argcheck CHROOT
    chroot ${CHROOT} ${CHROOT_ENV} -c "dpkg-query -W"
}

chroot_uninstall_filter()
{
    argcheck CHROOT
    local filter=$@ pkgs=""
    pkgs=$(chroot_listpkgs)
    chroot_uninstall $(eval "echo \"${pkgs}\" | ${filter} | awk '{print \$1}'")
}

chroot_apt_setup()
{
    $(opt_parse CHROOT UBUNTU_RELEASE UBUNTU_ARCH)

    ## Set up DPKG options so we don't get prompted for anything
    einfo "Setting up dpkg.cfg"
    echo 'force-confdef'          > ${CHROOT}/etc/dpkg/dpkg.cfg
    echo 'force-confold'         >> ${CHROOT}/etc/dpkg/dpkg.cfg
    echo 'no-debsig'             >> ${CHROOT}/etc/dpkg/dpkg.cfg
    echo 'log /var/log/dpkg.log' >> ${CHROOT}/etc/dpkg/dpkg.cfg

    ## APT Update
    ## In case a prior run failed let's clean up any prior dpkg and apt-get failures
    einfo "Initial configure/update"
    chroot_dpkg --configure -a
    chroot_cmd apt-get -f -y --force-yes install
    chroot_apt_update

    # Install Aptitude since we use that for everything in chroot
    einfo "Installing minimal package set"
    chroot_install_with_apt_get apt aptitude
    chroot_install curl vim wget

    # In case any packages didn't fully install (APT...)
    einfo "Final configure/update"
    chroot_dpkg --configure -a
    chroot_cmd apt-get -f -y --force-yes install
    chroot_apt_update
}

chroot_setup()
{
    $(opt_parse CHROOT UBUNTU_RELEASE UBUNTU_ARCH)
    einfo "Setting up $(lval CHROOT)"

    # Put this into a subshell to ensure error handling is done correctly on shell teardown
    (
        # Make /etc/mtab a symlink to /proc/mounts so that it is never out of sync with
        # our mount points. This matches how more modern Linux distributions work.
        chroot_cmd "ln -sf /proc/mounts /etc/mtab"

        # Because of how we mount things while building up our chroot sometimes
        # /etc/resolv.conf will be bind mounted into ${CHROOT}. When that happens
        # calling 'cp' will fail b/c they refer to the same inodes. So we need
        # to explicitly check for that here.
        for src in /etc/resolv.conf /etc/hosts; do
            local dst="${CHROOT}${src}"
            [[ "$(stat --format=%d.%i ${src})" != "$(stat --format=%d.%i ${dst})" ]] && cp -arL ${src} ${dst}
        done

        ## MOUNT
        trap_add chroot_unmount
        chroot_mount

        ## LOCALES/TIMEZONE
        einfo "Configuring locale and timezone"
        local LANG="en_US.UTF-8"
        local TZ="Etc/UTC"
        echo "LANG=\"${LANG}\"" > "${CHROOT}/etc/default/locale"
        chroot_cmd locale-gen ${LANG}
        chroot_cmd /usr/sbin/update-locale
        echo "${TZ}" > "${CHROOT}/etc/timezone"
        chroot_install_with_apt_get tzdata
        chroot_cmd dpkg-reconfigure tzdata

        ## SETUP
        chroot_apt_setup ${CHROOT} ${UBUNTU_RELEASE} ${UBUNTU_ARCH}

        ## CLEANUP
        chroot_apt_clean
    )
}

opt_usage mkchroot <<'END'
Create an UBUNTU based CHROOT using debootstrap.
END
mkchroot()
{
    $(opt_parse CHROOT UBUNTU_RELEASE UBUNTU_ARCH)
    edebug "$(lval CHROOT UBUNTU_RELEASE UBUNTU_ARCH)"

    ## Make sure that debootstrap is installed
    which debootstrap > /dev/null

    # Debootstrap image
    local CHROOT_IMAGE="chroot_${UBUNTU_RELEASE}.tgz"
    einfo "Creating $(lval CHROOT UBUNTU_RELEASE UBUNTU_ARCH)"
    efreshdir ${CHROOT}
    debootstrap --no-check-gpg --arch ${UBUNTU_ARCH} ${UBUNTU_RELEASE} ${CHROOT}

    chroot_setup ${CHROOT} ${UBUNTU_RELEASE} ${UBUNTU_ARCH}
}

#---------------------------------------------------------------------------------------------------
# SOURCING
#---------------------------------------------------------------------------------------------------
return 0
