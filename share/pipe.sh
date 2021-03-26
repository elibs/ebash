#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#---------------------------------------------------------------------------------------------------
#
# Pipe Functions
#
#---------------------------------------------------------------------------------------------------

opt_usage pipe_read <<'END'
Helper method to read from a pipe until we see EOF.
END
pipe_read()
{
    $(opt_parse "pipe")
    local line

    # Read returns an error when it reaches EOF. But we still want to emit that last line. So if we failed to read due
    # to EOF but saw a partial line we still want to echo it.
    #
    # NOTE: IFS='' and "-r" flag are critical here to ensure we don't lose whitespace or try to interpret anything.
    while IFS= read -r line || [[ -n "${line}" ]]; do
        echo "${line}"
    done <${pipe}
}

opt_usage pipe_read_quote <<'END'
Helper method to read from a pipe until we see EOF and then also intelligently quote the output in a way that can be
reused as shell input via "printf %q". This will allow us to safely eval the input without fear of anything being
exectued.

> **_NOTE:_** This method will echo `""` instead of using printf if the output is an empty string to avoid causing
various test failures where we'd expect an empty string `""` instead of a string with literal quotes in it `"''"`.
END
pipe_read_quote()
{
    $(opt_parse "pipe")
    local output
    output=$(pipe_read ${pipe})
    if [[ -n ${output} ]]; then
        printf %q "$(printf "%q" "${output}")"
    else
        echo -n ""
    fi
}
