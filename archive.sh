#!/bin/bash

# Copyright 2016, SolidFire, Inc. All rights reserved.

#-----------------------------------------------------------------------------
# ARCHIVE.SH
#
# archive.sh is a generic module for dealing with various archive formats in a
# generic and consistent manner. It also provides some really helpful and
# missing functionality not provided by upstream tools. 
#
# At present the list of supported archive formats is as follows:
#
# SQUASHFS: Squashfs is a compressed read-only filesystem for Linux. Squashfs
# intended for general read-only filesystem use, for archival use and in
# constrained block device/memory systems where low overhead is needed. Squashfs
# images are rapidly becoming a very common medium used throughout our build, 
# install, test and upgrade code due to their high compressibility, small
# resultant size, massive parallelization on both create and unpack and that 
# they can be directly mounted and booted into.
#
# ISO: An ISO image is an archive file of an optical disc, a type of disk image
# composed of the data contents from every written sector on an optical disc,
# including the optical disc file system. The name ISO is taken from the ISO
# 9660 file system used with CD-ROM media, but what is known as an ISO image
# can contain other file systems.
#
# TAR: A tar file is an archive file format that may or may not be compressed.
# The archive data sets created by tar contain various file system parameters,
# such as time stamps, ownership, file access permissions, and directory
# organization. Our archive_compress_program function is used to generalize our
# use of tar so that compression format is handled seamlessly based on the file
# extension in a way which picks the best compression program at runtime.
#-------------------------------------------------------------------------------

# Determine archive format based on the file suffix.
archive_type()
{
    $(declare_args src)
    
    if [[ ${src} =~ .squashfs ]]; then
        echo -n "squashfs"
    elif [[ ${src} =~ .iso ]]; then
        echo -n "iso"
    elif [[ ${src} =~ .tar|.tar.gz|.tgz|.taz|tar.bz2|.tz2|.tbz2|.tbz ]]; then
        echo -n "tar"
    elif [[ -d "${src}" ]]; then
        eerror "Unsupported fstype $(lval src)"
        return 1
    fi
}

# Determine the best compress programm to use based on the archive suffix.
archive_compress_program()
{
    $(declare_args fname)
    local nice=$(opt_get n)

    if [[ ${fname} =~ .bz2|.tz2|.tbz2|.tbz ]]; then
        progs=( lbzip2 pbzip2 bzip2 )
        [[ ${nice} -eq 1 ]] && progs=( bzip2 )
    elif [[ ${fname} =~ .gz|.tgz|.taz ]]; then
        progs=( pigz gzip )
        [[ ${nice} -eq 1 ]] && progs=( gzip )
    elif [[ ${fname} =~ xz ]]; then
        progs=( lzma xz )
    else
        eerror "No suitable compress program for $(lval fname)"
        return 1
    fi

    # Look for matching installed program using which and head -1 to select
    # the first matching program. If progs is empty, this will call 'which ""'
    # which is an error. which returns the number of failed arguments so we have
    # to look at the output and not rely on the return code.
    local prog=$(which ${progs[@]:-} 2>/dev/null | head -1 || true)
    echo -n "${prog}"
    [[ -n ${prog} ]]
} 

# Get flag for use with tar to select the right compress program (or none if it's
# not a compressed file).
archive_tar_compress_arg()
{
    $(declare_args fname)
    local nice=$(opt_get n)
    $(tryrc -o=prog -e=stderr archive_compress_program -n=${nice} "${fname}")

    if [[ ${rc} -eq 0 ]]; then
        echo -n " --use-compress-program=${prog}"
    fi

    return 0
}

# Generic function for creating an archive file of a given type from the given
# list of source paths and write it out to the requested destination directory.
# This function will intelligently figure out the correct archive type based
# on the suffix of the file.
#
# You can also optionally exclude certain paths from being included in
# the resultant archive. Unfortunately, each of the supported archive formats
# have different levels of support for excluding via filename, glob or regex.
# So, to provide a common interface in archive_create, we pre-expand all exclude
# paths using find(1).
#
# This function also provides a uniform way of dealing with multiple source
# paths. All of the various archive formats handle this differently so the
# uniformity is important. Essentially, any path provided will be the name of 
# a top-level entry in the archive with the entire directory structure intact.
# This is essentially how tar works but different from how mksquashfs and mkiso
# normally behave. 
# 
# A few examples will help clarify the behavior:
#
# Example #1: Suppose you have a directory "a" with the files 1,2,3 and you call
# `archive_create a dest.squashfs`. archive_create will then yield the following:
# a/1
# a/2
# a/3
#
# Example #2: Suppose you have these files spread out across three directories:
# a/1 b/2 c/3 and you call `archive_create a b c dest.squashfs`. archive_create
# will then yield the following:
# a/1
# b/2
# c/3
#
# In the above examples note that the contents are consistent regardless of 
# whether you provide a single file, single directory or list of files or list
# of directories.
archive_create()
{
    $(declare_args)

    # Parse positional arguments into a bashutils array. Then grab final argument
    # which is the destination.
    local srcs=( "$@" )
    local dest=${srcs[${#srcs[@]}-1]}
    unset srcs[${#srcs[@]}-1]

    # Parse options
    local dest_real=$(readlink -m "${dest}")
    local dest_type=$(archive_type "${dest}")
    local excludes=( $(opt_get x) )
    local ignore_missing=$(opt_get i)
    local nice=$(opt_get n)
    local cmd=""

    edebug "Creating archive $(lval srcs dest dest_real dest_type excludes ignore_missing nice)"
    mkdir -p "$(dirname "${dest}")"

    # Put entire function into a subshell to ensure clean up traps execute properly.
    (
        die_on_error
        die_on_abort

        # Create excludes file
        local exclude_file=$(mktemp /tmp/archive-exclude-XXXX)
        trap_add "rm --force ${exclude_file}"

        # Always exclude the source file. Need to canonicalize it and then remove
        # any illegal prefix characters (/, ./, ../)
        echo "${dest_real#${PWD}/}" | sed "s%^\(/\|./\|../\)%%" > ${exclude_file}

        # Provide a common API around excludes, use find to pre-expand all excludes.
        if array_not_empty excludes; then
 
            # In case including and excluding something excludes take precedence.
            array_remove srcs ${excludes[@]}
        
            # Look for matching excludes in each source directory
            for src in "${srcs[@]}"; do
                find ${excludes[@]} 2>/dev/null || true
            done | sort --unique >> "${exclude_file}"
        fi

        edebug "Exclude File:\n$(cat ${exclude_file})"

        # If only a single argument is provided then we can just directly archive it.
        # If, however, there are multiple arguments we need to merge them into a single
        # directory before archiving.
        local unified=$(mktemp -d /tmp/archive-create-XXXX)
        trap_add "rm --recursive --force ${unified}"
        local root=""

        if [[ $(array_size srcs) -gt 1 ]]; then

            merge_paths -i=${ignore_missing} ${srcs[@]} ${unified}
            
            # If nothing was merged and we're ignoring missing files that's still success.
            if directory_empty ${unified} ; then
                if [[ ${ignore_missing} -eq 1 ]]; then
                    edebug "Nothing merged and ignoring missing files"
                    rm --force "${dest}"
                    return 0
                else
                    eerror "Nothing merged"
                    rm --force "${dest}"
                    return 1
                fi
            fi

            cd ${unified}${PWD}
            root="."
        elif [[ ${srcs} == "." ]]; then
            root="${srcs}"
        else
            root="$(readlink -m ${srcs})"
            root="${root#${PWD}/}"
        fi

        # SQUASHFS
        if [[ ${dest_type} == squashfs ]]; then
    
            local mksquashfs_flags="-no-duplicates -no-recovery -no-exports -no-progress -noappend -wildcards"
            if [[ ${nice} -eq 1 ]]; then
                mksquashfs_flags+=" -processors 1"
            fi          

            if [[ ${root} != "." ]]; then
                mksquashfs_flags+=" -keep-as-directory"
            fi
            
            cmd="mksquashfs ${root} ${dest_real} ${mksquashfs_flags} -ef ${exclude_file}"

        # ISO
        elif [[ ${dest_type} == iso ]]; then

            # Optional flags to pass through into mkisofs
            local volume=$(opt_get v "")
            local bootable=$(opt_get b 0)

            cmd="mkisofs -r -V "${volume}" -cache-inodes -J -l -o "${dest_real}" -exclude-list ${exclude_file}"

            # Generate ISO flags
            if opt_true bootable; then
                cmd+=" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table"
            fi

            if [[ ${root} != "." ]]; then
                cmd+=" -root ${root}"
            fi

            cmd+=" ${root}"

        # TAR
        elif [[ ${dest_type} == tar ]]; then

            cmd+="tar --exclude-from ${exclude_file} --create"
            $(tryrc -o=prog -e=stderr archive_compress_program -n=${nice} "${dest_real}")
            if [[ ${rc} -eq 0 ]]; then
                cmd+=" --file - ${root} | ${prog} > ${dest_real}"
            else
                cmd+=" --file ${dest_real} ${root}"
            fi
        fi

        # Execute command
        edebug "$(lval cmd)"
        eval "${cmd}" |& edebug
    )
}

# Extract a previously constructed archive image. This works on all of our
# supported archive types. Also takes an optional list of find(1) glob patterns
# to limit what files are extracted from the archive. If no files are provided
# it will extract all files from the archive.
archive_extract()
{
    $(declare_args src dest)
    local files=( "${@}" )
    local ignore_missing=$(opt_get i)
    local nice=$(opt_get n)
    local src_type=$(archive_type "${src}")
    mkdir -p "${dest}"

    edebug "Extracting $(lval src dest src_type files ignore_missing)"

    # SQUASHFS + ISO
    # Neither of the tools for these archive formats support extracting a list
    # of globs patterns. So we mount them first and use find.
    if [[ ${src_type} =~ squashfs|iso ]]; then

        # NOTE: Do this in a subshell to ensure traps perform clean-up.
        (
            local mnt=$(mktemp -d /tmp/archive-mnt-XXXX)
            mount --read-only "${src}" "${mnt}"
            trap_add "eunmount -r -d ${mnt}"

            local dest_real=$(readlink -m "${dest}")
            cd "${mnt}"

            if array_empty files; then
                cp --archive --recursive . "${dest_real}"
            else

                local includes=( ${files[@]} )
                if [[ ${ignore_missing} -eq 1 ]]; then
                    includes=( $(find -wholename ./$(array_join files " -o -wholename ./")) )
                fi

                # If includes is EMPTY and we are ignoring missing files then there's nothing
                # to do because none of the requested files exist in the archive. In this case
                # we can just return success. Otherwise if includes is empty and we are not 
                # ignoring missing files then that's an error.
                if array_empty includes; then
                
                    if [[ ${ignore_missing} -eq 1 ]]; then
                        edebug "Nothing to extract -- returning success"
                        return 0
                    else
                        eerror "No matching files found to extract $(lval src dest files)"
                        return 1
                    fi
                fi

                # Do the actual extracting
                cp --archive --recursive --parents ${includes[@]} "${dest_real}"
            fi
        )

    # TAR
    elif [[ ${src_type} == tar ]]; then

        # By default the files to extract from the archive is all the files requested.
        # If files is an empty array this will evaluate to an empty string and all files
        # will be extracted.
        local includes=$(array_join files)

        # If ignore_missing flag was enabled filter out list of files in the archive to
        # only those which the caller requested. This will ensure we are essentially 
        # getting the intersection of actual files in the archive and the list of files 
        # the caller asked for (which may or may not actually be in the archive).
        if array_not_empty files && [[ ${ignore_missing} -eq 1 ]]; then
            includes=$(tar --list --file "${src}" | grep -P "($(array_join files '|'))" || true)

            # If includes is EMPTY there's nothing to do because none of the requested
            # files exist in the archive and we're ignoring missing files.
            if [[ -z ${includes} ]]; then
                edebug "Nothing to extract -- returning success"
                return 0
            fi
        fi

        # Do the actual extracting.
        local src_real=$(readlink  -m "${src}")
        pushd "${dest}"
        tar --extract --file "${src_real}" \
            $(archive_tar_compress_arg -n=${nice} "${src_real}") \
            --wildcards --no-anchored ${includes}
        popd
    fi
}

# Simple function to list the contents of an archive image.
archive_list()
{
    $(declare_args src)
    local src_type=$(archive_type "${src}")

    # SQUASHFS
    if [[ ${src_type} == squashfs ]]; then

        # Use unsquashfs to list the contents but modify the output so that it
        # matches output from our other supported formats. Also strip out the
        # "/" entry as that's not in ISO's output and generally not interesting.
        unsquashfs -ls "${src}" | grep "^squashfs-root" | sed -e 's|^squashfs-root[/]*||' -e '/^\s*$/d'
    
    # ISO
    elif [[ ${src_type} == iso ]]; then
        isoinfo -J -i "${src}" -f | sed -e 's|^/||'

    # TAR
    elif [[ ${src_type} == tar ]]; then

        # List contents of tar file in a manner consistent with the other tools.
        # They all output paths with '/' but tar's output is specific to if we
        # had multiple src files or not. This unifies that output by removing
        # leading './' (single path) and inserts '/' prefix to match the others.
        tar --list --file "${src}" | sed -e "s|^./||" -e '/^\/$/d' -e 's|/$||' #-e 's|^\([^/]\)|/\1|'
    fi
}

#-----------------------------------------------------------------------------
# CONVERSIONS
#-----------------------------------------------------------------------------

# Convert given source file into the requested destination type. This is done
# by figuring out the source and destination types using archive_type. Then it 
# mounts the source file into a temporary file, then calls archive_create on the
# temporary directory to write it out to the new destination type.
archive_convert()
{
    $(declare_args src dest)
    local src_type=$(archive_type "${src}")
    local dest_real=$(readlink -m "${dest}")
    edebug "Converting $(lval src src_type dest dest_real)"

    # Temporary directory for mounting
    (
        local mnt="$(mktemp -d /tmp/archive-mnt-XXXX)"
        trap_add "eunmount -r -d ${mnt}"

        # Mount (if possible) or extract the archive image if mounting is not supported.
        archive_mount_or_extract "${src}" "${mnt}"

        # Now we can create a new archive from 'mnt'
        cd ${mnt}
        archive_create . "${dest_real}"
    )
}

#-----------------------------------------------------------------------------
# MISC UTILITIES
#-----------------------------------------------------------------------------

# Diff two or more archive images.
archive_diff()
{
    # Put body in a subshell to ensure traps perform clean-up.
    (
        local mnts=()
        local src
        for src in "${@}"; do
            
            local mnt="$(mktemp -d /tmp/archive-mnt-XXXX)"
            trap_add "eunmount -r -d ${mnt}"
            local src_type=$(archive_type "${src}")
            mnts+=( "${mnt}" )

            # Mount (if possible) or extract the archive if mounting is not supported.
            archive_mount_or_extract "${src}" "${mnt}"
        done

        diff --recursive --unified "${mnts[@]}"
    )
}

# Mount a given archive type to a temporary directory read-only if mountable
# and if not extract it to the destination directory.
archive_mount_or_extract()
{
    $(declare_args src dest)
    local src_type=$(archive_type "${src}")

    # SQUASHFS or ISO can be directly mounted
    if [[ ${src_type} =~ squashfs|iso ]]; then
        mount --read-only "${src}" "${dest}"
    
    # TAR files need to be extracted manually :-[
    elif [[ ${src_type} == tar ]]; then
        archive_extract "${src}" "${dest}"
    fi
}

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
# use just 'overlay' so dynamically detected the correct type to use here.
__BU_OVERLAYFS=$(awk '/overlay/ {print $2}' /proc/filesystems 2>/dev/null || true)
__BU_KERNEL_MAJOR=$(uname -r | awk -F . '{print $1}')
__BU_KERNEL_MINOR=$(uname -r | awk -F . '{print $2}')

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

    ewarn "OverlayFS not enabled -- trying to load kernel module"

    if [[ ${__BU_KERNEL_MAJOR} -ge 4 || ( ${__BU_KERNEL_MAJOR} -eq 3 && ${__BU_KERNEL_MINOR} -ge 18 ) ]]; then
        edebug "Using newer kernel module name 'overlay'"
        modprobe overlay
    else
        edebug "Using legacy kernel module name 'overlayfs'"
        modprobe overlayfs
    fi

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
            trap_add "eunmount -r -d ${tmp}"
            fs_mount_or_extract "${arg}" "${tmp}"
            layers+=( "${tmp}" )
        done

        # Create temporary directory to hold read-only and read-write layers.
        # Create lowerdir parameter by joining all images with colon
        # (see https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt)
        local lower=$(array_join layers ":")
        local upper="$(mktemp -d /tmp/overlayfs-upper-XXXX)"
        local work="$(mktemp -d /tmp/overlayfs-work-XXXX)"
        trap_add "eunmount -r -d ${upper} ${work}"

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
        local lower=$(mktemp -d /tmp/overlayfs-lower-XXXX)
        fs_mount_or_extract "${args[0]}" "${lower}"
        unset args[0]

        # Extract all remaining layers into empty "middle" directory
        if array_not_empty args; then
       
            local middle=$(mktemp -d /tmp/overlayfs-middle-XXXX)
            local work=$(mktemp -d /tmp/overlayfs-work-XXXX)
            trap_add "eunmount -r -d ${middle} ${work}"

            # Extract this layer into middle directory using image specific mechanism.
            for arg in "${args[@]}"; do
                fs_extract "${arg}" "${middle}"
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
        trap_add "eunmount -r -d ${upper} ${work}"

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
    $(declare_args)
    local verbose=$(opt_get v 0)
    
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
        
        local layer
        for layer in ${parts[@]:-} "${upper}" "${work}" "${mnt}"; do
            eunmount_internal -v=${verbose} "${layer}"
        done

        # In case the overlayfs mounts are layered manually have to also unmount
        # the lower layers.
        overlayfs_unmount ${parts[0]:-}
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
