#!/usr/bin/env bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage eprompt <<'END'
eprompt allows the caller to present a prompt to the user and have the result the user types in echoed back to the
caller's standard output. The current design of eprompt is limited it that you can only prompt for a single value at
a time and it doesn't do anything fancy in terms of validation or knowing about optional or required values. Additionally
the output cannot currently contain newlines though it can contain whitespace.
END
eprompt()
{
    $(opt_parse \
        "+silent s | Be silent and do not echo input coming from the terminal.")

    echo -en "$(ecolor bold) * $*: $(ecolor none)" >&2
    local result=""

    if [[ "${silent}" -eq 1 ]]; then
        read -s result < /dev/stdin
        echo >&2
    else
        read result < /dev/stdin
    fi

    echo -en "${result}"
}

opt_usage eprompt_with_options <<'END'
eprompt_with_options allows the caller to specify what options are valid responses to the provided question using a
comma separated list. The caller can also optionally provide a list of "secret" options which will not be displayed in
the prompt to the user but will be accepted as a valid response. This list is also comma separated.
END
eprompt_with_options()
{
    $(opt_parse "msg" "opt" "?secret")

    local valid
    valid="$(echo ${opt},${secret} | tr ',' '\n' | sort --ignore-case --unique)"
    msg+=" (${opt})"

    ## Keep reading input until a valid response is given
    while true; do
        response=$(eprompt "${msg}")
        matches=( $(echo "${valid}" | grep -io "^${response}\S*" || true) )
        edebug "$(lval response opt secret matches valid)"
        [[ ${#matches[@]} -eq 1 ]] && { echo -en "${matches[0]}"; return 0; }

        eerror "Invalid response=[${response}] -- use a unique prefix from options=[${opt}]"
    done
}

opt_usage epromptyn <<'END'
epromptyn is a special case of eprompt_with_options wherein the only valid options are "Yes" and "No". If the caller
provides anything other than those values they will receive an error message and be presented with another prompt to
re-input the value correctly.
END
epromptyn()
{
    $(opt_parse "msg")
    eprompt_with_options "${msg}" "Yes,No"
}
