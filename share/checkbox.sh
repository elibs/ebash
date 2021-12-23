#!/bin/bash
#
# Copyright 2020, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.


opt_usage checkbox_open <<'END'
Dispay an open checkbox with an optional message to display. You can then later call checkbox_close to have the checkbox
filled in with a successful check mark or with a failing X. This is useful to display a list of dependencies or tasks.
END
checkbox_open()
{
    echo -n "$(tput setaf 209)$(tput bold)[ ]$(tput sgr0) ${*}" >&2
}

opt_usage checkbox_open_timer <<'END'
Display an open checkbox with an optional message as well as a timer. This is similar in purpose as checkbox_open only
this also displays a timer. This is useful when you want to have a long-running task with a timer and then fill in the
checkbox with a successful check mark or a failing X.
END
checkbox_open_timer()
{
    # Write the initial message out to a temporary file which we will cleanup.
    local checkfile
    checkfile=$(mktemp --tmpdir checkbox-open-timer-XXXXXX)
    printf "$(tput setaf 209)$(tput bold)[ ]$(tput sgr0) %-20s" "$*" > "${checkfile}"
    trap_add "rm --force ${checkfile}"

    # Now delegate the ticker to eprogress
    eprogress --style "echo" --file "${checkfile}"
}

opt_usage checkbox_close <<'END'
This is used to close a previosly opened checkbox with optional return code. The default if no return code is passed in
is `0` for success. This will move the curser up a line and fill in the open `[ ]` checkbox with a checkmark on success
and an `X` on failure.
END
checkbox_close()
{
    $(opt_parse \
        "+all a               | If set, kill ALL known checkbox_timer processes, not just the current one" \
        ":return_code rc r=0  | Should this checkbox show a mark for success or failure?"                  \
    )

    opt_forward eprogress_kill all return_code -- --callback "checkbox_eend"
}

opt_usage checkbox_eend <<'END'
`checkbox_eend` is used to print the final closing checkbox message via checkbox_close which in turn passes this function
into eprogress_kill. It will essentially ack the same as `eend` only it prints the checkbox with either a successful
check mark or a failing X.
END
checkbox_eend()
{
    $(opt_usage \
        "return_code=0 | Return code of the command that last ran. Success (0) will print '[✓]' message and any non-zero
                         value will emit '[✘]'." \
    )


    printf "\r"

    if [[ "${return_code}" -eq 0 ]]; then
        echo "$(tput setaf 2)$(tput bold)[✓]$(tput sgr0)"
    else
        echo "$(tput setaf 1)$(tput bold)[✘]$(tput sgr0)"
    fi
}

opt_usage checkbox <<'END'
checkbox is a simple function to display a checkbox at the start of the line followed by an optional message.
END
checkbox()
{
    echo "$(tput setaf 2)$(tput bold)[✓]$(tput sgr0) ${*}" >&2
}

opt_usage checkbox_passed <<'END'
checkbox_passed is a simple wrapper around checkbox that displays a successful checkbox and PASSED followed by an
optional message.
END
checkbox_passed()
{
    echo -e "$(tput setaf 2)$(tput bold)[✓] PASSED$(tput sgr0) ${*}" >&2
}

opt_usage checkbox_failed <<'END'
checkbox_failed is a simple wrapper around checkbox that displays a failure checkbox and FAILED followed by an optional
message.
END
checkbox_failed()
{
    echo -e "$(tput setaf 1)$(tput bold)[✘] FAILED$(tput sgr0) ${*}" >&2
}
