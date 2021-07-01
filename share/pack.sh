#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage pack_set <<'END'
Consider a "pack" to be a "new" data type for bash. It stores a set of key/value pairs in an arbitrary format inside
a normal bash (string) variable. This is much like an associative array, but has a few differences

- You can store packs INSIDE associative arrays (example in unit tests)
- The "keys" in a pack may not contain an equal sign, nor may they contain whitespace.
- Packed values cannot contain newlines.

For a (new or existing) variable whose contents are formatted as a pack, set one or more keys to values. For example,
the following will create a new variable packvar that will contain three keys (alpha, beta, n) with associated values
(a, b, 7)

```shell
pack_set packvar alpha=a beta=b n=7
```
END
pack_set()
{
    local _pack_set_pack=$1 ; shift

    for _pack_set_arg in "${@}" ; do
        local _pack_set_key="${_pack_set_arg%%=*}"
        local _pack_set_val="${_pack_set_arg#*=}"

        pack_set_internal "${_pack_set_pack}" "${_pack_set_key}" "${_pack_set_val}"
    done
}

opt_usage pack_update <<'END'
 Much like pack_set, and takes arguments of the same form. The difference is that pack_update will create no new keys
 -- it will only update keys that already exist.
END
pack_update()
{
    local _pack_update_pack=$1 ; shift

    for _pack_update_arg in "${@}" ; do
        local _pack_update_key="${_pack_update_arg%%=*}"
        local _pack_update_val="${_pack_update_arg#*=}"

        if pack_contains ${_pack_update_pack} "${_pack_update_key}"; then
            pack_set_internal "${_pack_update_pack}" "${_pack_update_key}" "${_pack_update_val}"
        fi

    done
}

pack_set_internal()
{
    local _pack_pack_set_internal=$1
    local _tag=$2
    local _val="$3"

    argcheck _tag
    [[ ${_tag} =~ = ]] && die "ebash internal error: tag ${_tag} cannot contain equal sign"
    [[ $(echo "${_val}" | wc -l) -gt 1 ]] && die "packed values cannot hold newlines"

    local _removeOld _addNew _packed
    _removeOld="$(echo -n "${!1:-}" | _unpack | grep -av '^'${_tag}'=' || true)"
    _addNew="$(echo "${_removeOld}" ; echo -n "${_tag}=${_val}")"
    _packed=$(echo "${_addNew}" | _pack)

    printf -v "${1}" "${_packed}"
}

opt_usage pack_get <<'END'
Get the last value assigned to a particular key in this pack.
END
pack_get()
{
    local _pack_pack_get=$1
    local _tag=$2

    argcheck _pack_pack_get _tag

    local _unpacked _found
    _unpacked="$(echo -n "${!_pack_pack_get:-}" | _unpack)"
    _found="$(echo -n "${_unpacked}" | grep -a "^${_tag}=" || true)"
    echo "${_found#*=}"
}

pack_contains()
{
    [[ -n $(pack_get "$@") ]]
}

opt_usage pack_copy <<'END'
Copy a packed value from one variable to another. Either variable may be part of an associative array, if you're so
inclined.

Examples:

```shell
pack_copy A B
pack_copy B A["alpha"]
pack_copy A["alpha"] B[1]
```
END
pack_copy()
{
    argcheck 1 2
    eval "${2}=\"\${!1}\""
}

opt_usage pack_iterate <<'END'
Call provided callback function on each entry in the pack. The callback function should take two arguments, and it
will be called once for each item in the pack and passed the key as the first value and its value as the second value.
END
pack_iterate()
{
    local _func=$1
    local _pack_pack_iterate=$2
    argcheck _func _pack_pack_iterate

    local _unpacked _lines
    _unpacked="$(echo -n "${!_pack_pack_iterate}" | _unpack)"
    array_init_nl _lines "${_unpacked}"

    for _line in "${_lines[@]}" ; do

        local _key="${_line%%=*}"
        local _val="${_line#*=}"

        ${_func} "${_key}" "${_val}"

    done
}

opt_usage pack_import <<'END'
Spews bash commands that, when executed will declare a series of variables in the caller's environment for each and
every item in the pack. This uses the "eval command invocation string" which the caller then executes in order to
manifest the commands. For instance, if your pack contains keys a and b with respective values 1 and 2, you can create
locals a=1 and b=2 by running:

```shell
$(pack_import pack)
```

If you don't want the pack's entire contents, but only a limited subset, you may specify them. For instance, in the
same example scenario, the following will create a local a=1, but not a local for b.

```shell
$(pack_import pack a)
```
END
pack_import()
{
    $(opt_parse \
        "+local l=1        | Emit local variables via local builtin (default)." \
        "+global g         | Emit global variables instead of local (i.e. undeclared variables)." \
        "+export e         | Emit exported variables via export builtin." \
        "_pack_import_pack | Pack to operate on.")

    local _pack_import_keys=("${@}")
    [[ $(array_size _pack_import_keys) -eq 0 ]] && _pack_import_keys=($(pack_keys ${_pack_import_pack}))

    # Determine requested scope for the variables
    local _pack_import_scope="local"
    [[ ${local} -eq 1 ]]  && _pack_import_scope="local"
    [[ ${global} -eq 1 ]] && _pack_import_scope=""
    [[ ${export} -eq 1 ]] && _pack_import_scope="export"

    local _pack_import_cmd="" _pack_import_val=""
    for _pack_import_key in "${_pack_import_keys[@]}" ; do
        _pack_import_val=$(pack_get ${_pack_import_pack} ${_pack_import_key})
        _pack_import_cmd+="$_pack_import_scope $_pack_import_key=\"${_pack_import_val}\"; "
    done

    echo "eval "${_pack_import_cmd}""
}

opt_usage pack_export <<'END'
Assigns values into a pack by extracting them from the caller environment. For instance, if you have locals a=1 and b=2
and run the following:

```shell
pack_export pack a b
```

You will be left with the same pack as if you instead said:

```shell
pack_set pack a=${a} b=${b}
```
END
pack_export()
{
    local _pack_export_pack=$1 ; shift

    local _pack_export_args=()
    for _pack_export_arg in "${@}" ; do
        _pack_export_args+=("${_pack_export_arg}=${!_pack_export_arg:-}")
    done

    pack_set "${_pack_export_pack}" "${_pack_export_args[@]}"
}

pack_size()
{
    [[ -z ${1} ]] && die "pack_size requires a pack to be specified as \$1"
    echo -n "${!1}" | _unpack | wc -l
}

opt_usage pack_keys <<'END'
Echo a whitespace-separated list of the keys in the specified pack to stdout.
END
pack_keys()
{
    [[ -z ${1} ]] && die "pack_keys requires a pack to be specified as \$1"
    echo "${!1:-}" | _unpack | sed 's/=.*$//'
}

opt_usage pack_keys_sort <<'END'
Echo a whitespace-separated list of the sorted keys in the specified pack to stdout.
END
pack_keys_sort()
{
    pack_keys "${@}" | sort
}

opt_usage pack_print <<'END'
Note: To support working with print_value, pack_print does NOT print a newline at the end of its output
END
pack_print()
{
    local _pack_pack_print=$1
    argcheck _pack_pack_print

    echo -n '('
    pack_iterate _pack_print_item ${_pack_pack_print}
    echo -n ')'
}

_pack_print_item()
{
    echo -n "[$1]=\"$2\" "
}

_unpack()
{
    # NOTE: BSD base64 is really chatty and this is the reason we discard its error output
    base64 --decode 2>/dev/null | tr '\0' '\n'
}

_pack()
{
    # NOTE: BSD base64 is really chatty and this is the reason we discard its error output
    grep -av '^$' | tr '\n' '\0' | base64 2>/dev/null
}

pack_encode()
{
    [[ -z ${1} ]] && die "pack_encode requires a pack to be specified as \$1"
    echo -n "${!1}"
}

pack_decode()
{
    [[ -z ${1} ]] && die "pack_decode requires an encoded pack to be specified as \$1"
    echo -n "${1}" | _unpack
}

pack_save()
{
    $(opt_parse \
        "_pack_save_name | Name of the pack to save to disk."      \
        "_pack_save_file | Name of the file to save the pack to."  \
    )

    mkdir -p "$(dirname "${_pack_save_file}")"
    pack_encode "${_pack_save_name}" > "${_pack_save_file}"
}

pack_load()
{
    $(opt_parse \
        "_pack_load_name   | Name of the pack to read into from disk."      \
        "_pack_load_file   | Name of the file to read the pack from."  \
    )

    local _pack_load_data
    _pack_load_data="$(cat "${_pack_load_file}")"
    pack_copy _pack_load_data ${_pack_load_name}
}
