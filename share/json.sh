#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage to_json <<'END'
Convert each argument, in turn, to json in an appropriate way and drop them all in a single json blob.
END
to_json()
{
    echo -n "{"
    local _notfirst="" _arg="" _arg_noqual=""
    for _arg in "${@}" ; do
        [[ -n ${_notfirst} ]] && echo -n ","

        _arg_noqual=$(__discard_qualifiers ${_arg})
        echo -n "$(json_escape ${_arg_noqual}):"
        if is_pack ${_arg} ; then
            pack_to_json "${_arg}"

        elif is_array ${_arg} ; then
            array_to_json "${_arg}"

        elif is_associative_array ${_arg} ; then
            associative_array_to_json "${_arg}"

        else
            # You don't strictly need the test here to determine if ${_arg} contains the name of a variable, but if we
            # skip the check then bash generates an error message that just says "!_arg: unbound variable" which really
            # isn't all that helpful. This way we can spit out the name of the bad variable.
            [[ -v ${_arg} ]] || die "Cannot create json from unbound variable ${_arg}."
            json_escape "${!_arg}"
        fi

        _notfirst=true
    done
    echo -n "}"
}

opt_usage array_to_json <<'END'
Convert an array specified by name (i.e ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json array containing the same data.
END
array_to_json()
{
    # This will store a copy of the specified array's contents into __array
    $(opt_parse __array)

    # Return immediately if if array is not set. The reason we don't error out on an unset array is because bash doesn't
    # save arrays with no members. For instance A=() unsets array A. Instead simply echo "[]" for the json equivalent
    # of an empty array.
    if array_empty ${__array}; then
        echo -n "[]"
        return 0
    fi

    # Otherwise grab the contents of the array and iterate over it and convert each element to json.
    eval "local __array=(\"\${${__array}[@]}\")"
    echo -n "["
    local i notfirst=""
    for i in "${__array[@]}" ; do
        [[ -n ${notfirst} ]] && echo -n ","
        echo -n "$(json_escape "$i")"
        notfirst=true
    done

    echo -n "]"
}

opt_usage associative_array_to_json <<'END'
Convert an associative array by name (e.g. ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json object containing the same
data.
END
associative_array_to_json()
{
    echo -n "{"
    local _notfirst="" _key
    edebug "1=$1"
    for _key in $(array_indexes_sort $1); do
        edebug $(lval _key)
        [[ -n ${_notfirst} ]] && echo -n ","

        echo -n "$(json_escape ${_key})"
        echo -n ':'
        echo -n "$(json_escape "$(eval echo -n \${$1[$_key]})")"

        _notfirst=true
    done
    echo -n "}"
}

opt_usage associative_array_to_json_split <<'END'
Convert an associative array by name (e.g. ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json object containing the same
data. This is similar to associative_array_to_json with some extra functionality layered ontop wherein it will split
each entry in the associative array on the provided delimiter into an array.

For example:

```shell
$ declare -A data
$ data[key1]="value1 value2 value3"
$ data[key2]="entry1 entry2 entry3"
$ associative_array_to_json_split data " " | jq .
{
    "key1": [
        "value1",
        "value2",
        "value3"
    ],
    "key2": [
        "entry1",
        "entry2",
        "entry3"
    ]
}
```
END
associative_array_to_json_split()
{
    $(opt_parse \
        "input  | Name of the associative array to convert to json." \
        "?delim | Delimiter to place between array items. Default is a space.")

    # If the array is empty return empty json object
    array_empty ${input} && { echo -n "{}"; return 0; } || true

    # Default delimiter is an empty string.
    : ${delim:=" "}

    echo -n "{"

    local _first=1 _key _entry _values
    for _key in $(array_indexes_sort ${input}); do
        edebug $(lval _key)

        [[ ${_first} -eq 1 ]] && _first=0 || echo -n ","

        eval "_entry=\${${input}[$_key]}"
        array_init _values "${_entry}" "${delim}"

        echo -n "$(json_escape ${_key})"
        echo -n ':'
        array_to_json _values

    done
    echo -n "}"
}

opt_usage pack_to_json <<'END'
Convert a single pack into a json blob where the keys are the same as the keys from the pack (and so are the values)
END
pack_to_json()
{
    $(opt_parse \
        "+lowercase | Convert keys in the pack to all lowercase" \
        "_pack      | Named pack to operate on.")

    local _pack _key _val _notfirst=""
    _pack=$(__discard_qualifiers ${_pack})
    echo -n "{"

    for _key in $(pack_keys ${_pack}) ; do

        [[ -n ${_notfirst} ]] && echo -n ","

        # Capture value before we modify the key for display purposes
        _val="$(json_escape "$(pack_get ${_pack} ${_key})")"

        if [[ ${lowercase} -eq 1 ]]; then
            _key="${_key,,}"
        fi

        echo -n '"'${_key}'":'"${_val}"

        _notfirst=true

    done

    echo -n "}"
}

opt_usage json_escape <<'END'
Escape an arbitrary string (specified as $1) so that it is quoted and safe to put inside json. This is done via a call
to jq with --raw-input which will cause it to emit a properly quoted and escaped string that is safe to use inside
json.
END
json_escape()
{
    # Newer jq has a -j flag to join newlines into a single flat string. To workaround the lack of this flag in older
    # versions, we wrap the call to jq in a subshell which is not quoted to strip off the final newline.
    echo -n "$(echo -n "${@}" | jq --monochrome-output --raw-input --slurp .)"
}

opt_usage json_import <<'END'
Import all of the key:value pairs from a non-nested Json object directly into the caller's environment as proper bash
variables. By default this will import all the keys available into the caller's environment. Alternatively you can
provide an optional list of keys to restrict what is imported. If any of the explicitly requested keys are not present
this will be interpreted as an error and json_import will return non-zero. Keys can be marked optional via the '?'
prefix before the key name in which case they will be set to an empty string if the key is missing.

Similar to a lot of other  methods inside ebash, this uses the "eval command invocation string" idom. So, the proper
calling convention for this is:

```shell
$(json_import)
```

By default this function operates on stdin. Alternatively you can change it to operate on a file via -f. To use via
STDIN use one of these idioms:

```shell
$(json_import <<< ${json}) $(curl ... | $(json_import)
```
END
json_import()
{
    $(opt_parse \
        "+global g           | Emit global variables instead of local ones." \
        "+export e           | Emit exported variables instead of local ones." \
        ":file f=-           | Parse contents of provided file instead of stdin." \
        "+lower_snake_case l | Convert all keys into lower_snake_case." \
        "+upper_snake_case u | Convert all keys into UPPER_SNAKE_CASE." \
        ":prefix p           | Prefix all keys with the provided required prefix." \
        ":query jq q         | Use JQ style query expression on given JSON before parsing." \
        ":exclude x          | Whitespace separated list of keys to exclude while importing." \
        "@_json_import_keys  | Optional list of json keys to import. If none, all are imported." )

    # Check for conflicting flags
    if [[ "${lower_snake_case}" -eq 1 && "${upper_snake_case}" -eq 1 ]]; then
        die "lower_snake_case and upper_snake_case are mutually exclusive"
    fi

    # Determine flags to pass into declare
    local dflags=""
    [[ ${global} -eq 1 ]] && dflags="-g"
    [[ ${export} -eq 1 ]] && dflags="-gx"

    # optional jq query, or . which selects everything in jq
    : ${query:=.}

    # Lookup optional filename to use. If no filename was given then we're operating on STDIN. In either case read into
    # a local variable so we can parse it repeatedly in this function.
    local _json_import_input _json_import_data
    _json_import_input=$(cat ${file} || true)
    _json_import_data=$(jq -r "${query}" <<< ${_json_import_input} || true)

    # Check if explicit keys are requested. If not, slurp all keys in from provided data.
    array_empty _json_import_keys && array_init_json _json_import_keys "$(jq -c -r keys <<< ${_json_import_data})"

    # Get list of optional keys to exclude
    local excluded
    array_init excluded "${exclude}"

    # Debugging
    edebug $(lval prefix query file _json_import_data _json_import_keys excluded)

    local cmd key val has_field
    for key in "${_json_import_keys[@]}"; do
        array_contains excluded ${key} && continue

        # If the key is marked as optional then add filter "//empty" so that 'null' literal is replaced with an empty string
        if [[ ${key} == \?* ]]; then
            key="${key#\?}"
            val=$(jq -c -r ".${key}//empty" <<< ${_json_import_data})
        else

            has_field=$(jq --raw-output --arg KEY "${key}" '. | has($KEY)' <<< "${_json_import_data}")

            if [[ ${has_field} != "true" ]] ; then
                die "Data does not contain required $(lval key _json_import_input _json_import_data)"
            fi

            val=$(jq -c -r --arg KEY "${key}" '.[$KEY]' <<< "${_json_import_data}")
        fi

        edebug $(lval key val)
        if [[ ${lower_snake_case} -eq 1 ]]; then
            key=$(to_lower_snake_case "${key}")
        elif [[ ${upper_snake_case} -eq 1 ]]; then
            key=$(to_upper_snake_case "${key}")
        fi

        # Replace illegal characters that can't be in a variable
        key="${key// /_}"
        key="${key//-/_}"
        key="${key//__/_}"

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
        "+exports   | File format is an 'exports file' (e.g. KEY=VALUE)." \
        "+lowercase | Convert all keys to lowercase during conversion."   \
        "file       | Parse contents of provided file.")

    assert_eq 1 "${exports}" "Unsupported file format (--exports=0)"

    (
        # Parse the file and strip out any ansi escape codes and then replace newlines with spaces. This gives a bunch
        # of separate, quoted items that we can safely insert into a pack. We can then pass that pack through eval so
        # that bash can safely interpret those quotes and make them separate arguments passed into pack_set.
        array_init_nl parts "$(cat "${file}" | noansi)"
        pack_set pack "${parts[@]}"
        opt_forward pack_to_json lowercase -- pack
    )
}

opt_usage json_compare <<'END'
Compare two json strings. This function returns diff's return code and if the json strings don't compare the diff
will be printed to stdout.
END
json_compare()
{
    $(opt_parse first second)

    if ! echo "${first}" | jq -e . &>/dev/null ; then
        die "ERROR: invalid json $(lval first)"
    fi
    if ! echo "${second}" | jq -e . &>/dev/null ; then
        die "ERROR: invalid json $(lval second)"
    fi

    # Using diff rather than cmp, you get a hint if what didn't compare. Otherwise, they are both silent.
    diff <(echo "${first}"  | jq --compact-output --sort-keys .) \
         <(echo "${second}" | jq --compact-output --sort-keys .)
}

opt_usage json_compare_files <<'END'
Compare two json files. The files can only contain a single json object.
END
json_compare_files()
{
    $(opt_parse left right)

    assert_exists "${left}" "${right}"

    json_compare "$(< "${left}")" "$(< "${right}")"
}
