#!/bin/bash

# Copyright 2015, SolidFire, Inc. All rights reserved.

#-------------------------------------------------------------------------------
# The squashfs module is the bashutils interface around squashfs images. It
# provides common functionality for using squashfs images seamlessly within our
# existing install and test code bases. Basically adding new functions to better
# encapsulate our use of squashfs images and provide missing functionality not
# provided by upstream squashfs-tools package.
#-------------------------------------------------------------------------------

# Create a squashfs image from a given directory. This is simply a passthrough
# operation into native mksquashfs from squashfs-tools. Please see that tool's
# documentation for usage and flags.
squashfs_create()
{
    mksquashfs "${@}"
}

# Extract a previously constructed squashfs image. This is simply a passthrough
# operation into native unsquashfs from squashfs-tools. Please see that tool's
# documentation for usage and flags.
squashfs_extract()
{
    $(declare_args src dest)

    unsquashfs -dest "${dest}" "${src}"
}

# Simple function to list the contents of a squashfs image.
squashfs_list()
{
    $(declare_args src)

    (
        local mnt="$(mktemp -d /tmp/squashfs-mnt-XXXX)"
        mount --types squashfs --read-only "${src}" "${mnt}"
        trap_add "eunmount_rm "${mnt}" |& edebug"

        find "${mnt}" | sort | sed "s|${mnt}||"
    )
}

# squashfs_mount will perform the following actions:
# (1) Mount squashfs image read-only
# (2) Mount read-write later on top of the read-only layer using overlayfs
# (3) Mount pseudo-filesystem directories on top (e.g. /dev, /sys, /proc).
squashfs_mount()
{
    $(declare_args src dest)

    # Create temporary directory to hold read-only and read-write layers
    local dest_ro="$(mktemp -d /tmp/squashfs-ro-XXXX)"
    local dest_rw="$(mktemp -d /tmp/squashfs-rw-XXXX)"
    local dest_work="$(mktemp -d /tmp/squashfs-work-XXXX)"
    trap_add "eunmount_rm ${dest_ro} ${dest_rw} ${dest_work} |& edebug"

    # Mount squashfs read-only at dest_ro
    mount --types squashfs --read-only "${src}" "${dest_ro}"
    
    # Mount layered mounts at requested destination, creating if it doesn't exist.
    mkdir -p "${dest}"
    mount --types overlay overlay -o lowerdir="${dest_ro}",upperdir="${dest_rw}",workdir="${dest_work}" "${dest}"
}

# squashfs_unmount will unmount a squashfs image that was previously mounted
# by calling squashfs_mount. It takes multiple arguments where each is the final
# mount point that the squashfs image was mounted at.
squashfs_unmount()
{
    # /proc/mounts will show the mount point and its lowerdir,upperdir and workdir so that we can unmount it properly:
    # "overlay /home/marshall/sandboxes/bashutils/output/squashfs.etest/ETEST_squashfs_mount/dst overlay rw,relatime,lowerdir=/tmp/squashfs-ro-basv,upperdir=/tmp/squashfs-rw-jWg9,workdir=/tmp/squashfs-work-cLd9 0 0"

    local mnt
    for mnt in "$@"; do
    
        # Parse out the lower, upper and work directories to be unmounted
        local output="$(grep "overlay $(readlink -m ${mnt})" /proc/mounts)"
        local lower="$(echo "${output}" | grep -Po "lowerdir=\K[^, ]*")"
        local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
        local work="$(echo "${output}"  | grep -Po "workdir=\K[^, ]*")"
        eunmount "${lower}" "${upper}" "${work}" "${mnt}"

    done
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
        pushd ${mnt}
        mkisofs -quiet -r "${iso_flags}" -cache-inodes -J -l -o "${dest_abs}" .
        popd
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
        pushd "${mnt}"
        etar --create --file "${dest_abs}" .
        popd
    )
}

squashfs_from_tar()
{
    $(declare_args src dest)

    # Unpack the tar file into a temporary directory. Then squash that directory.
    # Put body in a subshell to ensure traps perform clean-up.
    (
        local tmp="$(mktemp -d /tmp/squashfs-tar-XXXX)"
        trap_add "rm -rf ${tmp} |& edebug"
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

        diff --unified "${mnts[@]}"
    )
}

squashfs_save_rw_layer()
{
    $(declare_args mnt dest)

    # Currently only allows exporting to squashfs.
    if [[ ! ${dest} =~ .squashfs$ ]]; then
        eerror "Can only save RW layer to squashfs"
        return 1
    fi

    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "overlay $(readlink -m ${mnt})" /proc/mounts)"
    edebug "$(lval mnt dest output)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
    squashfs_create "${upper}" "${dest}"
}
