#!/usr/bin/env bash
#
# Copyright 2016-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2016-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage pkg_known <<'END'
Determine if the package manager locally knows of all of the packages specified. This won't update the pacakge database
to do its check. Note that this does *not* mean the package is installed. Just that the package manager knows about the
package and could install it.

See pkg_installed to check if a package is actually installed.
END
pkg_known()
{
    $(opt_parse "@names | Names of package to check.")

    edebug "Checking existence of $(lval names)"

    local name
    for name in "${names[@]}"; do
        case $(pkg_manager) in
            apk)
                [[ -n "$(apk list ${name} 2>/dev/null)" ]]
                ;;

            apt)
                apt-cache show ${name} &>/dev/null
                ;;

            brew)
                brew search ${name} &>/dev/null
                ;;

            pacman)
                pacman -Si ${name} &>/dev/null
                ;;

            portage)
                pkg_canonicalize "${name}" &>/dev/null
                ;;

            yum)
                yum list ${name} &>/dev/null
                ;;

            *)
                die "Unsupported package manager $(pkg_manager)"
                ;;
        esac
    done
}

opt_usage pkg_canonicalize <<'END'
Takes as input a package name and converts it to a canonical name. This is largely only an issue on Portage where package
names are fully qualified with a category name. If this is called on a distro that does not use portage, this will just
return the original input.

On a portage based system it will proceed as follows. The input may or may not have a category identifier on it. If it
does not have a category (e.g. app-misc or dev-util), then find the category that contains the specified package.

> **_NOTE:_** If the results would be ambiguous, fails and indicates that a category is required.
END
pkg_canonicalize()
{
    $(opt_parse "name | Package name whose category you'd like to find.")

    edebug "Canonicalizing $(lval name)"

    if [[ $(pkg_manager) != "portage" ]]; then
        echo "${name}"
        return 0
    fi

    if [[ ${name} == */* ]] ; then
        echo "${name}"

    else

        local matches size
        matches=( $(qsearch --name-only --nocolor "^${name}$" 2>/dev/null) )
        size=$(array_size matches)
        edebug "$(lval name matches size)"

        if [[ "${size}" -eq 0 ]]; then
            return 1

        elif [[ ${size} -eq 1 ]] ; then
            echo "${matches[0]}"
            return 0

        else
            eerror "${name} is ambiguous: $(lval matches)"
            return 2
        fi
    fi
}

opt_usage pkg_gentoo_canonicalize <<'END'
This is a legacy wrapper around pkg_canonicalize using the old gentoo-specific name.
END
pkg_gentoo_canonicalize()
{
    pkg_canonicalize "${@}"
}

opt_usage pkg_installed <<'END'
Returns success (0) if all the specified packages are installed on this machine and failure (1) if not.
END
pkg_installed()
{
    $(opt_parse \
        "@names | Name of the packages to check if they are installed.")

    local name
    for name in "${names[@]}"; do
        case $(pkg_manager) in
            apk)
                apk -e info ${name} &>/dev/null
                ;;

            apt)
                dpkg -s ${name} &>/dev/null
                ;;

            brew)
                brew list ${name} &>/dev/null
                ;;

            pacman)
                pacman -Q ${name} &>/dev/null
                ;;

            portage)
                qlist --installed --exact ${name} &>/dev/null
                ;;

            yum)
                yum list installed ${name} &>/dev/null
                ;;

            *)
                die "Unsupported package manager $(pkg_manager)"
                ;;
        esac
    done
}

opt_usage pkg_install <<'END'
Install a list of packages whose names are specified. This function abstracts out the complication of installing packages
on multiple OS and Distros with different package managers. Generally this approach works pretty well. But one of the
big problems is taht the **names** of packages are not always consistent across different OS or distros.

To handle installing packages with different names in different OS/Distro combinations, the following pattern, as used
in `install/recommends` is suggested:

```shell
# Non-distro specific pacakges we need to install
pkg_install --sync                \
    bzip2                         \
    cpio                          \
    curl                          \
    debootstrap                   \
    dialog                        \
    gettext                       \
    git                           \
    gzip                          \
    jq                            \
    squashfs-tools                \
    util-linux                    \

# Distro specific packages
if os darwin; then
    pkg_install gnu-tar iproute2mac
elif os_distro alpine; then
    pkg_install cdrkit gnupg iproute2 iputils ncurses ncurses-terminfo net-tools pstree xz
elif os_distro centos debian fedora; then
    pkg_install genisoimage iproute iptables ncurses net-tools psmisc xz
elif os_distro gentoo; then
    pkg_install cdrtools lbzip2 net-tools pigz psmisc
elif os_distro ubuntu; then
    pkg_install cgroup-lite gnupg-agent iproute2 iptables iptuils-ping mkisofs net-tools psmisc xz-utils
fi
```
END
pkg_install()
{
    $(opt_parse \
        "+sync     | Perform package sync before installing packages. This is normally automatically done if the packages
                     being installed are not known by the package manager. But this allows you to explicitly sync if
                     required."                                                                                        \
        "@names    | Names of packages (with optional distro specifics) to install."                                   \
    )

    # If no package names requested just return
    if array_empty names; then
        return 0
    fi

    einfo "Installing packages $(lval names sync)"

    # Automatically do a sync if any of the packages we're trying to install are not known to us.
    if [[ ${sync} -eq 1 ]] || ! pkg_known "${names[@]}" ; then
        pkg_sync
    fi

    case $(pkg_manager) in

        apk)
            apk add "${names[@]}"
            ;;

        apt)
            DEBIAN_FRONTEND=noninteractive apt install -y "${names[@]}"
            ;;

        brew)

            # Brew is lame. If you try to install something that's already installed and needs an upgrade, it returns
            # an error. So we have to first check each package to see if they are installed and skip them if so.
            local name
            for name in "${names[@]}"; do
                if ! brew ls --versions "${name}"; then
                    brew install "${name}"
                fi
            done
            ;;

        pacman)
            pacman -S --noconfirm --needed "${names[@]}"
            ;;

        portage)
            emerge --ask=n --quiet-build=y --noreplace "${names[@]}"
            ;;

        yum)
            yum install -y "${names[@]}"
            ;;

        *)
            die "Unsupported $(lval pkg_manager)"
            ;;
    esac
}

opt_usage pkg_uninstall <<'END'
Use local package manager to remove any number of specified packages without prompting to ask any questions.
END
pkg_uninstall()
{
    $(opt_parse "@names | Names of package to install.")

    einfo "Unistalling packages $(lval names)"

    case $(pkg_manager) in
        apk)
            apk del "${@}"
            ;;

        apt)
            DEBIAN_FRONTEND=noninteractive apt remove --purge -y "${@}"
            ;;

        brew)
            brew uninstall "${@}"
            ;;

        pacman)
            pacman -R --noconfirm "${@}"
            ;;

        portage)
            emerge --ask=n --unmerge "${@}"
            ;;

        yum)
            yum remove -y "${@}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_sync <<'END'
Sync the local package manager database with whatever remote repositories are known so that all packages known to those
repositories are also known locally.
END
pkg_sync()
{
    case $(pkg_manager) in
        apk)
            apk update
            ;;

        apt)
            apt update
            ;;

        brew)
            brew update
            ;;

        pacman)
            pacman -Sy
            ;;

        portage)
            emerge --sync
            ;;

        yum)
            yum makecache
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_clean <<'END'
Clean out the local package manager database cache and do anything else to the package manager to try to clean up any
bad states it might be in.
END
pkg_clean()
{
    case $(pkg_manager) in
        apk)
            apk cache --purge
            ;;

        apt)
            find /var/lib/apt/lists -type f -a ! -name lock -a ! -name partial -delete
            ;;

        brew)
            brew cleanup
            ;;

        pacman)
            pacman -Sc --noconfirm
            ;;

        portage)
            # Gentoo's sync is more thorough than the package syncing of most other package managers
            # and so cleaning is typically unnecessary
            ;;

        yum)
            yum clean expire-cache
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac

    pkg_sync
}

opt_usage pkg_upgrade <<'END'
Replace the existing version of the specified package with the newest available package by that name.
END
pkg_upgrade()
{
    $(opt_parse \
        "@names | Names of the packages that should be upgraded to the newest possible versions.")

    pkg_installed ${names[@]}

    einfo "Upgrading packages $(lval names)"

    case $(pkg_manager) in
        apk)
            apk upgrade "${names[@]}"
            ;;

        apt)
            DEBIAN_FRONTEND=noninteractive apt install -y "${names[@]}"
            ;;

        brew)
            brew upgrade "${names[@]}"
            ;;

        pacman)
            pacman -S --noconfirm "${names[@]}"
            ;;

        portage)
            emerge --update "${names[@]}"
            ;;

        yum)
            yum update -y "${names[@]}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

# EBASH_PKG_MANAGER is used to cache results from pkg_manager to avoid doing repeated lookups when it will never
# change from one call to the next. It also allows customization inside the user's environment to use an explicit
# package manager (e.g. portage on a non-gentoo OS).
: ${EBASH_PKG_MANAGER:=}

opt_usage pkg_manager <<'END'
Determine the package manager to use for the system we are running on. Specifically:
  - alpine -> apk
  - arch   -> pacman
  - centos -> yum
  - darwin -> brew
  - debian -> apt
  - ember  -> portage
  - fedora -> yum
  - gentoo -> portage
  - mint   -> apt
  - ubuntu -> apt

> **_NOTE:_** This honors EBASH_PKG_MANAGER if it has been set to allow the caller complete control over what package
manager to use on their system without auto detection. This might be useful if you wanted to use portage on a non-gentoo
OS for example or on a gentoo derivative that ebash doesn't know about.
END
pkg_manager()
{
    # Cache results in EBASH_PKG_MANAGER
    if [[ -n "${EBASH_PKG_MANAGER}" ]]; then
        echo "${EBASH_PKG_MANAGER}"
        return 0
    fi

    if os darwin; then
        EBASH_PKG_MANAGER="brew"
    elif os_distro alpine; then
        EBASH_PKG_MANAGER="apk"
    elif os_distro debian mint ubuntu; then
        EBASH_PKG_MANAGER="apt"
    elif os_distro arch; then
        EBASH_PKG_MANAGER="pacman"
    elif os_distro gentoo ember; then
        EBASH_PKG_MANAGER="portage"
    elif os_distro centos fedora; then
        EBASH_PKG_MANAGER="yum"
    else
        die "Unknown pkg manager for $(os_pretty_name)"
    fi

    echo "${EBASH_PKG_MANAGER}"
}
