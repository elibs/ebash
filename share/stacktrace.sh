#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Stacktrace
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage stacktrace <<'END'
Print stacktrace to stdout. Each frame of the stacktrace is separated by a newline. Allows you to optionally pass in a
starting frame to start the stacktrace at. 0 is the top of the stack and counts up. See also stacktrace and
error_stacktrace.
END
stacktrace()
{
    $(opt_parse ":frame f=0 | Frame number to start at if not the current one")

    while caller ${frame}; do
        (( frame+=1 ))
    done
}

opt_usage stacktrace_array <<'END'
Populate an array with the frames of the current stacktrace. Allows you to optionally pass in a starting frame to start
the stacktrace at. 0 is the top of the stack and counts up. See also stacktrace and eerror_stacktrace
END
stacktrace_array()
{
    $(opt_parse \
        ":frame f=1 | Frame number to start at" \
        "array")

    array_init_nl ${array} "$(stacktrace -f=${frame})"
}
