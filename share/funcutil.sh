#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Function Utilities
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage save_function <<'END'
save_function is used to safe off the contents of a previously declared function into ${1}_real to aid in overridding
a function or altering it's behavior.
END
save_function()
{
    local orig="" new=""
    orig=$(declare -f $1)
    new="${1}_real${orig#$1}"
    eval "${new}" &>/dev/null
}

opt_usage override_function <<'END'
override_function is a more powerful version of save_function in that it will still save off the contents of a
previously declared function into ${1}_real but it will also define a new function with the provided body ${2} and mark
this new function as readonly so that it cannot be overridden later. If you call override_function multiple times we
have to ensure it's idempotent. The danger here is in calling save_function multiple tiems as it may cause infinite
recursion. So this guards against saving off the same function multiple times.
END
override_function()
{
    $(opt_parse func body)

    # Don't save the function off it already exists to avoid infinite recursion
    declare -f "${func}_real" >/dev/null || save_function ${func}

    # If the function has already been overridden don't fail so long as it's IDENTICAL to what we've already defined it
    # as. This allows more graceful handling of sourcing a file multiple times with an override in it as it'll be
    # identical. Normally the eval below would produce an error with set -e enabled.
    local expected="${func} () ${body}"$'\n'"declare -rf ${func}"
    local actual
    actual="$(declare -pf ${func} 2>/dev/null || true)"
    [[ ${expected} == ${actual} ]] && return 0 || true

    eval "${expected}" &>/dev/null
    eval "declare -rf ${func}" &>/dev/null
}
