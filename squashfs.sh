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

    unsquashfs -dest "${dest}" "${src}"
}

# Simple function to list the contents of a squashfs image. squashfs-tools
# doesn't provide a way to do this natively, so this function has to mount
# the requested image in order to view its contents.
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

# squashfs_mount mounts one or more squashfs images read-write. The two really
# important things about this function that set it apart from doing a normal
# mount of a squashfs image:
#
# (1) Takes multiple squashfs images and layers them on top of one another
#     so the contents of all of them are seen in the final mounted directory.
#     This is a read-through filesystem such that higher layers mask out the 
#     contents of lower layers in the event of conflicts.
#
# (2) The final mounted directory is read-write rather than read-only. This
#     is super important since normally squashfs images can only be mounted
#     read-only. This is achieved by mounting the squashfs image into a temp
#     directory, then using overlayfs to mount a read-write layer on top of
#     the read-only layer. Any CHANGES are NOT PERSISTENT! You can use
#     the squashfs_save_changes function to save the changes if necessary.
#
# NOTE: The last argument in the list of positional parameters is the final
#       mount point to mount all the images at.
squashfs_mount()
{
    if [[ $# -lt 2 ]]; then
        eerror "squashfs_mount requires 2 or more arguments"
        return 1
    fi

    # Parse positional arguments into a bashutils array. Then grab final mount
    # point from args and create lowerdir parameter by joining all images with colon
    # (see https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt)
    local args=( "$@" )
    local dest=${args[${#args[@]}-1]}
    unset args[${#args[@]}-1]
   
    # Iterate through all the images and mount each one into a temporary directory
    local arg
    local layers=()
    for arg in "${args[@]}"; do
        local tmp=$(mktemp -d /tmp/squashfs-ro-XXXX)
        mount --types squashfs --read-only "${arg}" "${tmp}"
        trap_add "eunmount_rm ${tmp} |& edebug"
        layers+=( "${tmp}" )
    done

    # Create temporary directory to hold read-only and read-write layers
    local lower=$(array_join layers ":")
    local upper="$(mktemp -d /tmp/squashfs-rw-XXXX)"
    local work="$(mktemp -d /tmp/squashfs-work-XXXX)"
    trap_add "eunmount_rm ${upper} ${work} |& edebug"

    # Mount layered mounts at requested destination, creating if it doesn't exist.
    mkdir -p "${dest}"
    mount --types overlay overlay -o lowerdir="${lower}",upperdir="${upper}",workdir="${work}" "${dest}"
}

# squashfs_unmount will unmount a squashfs image that was previously mounted
# via squashfs_mount. It takes multiple arguments where each is the final
# mount point that the squashfs image was mounted at. In the event there are
# multiple squashfs images layered into the final mount image, they will all 
# be unmounted as well.
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
        
        # Split 'lower' on ':' so we can unmount each of the lower layers 
        local parts
        array_init parts "${lower}" ":"
        eunmount ${parts[@]} "${upper}" "${work}" "${mnt}"
    done
}

# Mount the squashfs image read-only and then call mkisofs on that directory
# to create the requested ISO image.
squashfs_to_iso()
{
    $(declare_opts \
        ":volume v  | Volume name to be written into the master block." \
        "bootable b | Make this a bootable ISO.")
 
    $(declare_args src dest)

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
    local output="$(grep "overlay $(readlink -m ${mnt})" /proc/mounts)"
    edebug "$(lval mnt dest output)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
    squashfs_create "${upper}" "${dest}"
}
