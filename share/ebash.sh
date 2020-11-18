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
# The preferred way to use ebash is to ensure ebash is in your path then replace your typical bash shebang with:
#    #!/usr/bin/env ebash
#
# Alternatively, you can use the older mechanism by adding this to your code:
#    $(${EBASH}/bin/ebash --source)
#
# Or to ensure ${EBASH}/bin is in your path and to load it like this:
#    $(ebash --source)
#
########################################################################################################################

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


# PLATFORM MUST BE FIRST.  It sets up aliases.  Those aliases won't be expanded inside functions that are already
# declared, only inside those declared after this.
source "${EBASH}/platform.sh"

# Efuncs needs to be soon after to define a few critical aliases such as try/catch before sourcing everything else
source "${EBASH}/efuncs.sh"

# opt_parse and os modules are used extensively throughout some of the other modules we're going to source. We need
# os in particular in all of these modules so that we can intelligently exclude certain modules from inclusion for
# particular OSes or distros.
source "${EBASH}/opt.sh"
source "${EBASH}/os.sh"

# Now we can source everything else.
source "${EBASH}/archive.sh"
source "${EBASH}/array.sh"
source "${EBASH}/assert.sh"
source "${EBASH}/cgroup.sh"
source "${EBASH}/chroot.sh"
source "${EBASH}/conf.sh"
source "${EBASH}/daemon.sh"
source "${EBASH}/dialog.sh"
source "${EBASH}/dpkg.sh"
source "${EBASH}/docker.sh"
source "${EBASH}/efetch.sh"
source "${EBASH}/elock.sh"
source "${EBASH}/emsg.sh"
source "${EBASH}/eprompt.sh"
source "${EBASH}/json.sh"
source "${EBASH}/mount.sh"
source "${EBASH}/netns.sh"
source "${EBASH}/network.sh"
source "${EBASH}/overlayfs.sh"
source "${EBASH}/pack.sh"
source "${EBASH}/pkg.sh"
source "${EBASH}/process.sh"

# Default traps
die_on_abort
die_on_error
enable_trace

# Add default trap for EXIT so that we can ensure _ebash_on_exit_start and _ebash_on_exit_end get called when the
# process exits. Generally, this allows us to do any error handling and cleanup needed when a process exits. But the
# main reason this exists is to ensure we can intercept abnormal exits from things like unbound variables (e.g. set -u).
trap_add "" EXIT

return 0
