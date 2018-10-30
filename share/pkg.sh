#!/usr/bin/env bash
#
# Copyright 2016-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

os darwin && return 0

opt_usage pkg_known <<'END'
Determine if the package management system locally knows of a package with the specified name.  This
won't update the package database to do its check.  Note that this does _not_ mean the package is
installed.  Just that the package system believes it could install it.

See pkg_installed to check if a package is actually installed.
END
pkg_known()
{
    $(opt_parse \
        "name | Name of package to look for.")

    case $(pkg_manager) in
        dpkg)
            apt-cache show ${name} &>/dev/null
            ;;

        portage)

            name=$(pkg_gentoo_canonicalize ${name})
            [[ -d /usr/portage/${name} ]]
            ;;

        dnf)
            dnf list ${name} &>/dev/null
            ;;

        pacman)
            pacman -Ss ${name} &>/dev/null
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_gentoo_canonicalize<<'END'
Takes as input a package name that may or may not have a category identifier on it.  If it does not
have a category (e.g. app-misc or dev-util), then find the category that contains the specified package.

NOTE: If the results would be ambiguous, fails and indicates that a category is required.
END
pkg_gentoo_canonicalize()
{
    $(opt_parse "name | Package name whose category you'd like to find.")

    if [[ ${name} == */* ]] ; then
        echo "${name}"

    else

        pushd /usr/portage
        local found=() size=0
        found=( */${name} )
        size=$(array_size found)
        popd

        if [[ ${size} -eq 0 ]] ; then
            return 1

        elif [[ ${size} -eq 1 ]] ; then
            echo "${found[0]}"

        else
            eerror "${name} is ambiguous.  You must specify a category."
            return 2
        fi
    fi
}

opt_usage pkg_installed<<'END'
Returns success if the specified package has been installed on this machine and false if it has not.
END
pkg_installed()
{
    $(opt_parse \
        "name | Name of package to look for.")

    local pkg_status=""
    case $(pkg_manager) in
        dpkg)
            pkg_status="$(dpkg -s "${name}" 2>/dev/null | grep '^Status:')"
            [[ "${pkg_status}" == 'Status: install ok installed' ]]
            ;;

        portage)

            name=$(pkg_gentoo_canonicalize ${name})
            pushd /var/db/pkg
            local all_versions=( ${name}* )
            popd
            [[ ${#all_versions[@]} -gt 0 && -d /var/db/pkg/${all_versions[0]} ]]
            ;;

        dnf)
            dnf list installed ${name} &>/dev/null
            ;;

        pacman)
            pacman -Q ${name} &>/dev/null
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_install <<'END'
Install some set of packages whose names are specified.  Note that while this function supports
several different package managers, packages may have different names on different systems.
END
pkg_install()
{
    $(opt_parse "@names | Names of package to install.")

    local pkg_manager
    pkg_manager=$(pkg_manager)

    if ! pkg_known "${@}" ; then
        pkg_sync
    fi

    case ${pkg_manager} in
        dpkg)
            $(tryrc DEBIAN_FRONTEND=noninteractive aptitude -y install "${@}")

            # If it fails the first time...
            if [[ ${rc} -ne 0 ]] ; then
                # Try a bit of cleanup
                DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a
                DEBIAN_FRONTEND=noninteractive aptitude -f -y --force-yes install

                # And then give it one more chance
                DEBIAN_FRONTEND=noninteractive aptitude -y install "${@}"
            fi
            ;;

        portage)
            emerge --ask=n "${@}"
            ;;


        dnf)
            dnf install --cacheonly -y "${@}"
            ;;


        pacman)
            pacman -S --noconfirm "${@}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_uninstall<<'END'
Use local package manager to remove any number of specified packages without prompting to ask any questions.
END
pkg_uninstall()
{
    $(opt_parse "@names | Names of package to install.")

    case $(pkg_manager) in
        dpkg)
            DEBIAN_FRONTEND=noninteractive aptitude purge -y "${@}"
            ;;

        portage)
            emerge --ask=n --unmerge "${@}"
            ;;


        dnf)
            dnf remove -y "${@}"
            ;;


        pacman)
            pacman -R --noconfirm "${@}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_sync<<'END'
Sync the local package manager database with whatever remote repositories are known so that all
packages known to those repositories are also known locally.
END
pkg_sync()
{
    case $(pkg_manager) in
        dpkg)
            aptitude update
            ;;

        portage)
            emerge --sync
            ;;

        dnf)
            dnf makecache
            ;;

        pacman)
            pacman -Sy
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_clean<<'END'
Clean out the local package manager database cache and do anything else to the package manager to
try to clean up any bad states it might be in.
END
pkg_clean()
{
    case $(pkg_manager) in
        dpkg)
            find /var/lib/apt/lists -type f -a ! -name lock -a ! -name partial -delete
            ;;

        portage)
            # Gentoo's sync is more thorough than the package syncing of most other package managers
            # and so cleaning is typically unnecessary
            ;;

        dnf)
            dnf clean expire-cache
            ;;

        pacman)
            pacman -Sc --noconfirm
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac

    pkg_sync
}

opt_usage pkg_upgrade<<'END'
Replace the existing version of the specified package with the newest available package by that name.
END
pkg_upgrade()
{
    $(opt_parse \
        "name | Name of the package that should be upgraded to the newest possible version.")

    pkg_installed ${name}

    case $(pkg_manager) in
        dpkg)
            DEBIAN_FRONTEND=noninteractive aptitude install -y "${name}"
            ;;

        portage)
            emerge --update "${name}"
            ;;

        dnf)
            dnf update -y "${name}"
            ;;

        pacman)
            pacman -S --noconfirm "${name}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

pkg_manager()
{
    if os_distro ubuntu mint debian ; then
        echo "dpkg"

    elif os_distro fedora; then
        echo "dnf"

    elif os_distro gentoo ember ; then
        echo "portage"

    elif os_distro arch ; then
        echo "pacman"

    else
        echo "unknown"
        return 1
    fi
}
