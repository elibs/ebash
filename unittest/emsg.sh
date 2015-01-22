show_text()
{
    [[ ${TEXT} -eq 1 ]] || return
    head /etc/fstab 
}

display_long_function()
{
    : ${ETEST_EMSG_DISABLED:=1}
    [[ ${ETEST_EMSG_DISABLED} -eq 1 ]] && return 0

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
    EDEBUG=display_long_function edebug  "This is a debugging message"; show_text

    return 0
}

ETEST_emsg_defaults()
{
    display_long_function
}

ETEST_emsg_time()
{
    EMSG_PREFIX="time" display_long_function
}

ETEST_emsg_time_legacy()
{
    EFUNCS_TIME=1 display_long_function
}

ETEST_emsg_level()
{
    EMSG_PREFIX="level" display_long_function
}

ETEST_emsg_caller()
{
    EMSG_PREFIX="caller" display_long_function
}

ETEST_emsg_time_level()
{
    EMSG_PREFIX="time level" display_long_function
}

ETEST_emsg_time_caller()
{
    EMSG_PREFIX="time caller" display_long_function
}

ETEST_emsg_time_level_caller()
{
    EMSG_PREFIX="time level caller" display_long_function
}

ETEST_emsg_nocolor()
{
    EFUNCS_COLOR=0 EMSG_PREFIX="time level caller" display_long_function
}

ETEST_emsg_msgcolor_all()
{
    EMSG_COLOR="all" EMSG_PREFIX="time level caller" display_long_function
    EMSG_COLOR="time level caller msg" EMSG_PREFIX="time level caller" display_long_function
}

ETEST_emsg_rainbow_of_pain()
{
    EMSG_COLOR="time" EMSG_PREFIX="time level caller" display_long_function
    EMSG_COLOR="level" EMSG_PREFIX="time level caller" display_long_function
    EMSG_COLOR="caller" EMSG_PREFIX="time level caller" display_long_function
    EMSG_COLOR="time level" EMSG_PREFIX="time level caller" display_long_function
    EMSG_COLOR="time level caller" EMSG_PREFIX="time level caller" display_long_function
    EMSG_COLOR=" " EMSG_PREFIX="time level caller" display_long_function
}
