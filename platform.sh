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
# now we assume things meet that assumption and that the gnu tools with a
# "g" prepended to their name are in the path.
#
#
#__BU_GNU_TOOLS=(
#    readlink
#    find
#    sort
#    tr
#    dd
#    sed
#    grep
#    tar
#    cp
#    mktemp
#    stat
#    sleep
#    timeout
#    cat
#    tee
#    base64
#    md5sum
#)
#
#redirect_gnu_tools()
#{
#    local tool
#    for tool in "${__BU_GNU_TOOLS[@]}" ; do
#
#    done
#}


# TODO modell sha256sum is special
    sha256sum() { shasum "${@}" ; }

# TODO modell rest of the gnu tools that bashutils uses
    readlink() { greadlink "${@}" ; }
    find() { gfind "${@}" ; }
    sort() { gsort "${@}" ; }
    tr() { gtr "${@}" ; }
    dd() { gdd "${@}" ; }
    sed() { gsed "${@}" ; }
    grep() { ggrep "${@}" ; }
    tar() { gtar "${@}" ; }
    cp() { gcp "${@}" ; }
    mktemp() { gmktemp "${@}" ; }
    stat() { gstat "${@}" ; }
    sleep() { gsleep "${@}" ; }
    timeout() { gtimeout "${@}" ; }
    cat() { gcat "${@}" ; }
    tee() { gtee "${@}" ; }
    base64() { gbase64 "${@}" ; }
    md5sum() { gmd5sum "${@}" ; }

