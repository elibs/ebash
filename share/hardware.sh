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

opt_usage get_memory_size_kb <<'END'
Get the size of memroy on the system in various units. This works properly on both Linux and Mac.

The --units option allows you to specify the desired units to express the size in. Both SI and IEC units are supporte.

Here is the list of supported unit values, along with their meanings:

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

    # Else delegate the conversion to numfmt
    numfmt --to-unit=${units} --round=down "${bytes}"
}
