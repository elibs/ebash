#!/usr/bin/env bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

########################################################################################################################
#
# The preferred way to load ebash in a script is to add this to your code:
#    $(${EBASH}/bin/ebash --source)
#
# Or to ensure ${EBASH}/bin is in your path and to load it like this:
#    $(ebash --source)
#
# Or just ensure ebash is in your PATH and then modify your shebang interpreter at the top of your script to:
#    #!/usr/bin/env ebash
#
########################################################################################################################

#-----------------------------------------------------------------------------------------------------------------------
#
# Bootstrap bash
#
#-----------------------------------------------------------------------------------------------------------------------
# In some rare circumstances we may be running under a non-bash shell need to switch over to bash before we can proceed.
#
# This can happen if we are invoked through some other interpeter such as via `sh bin/ebash` or `bash bin/ebash.sh`
# rather than directly calling `bin/ebash`. When invoked that way, ebash becaomes a parameter of `sh` and bash never
# gets invoked. This prevents ebash from being setup and executing properly. We solve this by simply checking if we're
# running inside a native BASH context and if we are not, we simply execute bash directly with our script as a parameter
# as well as any arguments we were passed.
if [[ "$(ps -p $$ -ocomm=)" != "bash" ]]; then
    exec bash "$0" "${@}"
fi

#-----------------------------------------------------------------------------------------------------------------------
#
# Global ebash settings
#
#-----------------------------------------------------------------------------------------------------------------------
set \
    -o errtrace  \
    -o functrace \
    -o nounset   \
    -o pipefail  \
    +o noclobber \
    +o posix     \

shopt -s           \
    checkwinsize   \
    expand_aliases \
    extglob        \

alias enable_trace='[[ -n ${ETRACE:-} && ${ETRACE:-} != "0" ]] && trap etrace DEBUG || trap - DEBUG'

__EBASH_OS=$(uname)

# Load configuration files
if [[ -e /etc/ebash.conf ]]; then
    source /etc/ebash.conf
fi

if [[ -e ${XDG_CONFIG_HOME:-${HOME:-}/.config}/ebash.conf ]]; then
    source ${XDG_CONFIG_HOME:-${HOME:-}/.config}/ebash.conf
fi

# If TERM is unset, bash C code actually sets it to "dumb" so that it has a value. But dumb terminals don't like tput,
# so we'll default to something better.
if [[ -z ${TERM:-} || ${TERM} == @(dumb|vt102|unknown) ]] ; then
    export TERM=xterm-256color
fi

# Unset CDPATH in case the caller exported it since it badly breaks `cd` commands.
unset CDPATH

#-----------------------------------------------------------------------------------------------------------------------
#
# Automatic documentation
#
#-----------------------------------------------------------------------------------------------------------------------
# All functions and ebash based scripts which utilize `opt_parse` get automatic documentation and usage information.
# This is automatically available via `--help` or `-?` options. For this to work, we have to store off the docstrings
# above each function into variables for subsequent output when the usage is requested via `--help` or `-?`.
#
# But we don't want to bloat the interpreter with a bunch of documentation every time we source ebash. Our solution is
# to only save them at times where we believe the variables are going to be needed. There's no reason to expect they
# will be necessary unless `--help` or `-?` is on the command line somewhere. Or for those few cases where it's needed,
# for any other reason, the caller can just set `__EBASH_SAVE_DOC=1` explicitly.
for arg in "$@" ; do
    if [[ ${arg} == "--help" || ${arg} == "-?" ]] ; then
        __EBASH_SAVE_DOC=1
    fi
done

# This function is used to create documentation for bash functions that can be queried at runtime. To avoid bloating
# the interpreter for this all the time, it is only performed when __EBASH_SAVE_DOC is set to 1.
#
# In order to create documentation for your command, do something like this near it:
#
#     opt_usage foo<<'END'
#     Here is my documentation for foo.
#     END
#     foo() { $(opt_parse...) ; do_stuff ; }
#
# Really short documentation blocks can be passed as a second string parameter to opt_usage rather than on stdin if
# you prefer like this
#
#     opt_usage foo "Short doc block"
#
# Documentation placed in either of those formats will be printed out in the usage statements (i.e. foo --help).
#
# It's our goal to eventually place this in man pages and web versions of documentation in the future but this is not
# yet implemented. If you need markup in the text, use Markdown -- that's what we intend to use for man page and web
# page documentation when the time comes.
declare -A __EBASH_DOC
opt_usage()
{
    [[ -n ${1:-} ]] || { echo "opt_usage calls require a function name argument." ; exit 2 ; }

    if [[ ${__EBASH_SAVE_DOC:-0} -eq 1 ]] ; then

        if [[ -n ${2:-} ]] ; then
            __EBASH_DOC[$1]="$2"
        else
            __EBASH_DOC[$1]=$(cat)
        fi

    else
        true
    fi
}

#-----------------------------------------------------------------------------------------------------------------------
#
# Load Modules
#
#-----------------------------------------------------------------------------------------------------------------------

# PRELOAD modules that need to be loaded before any others in order to establish required aliases. These aliases are not
# normally expanded inside functions that have already been declared. So we must source these modules before loading any
# others.
source "${EBASH}/platform.sh"
source "${EBASH}/try_catch.sh"

# opt_parse and os modules are used extensively throughout some of the other modules we're going to source. We need os
# in particular in all of these modules so that we can intelligently exclude certain modules from inclusion for
# particular OSes or distros.
source "${EBASH}/opt.sh"
source "${EBASH}/os.sh"
source "${EBASH}/emsg.sh"

# Now we can source everything else.
source "${EBASH}/archive.sh"
source "${EBASH}/array.sh"
source "${EBASH}/assert.sh"
source "${EBASH}/cgroup.sh"
source "${EBASH}/checkbox.sh"
source "${EBASH}/chroot.sh"
source "${EBASH}/compare.sh"
source "${EBASH}/conf.sh"
source "${EBASH}/daemon.sh"
source "${EBASH}/dialog.sh"
source "${EBASH}/die.sh"
source "${EBASH}/docker.sh"
source "${EBASH}/dpkg.sh"
source "${EBASH}/efetch.sh"
source "${EBASH}/elock.sh"
source "${EBASH}/elogfile.sh"
source "${EBASH}/elogrotate.sh"
source "${EBASH}/emetadata.sh"
source "${EBASH}/emock.sh"
source "${EBASH}/eprompt.sh"
source "${EBASH}/eretry.sh"
source "${EBASH}/etable.sh"
source "${EBASH}/etimeout.sh"
source "${EBASH}/exec.sh"
source "${EBASH}/fd.sh"
source "${EBASH}/filesystem.sh"
source "${EBASH}/funcutil.sh"
source "${EBASH}/hardware.sh"
source "${EBASH}/integer.sh"
source "${EBASH}/json.sh"
source "${EBASH}/mount.sh"
source "${EBASH}/netns.sh"
source "${EBASH}/network.sh"
source "${EBASH}/overlayfs.sh"
source "${EBASH}/pack.sh"
source "${EBASH}/pipe.sh"
source "${EBASH}/pkg.sh"
source "${EBASH}/process.sh"
source "${EBASH}/setvars.sh"
source "${EBASH}/signal.sh"
source "${EBASH}/stacktrace.sh"
source "${EBASH}/string.sh"
source "${EBASH}/testutil.sh"
source "${EBASH}/trap.sh"
source "${EBASH}/type.sh"

# Default traps
die_on_abort
die_on_error
enable_trace

# Add default trap for EXIT so that we can ensure _ebash_on_exit_start and _ebash_on_exit_end get called when the
# process exits. Generally, this allows us to do any error handling and cleanup needed when a process exits. But the
# main reason this exists is to ensure we can intercept abnormal exits from things like unbound variables (e.g. set -u).
trap_add "" EXIT
