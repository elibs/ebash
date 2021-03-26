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
# Logfile Rotation
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage elogrotate <<'END'
elogrotate rotates all the log files with a given basename similar to what happens with logrotate. It will always touch
an empty non-versioned file just log logrotate.

For example, if you pass in the pathname '/var/log/foo' and ask to keep a max of 5, it will do the following:

```shell
mv /var/log/foo.4 /var/log/foo.5
mv /var/log/foo.3 /var/log/foo.4
mv /var/log/foo.2 /var/log/foo.3
mv /var/log/foo.1 /var/log/foo.2
mv /var/log/foo   /var/log/foo.1
touch /var/log/foo
```
END
elogrotate()
{
    $(opt_parse \
        ":count c=5 | Maximum number of logs to keep" \
        ":size s=0  | If specified, rotate logs at this specified size rather than each call to
                      elogrotate. You can use these units: c -- bytes, w -- two-byte words, k --
                      kilobytes, m -- Megabytes, G -- gigabytes" \
        "name       | Base name to use for the logfile.")

    # If the file doesn't exist, there is nothing to do.
    if [[ ! -e "$(readlink -f "${name}")" ]]; then
        return 0
    fi

    # Ensure we don't try to rotate non-files
    if [[ ! -f $(readlink -f "${name}") ]]; then
        die "Cannot rotate non-file $(lval name)"
    fi

    # Find log files by exactly this name that are of the size that should be rotated
    local files
    files="$(find "$(dirname "${name}")" -maxdepth 1          \
                   -type f                                    \
                   -a -name "$(basename "${name}")"           \
                   -a \( -size ${size} -o -size +${size} \) )"

    edebug "$(lval name files count size)"

    # If log file exists and is smaller than size threshold just return
    if [[ -z "${files}"  ]]; then
        return 0
    fi

    local log_idx next
    for (( log_idx=${count}; log_idx > 0; log_idx-- )); do
        next=$(( log_idx+1 ))
        [[ -e ${name}.${log_idx} ]] && mv -f ${name}.${log_idx} ${name}.${next}
    done

    # Move non-versioned one over and create empty new file
    [[ -e ${name} ]] && mv -f ${name} ${name}.1
    mkdir -p $(dirname ${name})
    touch ${name}

    # Remove any log files greater than our retention count
    find "$(dirname "${name}")" -maxdepth 1                 \
               -type f -name "$(basename "${name}")"        \
            -o -type f -name "$(basename "${name}").[0-9]*" \
        | sort --version-sort | awk "NR>${count}" | xargs rm -f
}
