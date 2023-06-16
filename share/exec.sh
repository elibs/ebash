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
# Exec
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage reexec <<'END'
reexec re-executes our shell script along with all the arguments originally provided to it on the command-line
optionally as the root user and optionally inside a mount namespace.
END
reexec()
{
    # If opt_parse has already been called in the main script, we want to preserve the options that it removed from $@
    # as it worked. Luckily, it saves those off and we can read them from __EBASH_FULL_ARGS.
    #
    # Determining if __EBASH_FULL_ARGS contains anything is difficult for a couple reasons. One is that we want to be
    # compatible with bash 4.2, 4.3, and 4.4 and each behaves differently with respect to emtpy arrays and set -u. See
    # array_size in array.sh for more info on that. We'd normally use array_size, but it calls opt_parse which
    # helpfullly overwrites __EBASH_FULL_ARGS for us. Here, we sidestep the issue by presuming that opt_parse will have
    # done nothing to $@ unless it contains at least one characters, so we'll only do anything if __EBASH_FULL_ARGS
    # contains at least one character in any one slot in the array.
    #
    if [[ -n "${__EBASH_FULL_ARGS[*]:-}" ]] ; then
        __EBASH_REEXEC_CMD=( "${__EBASH_REEXEC_CMD[0]:-}" "${__EBASH_FULL_ARGS[@]}" )
    fi

    $(opt_parse \
        "+sudo             | Ensure this process is root, and use sudo to become root if not." \
        "+mountns mount_ns | Create a new mount namespace to run in.")

    array_not_empty __EBASH_REEXEC_CMD || die "reexec must be called via its eponymous alias."

    # If sudo was requested and the caller is not already root then exec sudo. Take special care to pass through the
    # TMPDIR variable since glibc silently deletes it from the environment of any suid binary such as sudo. If TMPDIR
    # isn't set, then set it to /tmp which is what would normally happen if the variable wasn't set.
    if [[ ${sudo} -eq 1 && $(id -u) != 0 ]] ; then
        exec sudo TMPDIR=${TMPDIR:-/tmp} -E -- "${__EBASH_REEXEC_CMD[@]}"
    fi

    if [[ ${mountns} -eq 1 && ${__EBASH_REEXEC_MOUNT_NS:-} != ${BASHPID} ]] ; then
        export __EBASH_REEXEC_MOUNT_NS=${BASHPID}
        exec unshare -m -- "${__EBASH_REEXEC_CMD[@]}"
    fi
    unset __EBASH_REEXEC_CMD
}

# Normally shellcheck is right here but we are defering this expansion until the alias is invoked and it does exactly
# what we expect in this particular case.
# shellcheck disable=SC2142
alias reexec='declare -a __EBASH_REEXEC_CMD=("$0" "$@") ; reexec'

opt_usage quote_eval <<'END'
Ever want to evaluate a bash command that is stored in an array?  It's mostly a great way to do things. Keeping the
various arguments separate in the array means you don't have to worry about quoting. Bash keeps the quoting you gave it
in the first place. So the typical way to run such a command is like this:

```shell
> cmd=(echo "\$\$")
> "${cmd[@]}"
$$
```

As you can see, since the dollar signs were quoted as the command was put into the array, so the quoting was retained
when the command was executed. If you had instead used eval, you wouldn't get that behavior:

```shell
> cmd=(echo "\$\$")
> "${cmd[@]}"
53355
```

Instead, the argument gets "evaluated" by bash, turning it into the current process id. So if you're storing commands in
an array, you can see that you typically don't want to use eval.

But there's a wrinkle, of course. If the first item in your array is the name of an alias, bash won't expand that alias
when using the first syntax. This is because alias expansion happens in a stage _before_ bash expands the contents of
the variable.

So what can you do if you want alias expansion to happen but also want things in the array to be quoted properly?  Use
`quote_array`. It will ensure that all of the arguments don't get evaluated by bash, but that the name of the command
_does_ go through alias expansion.

```shell
> cmd=(echo "\$\$")
> quote_eval "${cmd[@]}"
$$
```
END
quote_eval()
{
    local cmd=("$1")
    shift

    for arg in "${@}" ; do
        cmd+=( "$(printf %q "${arg}")" )
    done

    eval "${cmd[@]}"
}
