#!/usr/bin/env bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

if [[ ${EBASH_OS} == Linux ]] ; then
    EBASH_WORD_BEGIN='\<'
    EBASH_WORD_END='\>'
elif [[ ${EBASH_OS} == Darwin ]] ; then
    EBASH_WORD_BEGIN='[[:<:]]'
    EBASH_WORD_END='[[:>:]]'
fi

#-----------------------------------------------------------------------------------------------------------------------
#
# LINUX
#
#-----------------------------------------------------------------------------------------------------------------------

if [[ ${EBASH_OS} == "Linux" ]]; then

    # Detect what version of the kernel is running for code which requires it.
    __EBASH_KERNEL_MAJOR=$(uname -r | awk -F . '{print $1}')
    __EBASH_KERNEL_MINOR=$(uname -r | awk -F . '{print $2}')
    __EBASH_KERNEL_MICRO=$(uname -r | awk -F . '{print $3}' | sed 's|-\S*||')

    # Replace rm to ensure we always pass in --one-file-system flag.
    rm()
    {
        command rm --one-file-system "${@}"
    }

    # Replace sort with explicit LC_COLLATE so that we always get consistent sorting regardless of the user's locale.
    sort()
    {
        LC_COLLATE="C" command sort "${@}"
    }
fi

#-----------------------------------------------------------------------------------------------------------------------
#
# GNU TOOLS Redirection
#
#-----------------------------------------------------------------------------------------------------------------------

# On Darwin it's typical to install the GNU toolchain as binaries whose name is prefixed with a letter "g" via brew to
# avoid conflicting with the non-GNU tools already installed by the OS. For instance, GNU grep gets installed as ggrep.
#
# By default, on Darwin, ebash will redirect the GNU tools to be aliased within ebash so that we can consistently use
# the GNU versions. On Linux this is typically not necessary. However, sometimes it's desired for certain test
# scenarios. So we allow the caller direct control over this using EBASH_REDIRECT_GNU_TOOLS. If this is not set then
# we'll do the redirection on non-Linux and not do the redirection on Linux.
: ${EBASH_REDIRECT_GNU_TOOLS:=}
if [[ -z "${EBASH_REDIRECT_GNU_TOOLS}" ]]; then
    if [[ ${EBASH_OS} == "Darwin" ]]; then
        EBASH_REDIRECT_GNU_TOOLS=1
    else
        EBASH_REDIRECT_GNU_TOOLS=0
    fi
fi

# If no GNU Tool Redirection is required then just return.
if [[ "${EBASH_REDIRECT_GNU_TOOLS}" -ne 1 ]]; then
    return 0
fi

__EBASH_GNU_TOOLS=(
    # GNU Coreutils
    \[
    base64
    basename
    cat
    chcon
    chgrp
    chmod
    chown
    chroot
    cksum
    comm
    cp
    csplit
    cut
    date
    dd
    df
    dir
    dircolors
    dirname
    du
    # NOTE: Don't override bash builtin with function.
    #echo
    env
    expand
    expr
    factor
    false
    fmt
    fold
    groups
    head
    hostid
    id
    install
    join
    kill
    link
    ln
    logname
    ls
    md5sum
    mkdir
    mkfifo
    mknod
    mktemp
    mv
    nice
    nl
    nohup
    nproc
    numfmt
    od
    paste
    pathchk
    pinky
    pr
    printenv
    # NOTE: Don't override bash builtin with function
    # printf
    ptx
    # NOTE: Don't override bash builtin with function
    # pwd
    readlink
    realpath
    # NOTE: Don't override 'rm' as we have a function for it below.
    # rm
    rmdir
    runcon
    seq
    sha1sum
    sha224sum
    sha256sum
    sha384sum
    sha512sum
    shred
    shuf
    sleep
    # NOTE: Don't override 'sort' as we have a function for it below.
    # sort
    split
    stat
    stdbuf
    stty
    sum
    sync
    tac
    tail
    tee
    test
    timeout
    touch
    tr
    true
    truncate
    tsort
    tty
    uname
    unexpand
    uniq
    unlink
    uptime
    users
    vdir
    wc
    who
    whoami
    yes

    # And these are GNU tools that are not in coreutils but which we also
    # depend heavily on.
    egrep
    find
    grep
    readlink
    sed
    tar
)

# Alias every GNU tool that we use to call the g-prefixed version.
redirect_gnu_tools()
{
    local tool
    for tool in "${__EBASH_GNU_TOOLS[@]}" ; do
        alias "${tool}=g${tool}"
    done
}

redirect_gnu_tools

# Replace rm to ensure we always pass in --one-file-system flag.
rm()
{
    command grm --one-file-system "${@}"
}

# Replace sort with explicit LC_COLLATE so that we always get consistent sorting regardless of the user's locale.
sort()
{
    LC_COLLATE="C" command gsort "${@}"
}

return 0
