#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

# Default values for EMSG_PREFIX
: ${EMSG_PREFIX:=}
: ${EMSG_COLOR:=all}

# Default color codes for emsg related functions. These can be overridden in /etc/ebash.conf or ~/.config/ebash.conf.
: ${COLOR_INFO:="bold green"}
: ${COLOR_DEBUG:="salmon"}
: ${COLOR_TRACE:="yellow"}
: ${COLOR_WARN:="bold yellow"}
: ${COLOR_ERROR:="bold red"}
: ${COLOR_BRACKET:="bold blue"}
: ${COLOR_BANNER:="bold magenta"}
: ${COLOR_USAGE:="bold green"}
: ${COLOR_CHECKBOX:="lightslategrey"}

# Default timestamp format to use. Supports:
# RFC3339       (e.g. "2006-01-02T15:04:05Z07:00")
# StampMilli    (e.g. "Jan _2 15:04:05.000")
: ${ETIMESTAMP_FORMAT:=RFC3339}

# Any functions whose names are "==" to this are exempt from ETRACE. In other words, even if ETRACE=1, these functions
# actions will not be displayed in the output.
#
# By default, these are excluded:
#   1) Any parts of opt_parse (plus string_trim because opt_parse uses it)
#   2) Emsg and other message producing internals (but not the message functions like edebug, einfo)
#   3) Internals of die and stack generation (but leaving some parts of die so it's more clear what is happening.)
#   4) Signame, which does translations amongst signal names in various styles and signal numbers.
: ${ETRACE_BLACKLIST:=@(opt_parse|opt_parse_setup|opt_parse_options|opt_parse_arguments|opt_parse_find_canonical|argcheck|ecolor|ecolor_internal|ecolor_code|einteractive|emsg|string_trim|print_value|lval|disable_signals|reenable_signals|__eerror_internal|eerror_stacktrace|stacktrace|stacktrace_array|signame|array_size|array_empty|array_not_empty)}

opt_usage etrace <<'END'
`etrace` is an extremely powerful debugging technique. It essentially allows you to selectively emit a colorized
debugging message for **every line of code executed by ebash** without having to modify the source code and sprinkle it
with lots of explicit debugging messages. This means you can dynamically debug code in the field without having to make
and source code changes.

This is similar to the builtin bash `set -x` option. But ebash takes this a little further by using selective controls
for command tracing rather than blanket turning on `set -x` for the entire process lifetime. Additionally, the messages
are prefixed with a configurable color message showing the filename, line number, function name, and PID of the caller.
The color can be configured via `${COLOR_TRACE}`.

For example, suppose I have the following script:

```shell
#!/bin/bash

$(etrace --source)

echo "Hi"
a=alpha
b=beta
echo "$(lval a b)"
```

You can now run the above script with `etrace` enabled and get the following output. Not that rather than just the
**command** being printed as you'd get with `set -x`, etraces emits the file, line number and process PID:

```shell
$ ETRACE=etrace_test ./etrace_test
[etrace_test:6:main:24467] echo "Hi"
Hi
[etrace_test:7:main:24467] a=alpha
[etrace_test:8:main:24467] b=beta
[etrace_test:9:main:24467] echo "$(lval a b)"
[etrace_test:9:main:25252] lval a b
a="alpha" b="beta"
```

Like `EDEBUG`, `ETRACE` is a space-separated list of patterns which will be matched against your current filename and
function name. The etrace functionality has a much higher overhead than does running with edebug enabled, but it can be
immensely helpful when you really need it.

One caveat: you can’t change the value of ETRACE on the fly. The value it had when you sourced ebash is the one that
will affect the entire duration of the script.
END
etrace()
{
    # This function returns as soon as it can decide that tracing should not happen. If it makes its way to the end,
    # then it finally does the tracing it must do.

    # Is tracing globally off?
    [[ ${ETRACE} == "" || ${ETRACE} == "0" ]] && return 0 || true


    # Is tracing enabled, but not globally (i.e. now we check function and filenames)
    if [[ ${ETRACE} != "1" ]]; then

        local should_be_enabled=0

        local word
        for word in ${ETRACE}; do
            [[ ${BASH_SOURCE[1]:-} == *"${word}"*
                || ${FUNCNAME[1]:-} == *"${word}"* ]] && { should_be_enabled=1; break; }
        done

        [[ ${should_be_enabled} -eq 1 ]] || return 0
    fi


    # Whether we got here because ETRACE=1 or because a function was specifically chosen, we still leave out blacklisted
    # functions
    if [[ ${FUNCNAME[1]} == ${ETRACE_BLACKLIST} ]] ; then
        return 0
    fi

    {
        ecolor ${COLOR_TRACE}
        echo -n "[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]:-}:${FUNCNAME[1]:-}:${BASHPID}]"
        ecolor none
        echo "${BASH_COMMAND}"
    } >&2
}

opt_usage edebug_enabled <<'END'
`edebug_enabled` is a convenience function to check if edebug is currently enabled for the context the caller is calling
from. This will return success (0) if `edebug` is enabled, and failure (1) if not. This can then be used to perform
conditional code depending on if debugging is enabled or not.

For example:

```shell
if edebug_enabled; then
    dmesg > dmesg.out
    ip    > ip.out
fi
```
END
edebug_enabled()
{
    [[ -n ${1:-} ]] && die "edebug_enabled does not support arguments."

    [[ ${EDEBUG:=}  == "1" || ${ETRACE:=}  == "1" ]] && return 0
    [[ ${EDEBUG:-0} == "0" && ${ETRACE:-0} == "0" ]] && return 1

    # Walk up the stack and pick the first function that isn't in our list of
    # function names skipped
    local index=1
    local caller=${FUNCNAME[$index]}
    local filename=${BASH_SOURCE[$index]}
    if [[ ${caller} == @(edebug|edebug_out|tryrc) ]] ; then
        (( index += 1 ))
        caller=${FUNCNAME[$index]}
        filename=${BASH_SOURCE[$index]}
    fi

    # If the edebug or etrace strings contain a word that matches the name of the function or filename, then edebug is
    # on.
    local word
    for word in ${EDEBUG:-} ${ETRACE:-} ; do
        [[ "${caller}"   == *"${word}"* ]] && return 0
        [[ "${filename}" == *"${word}"* ]] && return 0
    done

    # Otherwise, it's not.
    return 1
}

opt_usage edebug_disabled <<'END'
`edebug_disabled` is the logical analogue of `edebug_enabled`. It returns success (0) if debugging is disabled and
failure (1) if it is enabled.
END
edebug_disabled()
{
    ! edebug_enabled
}

opt_usage edebug <<'END'
`edebug` is a powerful debugging mechanism to conditionally emit **selective** debugging messages that are statically
in the source code based on the `EDEBUG` environment variable. By default, `edebug` messages will not produce any output.
Moreover, they do not add any overhead to the code as we return immediately from the `edebug` function if debugging is
not enabled.

For example, suppose I have the following in my source code:

```shell
edebug "foo just borked rc=${rc}"
```

You can activate the output from these `edebug` statements either wholesale or selectively by setting an environment
variable. Setting `EDEBUG=1` will turn on all `edebug` output everywhere. We use this pervasively, so that is probably
going to way too much noise.

Instead of turning everything on, you can turn on `edebug` just for code in certain files or functions. For example,
using `EDEBUG="dtest dmake"` will turn on debugging for any `edebug` statements in any scripts named `dtest` or `dmake`
or any functions named `dtest` or `dmake`.

Another powerful feature `edebug` supports is to send the entire output of another command into `edebug` without having
to put an `if` statement around it and worrying about sending the output to STDERR. This is super easy to do:

```shell
cmd | edebug
```

The value of `EDEBUG` is actually a space-separated list of terms. If any of those terms match the filename (just
basename) **or** the name of the function that contains an `edebug` statement, it will generate output.
END
edebug()
{
    # Take input either from arguments or if no arguments were provided take input from standard input.
    if [[ $# -gt 0 ]]; then
        if ! edebug_enabled; then
            return 0
        fi
        EMSG_PREFIX="${EMSG_PREFIX:-} caller" emsg "${COLOR_DEBUG}" "" "DEBUG" "${@}"
    else
        if ! edebug_enabled; then
            cat > /dev/null
            return 0
        fi

        local line
        while IFS= read -r line || [[ -n "${line}" ]]; do
            EMSG_PREFIX="${EMSG_PREFIX:-} caller" emsg "${COLOR_DEBUG}" "" "DEBUG" "${line}"
        done
    fi
}

edebug_out()
{
    edebug_enabled && echo -n "/dev/stderr" || echo -n "/dev/null"
}

opt_usage einteractive <<'END'
Check if we are "interactive" or not. For our purposes, we are interactive if STDERR is attached to a terminal or not.
This is checked via the bash idiom "[[ -t 2 ]]" where "2" is STDERR. But we can override this default check with the
global variable EINTERACTIVE=1.
END
einteractive()
{
    [[ ${EINTERACTIVE:-0} -eq 1 ]] && return 0
    [[ -t 2 ]]
}

opt_usage einteractive_as_bool <<'END'
Get einteractive value as a boolean string
END
einteractive_as_bool()
{
    if einteractive; then
        echo -n "1"
    else
        echo -n "0"
    fi
}

opt_usage ecolor_code <<'END'
`ecolor_code` is used to map human color names like `black` to the corresponding ANSII color escape code (e.g. `0`).
This function supports the full 256 ANSII color code space.
END
ecolor_code()
{
   case $1 in

        # Primary
        black)            echo 0     ;;
        red)              echo 1     ;;
        green)            echo 2     ;;
        yellow)           echo 3     ;;
        blue)             echo 4     ;;
        magenta)          echo 5     ;;
        cyan)             echo 6     ;;
        white)            echo 7     ;;

        # Derivatives
        grey0)            echo 16     ;;
        navyblue)         echo 17     ;;
        darkgreen)        echo 22     ;;
        deepskyblue)      echo 24     ;;
        dodgerblue)       echo 26     ;;
        springgreen)      echo 35     ;;
        darkturqouise)    echo 44     ;;
        turquoise)        echo 45     ;;
        blueviolet)       echo 57     ;;
        orange)           echo 58     ;;
        slateblue)        echo 62     ;;
        paleturquoise)    echo 66     ;;
        steelblue)        echo 67     ;;
        cornflowerblue)   echo 69     ;;
        aquamarine)       echo 79     ;;
        darkred)          echo 88     ;;
        darkmagenta)      echo 90     ;;
        plum)             echo 96     ;;
        wheat)            echo 101    ;;
        lightslategrey)   echo 103    ;;
        darkseagreen)     echo 108    ;;
        darkviolet)       echo 128    ;;
        darkorange)       echo 130    ;;
        hotpink)          echo 132    ;;
        mediumorchid)     echo 134    ;;
        lightsalmon)      echo 137    ;;
        gold)             echo 142    ;;
        darkkhaki)        echo 143    ;;
        indianred)        echo 167    ;;
        orchid)           echo 170    ;;
        violet)           echo 177    ;;
        tan)              echo 180    ;;
        lightyellow)      echo 185    ;;
        honeydew)         echo 194    ;;
        salmon)           echo 209    ;;
        pink)             echo 218    ;;
        thistle)          echo 225    ;;

        # Lots of grey
        grey100)          echo 231    ;;
        grey3)            echo 232    ;;
        grey7)            echo 233    ;;
        grey11)           echo 234    ;;
        grey15)           echo 235    ;;
        grey19)           echo 236    ;;
        grey23)           echo 237    ;;
        grey27)           echo 238    ;;
        grey30)           echo 239    ;;
        grey35)           echo 240    ;;
        grey39)           echo 241    ;;
        grey42)           echo 242    ;;
        grey46)           echo 243    ;;
        grey50)           echo 244    ;;
        grey54)           echo 245    ;;
        grey58)           echo 246    ;;
        grey62)           echo 247    ;;
        grey66)           echo 248    ;;
        grey70)           echo 249    ;;
        grey74)           echo 250    ;;
        grey78)           echo 251    ;;
        grey82)           echo 252    ;;
        grey85)           echo 253    ;;
        grey89)           echo 254    ;;
        grey93)           echo 255    ;;

        # Unknown color code
        *)                die "Unknown color: $1" ;;
   esac

   return 0
}

opt_usage efuncs_color <<'END'
Determine value to use for efuncs_color. If `EFUNCS_COLOR` is empty then set it based on if STDERR is attached to a
console or not.
END
efuncs_color()
{
    ## If EFUNCS_COLOR is empty then set it based on if STDERR is attached to a console
    local value=${EFUNCS_COLOR:=}
    if [[ -z ${value} ]] && einteractive ; then
        value=1
    fi

    [[ ${value} -eq 1 ]]
}

opt_usage efuncs_color_as_bool <<'END'
Get efuncs_color as a boolean string.
END
efuncs_color_as_bool()
{
    if efuncs_color; then
        echo "1"
    else
        echo "0"
    fi
}

opt_usage ecolor <<'END'
`ecolor` is used to take a human color term such as `black` or with descriptors such as `bold black` and emit the ANSII
escape sequences needed to print to the screen to produce the desired color. Since we use a LOT of color messages
through ebash, this function caches the color codes in an associative array to avoid having to lookup the same values
repeatedly.

> **_NOTE:_** If `EFUNCS_COLOR` is set to `0`, this function is disabled and will not return any ANSII escape sequences.
END
ecolor()
{
    ## If EFUNCS_COLOR is empty then set it based on if STDERR is attached to a console
    local efuncs_color=${EFUNCS_COLOR:=}
    if [[ -z ${efuncs_color} ]] && einteractive ; then
        efuncs_color=1
    fi
    [[ ${efuncs_color} -eq 1 ]] || return 0

    declare -Ag __EBASH_COLOR_CACHE
    local index=$*
    if [[ ! -v "__EBASH_COLOR_CACHE[$index]" ]] ; then
        __EBASH_COLOR_CACHE[$index]=$(ecolor_internal "${index}")
    fi

    echo -n "${__EBASH_COLOR_CACHE[$index]}"
}

ecolor_internal()
{
    local c=""
    # We want to re-split the provided list of options on whitespace so disable shellcheck for this line
    # shellcheck disable=SC2068
    for c in $@; do
        case ${c} in
            dim)                echo -en "\033[2m"                 ;;
            invert)             tput rev                           ;;
            cub1|move_left)     tput cub1                          ;;
            el|clear_to_eol)    tput el                            ;;
            civis|hide_cursor)  tput civis                         ;;
            cvvis|show_cursor)  tput cnorm                         ;;
            cr|start_of_line)   tput cr                            ;;
            sc|save_cursor)     tput sc                            ;;
            rc|restore_cursor)  tput rc                            ;;
            bold)               tput bold                          ;;
            underline)          tput smul                          ;;
            reset|none|off)     echo -en "\033[0m"                 ;;
            b:*)                tput setab $(ecolor_code ${c#b:})  ;;
            *)                  tput setaf $(ecolor_code ${c})     ;;
        esac
    done
}

opt_usage noansi<<'END'
Noansi filters out ansi characters such as color codes. It can modify files in place if you specify any. If you do not,
it will assume that you'd like it to operate on stdin and repeat the modified output to stdout.
END
noansi()
{
    $(opt_parse "@files | Files to modify. If none are specified, operate on stdin and spew to stdout.")

    if array_empty files ; then
        sed "s:\x1B\[[0-9;]*[mK]::g"

    else
        sed -i "s:\x1B\[[0-9;]*[mK]::g" "${files[@]}"
    fi
}

opt_usage eclear <<'END'
`eclear` is used to clear the screen. But it's more portable than the standard `clear` command as it uses `tput` to
lookup the correct escape sequence needed to clear your terminal.
END
eclear()
{
    tput clear >&2
}

opt_usage ebanner<<'END'
Display a very prominent banner with a provided message which may be multi-line as well as the ability to provide any
number of extra arguments which will be included in the banner in a pretty printed tag=value optionally uppercasing the
keys if requested. All of this is implemented with print_value to give consistency in how we log and present information.
END
ebanner()
{
    $(opt_parse \
        "+uppercase upper u | If enabled, keys will be all uppercased." \
        "+lowercase lower l | If enabled, keys will be all lowercased." \
    )

    {
        local cols lines

        echo ""
        cols=$(tput cols)
        cols=$((cols-2))
        local str=""
        eval "str=\$(printf -- '-%.0s' {1..${cols}})"
        ecolor ${COLOR_BANNER}
        echo -e "+${str}+"
        ecolor ${COLOR_BANNER}
        echo -e "|"

        # Print the first message honoring any newlines
        array_init_nl lines "${1}"; shift
        for line in "${lines[@]}"; do
            ecolor ${COLOR_BANNER}
            echo -e "| ${line}"
        done

        # Iterate over all other arguments and stick them into an associative array optionally uppercasing the keys.
        # If a custom key was requested via "key=value" format then use the provided key and lookup value via print_value.
        declare -A details
        opt_forward expand_vars uppercase lowercase -- details "${@}"

        # Now output all the details (if any)
        if [[ -n "${details[*]:-}" ]]; then
            ecolor "${COLOR_BANNER}"
            echo -e "|"

            # Sort the keys and store into an array
            local keys
            keys=( $(for key in "${!details[@]}"; do echo "${key}"; done | sort) )

            # Figure out the longest key
            local longest=0
            for key in "${keys[@]}"; do
                local len=${#key}
                (( len > longest )) && longest=$len
            done

            # Iterate over the keys of the associative array and print out the values
            local pad="" ktag=""
            for key in "${keys[@]}"; do
                pad=$((longest-${#key}+1))
                ktag="${key}"

                # Optionally uppercase the key if requested.
                if [[ ${uppercase} -eq 1 ]]; then
                    ktag="${ktag^^}"
                fi

                ecolor "${COLOR_BANNER}"
                printf "| • %s%${pad}s :: %s\n" ${ktag} " " "${details[$key]}"
            done
        fi

        # Close the banner
        ecolor ${COLOR_BANNER}
        echo -e "|"
        ecolor ${COLOR_BANNER}
        echo -en "+${str}+"
        ecolor none
        echo ""

    } >&2

    return 0
}

opt_usage emsg <<'END'
`emsg` is a common function called by all logging functions inside ebash to allow a very configurable and extensible
logging format throughout all ebash code. The extremely configrable formatting of all ebash logging is controllable via
the `EMSG_PREFIX` environment variable.

Here are some examples showcasing how configurable this is:

```shell
$ EMSG_PREFIX=time ~/ebash_guide
[Nov 12 13:31:16] einfo
[Nov 12 13:31:16] ewarn
[Nov 12 13:31:16] eerror

$ EMSG_PREFIX=all ./ebash_guide
[Nov 12 13:24:19|INFO|ebash_guide:6:main] einfo
[Nov 12 13:24:19|WARN|ebash_guide:7:main] ewarn
[Nov 12 13:24:19|ERROR|ebash_guide:8:main] eerror
```

In the above you can the timestamp, log level, function name, line number, and filename of the code that generated the
message.

Here's the full list of configurable things you can turn on:
- time
- level
- caller
- pid
- all
END
emsg()
{
    {
        local color=$1 ; shift
        local header=$1 ; shift
        local level=$1 ; shift

        local final_newline=1

        if [[ ${1:-} == "-n" ]] ; then
            final_newline=0
            shift
        fi

        local msg="$*"

        local informative_header=0
        if [[ ${EMSG_PREFIX} =~ ${EBASH_WORD_BEGIN}(time|times|time_rfc3339|level|caller|pid|all)${EBASH_WORD_END} ]] ; then
            informative_header=1
        fi

        # Print the "informative header" containing things like timestamp, calling function, etc. We choose which ones
        # to print based on the contents of EMSG_PREFIX and which ones to color based on the value of EMSG_COLOR
        if [[ ${informative_header} == 1 && ${level} != @(INFOS|WARNS) ]] ; then
            ecolor $color
            echo -n "["
            ecolor reset

            local field first_printed=0
            for field in time time_rfc3339 level caller pid ; do

                # If the field is one selected by EMSG_PREFIX...
                if [[ ${EMSG_PREFIX} =~ ${EBASH_WORD_BEGIN}(all|${field})${EBASH_WORD_END} ]] ; then

                    # Separator if this isn't the first field to print
                    [[ ${first_printed} -eq 1 ]] && { ecolor reset ; echo -n "|" ; }

                    # Start color if appropriate
                    [[ ${EMSG_COLOR} =~ ${EBASH_WORD_BEGIN}(all|${field})${EBASH_WORD_END} ]] && ecolor $color

                    # Print the individual field
                    case ${field} in
                        time|times)
                            etimestamp
                            ;;
                        time_rfc3339)
                            etimestamp_rfc3339
                            ;;
                        level)
                            echo -n "${level}"
                            ;;
                        caller)
                            # BASH_SOURCE can be unbound if sourced code calls back to a caller's function
                            local source_file=${BASH_SOURCE[2]:-unknown}
                            # First field is filename with path info stripped off
                            echo -n "${source_file##*/}:${BASH_LINENO[1]:-0}:${FUNCNAME[2]:-unknown}"
                            ;;
                        pid)
                            echo -n "${BASHPID}"
                            ;;
                        *)
                            die "Internal error."
                            ;;
                    esac

                    first_printed=1
                    ecolor reset
                fi

            done

            ecolor $color
            echo -n "] "

        else
            # If not the informative header, just use the message-type-specific header passed as an argument to emsg
            ecolor $color
            echo -n "${header} "
        fi

        declare msg_color=1
        # If EMSG_COLOR doesn't say to color the message turn off color before we start printing it
        [[ ! ${EMSG_COLOR} =~ ${EBASH_WORD_BEGIN}(all|msg)${EBASH_WORD_END} ]] && { msg_color=0 ; ecolor reset ; }

        # Also, only print colored messages for certain levels
        [[ ${level} != @(DEBUG|WARN|WARNS|ERROR) ]] && { msg_color=0 ; ecolor reset ; }

        echo -n "${msg}"
        [[ ${msg_color} -eq 1 ]] && ecolor reset

        if [[ ${final_newline} -eq 1 ]] ; then
            echo ""
        fi
    } >&2
}

opt_usage tput <<'END'
`tput` is a wrapper around the real `tput` command that allows us more control over how to deal with `COLUMNS` not being
set properly in non-interactive environments such as our CI/CD build system. We also allow explicitly setting `COLUMNS`
to something and honoring that and bypassing calling `tput`. This is useful in our CI/CD build systems where we do not
have a console so `tput cols` would return an error. This also gracefully handles the scenario where tput isn't installed
at all as in some super stripped down docker containers.
END
tput()
{
    if [[ "${1:-}" == "cols" ]]; then

        if [[ -n "${COLUMNS:-}" ]]; then
            echo "${COLUMNS}"
            return 0
        elif which tput &>/dev/null; then
            command tput cols || true
            return 0
        else
            echo "80"
            return 0
        fi
    fi

    if ! which tput &> /dev/null; then
        return 0
    fi

    command tput "$@" || true
}

opt_usage einfo <<'END'
`einfo` is used to log informational messages to STDERR. They are prefixed with `>>` in `COLOR_INFO` which is `green` by
default. `einfo` is called just like you would normally call `echo`.
END
einfo()
{
    emsg "${COLOR_INFO}" ">>" "INFO" "$@"
}

opt_usage einfos <<'END'
`einfos` is used to log informational **sub** messages to STDERR. They are intdented and prefixed with a `-` in
`COLOR_INFOS` which is `cyan` by default. `einfos` is called just like you would normally call `echo`. This is designed
to line up underneath `einfo` messages to show submessages.
END
einfos()
{
    emsg "${COLOR_INFO}" "   -" "INFOS" "$@"
}

opt_usage ewarn <<'END'
`ewarn` is used to log warning messages to STDERR. They are prefixed with `>>` in `COLOR_WARN` which is `yellow` by
default. `ewarn` is called just like you would normally call `echo`.
END
ewarn()
{
    emsg "${COLOR_WARN}" ">>" "WARN" "$@"
}

opt_usage ewarns <<'END'
`ewarns` is used to log warning **sub** messages to STDERR. They are intdented and prefixed with a `-` in `COLOR_WARNS`
which is `yellow` by default. `ewarns` is called just like you would normally call `echo`. This is designed to line up
underneath `einfo` or `ewarn` messages to show submessages.
END
ewarns()
{
    emsg "${COLOR_WARN}" "   -" "WARNS" "$@"
}

opt_usage __eerror_internal <<'END'
`__eerror_internal` is an internal helper method to help make calling `eerror` more reusable internally.
END
__eerror_internal()
{
    $(opt_parse ":color c=${COLOR_ERROR} | Color to print the message in.")
    emsg "${color}" ">>" "ERROR" "$@"
}

opt_usage eerror <<'END'
`eerror` is used to log error messages to STDERR. They are prefixed with `!!` in `COLOR_ERROR` which is `red` by
default. `eerror` is called just like you would normally call `echo`.
END
eerror()
{
    emsg "${COLOR_ERROR}" ">>" "ERROR" "$@"
}

opt_usage etestmsg <<'END'
`etestmsg` is used to log informational testing related messages to STDERR. This is typically used inside `etest` test
code. These log messages are prefixed with `##` in `cyan`. `etestmsg` is called just like you would normally call
`echo`.
END
etestmsg()
{
    EMSG_COLOR="all" emsg "cyan" "##" "WARN" "$@"
}

opt_usage eerror_stacktrace <<'END'
Print an error stacktrace to stderr. This is like stacktrace only it pretty prints the entire stacktrace as a bright red
error message with the funct and file:line number nicely formatted for easily display of fatal errors.

Allows you to optionally pass in a starting frame to start the stacktrace at. 0 is the top of the stack and counts up.
See also stacktrace and eerror_stacktrace.
END
eerror_stacktrace()
{
    $(opt_parse \
        ":frame f=2              | Frame number to start at. Defaults to 2, which skips this function and its caller." \
        "+skip s                 | Skip the initial error message. Useful if the caller already displayed it." \
        ":color c=${COLOR_ERROR} | Use the specified color for output messages.")

    if [[ ${skip} -eq 0 ]]; then
        echo "" >&2
        __eerror_internal -c="${color}" "$@"
    fi

    local frames=() frame
    stacktrace_array -f=${frame} frames

    if array_empty frames; then
        return 0
    fi

    local line="" func="" file=""
    for frame in "${frames[@]}"; do
        line=$(echo ${frame} | awk '{print $1}')
        func=$(echo ${frame} | awk '{print $2}')
        file=$(basename $(echo ${frame} | awk '{print $3}'))

        [[ ${file} == "efuncs.sh" && ${func} == ${FUNCNAME} ]] && break

        printf "$(ecolor ${color})   :: %-20s | ${func}$(ecolor none)\n" "${file}:${line}" >&2
    done
}

opt_usage eend <<'END'
`eend` is used to print an informational ending message suitable to be called after an `emsg` function. The format of
this message is dependent upon the `return_code`. If `0`, this will print `[ ok ]` and if non-zero it will print `[ !! ]`.
END
eend()
{
    $(opt_parse \
        "+inline n=0        | Display eend inline rather than outputting a leading newline. The reason we emit a leading
                              newline by default is to work properly with emsg functions (e.g. einfo, ewarn, eerror) as
                              they all emit a message and then a trailing newline to move to the next line. When paired
                              with an eend, we want that eend message to show up on the SAME line. So we emit some
                              terminal magic to move up a line, and then right justify the eend message. This doesn't
                              work very well for non-interactive displays or in CI/CD output so you can disable it."   \
        ":inline_offset o=0 | Number of characters to offset inline mode by."                                          \
        "return_code=0      | Return code of the command that last ran. Success (0) will cause an 'ok' message and any
                              non-zero value will emit '!!'."                                                          \
    )

    # Get the number of columns
    local colums=0 startcol=0
    columns=$(tput cols)

    # If interactive AND not inline mode, move cursor up a line and then move it over to the far right column
    if einteractive && [[ ${inline} -eq 0 ]]; then
        startcol=$(( columns - 6 ))
        if [[ ${startcol} -gt 0 ]]; then
            echo -en "$(tput cuu1)$(tput cuf ${startcol} 2>/dev/null)" >&2
        fi
    else
        startcol=$(( columns - inline_offset - 6 ))

        if [[ ${startcol} -gt 0 ]]; then
            # Do NOT use tput here for padding. If we're non-interactive, it's not going to do what we expect. Instead
            # just print out a padded string that moves us to the desired position.
            local eend_pad
            eval "eend_pad=\$(printf -- ' %.0s' {1..${startcol}})"
            echo -en "${eend_pad}" >&2
        fi
    fi

    # NOW we can emit the actual success or failure message based on the provided return code.
    if [[ ${return_code} -eq 0 ]]; then
        echo -e "$(ecolor ${COLOR_BRACKET})[$(ecolor ${COLOR_INFO}) ok $(ecolor ${COLOR_BRACKET})]$(ecolor none)" >&2
    else
        echo -e "$(ecolor ${COLOR_BRACKET})[$(ecolor ${COLOR_ERROR}) !! $(ecolor ${COLOR_BRACKET})]$(ecolor none)" >&2
    fi
}

opt_usage print_value <<'END'
Print the value for the corresponding variable using a slightly modified version of what is returned by declare -p. This
is the lower level function called by lval in order to easily print tag=value for the provided arguments to lval. The
type of the variable will dictate the delimiter used around the value portion. Wherever possible this is meant to
generally mimic how the types are declared and defined.

Specifically:
  1) Strings: delimited by double quotes.
  2) Arrays and associative arrays: Delimited by ( ).
  3) Packs: You must preceed the pack name with a percent sign (i.e. %pack)

Examples:
  1) String: `"value1"`
  2) Arrays: `("value1" "value2 with spaces" "another")`
  3) Associative Arrays: `([key1]="value1" [key2]="value2 with spaces" )`
END
print_value()
{
    local __input=${1:-}
    [[ -z ${__input} ]] && return 0

    # Special handling for packs, as long as their name is specified with a '%' character in front of it
    if [[ "${__input:0:1}" == '%' ]] ; then
        pack_print "${__input:1}"
        return 0
    fi

    local __decl __val
    __decl=$(declare -p ${__input} 2>/dev/null || true)
    __val=$(echo "${__decl}")
    __val=${__val#*=}

    # Deal with properly declared variables which are empty
    [[ -z ${__val} ]] && __val='""'

    # Special handling for arrays and associative arrays
    local __array_regex="declare -a"
    local __assoc_regex="declare -A"
    if [[ ${__decl} =~ ${__array_regex} ]] ; then
        if [[ ${BASH_VERSINFO[0]} -ge 5 || ( ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -gt 3 ) ]] ; then
            # BASH 4.4 and beyond -- no single quote
            __val=$(declare -p ${__input} | sed -e "s/[^=]*=(\(.*\))/(\1)/" -e "s/[[[:digit:]]\+]=//g")
        else
            # BASH 4.2 and 4.3
            __val=$(declare -p ${__input} | sed -e "s/[^=]*='(\(.*\))'/(\1)/" -e "s/[[[:digit:]]\+]=//g")
        fi
    elif [[ ${__decl} =~ ${__assoc_regex} ]]; then
        __val="("
        local key
        for key in $(array_indexes_sort ${__input}); do
            eval '__val+="['${key}']=\"${'${__input}'['$key']}\" "'
        done
        __val+=")"
    fi

    echo -n "${__val}"
}

opt_usage expand_vars <<'END'
Iterate over arguments and interpolate them as-needed and store the resulting "key" and "value" into a provided
associative array. For each entry, if a custom "key=value" syntax is used, then "value" is checked to see if it refers
to another variable. If so, then it is expanded/interpolated using the `print_value` function. If it does not reference
another variable name, then it will be used as-is. This implementation allows for maximum flexibility at the call-site
where they want to have some variables reference other variables underlying values, as in:

```shell
expand_vars details DIR=PWD
```

But also sometimes want to be able to just directly provide the string literal to use, as in:

```shell
expand_vars details DIR="/home/marshall"
```

The keys may optionally be uppercased for consistency and quotes may optionally be stripped off of the resulting value
we load into the associative array.
END
expand_vars()
{
    $(opt_parse \
        "+uppercase | Uppercase the keys for consistency"                                                              \
        "+lowercase | Lowercase the keys for consistency"                                                              \
        "+quotes=1  | Include quotation marks around value."                                                           \
        "__details  | Name of the associative array to load the key=value pairs into."                                 \
        "@entries   | Variadic list of variables to interpolate and load the resulting values into the details array." \
    )

    local __entry __key __val __valexp
    for __entry in "${entries[@]:-}"; do
        [[ -z ${__entry} ]] && continue

        # Check if this is of the form KEY=VALUE. If so, attempt to expand VALUE if it's a variable. If it's not, use
        # it as-is.
        if [[ "${__entry}" =~ "=" ]]; then
            __key="${__entry%%=*}"
            __val="${__entry#*=}"
            __valexp="$(print_value ${__val})"
            if [[ "${__valexp}" != '""' ]]; then
                __val="${__valexp}"
            fi
            __key=${__key%}
        else
            __key="${__entry}"
            __val="$(print_value ${__key})"
        fi

        # Optionally uppercase the key if requested.
        if [[ ${uppercase} -eq 1 ]]; then
            __key="${__key^^}"
        elif [[ ${lowercase} -eq 1 ]]; then
            __key="${__key,,}"
        fi

        if [[ "${quotes}" -eq 1 ]]; then
            printf -v ${__details}[${__key}] "${__val}"
        else
            printf -v ${__details}[${__key}] "$(echo ${__val} | sed -e 's|^"||' -e 's|"$||')"
        fi
    done
}

opt_usage lval <<'END'
Log a list of variable in tag="value" form similar to our C++ logging idiom. This function is variadic (takes variable
number of arguments) and will log the tag="value" for each of them. If multiple arguments are given, they will be
separated by a space, as in: tag="value" tag2="value2" tag3="value3"

This is implemented via calling print_value on each entry in the argument list. The one other really handy thing this
does is understand our C++ LVAL2 idiom where you want to log something with a _different_ key. So you can say nice
things like:

```shell
$(lval PWD=$(pwd) VARS=myuglylocalvariablename)
```

You can optionally pass in -n or --no-quotes and it will omit the outer-most quotes used on simple variables such as
strings and numbers. But array and associative array values are still quoted to avoid ambiguity.
END
lval()
{
    local quotes=1
    if [[ "${1:-}" == "-n" || ${1:-} == "--no-quotes" ]] ; then
        quotes=0
        shift
    fi

    local __lval_pre=""
    for __arg in "${@}"; do

        # Tag provided?
        local __arg_tag=${__arg%%=*}; [[ -z ${__arg_tag} ]] && __arg_tag=${__arg}
        local __arg_val=${__arg#*=}
        __arg_tag=${__arg_tag#%}

        if [[ "${quotes}" -eq 1 ]]; then
            __arg_val="$(print_value "${__arg_val}")"
        else
            __arg_val="$(print_value "${__arg_val}" | sed -e 's|^"||' -e 's|"$||')"
        fi

        echo -n "${__lval_pre}${__arg_tag}=${__arg_val}"
        __lval_pre=" "
    done
}
