#!/bin/bash

source efuncs.sh

show_text()
{
    [[ ${TEXT} -eq 1 ]] || return
    head /etc/fstab 
}

msg()
{
    ## EINFO ##
    einfo "Building RTFI";  show_text
    einfos "Copying file1"; show_text
    einfos "Copying file2"; show_text

    ## WARN ##
    ewarn "OOPS -- there was a potential problem"; show_text
    ewarns "On file1"; show_text
    ewarns "Or file2"; show_text

    ## ERROR ##
    eerror "Aieee! Something terrible happened"; show_text
    ## DEBUG ##
    EDEBUG=msg edebug  "This is a debugging message"; show_text
}

ebanner "Defaults"
msg

ebanner "Time"
ELOG_PREFIX="time" msg

ebanner "Time via EFUNCS_TIME"
EFUNCS_TIME=1 msg

ebanner "Level only"
ELOG_PREFIX="level" msg

ebanner "Caller only"
ELOG_PREFIX="caller" msg

ebanner "Time + Level"
ELOG_PREFIX="time level" msg

ebanner "Time + caller"
ELOG_PREFIX="time caller" msg

ebanner "Time + level + caller"
ELOG_PREFIX="time level caller" msg
