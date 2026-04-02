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

    # Optimization: unpack once, modify in memory, pack once
    # This is O(n) instead of O(n²) when setting multiple keys
    # We use both an array (for order) and an associative array (for lookup)
    local _pack_set_keys=()
    declare -A _pack_set_values=()
    local _pack_set_unpacked _pack_set_line _pack_set_key _pack_set_val

    # Unpack existing data, preserving key order
    # Use || true to gracefully handle variables that contain non-pack data
    if [[ -n "${!_pack_set_pack:-}" ]]; then
        _pack_set_unpacked="$(echo -n "${!_pack_set_pack}" | _unpack || true)"
        while IFS= read -r _pack_set_line; do
            [[ -z "${_pack_set_line}" ]] && continue
            _pack_set_key="${_pack_set_line%%=*}"
            _pack_set_val="${_pack_set_line#*=}"
            _pack_set_keys+=("${_pack_set_key}")
            _pack_set_values["${_pack_set_key}"]="${_pack_set_val}"
        done <<< "${_pack_set_unpacked}"
    fi

    # Set new values (validates and updates)
    # Track which keys are being set so we can reorder once at the end
    declare -A _pack_set_new_keys_map=()
    local _pack_set_new_keys_order=()

    for _pack_set_arg in "${@}" ; do
        _pack_set_key="${_pack_set_arg%%=*}"
        _pack_set_val="${_pack_set_arg#*=}"

        [[ -z "${_pack_set_key}" ]] && continue
        [[ "${_pack_set_key}" == *=* ]] && die "ebash internal error: tag ${_pack_set_key} cannot contain equal sign"
        [[ "${_pack_set_val}" == *$'\n'* ]] && die "packed values cannot hold newlines"

        _pack_set_values["${_pack_set_key}"]="${_pack_set_val}"
        if [[ -z "${_pack_set_new_keys_map[$_pack_set_key]:-}" ]]; then
            _pack_set_new_keys_map["${_pack_set_key}"]=1
            _pack_set_new_keys_order+=("${_pack_set_key}")
        fi
    done

    # Rebuild key order once: existing keys (excluding new ones) + new keys in order
    local _pack_set_final_keys=()
    for _pack_set_k in "${_pack_set_keys[@]}"; do
        [[ -z "${_pack_set_new_keys_map[$_pack_set_k]:-}" ]] && _pack_set_final_keys+=("${_pack_set_k}")
    done
    _pack_set_keys=("${_pack_set_final_keys[@]}" "${_pack_set_new_keys_order[@]}")

    # Pack preserving key order (single encode)
    local _pack_set_to_pack=""
    for _pack_set_key in "${_pack_set_keys[@]}"; do
        _pack_set_to_pack+="${_pack_set_key}=${_pack_set_values[$_pack_set_key]}"$'\n'
    done
    local _pack_set_packed
    _pack_set_packed=$(echo -n "${_pack_set_to_pack}" | _pack)
    printf -v "${_pack_set_pack}" "%s" "${_pack_set_packed}"
}

opt_usage pack_update <<'END'
 Much like pack_set, and takes arguments of the same form. The difference is that pack_update will create no new keys
 -- it will only update keys that already exist.
END
pack_update()
{
    local _pack_update_pack=$1 ; shift

    # Optimization: unpack once to check which keys exist, then batch update
    declare -A _pack_update_existing=()
    local _pack_update_unpacked _pack_update_line _pack_update_key

    if [[ -n "${!_pack_update_pack:-}" ]]; then
        _pack_update_unpacked="$(echo -n "${!_pack_update_pack}" | _unpack || true)"
        while IFS= read -r _pack_update_line; do
            [[ -z "${_pack_update_line}" ]] && continue
            _pack_update_key="${_pack_update_line%%=*}"
            _pack_update_existing["${_pack_update_key}"]=1
        done <<< "${_pack_update_unpacked}"
    fi

    # Collect only the updates for keys that exist
    local _pack_update_args=()
    for _pack_update_arg in "${@}" ; do
        _pack_update_key="${_pack_update_arg%%=*}"
        if [[ -n "${_pack_update_existing[$_pack_update_key]:-}" ]]; then
            _pack_update_args+=("${_pack_update_arg}")
        fi
    done

    # Batch update all at once
    if [[ ${#_pack_update_args[@]} -gt 0 ]]; then
        pack_set "${_pack_update_pack}" "${_pack_update_args[@]}"
    fi
}

opt_usage pack_get <<'END'
Get the last value assigned to a particular key in this pack.
END
pack_get()
{
    local _pack_get_pack=$1
    local _pack_get_tag=$2

    argcheck _pack_get_pack _pack_get_tag

    [[ -z "${!_pack_get_pack:-}" ]] && return 0

    local _pack_get_unpacked _pack_get_line _pack_get_key _pack_get_result=""
    _pack_get_unpacked="$(echo -n "${!_pack_get_pack}" | _unpack)"

    while IFS= read -r _pack_get_line; do
        [[ -z "${_pack_get_line}" ]] && continue
        _pack_get_key="${_pack_get_line%%=*}"
        if [[ "${_pack_get_key}" == "${_pack_get_tag}" ]]; then
            # Keys are unique after pack_set, so we can return immediately
            echo "${_pack_get_line#*=}"
            return 0
        fi
    done <<< "${_pack_get_unpacked}"
}

pack_contains()
{
    # Returns true if key exists AND has a non-empty value
    [[ -n "$(pack_get "$@")" ]]
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
    local _pack_iterate_func=$1
    local _pack_iterate_pack=$2
    argcheck _pack_iterate_func _pack_iterate_pack

    [[ -z "${!_pack_iterate_pack:-}" ]] && return 0

    local _pack_iterate_unpacked _pack_iterate_line
    _pack_iterate_unpacked="$(echo -n "${!_pack_iterate_pack}" | _unpack)"

    while IFS= read -r _pack_iterate_line; do
        [[ -z "${_pack_iterate_line}" ]] && continue
        ${_pack_iterate_func} "${_pack_iterate_line%%=*}" "${_pack_iterate_line#*=}"
    done <<< "${_pack_iterate_unpacked}"
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
    # Fast path: common case with no flags - first arg is pack name, rest are optional keys
    # Flags start with - or +, pack names don't
    local _pack_import_scope="local"
    local _pack_import_pack=""
    local _pack_import_keys=()

    if [[ $# -gt 0 && "${1:0:1}" != "-" && "${1:0:1}" != "+" ]]; then
        # Fast path: no flags
        _pack_import_pack=$1
        shift
        _pack_import_keys=("${@}")
    else
        # Slow path: has flags, use opt_parse
        $(opt_parse \
            "+local l=1        | Emit local variables via local builtin (default)." \
            "+global g         | Emit global variables instead of local (i.e. undeclared variables)." \
            "+export e         | Emit exported variables via export builtin." \
            "_pack_import_pack | Pack to operate on.")

        [[ ${global} -eq 1 ]] && _pack_import_scope=""
        [[ ${export} -eq 1 ]] && _pack_import_scope="export"
        _pack_import_keys=("${@}")
    fi

    # Optimization: unpack once into associative array, then build command
    # This is O(n) instead of O(n²) - we decode once instead of once per key
    declare -A _pack_import_data=()
    local _pack_import_unpacked _pack_import_line _pack_import_key _pack_import_val

    if [[ -n "${!_pack_import_pack:-}" ]]; then
        _pack_import_unpacked="$(echo -n "${!_pack_import_pack}" | _unpack)"
        while IFS= read -r _pack_import_line; do
            [[ -z "${_pack_import_line}" ]] && continue
            _pack_import_key="${_pack_import_line%%=*}"
            _pack_import_val="${_pack_import_line#*=}"
            _pack_import_data["${_pack_import_key}"]="${_pack_import_val}"
        done <<< "${_pack_import_unpacked}"
    fi

    # Build command string
    local _pack_import_cmd=""

    if [[ ${#_pack_import_keys[@]} -eq 0 ]]; then
        # Import all keys - iterate unpacked lines to preserve order
        while IFS= read -r _pack_import_line; do
            [[ -z "${_pack_import_line}" ]] && continue
            _pack_import_key="${_pack_import_line%%=*}"
            _pack_import_cmd+="${_pack_import_scope} ${_pack_import_key}=\"${_pack_import_data[$_pack_import_key]}\"; "
        done <<< "${_pack_import_unpacked}"
    else
        # Import only specified keys
        for _pack_import_key in "${_pack_import_keys[@]}"; do
            _pack_import_cmd+="${_pack_import_scope} ${_pack_import_key}=\"${_pack_import_data[$_pack_import_key]:-}\"; "
        done
    fi

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
    [[ -z "${!1:-}" ]] && { echo 0; return 0; }

    local _pack_size_unpacked _pack_size_line _pack_size_count=0
    _pack_size_unpacked="$(echo -n "${!1}" | _unpack)"

    while IFS= read -r _pack_size_line; do
        [[ -n "${_pack_size_line}" ]] && (( ++_pack_size_count ))
    done <<< "${_pack_size_unpacked}"

    echo "${_pack_size_count}"
}

opt_usage pack_keys <<'END'
Echo a whitespace-separated list of the keys in the specified pack to stdout.
END
pack_keys()
{
    [[ -z ${1} ]] && die "pack_keys requires a pack to be specified as \$1"
    [[ -z "${!1:-}" ]] && return 0

    local _pack_keys_unpacked _pack_keys_line
    _pack_keys_unpacked="$(echo -n "${!1}" | _unpack)"

    while IFS= read -r _pack_keys_line; do
        [[ -z "${_pack_keys_line}" ]] && continue
        echo "${_pack_keys_line%%=*}"
    done <<< "${_pack_keys_unpacked}"
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
    local _pack_print_pack=$1
    argcheck _pack_print_pack

    echo -n '('
    if [[ -n "${!_pack_print_pack:-}" ]]; then
        local _pack_print_unpacked _pack_print_line
        _pack_print_unpacked="$(echo -n "${!_pack_print_pack}" | _unpack)"
        while IFS= read -r _pack_print_line; do
            [[ -z "${_pack_print_line}" ]] && continue
            echo -n "[${_pack_print_line%%=*}]=\"${_pack_print_line#*=}\" "
        done <<< "${_pack_print_unpacked}"
    fi
    echo -n ')'
}

pack_print_key_value()
{
    local _pack_print_kv_pack=$1
    argcheck _pack_print_kv_pack

    [[ -z "${!_pack_print_kv_pack:-}" ]] && return 0

    local _pack_print_kv_unpacked _pack_print_kv_line
    _pack_print_kv_unpacked="$(echo -n "${!_pack_print_kv_pack}" | _unpack)"
    while IFS= read -r _pack_print_kv_line; do
        [[ -z "${_pack_print_kv_line}" ]] && continue
        echo "${_pack_print_kv_line%%=*}=\"${_pack_print_kv_line#*=}\""
    done <<< "${_pack_print_kv_unpacked}"
}

_unpack()
{
    # NOTE: BSD base64 is really chatty and this is the reason we discard its error output
    base64 --decode 2>/dev/null | tr '\0' '\n'
}

_pack()
{
    # NOTE: BSD base64 is really chatty and this is the reason we discard its error output
    # Use awk to filter empty lines AND convert newlines to nulls in one process (was: grep | tr | base64)
    awk 'NF {printf "%s\0", $0}' | base64 2>/dev/null
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
    local _pack_save_name=$1
    local _pack_save_file=$2

    # Use bash string manipulation instead of dirname subshell
    local _pack_save_dir="${_pack_save_file%/*}"
    [[ "${_pack_save_dir}" != "${_pack_save_file}" ]] && mkdir -p "${_pack_save_dir}"
    pack_encode "${_pack_save_name}" > "${_pack_save_file}"
}

pack_load()
{
    local _pack_load_name=$1
    local _pack_load_file=$2

    local _pack_load_data
    _pack_load_data=$(<"${_pack_load_file}")
    printf -v "${_pack_load_name}" "%s" "${_pack_load_data}"
}
