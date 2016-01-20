#!/bin/bash

# Copyright 2016, SolidFire, Inc. All rights reserved.

#-------------------------------------------------------------------------------
# The squashfs module is the bashutils interface around squashfs images. It
# provides common functionality for using squashfs images seamlessly within our
# existing install and test code bases. Basically adding new functions to better
# encapsulate our use of squashfs images and provide missing functionality not
# provided by upstream squashfs-tools package.
#
# squashfs images are rapidly becoming a very common medium used throughout our
# build, install, test and upgrade code due to their high compressibility, small
# resultant size, massive parallelization on both create and unpack and that 
# they can be directly mounted and booted into. Given how much we use them 
# it made sense to build a common set of utilities around their use.
#-------------------------------------------------------------------------------

# Create a squashfs image from a given directory. This is simply a passthrough
# operation into native mksquashfs from squashfs-tools. Please see that tool's
# documentation for usage and flags.
# 
# NOTE: mksquashfs requires any option flags be at the END of the command line.
squashfs_create()
{
    mksquashfs "${@}"
}

# Extract a previously constructed squashfs image. This is not a passthrough
# operation into unsquashfs b/c that tool requires any options must be BEFORE
# the mount points to be unmounted which is really inconvenient for passthrough.
squashfs_extract()
{
    $(declare_args src dest)
    unsquashfs -force -dest "${dest}" "${src}"
}

# Simple function to list the contents of a squashfs image.
squashfs_list()
{
    $(declare_args src)
    unsquashfs -ls "${src}" | grep "^squashfs-root" | sed -e 's|squashfs-root||' -e '/^\s*$/d'
}

# Mount the squashfs image read-only and then call mkisofs on that directory
# to create the requested ISO image.
squashfs_to_iso()
{
    $(declare_args src dest)

    # Optional flags to pass through into mkisofs
    local volume=$(opt_get v "")
    local bootable=$(opt_get b 0)

    # Put body in a subshell to ensure traps perform clean-up.
    (
        local mnt="$(mktemp -d /tmp/squashfs-mnt-XXXX)"
        mount --types squashfs --read-only "${src}" "${mnt}"
        trap_add "eunmount_rm ${mnt} |& edebug"

        # Generate ISO flags
        local iso_flags="-V "${volume}""
        if opt_true bootable; then
            iso_flags+=" -b isolinux/isolinux.bin 
                         -c isolinux/boot.cat
                         -no-emul-boot
                         -boot-load-size 4
                         -boot-info-table"
        fi

        local dest_abs="$(readlink -m "${dest}")"
        cd ${mnt}
        mkisofs -quiet -r "${iso_flags}" -cache-inodes -J -l -o "${dest_abs}" .
    )        
}

# Mount the ISO and then call squashfs_create against that directory.
squashfs_from_iso()
{
    $(declare_args src dest)

    # Put body in a subshell to ensure traps perform clean-up
    (
        local mnt="$(mktemp -d /tmp/squashfs-mnt-XXXX)"
        mount --types iso9660 --read-only "${src}" "${mnt}"
        trap_add "eunmount_rm ${mnt} |& edebug"
        squashfs_create "${mnt}" "${dest}"
    )
}

squashfs_to_tar()
{
    $(declare_args src dest)

    # Mount the squashfs image into a temporary directory then tar that up to the requested location.
    # Put body in a subhsell to ensure traps perform clean-up.
    (
        local mnt="$(mktemp -d /tmp/squashfs-mnt-XXXX)"
        mount --types squashfs --read-only "${src}" "${mnt}"
        trap_add "eunmount_rm ${mnt} |& edebug"

        # TAR up the given directory and write it out to the requested destination. This will automatically
        # use correct compression based on the file extension.
        local dest_abs="$(readlink -m "${dest}")"
        cd "${mnt}"
        etar --create --file "${dest_abs}" .
    )
}

squashfs_from_tar()
{
    $(declare_args src dest)

    # Unpack the tar file into a temporary directory. Then squash that directory.
    # Put body in a subshell to ensure traps perform clean-up.
    (
        local tmp="$(mktemp -d /tmp/squashfs-tar-XXXX)"
        trap_add "rm -rf ${tmp}"
        etar --extract --file "${src}" --directory "${tmp}"
        squashfs_create "${tmp}" "${dest}"
    )
}

# Diff two or more squashfs images
squashfs_diff()
{
    (
        local mnts=()
        local src
        for src in "${@}"; do
            local mnt="$(mktemp -d /tmp/squashfs-mnt-XXXX)"
            mount --types squashfs --read-only "${src}" "${mnt}"
            trap_add "eunmount_rm "${mnt}" |& edebug"
            mnts+=( "${mnt}" )
        done

        diff --recursive --unified "${mnts[@]}"
    )
}

squashfs_save_changes()
{
    $(declare_args mnt dest)

    # Currently only allows exporting to squashfs.
    if [[ ! ${dest} =~ .squashfs$ ]]; then
        eerror "Can only save RW layer to squashfs"
        return 1
    fi

    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    edebug "$(lval mnt dest output)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
    squashfs_create "${upper}" "${dest}"
}
