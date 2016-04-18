#!/bin/bash

# Copyright 2016, SolidFire, Inc. All rights reserved.

[[ ${__BU_OS} == Linux ]] || return 0

#-------------------------------------------------------------------------------
# OVERLAYFS
# 
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
# use just 'overlay' so dynamically detected the correct type to use here. Some
# kernels also support BOTH in which case we need to only take the first one we
# find (hence the use of head -1).
__BU_OVERLAYFS=$(awk '/overlay/ {print $2}' /proc/filesystems 2>/dev/null | head -1 || true)

# Detect whether overlayfs is supported or not.
overlayfs_supported()
{
    [[ -n "${__BU_OVERLAYFS}" ]]
}

# Try to enable overlayfs by modprobing the kernel module.
overlayfs_enable()
{
    # If it's already supported then return - nothing to do
    if overlayfs_supported; then
        edebug "OverlayFS already enabled"
        return 0
    fi

    edebug "OverlayFS not enabled -- trying to load kernel module"

    # Try 'overlay' before 'overlayfs' b/c overlay is preferred if both are
    # supported because it supports Multi-Layering.
    local module
    for module in overlay overlayfs; do
        edebug "Trying to load $(lval module)"

        # Break as we only need one of the modules available.
        if modprobe -q ${module}; then
            edebug "Successfully loaded $(lval module)"
            __BU_OVERLAYFS=${module}
            break
        fi

        edebug "Failed to load $(lval module)"
    done

    # Verify it's now supported
    overlayfs_supported
}

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
# The versioning around OverlayFS is quite complex. The first version of the
# kernel which officially supported overlayfs was 3.18 and the kernel module
# name is just 'overlay'. Earlier, unofficial versions of the kernel module
# used the module name 'overlayfs'. The newer module 'overlay' requires 
# specifying an additional 'workdir' option for the scratch work performed
# by overlayfs. 3.19 added support for layering up to two overlayfs mounts
# on top of one another. 3.20 extended this support even more by allowing you
# to chain as many as you'd like in the 'lowerdir' option separated by colons
# and it would overlay them all seamlessly. The 3.19 version is not particularly
# interesting to us due to it's limitation of only 2 layers so we don't use that
# one at all.
overlayfs_mount()
{
    overlayfs_enable

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
     
    # NEWER KERNEL VERSIONS (>= 3.20)
    if [[ ${__BU_KERNEL_MAJOR} -ge 4 || ( ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 20 ) ]]; then

        edebug "Using Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"

        # Iterate through all the images and mount each one into a temporary directory
        local arg
        local layers=()
        for arg in "${args[@]}"; do
            local tmp=$(mktemp --tmpdir --directory overlayfs-lower-XXXXXX)

            archive_mount "${arg}" "${tmp}"
            layers+=( "${tmp}" )
        done

        # Create temporary directory to hold read-only and read-write layers.
        # Create lowerdir parameter by joining all images with colon
        # (see https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt)
        local lower=$(array_join layers ":")
        local upper="$(mktemp --tmpdir --directory overlayfs-upper-XXXXXX)"
        local work="$(mktemp --tmpdir --directory overlayfs-work-XXXXXX)"

        # Mount overlayfs
        mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${upper}",workdir="${work}" "${dest}"
 
    # OLDER KERNEL VERSIONS (<3.20)
    # NOTE: Older OverlayFS is really annoying because you can only stack 2 overlayfs
    # mounts. To get around this, we'll mount the bottom most layer as the read-only 
    # base image. Then we'll unpack all other images into a middle layer. Then mount
    # an empty directory as the top-most directory.
    #
    # NOTE: Versions >= 3.18 require the "workdir" option but older versions do not.
    else
       
        edebug "Using legacy non-Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"

        # Grab bottom most layer
        local lower=$(mktemp --tmpdir --directory overlayfs-lower-XXXXXX)
        archive_mount "${args[0]}" "${lower}"
        unset args[0]

        # Extract all remaining layers into empty "middle" directory
        if array_not_empty args; then
       
            local middle=$(mktemp --tmpdir --directory overlayfs-middle-XXXXXX)
            local work=$(mktemp --tmpdir --directory overlayfs-work-XXXXXX)

            # Extract this layer into middle directory using image specific mechanism.
            for arg in "${args[@]}"; do
                archive_extract "${arg}" "${middle}"
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
        local upper=$(mktemp --tmpdir --directory squashfs-upper-XXXXXX)
        local work=$(mktemp --tmpdir --directory squashfs-work-XXXXXX)

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
    local mnt
    for mnt in "$@"; do

        # If empty string or not mounted just skip it
        if [[ -z "${mnt}" ]] || ! emounted "${mnt}" ; then
            continue
        fi

        # Parse out required lower and upper directories to be unmounted.
        # /proc/mounts will show the mount point and its lowerdir,upperdir and workdir so that we can unmount it properly:
        # "overlay /home/marshall/sandboxes/bashutils/output/squashfs.etest/ETEST_squashfs_mount/dst overlay rw,relatime,lowerdir=/tmp/squashfs-ro-basv,upperdir=/tmp/squashfs-rw-jWg9,workdir=/tmp/squashfs-work-cLd9 0 0"
        local output="$(grep "${__BU_OVERLAYFS} $(emount_realpath ${mnt})" /proc/mounts)"
        local lower="$(echo "${output}" | grep -Po "lowerdir=\K[^, ]*")"
        local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"

        # On newer kernels, also need to unmount work directory.
        local work=""
        if [[ ${__BU_KERNEL_MAJOR} -ge 4 || ( ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 18 ) ]]; then
            work="$(echo "${output}"  | grep -Po "workdir=\K[^, ]*")"
        fi
        
        edebug "$(lval mnt lower upper work)"

        # Split 'lower' on ':' so we can unmount each of the lower layers 
        local parts
        array_init parts "${lower}" ":"
        
        # In the event we have stacked multiple overlayfs mounts on top of one another
        # we need to unmount the current set of mount points and then at the very end
        # of this function unmount the lowest layer. So we pull that out of our array
        # and handle it specially at the end.
        if array_not_empty parts; then
            lower=${parts[0]}
            unset parts[0]
        fi
 
        local layer
        for layer in ${parts[@]:-} "${upper}" "${work}" "${mnt}"; do

            if [[ -z ${layer} ]] || ! emounted "${layer}"; then
                edebug "Skipping non-mounted $(lval layer)"
                continue
            fi
            
            edebug "Unmounting $(lval layer)"
            umount -l "${layer}"

        done

        # In case the overlayfs mounts are layered manually have to also unmount
        # the lower layers. NOTE: It's important we call eunmount not overlayfs_unmount
        # because the bottom most layer may not be overlayfs.
        eunmount ${lower}
    done
}

# overlayfs_tree is used to display a graphical representation for an overlayfs
# mount. The graphical format is meant to show details about each layer in the
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
 
        # If not mounted, just skip this.
        if ! emounted "${mnt}"; then
            continue
        fi
 
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

# Save the top-most read-write later from an existing overlayfs mount into the
# requested destination file. This file can be a squashfs image, an ISO, or any
# supported archive format.
overlayfs_save_changes()
{
    $(opt_parse mnt dest)

    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    edebug "$(lval mnt dest output)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"

    # Save to requested type.   
    archive_create -d="${upper}" . "${dest}"
}

# Check if there are any changes in an overlayfs or not.
overlayfs_changed()
{
    $(opt_parse mnt)

    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"

    # If the directory isn't empty then there are changes made to the RW layer.
    directory_not_empty "${upper}"
}

# List the changes in an overlayfs
overlayfs_list_changes()
{
    $(opt_parse \
        "+long l=0 | Display long listing format." \
        "mnt       | The mountpoint to list changes for.")
        
    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"

    # Pretty print the list of changes
    if [[ ${long} -eq 1 ]]; then
        find "${upper}" -ls | awk '{ $1=""; print}' | sed -e "s|${upper}|/|" -e 's|//|/|' | column -t | sort -k10
    else
        find "${upper}" | sed -e "s|${upper}|/|" -e 's|//|/|' | sort
    fi
}

# Show a unified diff between the lower and upper layers 
overlayfs_diff()
{
    $(opt_parse mnt)

    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    local lower="$(echo "${output}" | grep -Po "lowerdir=\K[^, ]*")"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"

    diff --recursive --unified "${lower}" "${upper}"
}

# Dedupe files in overlayfs such that all files in the upper directory which are
# identical IN CONTENT to the original ones in the lower layer are removed from
# the upper layer. This uses 'cmp' in order to compare each file byte by byte.
# Thus even if the upper file has a newer timestamp it will be removed if its
# content is otherwise identical.
overlayfs_dedupe()
{
    $(opt_parse mnt)
 
    # Get RW layer from mounted src. This assumes the "upperdir" is the RW layer
    # as is our convention. If it's not mounted this will fail.
    local output="$(grep "${__BU_OVERLAYFS} $(readlink -m ${mnt})" /proc/mounts)"
    local lower="$(echo "${output}" | grep -Po "lowerdir=\K[^, ]*")"
    local upper="$(echo "${output}" | grep -Po "upperdir=\K[^, ]*")"
    
    # Check each file in parallel and remove any identical files.
    local pids=() path="" fname=""
    for path in $(find ${upper} -type f); do

        (
            if cmp --quiet "${path}" "${lower}/${path#${upper}}"; then
                edebug "Found duplicate $(lval path)"
                rm --force "${path}"
            fi
        ) &

        pids+=( $! )
        
    done

    if array_not_empty pids; then
        edebug "Waiting for $(lval pids)"
        wait ${pids[@]}
    fi

    # Now remove any empty orphaned directories in upper layer. Need to touch
    # a temporary file in upper to avoid find from also deleting that as well.
    local tmp=$(mktemp --tmpdir=${upper} .overlayfs_dedupe-XXXXXX)
    find "${upper}" -type d -empty -delete
    rm --force "${tmp}"

    # Since we have removed files from overlayfs upper directory we need to
    # remount the overlayfs mount so that the changes will be observed in
    # the final mount point properly.
    emount -o remount "${mnt}"
}