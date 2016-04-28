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
    local dest=$(readlink -m ${args[${#args[@]}-1]})
    unset args[${#args[@]}-1]
    
    # Mount layered mounts at requested destination, creating if it doesn't exist.
    mkdir -p "${dest}"
    
    # Top-level matadata directory
    local metadir=$(mktemp --tmpdir --directory overlayfs-meta-XXXXXX)
    stacktrace > "${metadir}/stacktrace"
    mkdir -p ${metadir}/{sources,lowerdirs,upperdir,workdir,merged}
    mount --bind "${dest}" "${metadir}/merged"

    # Track source and lowerdirs
    local src="" lower="" lower_src=""
    local sources=()
    local lowerdirs=()

    # NEWER KERNEL VERSIONS (>= 3.20)
    if [[ ${__BU_KERNEL_MAJOR} -ge 4 || ( ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 20 ) ]]; then

        edebug "Using Multi-Layer OverlayFS $(lval __BU_KERNEL_MAJOR __BU_KERNEL_MINOR)"

        # Iterate through all the images and mount each one into a temporary directory
        local idx
        for idx in $(array_indexes args); do
            src=$(readlink -f "${args[$idx]}")
            lower="${metadir}/lowerdirs/${idx}"
            lower_src="${metadir}/sources/${idx}"
            lowerdirs+=( "${lower}" )
            sources+=( "${src}" )

            ln -s "${src}" "${lower_src}"
            archive_mount "${src}" "${lower}"
        done

        mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="$(array_join lowerdirs :)",upperdir="${metadir}/upperdir",workdir="${metadir}/workdir" "${dest}"
 
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
        src=$(readlink -f "${args[0]}")
        lower="${metadir}/lowerdirs/0"
        lower_src="${metadir}/sources/0"
        unset args[0]
        lowerdirs+=( "${lower}" )
        sources+=( "${src}" )

        ln -s "${src}" "${lower_src}"
        archive_mount "${src}" "${lower}"
        
        # Extract all remaining layers into empty "middle" directory
        if array_not_empty args; then
       
            local middle="${metadir}/lowerdirs/1"
            ln -s "$(readlink -f "${args[1]}")" "${metadir}/sources/1"

            # Extract this layer into middle directory using image specific mechanism.
            for arg in "${args[@]}"; do
                archive_extract "${arg}" "${middle}"
            done
 
            if [[ ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 18 ]]; then
                mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${middle}",workdir="${metadir}/workdir" "${middle}"
            else
                mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${middle}" "${middle}"
            fi
            
            lower=${middle}
        fi

        if [[ ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 18 ]]; then
            mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${metadir}/upperdir",workdir="${metadir}/workdir" "${dest}"
        else
            mount --types ${__BU_OVERLAYFS} ${__BU_OVERLAYFS} --options lowerdir="${lower}",upperdir="${metadir}/upperdir" "${dest}"
        fi
    fi

    # Populate a pack with what we created.
    local layers=""
    pack_set layers "merged=${dest}"
    pack_set layers "metadir=${metadir}" 
    pack_set layers "lowerdirs=${lowerdirs[*]}"
    pack_set layers "upperdir=${metadir}/upperdir"
    pack_set layers "workdir=${metadir}/workdir"
    pack_set layers "sources=${sources[*]}"
    pack_set layers "lowest=${lowerdirs[0]}"
    pack_set layers "src=${sources[0]}"
    edebug "Created $(lval %layers)"
    echo "${layers}" > "${metadir}/layer.pack"
}

# overlayfs_unmount will unmount an overlayfs directory previously mounted
# via overlayfs_mount. It takes multiple arguments where each is the final
# overlayfs mount point. In the event there are multiple overlayfs layered
# into the final mount image, they will all be unmounted as well.
overlayfs_unmount()
{
    $(opt_parse mnt)

    # If empty string or not mounted just skip it
    if [[ -z "${mnt}" ]] || ! emounted "${mnt}" ; then
        return 0
    fi

    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers

    # Manually unmount merged mount point. Cannot call eunmount since it would see
    # this as an overlayfs mount and try to call overlayfs_unmount again and we'd
    # recurse infinitely.
    umount -l "${mnt}"

    # Now we can eunmount all the other layers to ensure everything is cleaned up.
    # This is necessary on older kernels which would leak the lower layer mounts.
    eunmount --all --recursive --delete "$(pack_get layers metadir)" "${mnt}"
}

# Parse an overlayfs mount point and populate a pack with entries for the 
# sources, lowerdirs, lowest, upperdir, workdir, and src and mnt.
#
# NOTE: Because 'lowerdir' may actually be stacked its value may contain
#       multiple whitespace separated entries we use the key 'lowerdirs'
#       instead of 'lowerdir' to more accurately reflect that it's multiple
#       entries instead of a single entry. There is an additional 'lowest'
#       key we put in the pack that is the bottom-most 'lowerdir' when we
#       need to directly access it.
#
# NOTE: Depending on kernel version, 'workdir' may be empty as it may not be used.
overlayfs_layers()
{
    $(opt_parse \
        "mnt        | Overlayfs mount point to list the layers for." \
        "layers_var | Pack to store the details into.")

    # Ensure we use absolute path
    mnt=$(readlink -m ${mnt})

    # Initialize pack.
    eval "${layers_var}="

    # Look for an overlayfs mount point matching provided mount point. It may NOT be
    # mounted (hence the || true) in which case we should just return.
    local entry=$(grep "^${__BU_OVERLAYFS} ${mnt}" /proc/mounts | grep -Po "upperdir=\K[^, ]*" || true)
    if [[ -z ${entry} ]]; then
        return 0
    fi

    # Read in contents of the pack if present. If not populate the pack with empty values.
    local metadir=$(dirname $(readlink -f "${entry}"))
    if [[ -e ${metadir}/layer.pack ]]; then
        eval "${layers_var}=\$(<"\${metadir}/layer.pack")"
    else
        pack_set ${layers_var} merged="${mnt}" metadir= lowerdirs= upperdir= workdir= sources= lowest= src=
    fi
}

# overlayfs_tree is used to display a graphical representation for an overlayfs
# mount. The graphical format is meant to show details about each layer in the
# overlayfs mount hierarchy to make it clear what files reside in what layers
# along with some basic metadata about each file (as provided by find -ls). The
# order of the output is top-down to clearly represent that overlayfs is a
# read-through layer cake filesystem such that things "above" mask things "below"
# in the layer cake.
overlayfs_tree()
{
    $(opt_parse mnt)

    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers

    # Parse all the lowerdirs and upperdir into an array of mount points to get contents of.
    # For display purposes want to display the sources of the mount points instead. So construct a
    # second array for that. This relies on the fact that the entries are in the same order inside
    # the layer map.
    local lowerdirs=( $(pack_get layers lowerdirs) $(pack_get layers upperdir) )
    local sources=( $(pack_get layers sources)  $(pack_get layers upperdir) )

    local idx
    for idx in $(array_rindexes lowerdirs); do
        local layer=${lowerdirs[$idx]}
        local src=${sources[$idx]}

        # Pretty print the contents
        local find_output=$(find ${layer} -ls           \
            | awk '{ $1=""; print}'                     \
            | sed -e "\|${layer}$|d" -e "s|${layer}/||" \
            | column -t | sort -k10)
        echo "$(ecolor green)+--layer${idx} [${src}]$(ecolor off)"
        echo "${find_output}" | sed 's#^#'$(ecolor green)\|$(ecolor off)\ \ '#g'
    done
}

# Commit all pending changes in the overlayfs write later back down into the lowest read-only
# layer and then unmount the overlayfs mount. The intention of this function is that you should
# call it when you're completely done with an overlayfs and you want its changes to persist
# back to the original archive. To avoid doing any unecessary work, this function will first
# call overlayfs_dedupe and only if something has changed will it actually write out a new
# archive.
#
# NOTE: You can't just save the overlayfs mounted directory back to the original archive while
#       it's mounted or you'll corrupt the currently mounted overlayfs. To work around this, we
#       archive the overlayfs mount point to a temporary archive, then we unmount the current
#       mount point so that we can safely copy the new archive over the original archive.
overlayfs_commit()
{
   $(opt_parse \
       ":callback      | Callback to invoke after commit completes." \
        "+color    c=1 | Show a color diff if possible."             \
        "+error    e=0 | Error out if there is nothing to do."       \
        "+diff     d=0 | Show a unified diff of the changes."        \
        "+list     l=0 | List the changes to stdout."                \
        "+progress p=0 | Show eprogress while committing changes."   \
        "mnt           | The overlayfs mount point.")

    # First de-dupe the overlayfs. If nothing changed, then simply unmount and return success
    # unless caller opted in for this to be an error case.
    overlayfs_dedupe "${mnt}"
    $(tryrc overlayfs_changed "${mnt}")
    if [[ ${rc} -ne 0 ]]; then
        edebug "Nothing changed"
        overlayfs_unmount "${mnt}"

        if [[ ${error} -eq 1 ]]; then
            eerror "Nothing changed"
            return 1
        fi

        return 0
    fi

    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers
    local src=$(pack_get layers src)
    local src_name=$(basename "${src}")
    local src_type=$(archive_type "${src}")

    # Optionally list the changes
    if [[ ${list} -eq 1 ]]; then
        einfo "Changed ${src_name}"
        overlayfs_list_changes "${mnt}"
    fi

    # Optionally diff of the changes but don't let overlayfs_diff cause a failure since
    # we expect them to be different.
    if [[ ${diff} -eq 1 ]]; then
        einfo "Diffing ${src_name}"
        opt_forward overlayfs_diff color -- "${mnt}" || true
    fi

    # Create a tmp file to store changed version
    local tmp=$(mktemp --tmpdir ${src_name}.XXXXXX)
    trap_add "rm --force ${tmp}"

    # Optionally start eprogress ticker
    if [[ ${progress} -eq 1 ]]; then
        eprogress "Committing ${src_name}"
    fi

    # Determine archive_create flags we need to use so we preserve flags originally used
    # when the underlying source archive was created.
    local flags=""
    if [[ ${src_type} == "iso" ]]; then

        # Get volume name and bootable flag.
        # NOTE: Suppress stderr because isoinfo spews messages to stderr that can't be turned
        # of such as 'Setting input-charset to 'UTF-8' from locale.'
        flags+=' --volume="'$(isoinfo -d -i "${src}" 2>/dev/null | grep -oP "Volume id: (\K.*)")'"'
        flags+=" --bootable=$(file "${src}" | grep --count "(bootable)" || true)"
    fi

    # Save the changes to a temporary archive of the same type then unmount
    # the original and move the new archive over the original.
    archive_create ${flags} --directory "${mnt}" . "${tmp}"
    overlayfs_unmount "${mnt}"
    mv --force "${tmp}" "${src}"

    # Optionally call callback
    if [[ -n ${callback} ]]; then
        edebug "Invoking $(lval callback)"
        ${callback}
    fi

    # Optionally stop eprogress ticker
    if [[ ${progress} -eq 1 ]]; then
        eprogress_kill
    fi
}

# Save the top-most read-write later from an existing overlayfs mount into the
# requested destination file. This file can be a squashfs image, an ISO, or any
# supported archive format.
overlayfs_save_changes()
{
    $(opt_parse mnt dest)

    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers

    # Save the upper RW layer to requested type.   
    archive_create -d="$(pack_get layers upperdir)" . "${dest}"
}

# Check if there are any changes in an overlayfs or not.
overlayfs_changed()
{
    $(opt_parse mnt)

    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers

    # If the directory isn't empty then there are changes made to the RW layer.
    directory_not_empty "$(pack_get layers upperdir)"
}

# List the changes in an overlayfs
overlayfs_list_changes()
{
    $(opt_parse \
        "+long l=0 | Display long listing format." \
        "mnt       | The mountpoint to list changes for.")
 
    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers
    local upperdir="$(pack_get layers upperdir)"

    # Pretty print the list of changes
    if [[ ${long} -eq 1 ]]; then
        find "${upperdir}" -ls                                \
            | awk '{ $1=""; print}'                           \
            | sed -e "\|${upperdir}$|d" -e "s|${upperdir}/||" \
            | column -t | sort -k10
    else
        find "${upperdir}"                                    \
            | sed -e "\|${upperdir}$|d" -e "s|${upperdir}/||" \
            | column -t | sort -k10
    fi
}

# Show a unified diff between the lowest and upper layers
overlayfs_diff()
{
    $(opt_parse \
        "+color c=1 | Display diff in color." \
        "mnt        | Overlayfs mount.")

    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers

    # Diff layers optionally using colordiff instead of normal diff.
    local bin="diff"
    if [[ ${EFUNCS_COLOR:-} -eq 1 && ${color} -eq 1 ]] && which colordiff &>/dev/null; then
        bin="colordiff"
    fi

    ${bin} --recursive --unified "$(pack_get layers lowest)" "$(pack_get layers upperdir)"
}

# Dedupe files in overlayfs such that all files in the upper directory which are
# identical IN CONTENT to the original ones in the lower layer are removed from
# the upper layer. This uses 'cmp' in order to compare each file byte by byte.
# Thus even if the upper file has a newer timestamp it will be removed if its
# content is otherwise identical.
overlayfs_dedupe()
{
    $(opt_parse mnt)
 
    # Load the layer map for this overlayfs mount
    local layers=""
    overlayfs_layers "${mnt}" layers

    # Get the upperdir and bottom-most lowerdir
    local lower=$(pack_get layers lowest)
    local upper=$(pack_get layers upperdir)

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
