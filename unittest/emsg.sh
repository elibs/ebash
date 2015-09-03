#!/usr/bin/env bash

show_text()
{
    [[ ${TEXT:-0} -eq 1 ]] || return 0
    head /etc/fstab 
    return 0
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

# Not really a unit test but simply display all possible colors
ETEST_COLORS=(
    black           red             green           yellow          blue            magenta
    cyan            white           navyblue        darkgreen       deepskyblue     dodgerblue
    springgreen     darkturqouise   turquoise       blueviolet      orange          slateblue
    paleturquoise   steelblue       cornflowerblue  aquamarine      darkred         darkmagenta
    plum            wheat           lightslategrey  darkseagreen    darkviolet      darkorange
    hotpink         mediumorchid    lightsalmon     gold            darkkhaki       indianred
    orchid          violet          tan             lightyellow     honeydew        salmon
    pink            thistle         grey0           grey3           grey7           grey11
    grey15          grey19          grey23          grey27          grey30          grey35
    grey39          grey42          grey46          grey50          grey54          grey58
    grey62          grey66          grey70          grey74          grey78          grey82
    grey85          grey89          grey93          grey100
)

ETEST_ecolor_chart()
{
    local pad padlength line c

    pad=$(printf '%0.1s' " "{1..60})
    padlength=20
    line=0
    
    for c in ${ETEST_COLORS[@]}; do
        printf "%s%*.*s" "$(ecolor $c)${c}$(ecolor none)" 0 $((padlength - ${#c} )) "${pad}"
        (( ++line % 8 == 0 )) && printf "\n" || true

        c="dim${c}"
        printf "%s%*.*s" "$(ecolor $c)${c}$(ecolor none)" 0 $((padlength - ${#c} )) "${pad}"
        (( ++line % 8 == 0 )) && printf "\n" || true
 
    done

    echo ""
}
