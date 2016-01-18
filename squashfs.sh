#!/bin/bash

[[ ${__BU_OS} == Linux ]] || return 0

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

# Older kernel versions used the filesystem type 'overlayfs' whereas newer ones
# use just 'overlay' so dynamically detected the correct type to use here.
__BU_OVERLAYFS=$(awk '/overlay/ {print $2}' /proc/filesystems)

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
#
# NOTE: There are two different actual implementations of this function to 
#       accomodate different underlying implementations within the kernel.
#       Kernels < 3.19 had a much more limited version which did not provide
#       Multi-Layer OverlayFS. As such, we check what version of the kernel
#       we're running and only define the right implementation for the version
#       of the kernel that we're running. This saves us from having to perform
#       this check every time we call this function as it's only done once at
#       source time.
__BU_KERNEL_MAJOR=$(uname -r | awk -F . '{print $1}')
__BU_KERNEL_MINOR=$(uname -r | awk -F . '{print $2}')

# NEWER KERNEL VERSIONS (>= 3.19)
if [[ ${__BU_KERNEL_MAJOR} -ge 4 || ( ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 19 ) ]]; then
squashfs_mount()
{
    if [[ $# -lt 2 ]]; then
        eerror "squashfs_mount requires 2 or more arguments"
        return 1
    fi

    edebug "Using Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"
    
    # Parse positional arguments into a bashutils array. Then grab final mount
    # point from args and create lowerdir parameter by joining all images with colon
    # (see https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt)
    local args=( "$@" )
    local dest=${args[${#args[@]}-1]}
    unset args[${#args[@]}-1]
    
    # Mount layered mounts at requested destination, creating if it doesn't exist.
    mkdir -p "${dest}"
     
    # Iterate through all the images and mount each one into a temporary directory
    local arg
    local layers=()
    for arg in "${args[@]}"; do
        local tmp=$(mktemp -d /tmp/squashfs-lower-XXXX)
        mount --types squashfs --read-only "${arg}" "${tmp}"
        trap_add "eunmount_rm ${tmp} |& edebug"
        layers+=( "${tmp}" )
    done

    # Create temporary directory to hold read-only and read-write layers
    local lower=$(array_join layers ":")
    local upper="$(mktemp -d /tmp/squashfs-upper-XXXX)"
    local work="$(mktemp -d /tmp/squashfs-work-XXXX)"
    trap_add "eunmount_rm ${upper} ${work} |& edebug"

    # Mount overlayfs
    mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${upper}",workdir="${work}" "${dest}"
}

# OLDER KERNEL VERSIONS (<3.19)
else

# Ugh. Older OverlayFS is really annoying because you can only stack 2 overlayfs
# mounts. To get around this, we'll mount the bottom most layer as the read-only 
# base image. Then we'll unpack all other images into a middle layer. Then mount
# an empty directory as the top-most directory.
squashfs_mount()
{
    if [[ $# -lt 2 ]]; then
        eerror "squashfs_mount requires 2 or more arguments"
        return 1
    fi
    
    edebug "Using legacy non-Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"

    # Parse positional arguments into a bashutils array. Then grab final mount
    # point from args and create lowerdir parameter by joining all images with colon
    # (see https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt)
    local args=( "$@" )
    local dest=${args[${#args[@]}-1]}
    unset args[${#args[@]}-1]
    
    # Mount layered mounts at requested destination, creating if it doesn't exist.
    mkdir -p "${dest}"

    # Grab bottom most layer
    local lower=$(mktemp -d /tmp/squashfs-mnt-XXXX)
    mount --types squashfs --read-only "${args[0]}" "${lower}"
    unset args[0]

    # Extract all remaining layers into empty "middle" directory
    if array_not_empty args; then
   
        local middle=$(mktemp -d /tmp/squashfs-middle-XXXX)
        trap_add "eunmount_rm ${middle} |& edebug"

        for arg in "${args[@]}"; do
            edebug "Extracting $(lval arg) to $(lval middle)"
            squashfs_extract "${arg}" "${middle}"
        done
    
        mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${middle}" "${middle}"
        lower=${middle}
    fi

    # Mount this unpacked directory into overlayfs layer with an empty read-write 
    # layer on top. This way if caller saves the changes they get only the changes
    # they made in the top-most layer.
    local upper=$(mktemp -d /tmp/squashfs-upper-XXXX)
    trap_add "eunmount_rm ${upper} |& edebug"
    mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${upper}" "${dest}"
}

fi # END squashfs_mount

# squashfs_unmount will unmount a squashfs image that was previously mounted
# via squashfs_mount. It takes multiple arguments where each is the final
# mount point that the squashfs image was mounted at. In the event there are
# multiple squashfs images layered into the final mount image, they will all 
# be unmounted as well.
squashfs_unmount()
{
    if [[ -z "$@" ]]; then
        return 0
    fi

    # /proc/mounts will show the mount point and its lowerdir,upperdir and workdir so that we can unmount it properly:
    # "overlay /home/marshall/sandboxes/bashutils/output/squashfs.etest/ETEST_squashfs_mount/dst overlay rw,relatime,lowerdir=/tmp/squashfs-ro-basv,upperdir=/tmp/squashfs-rw-jWg9,workdir=/tmp/squashfs-work-cLd9 0 0"

    local mnt
    for mnt in "$@"; do
  
        # Parse out the lower, upper and work directories to be unmounted
        local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
        local lower="$(echo "${output}" | grep -Po "lowerdir=\K[^, ]*")"
        local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
        local work="$(echo "${output}"  | grep -Po "workdir=\K[^, ]*")"
        
        # Split 'lower' on ':' so we can unmount each of the lower layers 
        local parts
        array_init parts "${lower}" ":"
        eunmount ${parts[@]:-} "${upper}" "${work}" "${mnt}"

        # Just in case the squashfs images were nested we also have to unmount
        # lower layers.... should this be an option (e.g. -r / --recursive?)
        squashfs_unmount ${parts[0]:-}
    done
}

# squashfs_tree is used to display a graphical representation for a squashfs
# mount. The graphical format is meant to show details about each layer in the
# overlayfs mount hierarchy to make it clear what files reside in what layers
# along with some basic metadata about each file (as provided by find -ls).
squashfs_tree()
{
    if [[ -z "$@" ]]; then
        return 0
    fi

    # /proc/mounts will show the mount point and its lowerdir,upperdir and workdir so that we can unmount it properly:
    # "overlay /home/marshall/sandboxes/bashutils/output/squashfs.etest/ETEST_squashfs_mount/dst overlay rw,relatime,lowerdir=/tmp/squashfs-ro-basv,upperdir=/tmp/squashfs-rw-jWg9,workdir=/tmp/squashfs-work-cLd9 0 0"

    local mnt
    for mnt in "$@"; do
  
        # Parse out the lower, upper and work directories to be unmounted
        local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
        local lower="$(echo "${output}" | grep -Po "lowerdir=\K[^, ]*")"
        local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
        
        # Split 'lower' on ':' so we can unmount each of the lower layers then
        # append upper to the list so we see that as well.
        local parts
        array_init parts "${lower}" ":"
        parts+=( "${upper}" )
        local idx
        for idx in $(array_indexes parts); do
            eval "local layer=\${parts[$idx]}"

            # Figure out source of the mountpoint
            local src=$(grep "${layer}" /proc/mounts | head -1)

            if [[ ${src} =~ "/dev/loop" ]]; then
                src=$(losetup $(echo "${src}" | awk '{print $1}') | awk '{print $3}' | sed -e 's|^(||' -e 's|)$||')
            elif [[ ${src} =~ "overlay" ]]; then
                src=$(echo "${src}" | awk '{print $2}')

            fi

            # Pretty print the contents
            local find_output=$(find ${layer} -ls | awk '{ $1=""; print}' | sed -e "s|${layer}|/|" -e 's|//|/|' | column -t | sort -k10)
            echo "$(ecolor green)+--layer${idx} [${src}:${layer}]$(ecolor off)"
            echo "${find_output}" | sed 's#^#'$(ecolor green)\|$(ecolor off)\ \ '#g'
        done
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
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    edebug "$(lval mnt dest output)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
    squashfs_create "${upper}" "${dest}"
}
