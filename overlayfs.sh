#!/bin/bash

# Copyright 2016, SolidFire, Inc. All rights reserved.

#-------------------------------------------------------------------------------
# The overlayfs module is the bashutils interface around OverlayFS mounts. This
# is a really useful filesystem that allows layering mounts into a single
# unified mount point with read-through semantics. This is the first official
# kernel filesystem providing this functionality which replaces prior similar
# filesystems such as unionfs, aufs, etc.
# 
# The implementation of the underlying kernel driver changed somewhat with
# different kernel versions. The first version of the kernel which officially
# supported overlayfs was 3.18. This original API requires specifying the
# workdir option for the scratch work performed by overlayfs. Overlayfs was
# available in older kernel versions but was not official and did not have this
# additional "workdir" option.
#-------------------------------------------------------------------------------

# Older kernel versions used the filesystem type 'overlayfs' whereas newer ones
# use just 'overlay' so dynamically detected the correct type to use here.
__BU_OVERLAYFS=$(awk '/overlay/ {print $2}' /proc/filesystems)
__BU_KERNEL_MAJOR=$(uname -r | awk -F . '{print $1}')
__BU_KERNEL_MINOR=$(uname -r | awk -F . '{print $2}')

# overlayfs_mount mounts multiple filesystems into a single unified writeable
# directory with read-through semantics. All the underlying filesystem layers
# are mounted read-only (if they are mountable) and the top-most layer is
# mounted read-write. Only the top-level layer is mounted read-write.
# 
# The most common uses cases for using overlayfs is to mount ISOs or squashfs
# images with a read-write layer on top of them. To make this implementation
# as generic as possible, it deals only with overlayfs mounting semantics.
# The specific mounting of ISO or squashfs images are handled by separate
# dedicated modules.
#
# This function takes multiple arguments where each argument is a layer
# to mount into the final unified overlayfs image. The final positional 
# parameter is the final mount point to mount everything at. This final 
# directory will be created if it doesn't exist.
#
# NOTE: The first version of the kernel which officially supported overlayfs
#       was 3.18. This original API requires specifying the workdir option
#       for the scratch work performed by overlayfs. Overlayfs was available
#       in older kernel versions but was not official and did not have this
#       additional "workdir" option.
# 
# NOTE: There are two different actual implementations of this function to 
#       accomodate different underlying implementations within the kernel.
#       Kernels < 3.19 had a much more limited version which did not provide
#       Multi-Layer OverlayFS. As such, we check what version of the kernel
#       we're running and only define the right implementation for the version
#       of the kernel that we're running. This saves us from having to perform
#       this check every time we call this function as it's only done once at
#       source time.
#
overlayfs_mount()
{
    if [[ $# -lt 2 ]]; then
        eerror "overlayfs_mount requires 2 or more arguments"
        return 1
    fi

    # Parse positional arguments into a bashutils array. Then grab final mount
    # point from args.
    local args=( "$@" )
    local dest=${args[${#args[@]}-1]}
    unset args[${#args[@]}-1]

    # Mount layered mounts at requested destination, creating if it doesn't exist.
    mkdir -p "${dest}"

    # NEWER KERNEL VERSIONS (>= 3.19)
    if [[ ${__BU_KERNEL_MAJOR} -ge 4 || ( ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 19 ) ]]; then

        edebug "Using Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"
        
        # Iterate through all the images and mount each one into a temporary directory
        local arg
        local layers=()
        for arg in "${args[@]}"; do
            local tmp=$(mktemp -d /tmp/overlayfs-lower-XXXX)
            mount --read-only "${arg}" "${tmp}"
            trap_add "eunmount_rm ${tmp} |& edebug"
            layers+=( "${tmp}" )
        done

        # Create temporary directory to hold read-only and read-write layers.
        # Create lowerdir parameter by joining all images with colon
        # (see https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt)
        local lower=$(array_join layers ":")
        local upper="$(mktemp -d /tmp/overlayfs-upper-XXXX)"
        local work="$(mktemp -d /tmp/overlayfs-work-XXXX)"
        trap_add "eunmount_rm ${upper} ${work} |& edebug"

        # Mount overlayfs
        mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${upper}",workdir="${work}" "${dest}"
 
    # OLDER KERNEL VERSIONS (<3.19)
    # NOTE: Older OverlayFS is really annoying because you can only stack 2 overlayfs
    # mounts. To get around this, we'll mount the bottom most layer as the read-only 
    # base image. Then we'll unpack all other images into a middle layer. Then mount
    # an empty directory as the top-most directory.
    #
    # NOTE: Versions >= 3.18 require the "workdir" option but older versions do not.
    else
       
        edebug "Using legacy non-Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"

        # Grab bottom most layer
        local lower=$(mktemp -d /tmp/overlayfs-mnt-XXXX)
        mount --read-only "${args[0]}" "${lower}"
        unset args[0]

        # Extract all remaining layers into empty "middle" directory
        if array_not_empty args; then
       
            local middle=$(mktemp -d /tmp/overlayfs-middle-XXXX)
            local work=$(mktemp -d /tmp/overlayfs-work-XXXX)
            trap_add "eunmount_rm ${middle} ${work} |& edebug"

            for arg in "${args[@]}"; do
                
                edebug "Extracting $(lval arg) to $(lval middle)"

                # Extract this layer into middle directory using
                # image specific mechanism.
                if [[ ${arg} =~ .squashfs ]]; then
                    squashfs_extract "${arg}" "${middle}"
                elif [[ ${arg} =~ .iso ]]; then
                    iso_extract "${arg}" "${middle}"
                fi

            done
       
            if [[ ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 18 ]]; then
                mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${middle}",workdir="${work}" "${middle}"
            else
                mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${middle}" "${middle}"
            fi
            
            lower=${middle}
        fi

        # Mount this unpacked directory into overlayfs layer with an empty read-write 
        # layer on top. This way if caller saves the changes they get only the changes
        # they made in the top-most layer.
        local upper=$(mktemp -d /tmp/squashfs-upper-XXXX)
        local work=$(mktemp -d /tmp/squashfs-work-XXXX)
        trap_add "eunmount_rm ${upper} ${work} |& edebug"

        if [[ ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 18 ]]; then
            mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${upper}",workdir="${work}" "${dest}"
        else
            mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${upper}" "${dest}"
        fi
    fi
}

# overlayfs_unmount will unmount an overlayfs directory previously mounted
# via overlayfs_mount. It takes multiple arguments where each is the final
# overlayfs mount point. In the event there are multiple overlayfs layered
# into the final mount image, they will all be unmounted as well.
overlayfs_unmount()
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

        # In case the overlayfs mounts are layered manually have to also unmount
        # the lower layers.
        overlayfs_unmount ${parts[0]:-}
    done
}

# overlayfs_tree is used to display a layered textual representation for an
# overlayfs mount. The format is meant to show details about each layer in the
# overlayfs mount hierarchy to make it clear what files reside in what layers
# along with some basic metadata about each file (as provided by find -ls).
overlayfs_tree()
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

            # ISOs and SquashFS images are mounted as loop devices.
            if [[ ${src} =~ "/dev/loop" ]]; then
                
                # The heinous bit of code below take the entire output from mount
                # command above (stored in 'src') and parses out the first column
                # to get something like "/dev/loop0" or "overlayfs". Then it uses
                # losetup to get the source of the loop device mount and gets the
                # third column from that output. This is the source of the loop
                # device mount and has parens around it. So we strip off those 
                # parens with tr -d.
                src=$(losetup $(echo "${src}" | awk '{print $1}') | awk '{print $3}' | tr -d '()')

            # Overlayfs mounts will show up with 'overlay' or 'overlayfs' as 
            # first column.
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
