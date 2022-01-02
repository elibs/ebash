#!/bin/bash
#
# Copyright 2014-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2014-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# OS
#
#-----------------------------------------------------------------------------------------------------------------------

# EBASH_DISTRO is used to cache results from `edistro` to avoid repeated lookups when it will never change from one call
# to the next. It also allows customization inside the user's environment to use an explicit distro that might otherwise
# be misdetected or to facilitate dependency injection testing approaches.
#
: ${EBASH_DISTRO:=}

opt_usage edistro <<'END'
edistro is a generic way to figure out what "distro" we are running on. This is largely only a Linux concept so on MacOS
this produces "darwin" as per `uname` output. Otherwise, Linux generically supports getting the Distro by looking in
`/etc/os-release`. This is lighter weight than having to ensure that lsb_release is installed on all clients. If we have
to, we'll fall back to lsb_release and finally just use raw `uname` output if nothing is available.

NOTE: Instead of calling `uname` here we just use `EBASH_OS` which is set inside `ebash.sh` to avoid having to call that
      repeatedly.
END
edistro()
{
    # Cache results in EBASH_DISTRO
    if [[ -n "${EBASH_DISTRO}" ]]; then
        echo "${EBASH_DISTRO}"
        return 0
    fi

    local name="" result=""
    name="${EBASH_OS}"

    if [[ "${name}" == "Darwin" ]]; then
        result="darwin"
    elif [[ -e "/etc/os-release" ]]; then
        result=$(awk -F'[="]*' '/^ID=/ {print $2}' /etc/os-release)
    elif command_exists lsb_release; then
        result=$(lsb_release -is)
    else
        result="${name}"
    fi

    echo "${result,,}"
}

opt_usage os_distro <<'EOF'
Get the name of the currently running distro, or check whether it is in a list of specified distros.
EOF
os_distro()
{
    $(opt_parse \
        "@args | If specified, as long as the current distro is one of those in this list, the command will be
                 successful. If none is specified, the current distro will simply be printed")

    local actual_distro=""
    if [[ ${EBASH_OS,,} == "linux" ]] ; then
        actual_distro=$(edistro)
    fi

    if [[ -n ${actual_distro} && ${#@} -gt 0 ]] ; then

        local distro
        for distro in "${@}" ; do
            if [[ ${distro,,} == ${actual_distro,,} ]] ; then
                return 0
            fi
        done

        return 1

    elif [[ -z ${actual_distro} && ${#@} -gt 0 ]] ; then
        # If we're not on an OS with distros, no specified distro can be a match.
        return 1

    else
        echo "${actual_distro}"
    fi
}

opt_usage os_release <<'EOF'
Get the released version of the currently running OS or distribution, OR check whether that is in a list of release
versions that you specify.
EOF
os_release()
{
    $(opt_parse \
        "@args | If specified, as long as the release of the current OS or distro is one of those in the list, the
                 command will succeed. If unspecified, the current release will simply be printed.")

    if os linux ; then
        if command_exists lsb_release; then
            actual_release=$(lsb_release --release --short)
        else
            actual_release=$(awk -F'[="]*' '/^VERSION_ID=/ {print $2}' /etc/os-release)
        fi

    elif os darwin ; then
        actual_release=$(sw_vers -productVersion)

    else
        die "os_release supports only linux and darwin, not ${EBASH_OS}"
    fi


    if [[ ${#@} -gt 0 ]] ; then

        local release
        for release in "${@}" ; do

            if [[ ${actual_release,,} == ${release,,} ]] ; then
                return 0
            fi
        done

        return 1

    else

        echo "${actual_release}"

    fi

}

opt_usage os <<'EOF'
Get the unix name of the currently running OS, OR test it against a list of specified OSes returning success if it is in
that list.
EOF
os()
{
    $(opt_parse \
        "@args | If specified, as long as the uname of the current OS or distro is one of those in the list, the command
                 will succeeds. If unspecified, the current OS will simply be printed. Comparisons are case-insensitive")

    if [[ ${#@} -gt 0 ]] ; then

        local os
        for os in "${@}" ; do
            if [[ ${os,,} == ${EBASH_OS,,} ]] ; then
                return 0
            fi
        done
        return 1

    else
        echo "${EBASH_OS}"
    fi
}

opt_usage os_pretty_name <<'EOF'
Get a prety name for this OS in the form of:

```shell
${DISTRO} ${OS} ${RELEASE}
```

For example:
```
Gentoo Linux 2.7
Alpine Linux 3.11
Darwin 10.15.7
```
EOF
os_pretty_name()
{
    if os darwin; then
        echo "Darwin $(os_release)"
    else
        local distro
        distro="$(edistro)"
        echo "${distro^} $(os) $(os_release)"
    fi
}

opt_usage command_exists <<'END'
Helper function to check if a command exists. The actual implementation could be a function in our environment or an
external program.
END
command_exists()
{
    { declare -f "${1}" || which "${1}"; } &>/dev/null
}

opt_usage require <<'END'
Helper function to validate that a list of commands are all installed in our PATH.
END
require()
{
    local missing=0
    local cmd
    for cmd in "${@}"; do
        if ! command_exists "${cmd}"; then
            eerror "Command ${cmd} not found in ${PATH}"
            (( missing += 1 ))
        fi
    done

    assert_zero "${missing}"
}
