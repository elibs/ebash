#!/usr/bin/env bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

# We presently assume that linux boxes will have a proper gnu toolchain in
# the default path.  For them, nothing need be done.
[[ ${__BU_OS} == "Linux" ]] && return 0


# But for others OSes, it's typical to install the gnu toolchain as
# binaries whose name is prefixed with a letter "g".  For instance, GNU
# grep gets installed as ggrep.
#
# This would probably be a nice area to allow for configuration, but for
# now we assume that the GNU toolchain is installed in that fashion on anything
# that is not Linux.  (GNU/Linux? ;-)
#
#
__BU_GNU_TOOLS=(
    base64
    cat
    cp
    dd
    find
    grep
    md5sum
    mktemp
    readlink
    sed
    sha256sum
    sleep
    sort
    stat
    tar
    tee
    timeout
    tr
)

# Make a function to take the place of every GNU tool in __BU_GNU_TOOLS that
# calls the g-prefixed version of the same gnu tool
redirect_gnu_tools()
{
    local tool
    for tool in "${__BU_GNU_TOOLS[@]}" ; do

        eval "function ${tool} { g${tool} \"\${@}\" ; }"

    done
}

redirect_gnu_tools
