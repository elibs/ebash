#!/bin/bash
#
# Copyright 2015-2016, SolidFire, Inc. All rights reserved.
#

: <<'END'
opt_parse
============

Terminology
-----------

First a quick bit of background on the terminology used for bashutils parameter
parsing.  Different well-meaning folks use different terms for the same things,
but these are the definitions as they apply within bashutils documentation.

First, here's an example command line you might use to search for lines that do
not contain "alpha" within a file named "somefile".

    grep --word-regexp -v alpha somefile

In this case --word-regexp and -v are _options_.  That is to say, they're
optional flags to the command whose names start with hyphens.  Options follow
the GNU style in that single character options have one hyphen before their
name, while long options have two hyphens before their name.

Typically, a single functionality within a tool can be controlled by the
caller's choice of either a long option or a short option.  For instance, grep
considers -v and --invert to be equivalent options.

_Arguments_ are the positional things that must occur on the command line
following all of the options.  If you're ever concerned that there could be
ambiguity, you can explicitly separate the two with a pair of hyphens on their
own.  The following is equivalent to the first example.

    grep --word-regex -v -- alpha somefile


To add to the confusing terminology, some options accept their own arguments.
For example, grep can limit the number of matches with the --max-count option.
This will print the first line in somefile that matches alpha.

    grep --max-count 1 alpha somefile.

So we say that if --max-count is specified, it requires an _argument_.


Arguments
---------

The simplest functions frequently just take an argument or two.  We discovered
early in the life of bashutils a frequent pattern:

    foo()
    {
        local arg1=$1
        local arg2=$2
        shift 2
        argcheck arg1 arg2
    
        # Do some stuff here with ${arg1} and ${arg2}
    }

But we wanted to make it more concise. Enter opt_parse.  This is equivalent
to those four lines of argument handling code in `foo()`.  That is, it creates
two local variables (`arg1` and `arg2`) and then verifies that both of them are
non-empty by calling `argcheck` on them.

    $(opt_parse arg1 arg2)

As a best practice, we suggest documenting said arguments within the opt_parse
declaration.  Note that each quoted string passed to opt_parse creates a single
argument or option.  Pipe characters separate sections, and whitespace near the
pipe characters is discarded. This, too, is equivalent.

    $(opt_parse \
        "arg1 | This is what arg1 means." \
        "arg2 | This is what arg2 means.")

Note that `argcheck` in the original example ensures that your function will blow
up if either `arg1` or `arg2` is empty.  This is pretty handy for bash functions,
but not always what you want.  You can specify that a given argument _may_ be
empty by putting a question mark before its name.

    $(opt_parse \
        "arg1  | This argument must contain at least a character." \
        "?arg2 | This argument may be empty.")

You may also specify a default value for an argument.

    $(opt_parse \
        "file=filename.json | This argument defaults to filename.json")

Note that having a default value is a separate concern from the check that
verifies that the value is non-empty.

    $(opt_parse \
        "a    | Default is empty, blows up if it is called with no value" \
        "?b   | Default is empty, doesn't mind being called with no value" \
        "c=1  | Default is 1, if called with '', will blow up" \
        "?d=1 | Default is 1, will still be happy if '' is specified")


Options
--------

Options are specified in a similar form to arguments.  The biggest difference
is that options may have multiple names.  Both short and long options are
supported.

    $(opt_parse \
        "+word_regex w | if specified, match only complete words" \
        "+invert v     | if specified, match only lines that do NOT contain the regex.")

    [[ ${word_regex} -eq 1 ]] && # do stuff for words
    [[ ${invert}     -eq 1 ]] && # do stuff for inverting

 
As with arguments, `opt_parse` creates a local variable for each option.  The
name of that variable is always the _first_ name given.

This means that -w and --word-regex are equivalent, and so are --invert and -v.
Note that there's a translation here in the name of the option. By convention,
words are separated with hyphens in option names, but hyphens are not allowed
to be characters in bash variables, so we use underscores in the variable name
and automatically translate that to a hyphen in the option name.

At present, bashutils supports two different types of options: boolean and
string.


Boolean Options
---------------

Word_regex and invert in the example above are both boolean options.  That is,
they're either on the command line (in which case opt_parse assigns 1 to the
variable) or not on the command line (in which case opt_parse assigns 0 to the
variable).

You can also be explicit about the value you'd like to choose for an option by
specifying =0 or =1 at the end of the option.  For instance, these are
equivalent and would enable the word_regex option and disable the invert
option.

    cmd --invert=0 --word-regex=1
    cmd -i=0 -w=1

Note that these two options are considered to be boolean.  Either they were
specified on the command line or they were not.  When specified, the value of
the variable will be 1, when not specified it will be zero.

The long option versions of boolean options also implicitly support a negation
by prepending the option name with no-.  For example, this is also equivalent
to the above examples.

    cmd --no-invert --word-regex


String Options
--------------

Opt_parse also supports options whose value is a string.  When specified on the
command line, these _require_ an argument, even if it is an empty string.  In
order to get a string option, you prepend its name with a colon character.

    func()
    {
        $(opt_parse ":string s")
        echo "STRING: X${string}X"
    }

    func --string "alpha"
    # output -- STRING: XalphaX
    func --string ""
    # output -- STRING: XX

    func --string=alpha
    # output -- STRING: XalphaX
    func --string=
    # output -- STRING: XX


Default Values
--------------

By default, the value of boolean options is false and string options are an
empty string, but you can specify a default in your definition just as you
would with arguments.

    $(opt_parse \
        "+boolean b=1        | Boolean option that defaults to true" \
        ":string s=something | String option that defaults to "something")


Automatic Help
--------------

Opt_parse automatically supports a --help option for you, which will display
a usage statement using the docstrings that you provided for each of the
options and arguments.

Functions called with --help as processed by opt_parse will not perform their
typical operation and will instead return successfully after printing this
usage statement.

END
opt_parse()
{
    # An interesting but non-obvious trick is being played here.
    # Opt_parse_setup is called during the opt_parse call, and it sets up some
    # variables (such as __BU_OPT and __BU_ARG).  Since they're already
    # created, when we eval the calls to opt_parse_options and
    # opt_parse_arguments, we can modify those variables and pass them amongst
    # the internals of opt_parse.  This makes it easier to write the more
    # complicated stuff in literal functions.  Then we can limit the size of
    # the blocks of code that have to be "echo"-ed out for the caller to
    # execute.  Much simpler to get them to call a function (but of course that
    # function can't create local variables for them).
    echo "eval "
    opt_parse_setup "${@}"

    # __BU_FULL_ARGS is the list of arguments as initially passed to
    # opt_parse. Opt_parse_options will modifiy __BU_ARGS to be whatever was
    # left to be processed after it is finished. Note: here $@ is quoted so it
    # refers to the caller's arguments
    echo 'declare __BU_FULL_ARGS=("$@") ; '
    echo 'declare __BU_ARGS=("$@") ; '
    echo 'declare __BU_OPT_USAGE_REQUESTED=0 ; '
    echo "opt_parse_options ; "

    # If usage was requsted, print it and return success without doing anything
    # else
    echo 'if [[ ${__BU_OPT_USAGE_REQUESTED:-0} -eq 1 ]] ; then '
    echo '   opt_display_usage ; '
    echo '   [[ -v FUNCNAME ]] && return 0 || exit 0 ; '
    echo 'fi ; '

    # Process options
    echo 'declare opt ; '
    echo 'if [[ ${#__BU_OPT[@]} -gt 0 ]] ; then '
        echo 'for opt in "${!__BU_OPT[@]}" ; do'
            echo 'declare "${opt//-/_}=${__BU_OPT[$opt]}" ; '
        echo 'done ; '
    echo 'fi ; '

    # Process arguments
    echo 'opt_parse_arguments ; '
    echo 'if [[ ${#__BU_ARG[@]} -gt 0 ]] ; then '
        echo 'for index in "${!__BU_ARG[@]}" ; do '
            echo '[[ -n ${index} ]] || continue ; '
            echo '[[ ${__BU_ARG_NAMES[$index]} != _ ]] && declare "${__BU_ARG_NAMES[$index]}=${__BU_ARG[$index]}" ; '
        echo 'done ; '
    echo 'fi ; '
    echo 'argcheck "${__BU_ARG_REQUIRED[@]:-}" ; '
    echo '[[ ${#__BU_ARGS[@]:-} -gt 0 ]] && set -- "${__BU_ARGS[@]}" || set -- ; '
}

opt_parse_setup()
{
    local opt_cmd="__BU_OPT=( "
    local opt_regex_cmd="__BU_OPT_REGEX=( "
    local opt_synonyms_cmd="__BU_OPT_SYNONYMS=( "
    local opt_type_cmd="__BU_OPT_TYPE=( "
    local opt_docstring_cmd="__BU_OPT_DOCSTRING=( "

    local arg_cmd="__BU_ARG=( "
    local arg_names_cmd="__BU_ARG_NAMES=( "
    local arg_required_cmd="__BU_ARG_REQUIRED=( "
    local arg_docstring_cmd="__BU_ARG_DOCSTRING=( "

    while (( $# )) ; do
        local complete_arg=$1 ; shift

        # Arguments to opt_parse may contain multiple chunks of data, separated
        # by pipe characters.
        if [[ "${complete_arg}" =~ ^([^|]*)(\|([^|]*))?$ ]] ; then
            local opt_definition=$(string_trim "${BASH_REMATCH[1]}")
            local docstring=$(string_trim "${BASH_REMATCH[3]}")

        else
            die "Invalid option declaration: ${complete_arg}"
        fi

        [[ -n ${opt_definition} ]] || die "${FUNCNAME[2]}: invalid opt_parse syntax.  Option definition is empty."

        # Make sure this option looks right
        [[ ${opt_definition} =~ ([+:?])?([^=]+)(=.*)? ]]

        # TYPE is the first character of the definition
        local opt_type_char=${BASH_REMATCH[1]}

        # NAMEs come next, whitespace separated up until the equal sign, if any
        local all_names=${BASH_REMATCH[2]}
        all_names=${all_names%%+([[:space:]])}

        # DEFAULT VALUE is everything after the equal sign, excluding trailing
        # whitespace
        local default=${BASH_REMATCH[3]#=}
        default=${default%%+([[:space:]])}

        # CANONICAL NAME is the first name specified
        local canonical=${all_names%%[ 	]*}

        # It must be non-empty and must not contain hyphens (because hyphens
        # are not allowed in bash variable names)
        [[ -n ${canonical} ]]      || die "${FUNCNAME[2]}: invalid opt_parse syntax.  Name is empty."
        [[ ! ${canonical} = *-* ]] || die "${FUNCNAME[2]}: name ${canonical} is not allowed to contain hyphens."

        # None of the option names are allowed override help, which is provided
        # by opt_parse
        local name
        for name in ${all_names} ; do
            [[ "${name}" != "help" ]] || die "${FUNCNAME[2]}: The opt_parse help option cannot be overridden."
        done


        # OPTIONS
        if [[ ${opt_type_char} == ":" || ${opt_type_char} == "+" ]] ; then

            local name_regex=^\(${all_names//+( )/|}\)$

            if [[ ${opt_type_char} == ":" ]] ; then
                opt_type="string"

            elif [[ ${opt_type_char} == "+" ]] ; then
                opt_type="boolean"

                # Boolean options implicitly get a version whose name starts with
                # no- that is a negation of the option.  Adjust the name regex.
                name_regex=${name_regex/^/^\(no_\)?}

                # And forbid double-negative options
                [[ ! ${canonical} = no_* ]] || die "${FUNCNAME[2]}: names of boolean options may not begin with no_ because no_<option> is implicitly created."

                : ${default:=0}

                if [[ ${default} != 0 && ${default} != 1 ]] ; then
                    die "${FUNCNAME[2]}: boolean option has invalid default of ${default}"
                fi

            fi

            # Now that they're all computed, add them to the command that will generate associative arrays
            opt_cmd+="[${canonical}]='${default}' "
            opt_regex_cmd+="[${canonical}]='${name_regex}' "
            opt_synonyms_cmd+="[${canonical}]='${all_names}' "
            opt_type_cmd+="[${canonical}]='${opt_type}' "

            # Docstring might contain weird characters like quotes and
            # apostrophes, so let printf quote it to be sure
            printf -v quoted_docstring "%q" "${docstring}"
            opt_docstring_cmd+="[${canonical}]=${quoted_docstring} "


        # ARGUMENTS
        else
            [[ ${all_names} != *[[:space:]]* ]] || die "${FUNCNAME[2]}: arguments can only have a single name, but ${all_names} was specified."

            arg_cmd+="'${default}' "
            arg_names_cmd+="'${canonical}' "

            # Keep __BU_ARG_REQUIRED array indexed the same, but only put in
            # names for items that are required
            if [[ ${opt_type_char} == "?" ]] ; then
                arg_required_cmd+="'' "
            else
                arg_required_cmd+="'${canonical}' "
            fi

            printf -v quoted_docstring "%q" "${docstring}"
            arg_docstring_cmd+="${quoted_docstring} "
        fi

    done

    opt_cmd+=")"
    opt_regex_cmd+=")"
    opt_synonyms_cmd+=")"
    opt_type_cmd+=")"
    opt_docstring_cmd+=")"

    arg_cmd+=")"
    arg_names_cmd+=")"
    arg_required_cmd+=")"
    arg_docstring_cmd+=")"

    printf "declare -A %s %s %s %s %s; " "${opt_cmd}" "${opt_regex_cmd}" "${opt_synonyms_cmd}" "${opt_type_cmd}" "${opt_docstring_cmd}"
    printf "declare %s %s %s %s ; " "${arg_cmd}" "${arg_names_cmd}" "${arg_required_cmd}" "${arg_docstring_cmd}"
}

opt_parse_options()
{
    # No options?  Nothing to do.
    if [[ ${#__BU_FULL_ARGS[@]:-} -eq 0 ]] ; then
        return 0
    fi

    set -- "${__BU_FULL_ARGS[@]}"

    local shift_count=0
    while (( $# )) ; do
        case "$1" in
            --)
                (( shift_count += 1 ))
                break
                ;;
            --help)
                __BU_OPT_USAGE_REQUESTED=1
                return 0
                ;;

            --*)
                # Drop the initial hyphens, grab the option name and capture
                # "=value" from the end if there is one
                [[ $1 =~ ^--([^=]+)(=(.*))?$ ]]
                local long_opt=${BASH_REMATCH[1]}
                local has_arg=${BASH_REMATCH[2]}
                local opt_arg=${BASH_REMATCH[3]}

                # Find the internal name of the long option (using its name
                # with underscores, which is how we treat it throughout the
                # opt_parse code rather than with hyphens which is how it
                # should be specified on the command line)
                local canonical=$(opt_parse_find_canonical ${long_opt//-/_})
                [[ -n ${canonical} ]] || die "${FUNCNAME[1]}: unexpected option --${long_opt}"

                if [[ ${__BU_OPT_TYPE[$canonical]} == "string" ]] ; then
                    # If it wasn't specified after an equal sign, instead grab
                    # the next argument off the command line
                    if [[ -z ${has_arg} ]] ; then
                        [[ $# -ge 2 ]] || die "${FUNCNAME[1]}: option --${long_opt} requires an argument but didn't receive one."
                        opt_arg=$2
                        shift && (( shift_count += 1 ))
                    fi

                    __BU_OPT[$canonical]=${opt_arg}

                elif [[ ${__BU_OPT_TYPE[$canonical]} == "boolean" ]] ; then

                    # The value that will get assigned to this boolean option
                    local value=1
                    if [[ -n ${has_arg} ]] ; then
                        value=${opt_arg}
                    fi

                    # Negate the value it was if the option starts with no
                    if [[ ${long_opt} = no[-_]* ]] ; then
                        if [[ ${value} -eq 1 ]] ; then
                            value=0
                        else
                            value=1
                        fi
                    fi

                    __BU_OPT[$canonical]=${value}
                else
                    die "${FUNCNAME[1]}: option --${long_opt} has an invalid type ${__BU_OPT_TYPE[$canonical]}"
                fi
                ;;

            -*)
                # Drop the initial hyphen, grab the single-character options as
                # a blob, and capture an "=value" if there is one.
                [[ $1 =~ ^-([^=]+)(=(.*))?$ ]]
                local short_opts=${BASH_REMATCH[1]}
                local has_arg=${BASH_REMATCH[2]}
                local opt_arg=${BASH_REMATCH[3]}

                # Iterate over the single character options except the last,
                # handling each in turn
                local index
                for (( index = 0 ; index < ${#short_opts} - 1; index++ )) ; do
                    local char=${short_opts:$index:1}
                    local canonical=$(opt_parse_find_canonical ${char})
                    [[ -n ${canonical} ]] || die "${FUNCNAME[1]}: unexpected option --${long_opt}"

                    if [[ ${__BU_OPT_TYPE[$canonical]} == "string" ]] ; then
                        die "${FUNCNAME[1]}: option -${char} requires an argument but didn't receive one."
                    fi

                    __BU_OPT[$canonical]=1
                done

                # Handle the last one separately, because it might have an argument.
                local char=${short_opts:$index}
                local canonical=$(opt_parse_find_canonical ${char})
                [[ -n ${canonical} ]] || die "${FUNCNAME[1]}: unexpected option -${char}"

                # If it expects an argument, make sure it has one and use it.
                if [[ ${__BU_OPT_TYPE[$canonical]} == "string" ]] ; then

                    # If it wasn't specified after an equal sign, instead grab
                    # the next argument off the command line
                    if [[ -z ${has_arg} ]] ; then
                        [[ $# -ge 2 ]] || die "${FUNCNAME[1]}: option -${char} requires an argument but didn't receive one."

                        opt_arg=$2
                        shift && (( shift_count += 1 ))
                    fi
                    __BU_OPT[$canonical]=${opt_arg}

                elif [[ ${__BU_OPT_TYPE[$canonical]} == "boolean" ]] ; then

                    # Boolean options may optionally be specified a value via
                    # -b=(0|1).  Take it if it's there.
                    if [[ -n ${has_arg} ]] ; then
                        __BU_OPT[$canonical]=${opt_arg}
                    else
                        __BU_OPT[$canonical]=1
                    fi

                else
                    die "${FUNCNAME[1]}: option -${char} has an invalid type ${__BU_OPT_TYPE[$canonical]}"
                fi
                ;;
            *)
                break
                ;;
        esac

        # Make sure that the value chosen for boolean options is either 0 or 1
        if [[ ${__BU_OPT_TYPE[$canonical]} == "boolean" \
            && ${__BU_OPT[$canonical]} != 1 && ${__BU_OPT[$canonical]} != 0 ]] ; then
                die "${FUNCNAME[1]}: option $canonical can only be 0 or 1 but was ${__BU_OPT[$canonical]}."
        fi

        # Move on to the next item, recognizing that an option may have consumed the last one
        shift && (( shift_count += 1 )) || break
    done

    # Assign to the __BU_ARGS array so that the opt_parse macro can make its
    # contents the remaining set of arguments in the calling function.
    if [[ ${#__BU_ARGS[@]:-} -gt 0 ]] ; then
        __BU_ARGS=( "${__BU_ARGS[@]:$shift_count}" )
    fi
}

opt_parse_find_canonical()
{
    for option in "${!__BU_OPT[@]}" ; do
        if [[ ${1} =~ ${__BU_OPT_REGEX[$option]} ]] ; then
            echo "${option}"
            return 0
        fi
    done
}

opt_parse_arguments()
{
    if [[ ${#__BU_ARGS[@]} -gt 0 ]] ; then

        # Take the arguments that already have options stripped out of them and
        # treat them as parameters to this function.
        set -- "${__BU_ARGS[@]}"

        # Iterate over the (indexes of the) positional arguments
        local index arg_name shift_count=0
        for index in "${!__BU_ARG_NAMES[@]}" ; do

            # If there are no more arguments to process, stop
            [[ $# -gt 0 ]] || break

            #  Put the next argument from the command line into the next argument
            #  value slot
            __BU_ARG[$index]=$1
            shift && (( shift_count += 1 ))
        done

        __BU_ARGS=( "${__BU_ARGS[@]:$shift_count}" )
    fi
}

opt_display_usage()
{
    {
        # Function name and <option> specification if there are any options
        echo -n "Usage: ${FUNCNAME[1]} "
        [[ ${#__BU_OPT[@]} -gt 0 ]] && echo -n "[option]... "

        # List arguments on the first line
        local i
        for i in ${!__BU_ARG_NAMES[@]} ; do

            # Display name of the argument with brackets around it if it is
            # optional
            [[ -n ${__BU_ARG_REQUIRED[$i]} ]] || echo -n "["
            echo -n "${__BU_ARG_NAMES[$i]}"
            [[ -n ${__BU_ARG_REQUIRED[$i]} ]] || echo -n "]"

            echo -n " "
        done
        echo

        if [[ -n "${__BU_DOC[${FUNCNAME[1]:-}]:-}" ]] ; then
            printf -- "\n%s\n" "${__BU_DOC[${FUNCNAME[1]}]}"
        fi

        if [[ ${#__BU_OPT[@]} -gt 0 ]] ; then
            echo
            echo "Options:"
            local opt
            for opt in ${!__BU_OPT[@]} ; do

                # Print the names of all option "synonyms" next to each other
                printf "   "
                local synonym="" first=1
                for synonym in ${__BU_OPT_SYNONYMS[$opt]} ; do

                    if [[ ${first} -ne 1 ]] ; then
                        printf ", "
                    else
                        first=0
                    fi

                    if [[ ${#synonym} -gt 1 ]] ; then
                        printf -- "--%s" "${synonym//_/-}"
                    else
                        printf -- "-%s" "${synonym}"
                    fi

                done

                # If the option accepts arguments, say that
                [[ ${__BU_OPT_TYPE[$opt]} == "string" ]] && echo -n " <value>"
                echo

                # Print the docstring, constrained to term width of 80,
                # indented another level past the option names, and compress
                # whitespace to look like normal english prose.
                printf "%s" "${__BU_OPT_DOCSTRING[$opt]}" \
                    | tr '\n' ' ' \
                    | fmt --uniform-spacing --width 80 \
                    | pr -T --indent 8

                echo

            done
        fi
        if [[ ${#__BU_ARG_NAMES[@]} -gt 0 ]] ; then
            echo "Arguments:"

            for i in "${!__BU_ARG_NAMES[@]}" ; do
                printf  "   %s\n" "${__BU_ARG_NAMES[$i]}"

                # Print the docstring, constrained to term width of 80,
                # indented another level past the argument name, and compress
                # whitespace to look like normal english prose.
                printf "%s" "${__BU_ARG_DOCSTRING[$i]:-}" \
                    | tr '\n' ' ' \
                    | fmt --uniform-spacing --width 80 \
                    | pr -T --indent 8
            done
        fi

    } >&2
}

opt_dump()
{
    for option in "${!__BU_OPT[@]}" ; do
        echo -n "${option}=\"${__BU_OPT[$option]}\" "
    done
    echo
}

: <<'END'
opt_forward
===========

When you have a bunch of options that were passed into a function that wants to
simply forward them into an internal function, it can be a little tedious to
make the call to that internal function because you have to repeat all of the
options and then read the value that the option of the same name was stored
into.  For instance look at the foo_internal call here, assuming it takes an
identical set of options as foo.

    foo()
    {
        $(opt_parse "+a" "+b" "+c")

        # Do some stuff then call internal function to handle more details
        foo_internal -a="${a}" -b="${b}" -c="${c}"

    }

Of course, that only gets worse as you have more or as the names of your
options get longer.  And if you quote it incorrectly, it will continue to work
until one of your options contains something weird like whitespace in which
case it will probably fail subtly.

`Opt_forward` exists simply to make this easier.  It knows how to forward
options that were parsed by `opt_parse` to another function, quoting correctly.
You can use it like this

    opt_forward <command> <names of options to forward>+ [-- [other args]]

To cover the example case, you'd call it like this:

    opt_forward foo_internal a b c

Or, if you needed to pass additional things to `foo_internal`, like this:

    opt_forward foo_internal a b c -- additional things

You may find that the option has a different name in the function you'd like to
forward to.  You can specify this by adding a colon followed by the name of
the option in the function you're asking `opt_forward` to call.  For instance,
if the function you wanted to _call_ has options named X, Y, and Z.

    opt_forward foo_internal a:X b:Y c:Z

Note that `opt_forward` is forgiving about the fact that we use underscores in
variable names but options support hyphens.  You can pass option names in
either form to `opt_forward`.
END
opt_forward()
{
    [[ $# -gt 0 ]] || die "Must specify at least a command to run and an option to forward."
    local cmd=$1 ; shift

    local args=( )

    while [[ $# -gt 0 ]] ; do
        local __option=$1 ; shift

        # Keep processing things until --.  If we encounter that it means the
        # caller wants to present more arguments or options that are not
        # forwarded
        [[ ${__option} == "--" ]] && break


        # If there's no colon in the option name to be forwarded, then assume
        # the option names match in this function and the other.  If there IS
        # one, then use the first portion to be the name of the local variable,
        # and the part after the colon to be the name of the option in the
        # called function.
        local __local_name=${__option%%:*}
        local __called_name=${__option##*:}
        : ${__called_name:=__local_name}

        # Use only underscores in variable names and only hyphens in option
        # names
        __called_name=${__called_name//_/-}
        __local_name=${__local_name//-/_}

        args+=("--${__called_name//-/_}=${!__local_name}")
    done

    while [[ $# -gt 0 ]] ; do
        args+=("$1")
        shift
    done

    quote_eval ${cmd} "${args[@]}"
}

# The opt_usage function is in bashutils.sh because it must be there before
# anything else is sourced to have documentation work for files in bashutils.

return 0
