show_text()
{
    [[ ${TEXT} -eq 1 ]] || return
    head /etc/fstab 
}

emsg_aux()
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
    EDEBUG=emsg_aux edebug  "This is a debugging message"; show_text

    return 0
}

ETEST_emsg_defaults()
{
    emsg_aux
}

ETEST_emsg_time()
{
    EMSG_PREFIX="time" emsg_aux
}

ETEST_emsg_time_legacy()
{
    EFUNCS_TIME=1 emsg_aux
}

ETEST_emsg_level()
{
    EMSG_PREFIX="level" emsg_aux
}

ETEST_emsg_caller()
{
    EMSG_PREFIX="caller" emsg_aux
}

ETEST_emsg_time_level()
{
    EMSG_PREFIX="time level" emsg_aux
}

ETEST_emsg_time_caller()
{
    EMSG_PREFIX="time caller" emsg_aux
}

ETEST_emsg_time_level_caller()
{
    EMSG_PREFIX="time level caller" emsg_aux
}

ETEST_emsg_nocolor()
{
    EFUNCS_COLOR=0 EMSG_PREFIX="time level caller" emsg_aux
}

ETEST_emsg_msgcolor_all()
{
    EMSG_COLOR="all" EMSG_PREFIX="time level caller" emsg_aux
    EMSG_COLOR="time level caller msg" EMSG_PREFIX="time level caller" emsg_aux
}

ETEST_emsg_rainbow_of_pain()
{
    EMSG_COLOR="time" EMSG_PREFIX="time level caller" emsg_aux
    EMSG_COLOR="level" EMSG_PREFIX="time level caller" emsg_aux
    EMSG_COLOR="caller" EMSG_PREFIX="time level caller" emsg_aux
    EMSG_COLOR="time level" EMSG_PREFIX="time level caller" emsg_aux
    EMSG_COLOR="time level caller" EMSG_PREFIX="time level caller" emsg_aux
    EMSG_COLOR=" " EMSG_PREFIX="time level caller" emsg_aux
}
