#!/usr/bin/env bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License as
# published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Hardware
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage get_memory_size <<'END'
Get the size of memory on the system in various units. This works properly on both Linux and Mac.

The `--units` option allows you to specify the desired 1 or 2 character code of the units to express the size in. Both
SI and IEC units are supported.

Here is the list of supported unit codes (case-sensitive) along with their meanings:

    B  = bytes

    SI Units
    --------
    K  = kilobytes
    M  = megabytes
    G  = gigabytes
    T  = terabytes
    P  = petabytes

    IEC Units
    ---------
    Ki = kibibyte
    Mi = Mebibyte
    Gi = gibibyte
    Ti = tebibyte
    Pi = pebibyte
END
get_memory_size()
{
    local supported_units="B|K|M|G|T|P|Ki|Mi|Gi|Ti|Pi"
    $(opt_parse \
        ":units=B | Units to report memory in (${supported_units//|/,})." \
    )

    assert_match "${units}" "(${supported_units})"

    local bytes=""
    if [[ ${__EBASH_OS} == Linux ]] ; then
        bytes=$(free --bytes | grep "Mem:" | awk '{print $2}')
    elif [[ ${__EBASH_OS} == Darwin ]] ; then
        bytes=$(sysctl -n hw.memsize)
    else
        die "Unsupported OS=${__EBASH_OS}"
    fi

    if [[ "${units}" == "B" ]]; then
        echo "${bytes}"
        return 0
    fi

    # Convert the bytes to the desired units
    case "${units}" in

        Ki) echo $(( bytes / 1024 )) ;;
        Mi) echo $(( bytes / 1024 / 1024 )) ;;
        Gi) echo $(( bytes / 1024 / 1024 / 1024 )) ;;
        Ti) echo $(( bytes / 1024 / 1024 / 1024 / 1024 )) ;;
        Pi) echo $(( bytes / 1024 / 1024 / 1024 / 1024 / 1024 )) ;;

        K)  echo $(( bytes / 1000 )) ;;
        M)  echo $(( bytes / 1000 / 1000 )) ;;
        G)  echo $(( bytes / 1000 / 1000 / 1000 )) ;;
        T)  echo $(( bytes / 1000 / 1000 / 1000 / 1000 )) ;;
        P)  echo $(( bytes / 1000 / 1000 / 1000 / 1000 / 1000 )) ;;

        # Unsupported
        *) die "Unsupported $(lval units)"
    esac
}
