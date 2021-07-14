# Module pkg


## func pkg_canonicalize


Takes as input a package name and converts it to a canonical name. This is largely only an issue on Portage where package
names are fully qualified with a category name. If this is called on a distro that does not use portage, this will just
return the original input.

On a portage based system it will proceed as follows. The input may or may not have a category identifier on it. If it
does not have a category (e.g. app-misc or dev-util), then find the category that contains the specified package.

> **_NOTE:_** If the results would be ambiguous, fails and indicates that a category is required.

```Groff
ARGUMENTS

   name
         Package name whose category you'd like to find.

```

## func pkg_clean

Clean out the local package manager database cache and do anything else to the package manager to try to clean up any
bad states it might be in.

## func pkg_gentoo_canonicalize

This is a legacy wrapper around pkg_canonicalize using the old gentoo-specific name.

## func pkg_install


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

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --sync
         Perform package sync before installing packages. This is normally automatically done
         if the packages being installed are not known by the package manager. But this allows
         you to explicitly sync if required.


ARGUMENTS

   names
         Names of packages (with optional distro specifics) to install.
```

## func pkg_installed


Returns success (0) if all the specified packages are installed on this machine and failure (1) if not.

```Groff
ARGUMENTS

   names
         Name of the packages to check if they are installed.
```

## func pkg_known


Determine if the package manager locally knows of all of the packages specified. This won't update the pacakge database
to do its check. Note that this does *not* mean the package is installed. Just that the package manager knows about the
package and could install it.

See pkg_installed to check if a package is actually installed.

```Groff
ARGUMENTS

   names
         Names of package to check.
```

## func pkg_manager

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

## func pkg_sync

Sync the local package manager database with whatever remote repositories are known so that all packages known to those
repositories are also known locally.

## func pkg_uninstall


Use local package manager to remove any number of specified packages without prompting to ask any questions.

```Groff
ARGUMENTS

   names
         Names of package to install.
```

## func pkg_upgrade


Replace the existing version of the specified package with the newest available package by that name.

```Groff
ARGUMENTS

   names
         Names of the packages that should be upgraded to the newest possible versions.
```
