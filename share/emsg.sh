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
: ${COLOR_DEBUG:="dim blue"}
: ${COLOR_TRACE:="yellow"}
: ${COLOR_WARN:="bold yellow"}
: ${COLOR_ERROR:="bold red"}
: ${COLOR_BRACKET:="bold blue"}
: ${COLOR_BANNER:="bold magenta"}
: ${COLOR_USAGE:="bold green"}

# By default enable eprogress style tickers
: ${EPROGRESS:=1}

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
: ${ETRACE_BLACKLIST:=@(opt_parse|opt_parse_setup|opt_parse_options|opt_parse_arguments|opt_parse_find_canonical|argcheck|ecolor|ecolor_internal|ecolor_code|einteractive|emsg|string_trim|print_value|lval|disable_signals|reenable_signals|eerror_internal|eerror_stacktrace|stacktrace|stacktrace_array|signame|array_size|array_empty|array_not_empty)}

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

edebug_disabled()
{
    ! edebug_enabled
}

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

#opt_usage einteractive <<'END'
#Check if we are "interactive" or not. For our purposes, we are interactive if STDERR is attached to a terminal or not.
#This is checked via the bash idiom "[[ -t 2 ]]" where "2" is STDERR. But we can override this default check with the
#global variable EINTERACTIVE=1.
#END
einteractive()
{
    [[ ${EINTERACTIVE:-0} -eq 1 ]] && return 0
    [[ -t 2 ]]
}

#opt_usage einteractive_as_bool <<'END'
#Get einteractive value as a boolean string
#END
einteractive_as_bool()
{
    if einteractive; then
        echo -n "1"
    else
        echo -n "0"
    fi
}

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

#opt_usage efuncs_color <<'END'
#Determine value to use for efuncs_color.
#If EFUNCS_COLOR is empty then set it based on if STDERR is attached to a console
#END
efuncs_color()
{
    ## If EFUNCS_COLOR is empty then set it based on if STDERR is attached to a console
    local value=${EFUNCS_COLOR:=}
    if [[ -z ${value} ]] && einteractive ; then
        value=1
    fi

    [[ ${value} -eq 1 ]]
}

#opt_usage efuncs_color_as_bool <<'END'
#Get efuncs_color as a boolean string.
#END
efuncs_color_as_bool()
{
    if efuncs_color; then
        echo "1"
    else
        echo "0"
    fi
}

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

eclear()
{
    tput clear >&2
}

etimestamp()
{
    if [[ "${ETIMESTAMP_FORMAT:-}" == "StampMilli" ]]; then
        echo -en "$(date '+%b %d %T.%3N')"
    elif [[ "${ETIMESTAMP_FORMAT:-}" == "RFC3339" ]]; then
        echo -en "$(date '+%FT%TZ')"
    else
        die "Unsupported $(lval ETIMESTAMP_FORMAT)"
    fi
}

etimestamp_rfc3339()
{
    echo -en $(date '+%FT%TZ')
}

opt_usage ebanner<<'END'
Display a very prominent banner with a provided message which may be multi-line as well as the ability to provide any
number of extra arguments which will be included in the banner in a pretty printed tag=value optionally upercasing the
keys if requested. All of this is implemented with print_value to give consistency in how we log and present information.
END
ebanner()
{
    $(opt_parse \
        "+uppercase upper u | If enabled, keys will be all uppercased.")

    {
        local cols lines entries

        echo ""
        cols=${COLUMNS:-80}
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
        declare -A __details

        local entries=("${@}")
        for k in "${entries[@]:-}"; do
            [[ -z ${k} ]] && continue

            local _ktag="${k%%=*}"
            : ${_ktag:=${k}}
            local _kval="${k#*=}"
            _ktag=${_ktag#%}

            # Optionally uppercase the key if requested.
            if [[ ${uppercase} -eq 1 ]]; then
                _ktag="${_ktag^^}"
            fi

            __details[${_ktag}]=$(print_value ${_kval})

        done

        # Now output all the details (if any)
        if [[ -n ${__details[@]:-} ]]; then
            ecolor ${COLOR_BANNER}
            echo -e "|"

            # Sort the keys and store into an array
            local keys
            keys=( $(for key in ${!__details[@]}; do echo "${key}"; done | sort) )

            # Figure out the longest key
            local longest=0
            for key in ${keys[@]}; do
                local len=${#key}
                (( len > longest )) && longest=$len
            done

            # Iterate over the keys of the associative array and print out the values
            local pad="" ktag=""
            for key in ${keys[@]}; do
                pad=$((longest-${#key}+1))
                ktag="${key}"

                # Optionally uppercase the key if requested.
                if [[ ${uppercase} -eq 1 ]]; then
                    ktag="${ktag^^}"
                fi

                ecolor ${COLOR_BANNER}
                printf "| • %s%${pad}s :: %s\n" ${ktag} " " "${__details[$key]}"
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

tput()
{
    if [[ "${1:-}" == "cols" && -n "${COLUMNS:-}" ]] ; then
        echo "${COLUMNS}"
        return 0
    fi

    command tput $@ 2>/dev/null || true
}

einfo()
{
    emsg "${COLOR_INFO}" ">>" "INFO" "$@"
}

einfos()
{
    emsg "${COLOR_INFO}" "   -" "INFOS" "$@"
}

ewarn()
{
    emsg "${COLOR_WARN}" ">>" "WARN" "$@"
}

ewarns()
{
    emsg "${COLOR_WARN}" "   -" "WARNS" "$@"
}

eerror_internal()
{
    $(opt_parse ":color c=${COLOR_ERROR} | Color to print the message in.")
    emsg "${color}" ">>" "ERROR" "$@"
}

eerror()
{
    emsg "${COLOR_ERROR}" ">>" "ERROR" "$@"
}

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
        eerror_internal -c="${color}" "$@"
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

spinout()
{
    local char="$1"
    echo -n -e "\b${char}" >&2
    sleep 0.10
}

eprogress()
{
    $(opt_parse \
        ":align=left                      | Where to align the tickker to (valid options are 'left' and 'right')."     \
        ":delay=${EPROGRESS_DELAY:-}      | Optional delay between tickers to avoid flooding the screen. Useful for
                                            automated CI/CD builds where we are not writing to an actual terminal but
                                            want to see periodic updates."                                             \
        "+spinner=${EPROGRESS_SPINNER:-1} | Display spinner inline with the message and timer."                        \
        "+inline=${EPROGRESS_INLINE:-1}   | Display message, timer and spinner all inline. If you disable this the full
                                            message and timer is printed on a separate line on each iteration instead.
                                            This is useful for automated CI/CD builds where we are not writing to an
                                            actual terminal."                                                          \
        "+delete d=1                      | Delete file when eprogress completes if one was specified via --file."     \
        ":file f                          | A file whose contents should be continually updated and displayed along with
                                            the ticker. This file will be deleted by default when eprogress completes."\
        "+time=1                          | As long as not turned off with --no-time, the amount of time since eprogress
                                            start will be displayed next to the ticker."                               \
        ":style=einfo                     | Style used when displaying the message. You might want to use, for instance,
                                            einfos or ewarn or eerror instead."                                        \
        "@message                         | A message to be displayed once prior to showing a time ticker. This will
                                            occur before the file contents if you also use --file.")

    assert_match "${align}" "(left|right)"

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0. Simply display static message and then return.
    if [[ ${EPROGRESS} -eq 0 ]]; then

        "${style}" -n "$* "

        # Delete file if requested
        if [[ -n ${file} && -r ${file} && ${delete} -eq 1 ]] ; then
            rm --force "${file}"
        fi

        return 0
    fi

    # Background a subshell to perform actual eprogress ticker work. Store the new pid in our list of eprogress PIDs
    # and setup a trap to ensure we kill this background process in the event we die before calling eprogress_kill.
    (
        # Close any file descriptors our parent had open.
        close_fds

        # Don't produce any errors when tools here catch a signal. That's what we expect to happen
        nodie_on_error

        # Sentinal for breaking out of the loop on signal from eprogress_kill
        local done=0
        trap "done=1" ${DIE_SIGNALS[@]}

        # Display static message.
        "${style}" -n "$*"

        # Save current position and start time
        if [[ ${inline} -eq 1 ]]; then
            ecolor save_cursor >&2
        fi
        local start=${SECONDS}

        # Infinite loop until we are signaled to stop at which point 'done' is set to 1 and we'll break out
        # gracefully at the right point in the loop.
        local new="" diff="" lines=0 columns=0 offset=0
        while true; do
            now="${SECONDS}"
            diff=$(( ${now} - ${start} ))

            # Display file contents if appropriate (minus final newline)
            if [[ -n ${file} && -r ${file} ]] ; then
                printf "%s" "$(<${file})"
            fi

            if [[ ${time} -eq 1 ]] ; then

                # Terminal magic that moves our cursor to the bottom right corner of the screen then backs it up just
                # enough to allow the ticker to display such that it is right justified instead of lost on the far left
                # of the screen intermingled with actions being performed.
                if [[ "${align}" == "right" ]]; then
                    lines=$(tput lines)
                    columns=$(tput cols)
                    offset=$(( columns - 18 ))
                    tput cup "${lines}" "${offset}" 2>/dev/null
                fi

                ecolor bold
                printf " [%02d:%02d:%02d] " $(( ${diff} / 3600 )) $(( (${diff} % 3600) / 60 )) $(( ${diff} % 60 ))
                ecolor none
            fi

            # Optionally display the spinner.
            if [[ ${spinner} -eq 1 ]]; then
                echo -n " "
                ecolor clear_to_eol

                spinout "/"
                spinout "-"
                spinout "\\"
                spinout "|"
                spinout "/"
                spinout "-"
                spinout "\\"
                spinout "|"
            fi

            # If we are done then break out of the loop and perform necessary clean-up. Otherwise prepare for next
            # iteration.
            if [[ ${done} -eq 1 ]]; then
                break
            fi

            # Optionally sleep if delay was requested.
            if [[ -n "${delay}" ]]; then
                sleep "${delay}"
            fi

            # If we are NOT in inline mode, then emit a newline followed by the static message to prepare for the next
            # iteration.
            if [[ ${inline} -eq 0 ]]; then
                printf "\n"
                "${style}" -n "$*"
            else
                ecolor restore_cursor
            fi

        done >&2

        # If we're terminating delete whatever character was lost displayed and print a blank space over it
        { ecolor move_left ; echo -n " " ; } >&2

        # Delete file if requested
        if [[ -n ${file} && -r ${file} && ${delete} -eq 1 ]] ; then
            rm --force "${file}"
        fi

        # Always exit with success
        exit 0

    ) &

    __EBASH_EPROGRESS_PIDS+=( $! )
    trap_add "eprogress_kill -r=1 $!"
}

opt_usage eprogress_kill <<'END'
Kill the most recent eprogress in the event multiple ones are queued up. Can optionally pass in a specific list of
eprogress pids to kill.
END
eprogress_kill()
{
    $(opt_parse \
        ":rc return_code r=0  | Should this eprogress show a mark for success or failure?" \
        "+all a               | If set, kill ALL known eprogress processes, not just the current one")

    # Allow caller to opt-out of eprogress entirely via EPROGRESS=0
    if [[ ${EPROGRESS} -eq 0 ]] ; then
        eend ${rc}
        return 0
    fi

    # If given a list of pids, kill each one. Otherwise kill most recent. If there's nothing to kill just return.
    local pids=()
    if [[ $# -gt 0 ]]; then
        pids=( ${@} )
    elif array_not_empty __EBASH_EPROGRESS_PIDS; then
        if [[ ${all} -eq 1 ]] ; then
            pids=( "${__EBASH_EPROGRESS_PIDS[@]}" )
        else
            pids=( "${__EBASH_EPROGRESS_PIDS[-1]}" )
        fi
    else
        return 0
    fi

    # Kill requested eprogress pids
    local pid
    for pid in ${pids[@]}; do

        # Don't kill the pid if it's not running or it's not an eprogress pid. This catches potentially disasterous
        # errors where someone would do "eprogress_kill ${rc}" when they really meant "eprogress_kill -r=${rc}"
        if process_not_running ${pid} || ! array_contains __EBASH_EPROGRESS_PIDS ${pid}; then
            continue
        fi

        # Kill process and wait for it to complete
        ekill ${pid} &>/dev/null
        wait ${pid} &>/dev/null || true
        array_remove __EBASH_EPROGRESS_PIDS ${pid}

        # Output
        einteractive && echo "" >&2
        eend ${rc}
    done

    return 0
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
  1) String: "value1"
  2) Arrays: ("value1" "value2 with spaces" "another")
  3) Associative Arrays: ([key1]="value1" [key2]="value2 with spaces" )
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
        if [[ BASH_VERSINFO[0] -ge 5 || ( BASH_VERSINFO[0] -eq 4 && BASH_VERSINFO[1] -gt 3 ) ]] ; then
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

opt_usage lval <<'END'
Log a list of variable in tag="value" form similar to our C++ logging idiom. This function is variadic (takes variable
number of arguments) and will log the tag="value" for each of them. If multiple arguments are given, they will be
separated by a space, as in: tag="value" tag2="value2" tag3="value3"

This is implemented via calling print_value on each entry in the argument list. The one other really handy thing this
does is understand our C++ LVAL2 idiom where you want to log something with a _different_ key. So you can say nice
things like:

$(lval PWD=$(pwd) VARS=myuglylocalvariablename)
END
lval()
{
    local __lval_pre=""
    for __arg in "${@}"; do

        # Tag provided?
        local __arg_tag=${__arg%%=*}; [[ -z ${__arg_tag} ]] && __arg_tag=${__arg}
        local __arg_val=${__arg#*=}
        __arg_tag=${__arg_tag#%}
        __arg_val=$(print_value "${__arg_val}")

        echo -n "${__lval_pre}${__arg_tag}=${__arg_val}"
        __lval_pre=" "
    done
}

return 0
