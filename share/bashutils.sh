#!/usr/bin/env bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

__BU_OS=$(uname)


# Load configuration files
if [[ -e /etc/bashutils.conf ]]; then
    source /etc/bashutils.conf
fi

if [[ -e ${XDG_CONFIG_HOME:-${HOME:-}/.config}/bashutils.conf ]]; then
    source ${XDG_CONFIG_HOME:-${HOME:-}/.config}/bashutils.conf
fi

# If TERM is unset, bash C code actually sets it to "dumb" so that it has a
# value.  But dumb terminals don't like tput, so we'll default to something
# better.
if [[ -z ${TERM:-} || ${TERM} == "dumb" || ${TERM} == "vt102" ]] ; then
    export TERM=xterm-256color
fi

# PLATFORM MUST BE FIRST.  It sets up aliases.  Those aliases won't be expanded
# inside functions that are already declared, only inside those declared after
# this.
source "${BASHUTILS}/platform.sh"

# Efuncs needs to be soon after to define a few critical aliases such as
# try/catch before sourcing everything else 
source "${BASHUTILS}/efuncs.sh"


source "${BASHUTILS}/archive.sh"
source "${BASHUTILS}/array.sh"
source "${BASHUTILS}/cgroup.sh"
source "${BASHUTILS}/chroot.sh"
source "${BASHUTILS}/daemon.sh"
source "${BASHUTILS}/dpkg.sh"
source "${BASHUTILS}/elock.sh"
source "${BASHUTILS}/emsg.sh"
source "${BASHUTILS}/json.sh"
source "${BASHUTILS}/mount.sh"
source "${BASHUTILS}/netns.sh"
source "${BASHUTILS}/network.sh"
source "${BASHUTILS}/opt.sh"
source "${BASHUTILS}/overlayfs.sh"
source "${BASHUTILS}/pack.sh"
source "${BASHUTILS}/process.sh"

# Default traps
die_on_abort
die_on_error
enable_trace

# Add default trap for EXIT so that we can ensure _bashutils_on_exit_start
# and _bashutils_on_exit_end get called when the process exits. Generally, 
# this allows us to do any error handling and cleanup needed when a process
# exits. But the main reason this exists is to ensure we can intercept
# abnormal exits from things like unbound variables (e.g. set -u).
trap_add "" EXIT

return 0
