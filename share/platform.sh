#!/usr/bin/env bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

if [[ ${__BU_OS} == Linux ]] ; then
    BU_WORD_BEGIN='\<'
    BU_WORD_END='\>'
elif [[ ${__BU_OS} == Darwin ]] ; then
    BU_WORD_BEGIN='[[:<:]]'
    BU_WORD_END='[[:>:]]'
fi

#-----------------------------------------------------------------------------
# LINUX
#-----------------------------------------------------------------------------

if [[ ${__BU_OS} == "Linux" ]]; then

    # Detect what version of the kernel is running for code which requires it.
    __BU_KERNEL_MAJOR=$(uname -r | awk -F . '{print $1}')
    __BU_KERNEL_MINOR=$(uname -r | awk -F . '{print $2}')
    __BU_KERNEL_MICRO=$(uname -r | awk -F . '{print $3}' | sed 's|-\S*||')

    # Replace rm to ensure we always pass in --one-file-system flag.
    rm()
    {
        command rm --one-file-system "${@}" 
    }

    # We presently assume that linux boxes will have a proper gnu toolchain in
    # the default path.  For them, nothing need be done so just return.
    return 0
fi

#-----------------------------------------------------------------------------
# OTHER
#-----------------------------------------------------------------------------

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
    #pwd
    readlink
    realpath
    # NOTE: Don't override rm as we do that one one-off below.
    #rm
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
    sort
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
    for tool in "${__BU_GNU_TOOLS[@]}" ; do
        alias "${tool}=g${tool}"
    done
}

redirect_gnu_tools

# Replace rm to ensure we always pass in --one-file-system flag.
rm()
{
    command grm --one-file-system "${@}" 
}
