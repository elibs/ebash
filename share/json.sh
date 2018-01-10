#!/bin/bash
#
# Copyright 2011-2016, SolidFire, Inc. All rights reserved.
#

# Convert each argument, in turn, to json in an appropriate way and drop them
# all in a single json blob.
#
to_json()
{
    echo -n "{"
    local _notfirst="" _arg
    for _arg in "${@}" ; do
        [[ -n ${_notfirst} ]] && echo -n ","

        local _arg_noqual=$(discard_qualifiers ${_arg})
        echo -n "$(json_escape ${_arg_noqual}):"
        if is_pack ${_arg} ; then
            pack_to_json ${_arg}

        elif is_array ${_arg} ; then
            array_to_json ${_arg}

        elif is_associative_array ${_arg} ; then
            associative_array_to_json ${_arg}

        else
            # You don't strictly need the test here to determine if ${_arg}
            # contains the name of a variable, but if we skip the check then
            # bash generates an error message that just says "!_arg: unbound
            # variable" which really isn't all that helpful.  This way we can
            # spit out the name of the bad variable.
            [[ -v ${_arg} ]] || die "Cannot create json from unbound variable ${_arg}."
            json_escape "${!_arg}"
        fi

        _notfirst=true
    done
    echo -n "}"
}

opt_usage array_to_json <<'END'
Convert an array specified by name (i.e ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json array
containing the same data.
END
array_to_json()
{
    # This will store a copy of the specified array's contents into __array
    $(opt_parse __array)

    # Return immediately if if array is not set. The reason we don't error out on
    # an unset array is because bash doesn't save arrays with no members.
    # For instance A=() unsets array A. Instead simply echo "[]" for the json
    # equivalent of an empty array.
    if array_empty ${__array}; then
        echo -n "[]"
        return 0
    fi

    # Otherwise grab the contents of the array and iterate over it and convert
    # each element to json.
    eval "local __array=(\"\${${__array}[@]}\")"
    echo -n "["
    local i notfirst=""
    for i in "${__array[@]}" ; do
        [[ -n ${notfirst} ]] && echo -n ","
        echo -n $(json_escape "$i")
        notfirst=true
    done

    echo -n "]"
}

associative_array_to_json()
{
    echo -n "{"
    local _notfirst="" _key
    edebug "1=$1"
    for _key in $(eval echo -n "\${!$1[@]}") ; do
        edebug $(lval _key)
        [[ -n ${_notfirst} ]] && echo -n ","

        echo -n $(json_escape ${_key})
        echo -n ':'
        echo -n $(json_escape "$(eval echo -n \${$1[$_key]})")

        _notfirst=true
    done
    echo -n "}"
}

# Convert a single pack into a json blob where the keys are the same as the
# keys from the pack (and so are the values)
#
pack_to_json()
{
    [[ -z ${1} ]] && die "pack_to_json requires a pack to be specified as \$1"

    local _pack _key _notfirst=""
    _pack=$(discard_qualifiers $1)
    echo -n "{"
    for _key in $(pack_keys ${_pack}) ; do
        [[ -n ${_notfirst} ]] && echo -n ","
        echo -n '"'${_key}'":'"$(json_escape "$(pack_get ${_pack} ${_key})")"
        _notfirst=true
    done
    echo -n "}"
}

# Escape an arbitrary string (specified as $1) so that it is quoted and safe to
# put inside json. This is done via a call to jq with --raw-input which will 
# cause it to emit a properly quoted and escaped string that is safe to use
# inside json.
#
json_escape()
{
    # Newer jq has a -j flag to join newlines into a single flat string.
    # To workaround the lack of this flag in older versions, we wrap the call
    # to jq in a subshell which is not quoted to strip off the final newline.
    echo -n $(echo -n "$1" | jq --raw-input --slurp .)
}

opt_usage json_import <<'END'
Import all of the key:value pairs from a non-nested Json object directly into the caller's
environment as proper bash variables. By default this will import all the keys available into the
caller's environment. Alternatively you can provide an optional list of keys to restrict what is
imported. If any of the explicitly requested keys are not present this will be interpreted as an
error and json_import will return non-zero. Keys can be marked optional via the '?' prefix before
the key name in which case they will be set to an empty string if the key is missing. 

Similar to a lot of other  methods inside bashutils, this uses the "eval command invocation string"
idom. So, the proper calling convention for this is:

    $(json_import)

By default this function operates on stdin. Alternatively you can change it to operate on a file via
-f. To use via STDIN use one of these idioms:

    $(json_import <<< ${json})
    $(curl ... | $(json_import)

END
json_import()
{
    $(opt_parse \
        "+global g           | Emit global variables instead of local ones." \
        "+export e           | Emit exported variables instead of local ones." \
        ":file f=-           | Parse contents of provided file instead of stdin." \
        "+upper_snake_case u | Convert all keys into UPPER_SNAKE_CASE." \
        ":prefix p           | Prefix all keys with the provided required prefix." \
        ":query jq q         | Use JQ style query expression on given JSON before parsing." \
        ":exclude x          | Whitespace separated list of keys to exclude while importing." \
        "@_json_import_keys  | Optional list of json keys to import.  If none, all are imported." )

    # Determine flags to pass into declare
    local dflags=""
    [[ ${global} -eq 1 ]] && dflags="-g"
    [[ ${export} -eq 1 ]] && dflags="-gx"

    # optional jq query, or . which selects everything in jq
    : ${query:=.}

    # Lookup optional filename to use. If no filename was given then we're operating on STDIN.
    # In either case read into a local variable so we can parse it repeatedly in this function.
    local _json_import_input=$(cat ${file} || true)
    local _json_import_data=$(jq -r "${query}" <<< ${_json_import_input} || true)

    # Check if explicit keys are requested. If not, slurp all keys in from provided data.
    array_empty _json_import_keys && array_init_json _json_import_keys "$(jq -c -r keys <<< ${_json_import_data})"

    # Get list of optional keys to exclude
    local excluded
    array_init excluded "${exclude}"

    # Debugging
    edebug $(lval prefix query file _json_import_data _json_import_keys excluded)

    local cmd key val
    for key in "${_json_import_keys[@]}"; do
        array_contains excluded ${key} && continue

        # If the key is marked as optional then add filter "//empty" so that 'null' literal is replaced with an empty string
        if [[ ${key} == \?* ]]; then
            key="${key#\?}"
            val=$(jq -c -r ".${key}//empty" <<< ${_json_import_data})
        else

            local has_field=$(jq --raw-output '. | has("'${key}'")' <<< "${_json_import_data}")

            if [[ ${has_field} != "true" ]] ; then
                die "Data does not contain required $(lval key _json_import_input _json_import_data)"
            fi

            val=$(jq -c -r '.'${key} <<< "${_json_import_data}")
        fi

        edebug $(lval key val)
        [[ ${upper_snake_case} -eq 1 ]] && key=$(to_upper_snake_case "${key}")

        # If the value is an array implicitly convert it
        if [[ "${val:0:1}" == "[" && "${val: -1}" == "]" ]]; then
            local array_val=()
            array_init_json -k array_val "${val}"
            cmd+="declare ${dflags} -a ${prefix}${key}=( "${array_val[@]:-}" );"
        else
            cmd+="$(printf "declare %s %s%s=%q ;" "${dflags}" "${prefix}" "${key}" "${val}")"
        fi
    done

    edebug $(lval cmd)
    echo -n "eval ${cmd}"
}

opt_usage file_to_json <<'END'
Parse the contents of a given file and echo the output in JSON format. This function requires you to specify the format
of the file being parsed. At present the only supported format is --exports which is essentially a KEY=VALUE exports
file.
END
file_to_json()
{
    $(opt_parse \
        "+exports  | File format is an 'exports file' (e.g. KEY=VALUE)." \
        "file      | Parse contents of provided file.")

    if [[ ${exports} -eq 1 ]]; then
    (
        # Parse the file and strip out any ansi escape codes and then replace newlines with spaces. This gives a bunch
        # of separate, quoted items that we can safely insert into a pack. We can then pass that pack through eval so
        # that bash can safely interpret those quotes and make them separate arguments passed into pack_set. 
        array_init_nl parts "$(cat "${file}" | noansi)"
        pack_set pack "${parts[@]}"
        pack_to_json pack
    )
    else
        die "Unsupported file format"
    fi
}

opt_usage json_compare <<'END'
Compare two json strings.
END
json_compare()
{
    $(opt_parse first second)

    if ! echo "${first}" | jq . &>/dev/null ; then
        die "ERROR: invalid json $(lval first)"
    fi
    if ! echo "${second}" | jq . &>/dev/null ; then
        die "ERROR: invalid json $(lval second)"
    fi

    # Using diff rather than cmp, you get a hint if what didn't compare.  Otherwise, they are both silent.
    if diff <(echo "${first}" | jq --compact-output --sort-keys .) \
            <(echo "${second}" | jq --compact-output --sort-keys .) ; then
        return 0
    else
        return 1
    fi
}

opt_usage json_compare_files <<'END'
Compare two json files.  The files can only contain a single json object.
END
json_compare_files()
{
    $(opt_parse left right)

    assert_exists "${left}" "${right}"

    json_compare "$(cat ${left})" "$(cat ${right})"
}

return 0
