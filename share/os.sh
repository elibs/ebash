#!/bin/bash
#
# Copyright 2014-2016, SolidFire, Inc. All rights reserved.
#

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

os_distro()
{
    $(opt_parse \
        "@args | If specified, as long as the current distro is one of those in this list, the
                 command will return success.  If none is specified, the current distro will
                 simply be printed")

    local actual_distro=""
    if [[ ${__BU_OS,,} == "linux" ]] ; then
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

    else
        echo "${actual_distro}"
    fi
}

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
        die "os_release supports only linux and darwin, not ${__BU_OS}"
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

os()
{
    $(opt_parse \
        "@args | If specified, as long as the uname of the current OS or distro is one of those in
                 the list, the command will return success.  If unspecified, the current OS will
                 simply be printed.  Comparisons are case-insensitive")

    if [[ ${#@} -gt 0 ]] ; then

        local os
        for os in "${@}" ; do
            if [[ ${os,,} == ${__BU_OS,,} ]] ; then
                return 0
            fi
        done
        return 1

    else
        echo "${__BU_OS}"
    fi
}

os_is_linux()
{
    [[ ${__BU_OS,,} == "linux" ]]
}

os_is_darwin()
{
    [[ ${__BU_OS,,} == "darwin" ]]
}
