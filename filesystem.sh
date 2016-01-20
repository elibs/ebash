#!/bin/bash

# Copyright 2016, SolidFire, Inc. All rights reserved.

#-----------------------------------------------------------------------------
# filesystem.sh is a generic module for dealing with various filesystem types
# in a more generic and consistent manner. It also provides some really helpful
# and missing functionality not provided by upstream tools. 
#
# At present the list of supported filesystem types are as follows:
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
# organization. Our etar function generalizes the use of tar files so that 
# compression format is handled seamlessly based on the file extension.
#-------------------------------------------------------------------------------

# Determine filesystem type based on the file suffix.
fs_type()
{
    $(declare_args src)
    
    if [[ ${src} =~ .squashfs ]]; then
        echo -n "squashfs"
    elif [[ ${src} =~ .iso ]]; then
        echo -n "iso"
    elif [[ ${src} =~ .tar|.tar.gz|.tgz|.taz|tar.bz2|.tz2|.tbz2|.tbz ]]; then
        echo -n "tar"
    elif [[ -d "${src}" ]]; then
        echo -n "directory"
    elif [[ -f "${src}" ]]; then
        echo -n "file"
    else
        ewarn "Unsupported fstype $(lval src)"
        return 1
    fi
}

# Generic function for creating a filesystem of a given type from the given
# source directory and write it out to the requested destination directory. 
# This function will intelligently figure out the type of file to create 
# based on the suffix of the file.
fs_create()
{
    $(declare_args src dest)
    local src_type=$(fs_type "${src}")
    local dst_type=$(fs_type "${dest}")

    edebug "Creating filesystem $(lval src dest src_type dst_type)"

    if [[ ! ${src_type} =~ file|directory ]]; then
        eerror "Unsupported $(lval src src_type) (src must be a file or directory)"
    fi

    # SQUASHFS
    if [[ ${dst_type} == squashfs ]]; then
        mksquashfs "${src}" "${dest}" -noappend

    # ISO
    elif [[ ${dst_type} == iso ]]; then

        # Optional flags to pass through into mkisofs
        local volume=$(opt_get v "")
        local bootable=$(opt_get b 0)

        # Put body in a subshell to ensure traps perform clean-up.
        (
            # Generate ISO flags
            local iso_flags="-V "${volume}""
            if opt_true bootable; then
                iso_flags+=" -b isolinux/isolinux.bin 
                             -c isolinux/boot.cat
                             -no-emul-boot
                             -boot-load-size 4
                             -boot-info-table"
            fi

            local dst_abs="$(readlink -m "${dest}")"
            cd ${src}
            mkisofs -r "${iso_flags}" -cache-inodes -J -l -o "${dst_abs}" . |& edebug
        ) 

    # TAR
    elif [[ ${dst_type} == tar ]]; then
        local dst_real=$(readlink -m "${dest}")
        pushd "${src}"
        etar --create --file "${dst_real}" .
        popd

    fi
}

# Extract a previously constructed filesystem image. This works on all of our
# supported filesystem types.
fs_extract()
{
    $(declare_args src dest)
    local src_type=$(fs_type "${src}")
    mkdir -p "${dest}"

    # SQUASHFS
    if [[ ${src_type} == squashfs ]]; then
        unsquashfs -force -dest "${dest}" "${src}"
    
    # ISO
    elif [[ ${src_type} == iso ]]; then

        # Neither cdrtools nor isoinfo provide a native way to extract the
        # contents of an ISO. The closest is isoinfo -x but that only works
        # on a single file at a time and is not recursive. So we have to mount
        # it then copy the mounted directory to the destination directory.
        # NOTE: Do this in a subshell to ensure traps perform clean-up.
        (
            local mnt=$(mktemp -d /tmp/filesystem-mnt-XXXX)
            mount --read-only "${src}" "${mnt}"
            trap_add "eunmount_rm ${mnt} |& edebug"
            cp --archive --recursive "${mnt}/." "${dest}"
        )
        
    # TAR
    elif [[ ${src_type} == tar ]]; then
        local src_real=$(readlink  -m "${src}")
        pushd "${dest}"
        etar --absolute-names --extract --file "${src_real}" .
        popd
    fi
}

# Simple function to list the contents of a filesystem image.
fs_list()
{
    $(declare_args src)
    local src_type=$(fs_type "${src}")

    # SQUASHFS
    if [[ ${src_type} == squashfs ]]; then

        # Use unsquashfs to list the contents but modify the output so that it
        # matches output from our other supported formats. Also strip out the
        # "/" entry as that's not in ISO's output and generally not interesting.
        unsquashfs -ls "${src}" | grep "^squashfs-root" | sed -e 's|squashfs-root||' -e '/^\s*$/d'
    
    # ISO
    elif [[ ${src_type} == iso ]]; then
        isoinfo -J -i "${src}" -f

    # TAR
    elif [[ ${src_type} == tar ]]; then

        # List contents of tar file but remove the "./" from the output so it
        # matches output of squashfs and iso.
        etar --list --file "${src}" | sed -e "s|^./|/|" -e '/^\/$/d'
    fi
}

#-----------------------------------------------------------------------------
# TAR
#-----------------------------------------------------------------------------

# etar is a wrapper around the normal 'tar' command with a few enhancements:
# - Suppress all the normal noisy warnings that are almost never of interest
#   to us.
# - Automatically detect fastest compression program by default. If this isn't
#   desired then pass in --use-compress-program=<PROG>. Unlike normal tar, this
#   will big the last one in the command line instead of giving back a fatal
#   error due to multiple compression programs.
etar()
{
    # Disable all tar warnings which are expected with unknown file types, sockets, etc.
    local args=("--warning=none")

    # Provided an explicit compression program wasn't provided via "-I/--use-compress-program"
    # then automatically determine the compression program to use based on file
    # suffix... but substitute in pbzip2 for bzip and pigz for gzip
    local match=$(echo "$@" | egrep '(-I|--use-compress-program)' || true)
    if [[ -z ${match} ]]; then

        local prog=""
        if [[ -n $(echo "$@" | egrep "\.bz2|\.tz2|\.tbz2|\.tbz" || true) ]]; then
            prog="pbzip2"
        elif [[ -n $(echo "$@" | egrep "\.gz|\.tgz|\.taz" || true) ]]; then
            prog="pigz"
        fi

        # If the program we selected is available set that as the compression program
        # otherwise fallback to auto-compress and let tar pick for us.
        if [[ -n ${prog} && -n $(which ${prog} 2>/dev/null || true) ]]; then
            args+=("--use-compress-program=${prog}")
        else
            args+=("--auto-compress")
        fi
    fi

    tar "${args[@]}" "${@}"
}

#-----------------------------------------------------------------------------
# CONVERSIONS
#-----------------------------------------------------------------------------

# Convert given source file into the requested destination type. This is done
# by figuring out the source and destination types using fs_type. Then it 
# mounts the source file into a temporary file, then calls fs_create on the
# temporary directory to write it out to the new destination type.
fs_convert()
{
    $(declare_args src dest)
    local src_type=$(fs_type "${src}")
    edebug "Converting $(lval src dest src_type)"

    # Temporary directory for mounting
    local mnt="$(mktemp -d /tmp/filesystem-mnt-XXXX)"
    trap_add "eunmount_rm ${mnt} |& edebug"

    # Mount (if possible) or extract the filesystem if mounting is not supported.
    fs_mount_or_extract "${src}" "${mnt}"

    # Now we can do the new filesystem creation from 'mnt'
    fs_create "${mnt}" "${dest}"
}

#-----------------------------------------------------------------------------
# MISC UTILITIES
#-----------------------------------------------------------------------------

# Diff two or more mountable filesystem images.
fs_diff()
{
    # Put body in a subshell to ensure traps perform clean-up.
    (
        local mnts=()
        local src
        for src in "${@}"; do
            
            local mnt="$(mktemp -d /tmp/filesystem-mnt-XXXX)"
            trap_add "eunmount_rm "${mnt}" |& edebug"
            local src_type=$(fs_type "${src}")
            mnts+=( "${mnt}" )

            # Mount (if possible) or extract the filesystem if mounting is not supported.
            fs_mount_or_extract "${src}" "${mnt}"
        done

        diff --recursive --unified "${mnts[@]}"
    )
}

# Mount a given filesystem type to a temporary directory read-only if it's
# a mountable filesystem and otherwise extract it to the directory.
fs_mount_or_extract()
{
    $(declare_args src dest)
    local src_type=$(fs_type "${src}")

    # SQUASHFS or ISO can be directly mounted
    if [[ ${src_type} =~ squashfs|iso ]]; then
        mount --read-only "${src}" "${dest}"
    
    # TAR files need to be extracted manually :-[
    elif [[ ${src_type} == tar ]]; then
        fs_extract "${src}" "${dest}"
    fi
}
