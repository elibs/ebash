#!/bin/bash
#
# Copyright 2011-2016, SolidFire, Inc. All rights reserved.
#

# array_init will split a string on any characters you specify, placing the
# results in an array for you.
#
#  $1: name of array to assign to (i.e. "array")
#  $2: string to be split
#  $3: (optional) character(s) to be used as delimiters.
array_init()
{
    $(opt_parse "__array" "?__string" "?__delim")

    # If nothing was provided to split on just return immediately
    [[ -z ${__string} ]] && { eval "${__array}=()"; return 0; } || true

    # Default bash IFS is space, tab, newline, so this will default to that
    : ${__delim:=$' \t\n'}

    IFS="${__delim}" eval "${__array}=(\${__string})"
}

# This function works like array_init, but always specifies that the delimiter
# be a newline.
array_init_nl()
{
    [[ $# -eq 2 ]] || die "array_init_nl requires exactly two parameters"
    array_init "$1" "$2" $'\n'
}

# Initialize an array from a Json array. This will essentially just strip
# of the brackets from around the Json array and then remove the internal
# quotes on each value since they are unecessary in bash.
array_init_json()
{
    [[ $# -ne 2 ]] && die "array_init_json requires exactly two parameters"
    array_init "$1" "$(echo "${2}" | sed -e 's|^\[\s*||' -e 's|\s*\]$||' -e 's|",\s*"|","|g' -e 's|"||g')" ","
}

# Print the size of any array.  Yes, you can also do this with ${#array[@]}.
# But this functions makes for symmertry with pack (i.e. pack_size).
array_size()
{
    $(opt_parse __array)

    # Treat unset variables as being an empty array, because when you tell
    # bash to create an empty array it doesn't really allow you to
    # distinguish that from an unset variable.  (i.e. it doesn't show you
    # the variable until you put something in it)
    # 
    # NOTE: The mechanism we use here is to stringify the contents of an 
    # array and see if that's an empty string or not. If it is, then we'll
    # consider the array itself to have no elements. That's not actually
    # true of course because you could have an array with empty strings
    # inside of it. We accept this obvious shortcoming in order to provide
    # greater compatibility with older versions of bash. In bash-4.3 and
    # higher, the right way to determine this is to use the -v operation
    # and to explicitly make it a string. As in:
    #
    # a=()
    # [[ ! -v a[@] ]] && echo 0
    #
    # The problem is that this doesn't work with bash-4.2 because the -v
    # operator doesn't work on arrays. This was added explicitly in 4.3:
    # https://tiswww.case.edu/php/chet/bash/CHANGES:
    # a.  The [[ -v ]] option now understands array references (foo[1]) and returns
    #    success if the referenced element has a value.
    #
    local value=$(eval "echo \${${__array}[*]:-}")
    if [[ -z "${value}" ]]; then
        echo 0
    else
        eval "echo \${#${__array}[@]}"
    fi

    return 0
}

# Return true (0) if an array is empty and false (1) otherwise
array_empty()
{
    $(opt_parse __array)
    [[ $(array_size ${__array}) -eq 0 ]]
}

# Returns true (0) if an array is not empty and false (1) otherwise
array_not_empty()
{
    $(opt_parse __array)
    [[ $(array_size ${__array}) -ne 0 ]]
}

# array_add will split a given input string on requested delimiters and add them
# to the given array (which may or may not already exist).
#
# $1: name of the array to add the new elements to
# $2: string to be split
# $3: (optional) character(s) to be used as delimiters.
array_add()
{
    $(opt_parse "__array" "?__string" "?__delim")

    # If nothing was provided to split on just return immediately
    [[ -z ${__string} ]] && return 0

    # Default bash IFS is space, tab, newline, so this will default to that
    : ${__delim:=$' \t\n'}

    # Parse the input given the delimiter and append to the array.
    IFS="${__delim}" eval "${__array}+=(\${__string})"
}

# Identical to array_add only hard codes the delimter to be a newline.
array_add_nl()
{
    [[ $# -ne 2 ]] && die "array_add_nl requires exactly two parameters"
    array_add "$1" "$2" $'\n'
}

# array_remove will remove the given value(s) from an array, if present.
#
# OPTIONS:
# -a=(0|1) Remove all instances (defaults to only removing the first instance)
array_remove()
{
    $(opt_parse \
        "+all a  | Remove all instances of the item instead of just the first." \
        "__array | Name of array to operate on.")

    # Return immediately if if array is empty or no values were given to be
    # removed. The reason we don't error out on an unset array is because
    # bash doesn't save arrays with no members.  For instance A=() unsets array A...
    if array_empty ${__array} || [[ $# -eq 0 ]]; then
        return 0
    fi
    
    local value
    for value in "${@}"; do

        local idx
        for idx in $(array_indexes ${__array}); do
            eval "local entry=\${${__array}[$idx]}"
            [[ "${entry}" == "${value}" ]] || continue

            unset ${__array}[$idx]

            # Remove all instances or only the first?
            [[ ${all} -eq 1 ]] || break
        done
    done
}

# Bash arrays may have non-contiguous indexes.  For instance, you can unset an
# ARRAY[index] to remove an item from the array and bash does not shuffle the
# indexes.
#
# If you need to iterate over the indexes of an array (rather than simply
# iterating over the items), you can call array_indexes on the array and it
# will echo all of the indexes that exist in the array.
#
array_indexes()
{
    $(opt_parse __array_indexes_array)
    eval "echo \${!${__array_indexes_array}[@]}"
}

# Same as array_indexes only this enumerates them in reverse order.
array_rindexes()
{
    $(opt_parse __array_indexes_array)
    eval "echo \${!${__array_indexes_array}[@]} | rev"
}

# array_contains will check if an array contains a given value or not. This
# will return success (0) if it contains the requested element and failure (1)
# if it does not.
#
# $1: name of the array to search
# $2: value to check for existance in the array
array_contains()
{
    $(opt_parse __array __value)

    local idx=0
    for idx in $(array_indexes ${__array}); do
        eval "local entry=\${${__array}[$idx]}"
        [[ "${entry}" == "${__value}" ]] && return 0
    done

    return 1
}

# array_join will join an array into one flat string with the provided multi
# character delimeter between each element in the resulting string. Can also
# optionally pass in options to also put the delimiter before or after (or both)
# all elements.
#
# $1: name of the array to join
# $2: (optional) delimiter
array_join()
{
    $(opt_parse \
        "+before b | Insert delimiter before all joined elements." \
        "+after a  | Insert delimiter after all joined elements."  \
        "__array   | Name of array to operate on."                 \
        "?delim    | Delimiter to place between array items.  Default is a space.")

    # If the array is empty return empty string
    array_empty ${__array} && { echo -n ""; return 0; } || true

    # Default delimiter is an empty string.
    : ${delim:=" "}

    # If requested, emit the delimiter before hand.
    if [[ ${before} -eq 1 ]]; then
        echo -n "${delim}"
    fi

    # Iterate over each element of the array and echo that element with the
    # delimiter following it. Special case the last element in the array because
    # we only want to emit the trailing delimiter if requested.
    local indexes=( $(array_indexes ${__array}) )
    local idx_last=$(echo "${indexes[@]}" | awk '{print $NF}')

    local idx
    for idx in ${indexes[@]}; do
        eval "echo -n \"\${${__array}[$idx]}\""

        # If this is not the last element then always echo the delimiter. 
        # If this is the last element only echo the delimiter if after==1.
        if [[ ${idx} -lt ${idx_last} || ${after} -eq 1 ]]; then
            echo -n "${delim}"
        fi
    done
}

# Identical to array_join only it hardcodes the dilimter to a newline.
array_join_nl()
{
    [[ $# -ne 1 ]] && die "array_join_nl requires exactly one parameter"
    array_join "$1" $'\n'
}

# Create a regular expression that will match any one of the items in this
# array.  Suppose you had an array containing the first four letters of the
# alphabet.  Calling array_regex on that array will produce:
#
#    (a|b|c|d)
#
# Perhaps this is an esoteric thing to do, but it's pretty handy when you want
# it.
#
# NOTE: Be sure to quote the output of your array_regex call, because bash
# finds parantheses and pipe characters to be very important.
#
# WARNING: This probably only works if your array contains items that do not
# have whitespace or regex-y characters in them.  Pids are good.  Other stuff,
# probably not so much.
#
array_regex()
{
    $(opt_parse __array)

    echo -n "("
    array_join ${__array}
    echo -n ")"
}

# Sort an array in-place.
#
array_sort()
{
    $(opt_parse \
        "+unique u  | Remove all but one copy of each item in the array." \
        "+version V | Perform a natural (version number) sort.")

    local __array
    for __array in "${@}" ; do
        local flags=()

        [[ ${unique} -eq 1 ]]  && flags+=("--unique")
        [[ ${version} -eq 1 ]] && flags+=("--version-sort")
        
        readarray -t ${__array} < <(
            local idx
            for idx in $(array_indexes ${__array}); do
                eval "echo \${${__array}[$idx]}"
            done | sort ${flags[@]:-}
        )
    done
}

return 0
