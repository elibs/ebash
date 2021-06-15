#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

# Default timestamp format to use. Supports:
# RFC3339       (e.g. "2006-01-02T15:04:05Z07:00")
# StampMilli    (e.g. "Jan _2 15:04:05.000")
: ${ETIMESTAMP_FORMAT:=RFC3339}

opt_usage etimestamp <<'END'
`etimestamp` is used to emit a timestamp in a standard format that we use through ebash. The format that we used is
controlled via `ETIMESTAMP_FORMAT` and defaults to `RFC3339`.
END
etimestamp()
{
    if [[ "${ETIMESTAMP_FORMAT:-}" == "StampMilli" ]]; then
        echo -en "$(date '+%b %d %T.%3N')"
    elif [[ "${ETIMESTAMP_FORMAT:-}" == "RFC3339" ]]; then
        echo -en "$(date '+%FT%TZ')"
    else
        die "Unsupported $(lval ETIMESTAMP_FORMAT)"
    fi
}

opt_usage etimestamp_rfc3339 <<'END'
`etimestamp_rfc3339` is a more explicit version of `etimestamp` which emits the time format in `RFC3339` format regardless
of the value of `ETIMESTAMP_FORMAT`.
END
etimestamp_rfc3339()
{
    echo -en $(date '+%FT%TZ')
}

opt_usage duration_string <<'END'
`duration_string` is used to emit a time duration in ISO8601/RFC3339 format between two times where the ending time
defaults to `now`. The format used is `hh:mm:ss`.
END
time_duration()
{
    $(opt_parse \
        "start            | Starting time represented in seconds. Typically obtained via bash global variable SECONDS." \
        "?stop=${SECONDS} | Stopping time represented in seconds. Defaults to the current time obtained via SECONDS."   \
    )

    local diff
    diff=$(( stop - start ))
    printf "%02d:%02d:%02d" $(( diff / 3600 )) $(( (diff % 3600) / 60 )) $(( diff % 60 ))
}
