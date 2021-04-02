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

    case $(pkg_manager) in
        apk)
            [[ -n "$(apk list ${names[@]} 2>/dev/null)" ]]
            ;;

        apt)
            apt-cache show ${names[@]} &>/dev/null
            ;;

        brew)
            brew search ${names[@]} &>/dev/null
            ;;

        pacman)
            pacman -Ss ${names[@]} &>/dev/null
            ;;

        portage)

            local name portdir
            for name in "${names[@]}"; do
                name=$(pkg_gentoo_canonicalize ${name})
                portdir=$(portageq get_repo_path / gentoo)
                [[ -d "${portdir}/${name}" ]]
            done
            ;;

        yum)
            yum list ${names[@]} &>/dev/null
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_gentoo_canonicalize <<'END'
Takes as input a package name that may or may not have a category identifier on it. If it does not have a category
(e.g. app-misc or dev-util), then find the category that contains the specified package.

> **_NOTE:_** If the results would be ambiguous, fails and indicates that a category is required.
END
pkg_gentoo_canonicalize()
{
    $(opt_parse "name | Package name whose category you'd like to find.")

    if [[ ${name} == */* ]] ; then
        echo "${name}"

    else

        local portdir
        portdir=$(portageq get_repo_path / gentoo)
        pushd "${portdir}"

        local found=() size=0
        found=( */${name} )
        size=$(array_size found)
        popd

        if [[ ${size} -eq 0 ]] ; then
            return 1

        elif [[ ${size} -eq 1 ]] ; then
            echo "${found[0]}"

        else
            eerror "${name} is ambiguous. You must specify a category."
            return 2
        fi
    fi
}

opt_usage pkg_installed <<'END'
Returns success (0) if all the specified packages are installed on this machine and failure (1) if not.
END
pkg_installed()
{
    $(opt_parse \
        "@names | Name of the packages to check if they are installed.")

    case $(pkg_manager) in

        apk)
            apk -e info ${names[@]} &>/dev/null
            ;;

        apt)
            dpkg -s ${names[@]} &>/dev/null
            ;;

        brew)
            brew list ${names[@]} &>/dev/null
            ;;

        pacman)
            pacman -Q ${names[@]} &>/dev/null
            ;;

        portage)
            qlist --installed --exact ${names[@]} &>/dev/null
            ;;

        yum)
            yum list installed ${names[@]} &>/dev/null
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

opt_usage pkg_install <<'END'
Install a list of packages whose names are specified. This function supports several different package managers correctly,
but the actual package names are very frequently different on different OS or distros.

To that end, there is a `--binaries` flag which will interpret the list of names as binaries to install rather than
packages. When run in this mode, we use the appropriate package manager for the system in question to determine the
names of the packages to install in order to get the desired binaries installed.

Because some distros provide various binaries which might suit your needs, the syntax for the binaries to install is
very flexible via the `alternative` operator as in `mkisofs|genisoimage|xorrisofs`. When given a binary name which has
the alternative operator in it, ebash will split on the `|` and try them one at a time. The first one which it can
successfully map to an installable package will be used.
END
pkg_install()
{
    $(opt_parse \
        "+sync     | Perform pkg_sync before trying to lookup and install the packages." \
        "+binaries | Interpret the names as binaries to install rather than actual package names. In this mode the
                     package manager is queried via pkg_binary to map the binaries to package names." \
        "@names    | Names of packages or binaries (with optional alternatives) to install." \
    )

    # If no package names requested just return
    if array_empty names; then
        return 0
    fi

    einfo "Installing packages $(lval binaries names sync)"

    if [[ ${sync} -eq 1 ]]; then
        pkg_sync
    fi

    if [[ ${binaries} -eq 1 ]]; then
        edebug "Converting binaries to packages $(lval names)"
        names=( $(pkg_binary ${names[@]}) )
        edebug "Converted binaries to packages $(lval names)"
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
            emerge --ask=n "${names[@]}"
            ;;

        yum)
            yum install -y "${names[@]}"
            ;;

        *)
            die "Unsupported $(lval pkg_manager)"
            ;;
    esac
}

opt_usage pkg_binary <<'END'
Take a list of binaries with optional `alternative` operator `|` and figure out what package would need to be installed
to get the specified binary. Since this sort of lookup is not possible with most package managers, we delegate this work
out to the fantastic service provided by [command-not-found](https://command-not-found.com). This returns the command
to be executed to install a command on various operating systems. This includes all our supported OS and distros with
the exception of Gentoo.

So for Gentoo, we delegate this task to the similar [portage-file-list](https://www.portagefilelist.de/site/query) which
is wrapped by the helpful tool `e-file` as part of the `pfl` package. In the gentoo case, we often get duplicate results
back because different packages can install the same binary and USE flags dicate which one would get used. In this case
we simply iterate over our PATH and pick the first installable package which would install a binary earliest in our
PATH.
END
pkg_binary()
{
    $(opt_parse "@names | Names of binaries to map to the corresponding OS Package that needs to be installed.")

    local packages=()

    # Check each package
    local name
    for name in "${names[@]}"; do
        edebug "Converting $(lval name) to package"

        # If the name contains a list of alternatives, split on "|" and try each on in turn, stopping on the first one
        # that is valid for this OS.
        if [[ "${name}" =~ "|" ]]; then
            local part parts=()
            array_init parts "${name}" "|"
            for part in "${parts[@]}"; do
                local match
                if match=$(__pkg_binary "${part}"); then
                    packages+=( "${match}" )
                    break
                fi
            done
        else
            packages+=( $(__pkg_binary "${name}" || die "Failed to find a matching package for binary=${name}") )
        fi
    done

    array_sort --unique packages
    edebug "Package $(lval names) -> $(lval packages)"
    echo "${packages[@]}"
}

opt_usage __pkg_binary <<'END'
__pkg_binary is an internal helper method called by pkg_binary to make the code more reusable inside a loop. This is
what does the heavy lifting of calling out to command-not-found.com or using e-file to map a binary name to a package.
The binary name cannot contain any paths in it. For example, you can pass in 'bash' but not '/bin/bash'.
END
__pkg_binary()
{
    $(opt_parse \
        "name        | The name of the package we are looking up."   \
    )

    edebug "Mapping binary $(lval name) to package"
    assert_not_match "${name}" "/" "${name} cannot contain path separator '/'"
    assert_not_match "${name}" "|" "${name} cannot contain alternation separator '|'"

    case $(pkg_manager) in

        apk)
            curl -s "https://command-not-found.com/${name}" | grep -Po "apk add \K[^\<]*" | sort -u
            ;;

        apt)
            curl -s "https://command-not-found.com/${name}" | grep -Po "apt-get install \K[^\<]*" | sort -u
            ;;

        brew)
            curl -s "https://command-not-found.com/${name}" | grep -Po "brew install \K[^\<]*" | sort -u
            ;;

        pacman)
            curl -s "https://command-not-found.com/${name}" | grep -Po "pacman -S \K[^\<]*" | sort -u
            ;;

        portage)

            # Split PATH into directories and search each one looking for a package which provides that binary. This
            # way we are ensured to stop on the first one that would normally be installed and used on this system. It
            # also avoids having to really gross parsing of e-file's output if we did a lookup with just '${name}' as
            # it would find sub-string matches which we would have to filter out.
            local path parts matches=()
            array_init parts "${PATH}" ":"
            for path in "${parts[@]}"; do
                if e-file -c never "${path}/${name}" | grep -Po '^(\[I\]| \* ) \K.*'; then
                    return 0
                fi
            done

            edebug "Failed to map $(lval name) to a package"
            return 1

            ;;

        yum)
            curl -s "https://command-not-found.com/${name}" | grep -Po "yum install \K[^\<]*" | sort -u
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
