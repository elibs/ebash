#!/bin/bash
#
# Copyright 2014-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

edistro()
{
    lsb_release -is
}

isubuntu()
{
    [[ "Ubuntu" == $(edistro) ]]
}

isgentoo()
{
    [[ "Gentoo" == $(edistro) ]]
}

isfedora()
{
    [[ "Fedora" == $(edistro) ]]
}

opt_usage os_distro<<'EOF'
Get the name of the currently running distro, or check whether it is in a list of specified distros.
EOF
os_distro()
{
    $(opt_parse \
        "@args | If specified, as long as the current distro is one of those in this list, the
                 command will return success.  If none is specified, the current distro will
                 simply be printed")

    local actual_distro=""
    if [[ ${__EBASH_OS,,} == "linux" ]] ; then
        actual_distro=$(lsb_release --id --short)
    fi

    if [[ -n ${actual_distro} && ${#@} -gt 0 ]] ; then

        local distro
        for distro in "${@}" ; do
            if [[ ${distro,,} == ${actual_distro,,} ]] ; then
                return 0;
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
Get the released version of the currently running OS or distribution, OR check whether that is in a
list of release versions that you specify.
EOF
os_release()
{
    $(opt_parse \
        "@args | If specified, as long as the release of the current OS or distro is one of those in
                 the list, the command will return success.  If unspecified, the current release
                 will simply be printed.")

    if os linux ; then
        actual_release=$(lsb_release --release --short)

    elif os darwin ; then
        actual_release=$(sw_vers -productVersion)

    else
        die "os_release supports only linux and darwin, not ${__EBASH_OS}"
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
Get the unix name of the currently running OS, OR test it against a list of specified OSes returning
success if it is in that list.
EOF
os()
{
    $(opt_parse \
        "@args | If specified, as long as the uname of the current OS or distro is one of those in
                 the list, the command will return success.  If unspecified, the current OS will
                 simply be printed.  Comparisons are case-insensitive")

    if [[ ${#@} -gt 0 ]] ; then

        local os
        for os in "${@}" ; do
            if [[ ${os,,} == ${__EBASH_OS,,} ]] ; then
                return 0
            fi
        done
        return 1

    else
        echo "${__EBASH_OS}"
    fi
}
