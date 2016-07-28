#!/bin/bash

# Copyright 2016, SolidFire, Inc. All rights reserved.

[[ ${__BU_OS} == Linux ]] || return 0

#---------------------------------------------------------------------------------------------------
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
#
# CPIO: "cpio is a general file archiver utility and its associated file format.
# It is primarily installed on Unix-like computer operating systems. The software
# utility was originally intended as a tape archiving program as part of the
# Programmer's Workbench (PWB/UNIX), and has been a component of virtually every
# Unix operating system released thereafter. Its name is derived from the phrase
# copy in and out, in close description of the program's use of standard input
# and standard output in its operation. All variants of Unix also support other
# backup and archiving programs, such as tar, which has become more widely
# recognized.[1] The use of cpio by the RPM Package Manager, in the initramfs
# program of Linux kernel 2.6, and in Apple Computer's Installer (pax) make cpio
# an important archiving tool" (https://en.wikipedia.org/wiki/Cpio).
#-----------------------------------------------------------------------------------------------------


opt_usage archive_type <<'END'
Determine archive format based on the file suffix. You can override type detection by passing in
explicit -t=type where type is one of the supported file extension types (e.g. squashfs, iso, tar,
tgz, cpio, cgz, etc).
END
archive_type()
{
    $(opt_parse \
        ":type t | Override automatic type detection and use explicit archive type." \
        "src     | Archive file name.")
    
    # Allow overriding type detection based on suffix and instead use provided
    # type providing it's a valid type we know about. To unify the code as
    # much as possible this accepts any of our known suffixes.
    if [[ -n ${type} ]]; then
        src=".${type}"
    fi

    # Detect type based on suffix
    if [[ ${src} == @(*.squashfs) ]]; then
        echo -n "squashfs"
    elif [[ ${src} == @(*.iso) ]]; then
        echo -n "iso"
    elif [[ ${src} == @(*.tar|*.tar.gz|*.tgz|*.taz|*.tar.bz2|*.tz2|*.tbz2|*.tbz|*.txz|*.tlz) ]]; then
        echo -n "tar"
    elif [[ ${src} == @(*.cpio|*.cpio.gz|*.cgz|*.caz|*.cpio.bz2|*.cz2|*.cbz2|*.cbz|*.cxz|*.clz) ]]; then
        echo -n "cpio"
    else
        eerror "Unsupported fstype $(lval src)"
        return 1
    fi
}

# Determine the best compress programm to use based on the archive suffix.
archive_compress_program()
{
    $(opt_parse \
        "+nice n | Be nice and use non-parallel compressors and only a single core." \
        ":type t | Override automatic type detection and use explicit archive type." \
        "fname   | Archive file name.")

    # Allow overriding type detection based on suffix and instead use provided
    # type providing it's a valid type we know about. To unify the code as
    # much as possible this accepts any of our known suffixes.
    if [[ -n ${type} ]]; then
        fname=".${type}"
    fi

    if [[ ${fname} == @(*.bz2|*.tz2|*.tbz2|*.tbz) ]]; then
        progs=( lbzip2 pbzip2 bzip2 )
        [[ ${nice} -eq 1 ]] && progs=( bzip2 )
    elif [[ ${fname} == @(*.gz|*.tgz|*.taz|*.cgz) ]]; then
        progs=( pigz gzip )
        [[ ${nice} -eq 1 ]] && progs=( gzip )
    elif [[ ${fname} == @(*.xz|*.txz|*.tlz|*.cxz|*.clz) ]]; then
        progs=( lzma xz )
    else
        edebug "No suitable compress program for $(lval fname)"
        return 0
    fi

    # Look for matching installed program using which and head -1 to select
    # the first matching program. If progs is empty, this will call 'which ""'
    # which is an error. which returns the number of failed arguments so we have
    # to look at the output and not rely on the return code.
    local prog=$(which ${progs[@]:-} 2>/dev/null | head -1 || true)
    echo -n "${prog}"
}

opt_usage archive_create <<END
Generic function for creating an archive file of a given type from the given list of source paths
and write it out to the requested destination directory. This function will intelligently figure out
the correct archive type based on the suffix of the destination file.

${PATH_MAPPING_SYNTAX_DOC}

You can also optionally exclude certain paths from being included in the resultant archive.
Unfortunately, each of the supported archive formats have different levels of support for excluding
via filename, glob or regex. So, to provide a common interface in archive_create, we pre-expand all
exclude paths using find(1).

This function also provides a uniform way of dealing with multiple source paths. All of the various
archive formats handle this differently so the uniformity is important. Essentially, any path
provided will be the name of a top-level entry in the archive with the entire directory structure
intact. This is essentially how tar works but different from how mksquashfs and mkiso normally
behave. 

A few examples will help clarify the behavior:

Example #1: Suppose you have a directory "a" with the files 1,2,3 and you call "archive_create a
dest.squashfs". archive_create will then yield the following:

    a/1
    a/2
    a/3

Example #2: Suppose you have these files spread out across three directories: a/1 b/2 c/3 and you
call "archive_create a b c dest.squashfs". archive_create will then yield the following:

    a/1
    b/2
    c/3

In the above examples note that the contents are consistent regardless of whether you provide a
single file, single directory or list of files or list of directories.
END
archive_create()
{
    $(opt_parse \
        "+best             | Use the best compression (level=9)." \
        "+bootable boot b  | Make the ISO bootable (ISO only)." \
        ":directory dir  d | Directory to cd into before archive creation." \
        ":exclude x        | List of paths to be excluded from archive." \
        "+fast             | Use the fastest compression (level=1)." \
        "+ignore_missing i | Ignore missing files instead of failing and returning non-zero." \
        ":level l=9        | Compression level (1=fast, 9=best)." \
        "+nice n           | Be nice and use non-parallel compressors and only a single core." \
        ":type t           | Override automatic type detection and use explicit archive type." \
        ":volume v         | Optional volume name to use (ISO only)." \
        "@srcs             | Source paths to archive.")

    # Parse positional arguments into a bashutils array. Then grab final argument
    # which is the destination.
    local dest=${srcs[${#srcs[@]}-1]}
    unset srcs[${#srcs[@]}-1]

    # Parse options
    local dest_real=$(readlink -m "${dest}")
    local dest_type=$(archive_type --type "${type}" "${dest}")
    local excludes=( ${exclude} )
    local cmd=""
   
    # Set the compression level
    if [[ ${best} -eq 1 ]]; then
        level=9
    elif [[ ${fast} -eq 1 ]]; then
        level=1
    fi

    edebug "Creating archive $(lval directory srcs dest dest_real dest_type excludes ignore_missing nice level)"
    mkdir -p "$(dirname "${dest}")"

    # List of files to clean-up
    local cleanup_files=()
    trap_add "array_not_empty cleanup_files && eunmount --all --recursive --delete \${cleanup_files[@]}"

    # If requested change directory first
    if [[ -n ${directory} ]]; then
        pushd "${directory}"
    fi

    # Create excludes file
    local exclude_file=$(mktemp --tmpdir archive-create-exclude-XXXXXX)
    cleanup_files+=( "${exclude_file}" )
    
    # Also exclude any of our sources which would incorrectly contain the destination
    local exclude_prefix=""
    if [[ ${dest_type} == iso ]]; then
        exclude_prefix="./"
    fi

    # In case including and excluding something excludes take precedence.
    if array_not_empty excludes; then
        array_remove srcs ${excludes[@]}
    fi
 
    # Always exclude the destination file. Need to canonicalize it and then remove
    # any illegal prefix characters (/, ./, ../)
    echo "${dest_real#${PWD}/}" | sed "s%^\(/\|./\|../\)%%" > ${exclude_file}

    # Provide a common API around excludes, use find to pre-expand all excludes.
    local entry
    for entry in "${srcs[@]}"; do

        # Parse optional ':' in the entry to be able to bind mount at alternative path. If not
        # present default to full path.
        local src="${entry%%:*}"
        local mnt="${entry#*:}"
        : ${mnt:=${src}}
        
        local src_norm=$(readlink -m "${src}")
        if [[ ${dest_real} == ${src_norm}/* ]]; then
            echo "${dest_real#${src_norm}/}" | sed "s%^\(/\|./\|../\)%%"
        fi

        if array_not_empty excludes; then
            find ${excludes[@]} -maxdepth 0 2>/dev/null | sed "s|^|${exclude_prefix}|" || true
        fi

    done | sort --unique >> "${exclude_file}"

    edebug $'Exclude File:\n'"$(cat ${exclude_file})"
    
    # In order to provide a common interface around all the archive formats we
    # must deal with inconsistencies in how multiple mount points are handled. 
    # mksquashfs would use the basename of each provided path, whereas mkisofs 
    # would merge them all into a flat directory while tar would preserve the
    # entire directory structure for each provided path. In order to make them
    # all work the same we bind mount each provided source into a single unified
    # directory. This isn't strictly necessary if a single source path is given
    # but it drastically simplifies the code to treat it the same and the overhead
    # of a bind mount is so small that it is justified by the simpler code path.
    local unified=$(mktemp --tmpdir --directory archive-create-unified-XXXXXX)
    cleanup_files+=( "${unified}" )
    opt_forward ebindmount_into ignore_missing -- "${unified}" "${srcs[@]}"

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

    # Change directory into single unified directory so all tools produce same output
    pushd "${unified}"
   
    # SQUASHFS
    if [[ ${dest_type} == squashfs ]]; then

        local mksquashfs_flags="-no-duplicates -no-recovery -no-exports -no-progress -noappend -wildcards"
        if [[ ${nice} -eq 1 ]]; then
            mksquashfs_flags+=" -processors 1"
        fi          

        cmd="mksquashfs . ${dest_real} ${mksquashfs_flags} -ef ${exclude_file}"

    # ISO
    elif [[ ${dest_type} == iso ]]; then

        local mkisofs
        if which mkisofs &> /dev/null ; then
            mkisofs=mkisofs
        elif which xorrisofs &> /dev/null ; then
            mkisofs=xorrisofs
        else
            eerror "no mkisofs-compatible program found"
            return 1
        fi

        cmd="${mkisofs} -r -V "${volume}" -cache-inodes -J -l -o "${dest_real}" -exclude-list ${exclude_file}"
        
        if [[ ${bootable} -eq 1 ]]; then
            cmd+=" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table"
        fi

        cmd+=" ."

    # TAR
    elif [[ ${dest_type} == tar ]]; then

        cmd="tar --exclude-from ${exclude_file} --create"
        local prog=$(archive_compress_program --nice=${nice} --type "${type}" "${dest_real}")
        if [[ -n "${prog}" ]]; then
            cmd+=" --file - . | ${prog} -${level} > ${dest_real}"
        else
            cmd+=" --file ${dest_real} ."
        fi

    # CPIO
    elif [[ ${dest_type} == cpio ]]; then
        
        cmd="find . | grep --invert-match --word-regexp --file ${exclude_file} | cpio --quiet -o -H newc"
        local prog=$(archive_compress_program --nice=${nice} --type "${type}" "${dest_real}")
        if [[ -n "${prog}" ]]; then
            cmd+=" | ${prog} -${level} > ${dest_real}"
        else
            cmd+=" --file ${dest_real}"
        fi
    fi

    # Execute command
    edebug "$(lval cmd)"
    eval "${cmd}" |& edebug

    # Pop out of the unified directory
    popd

    # If requested change directory first
    if [[ -n ${directory} ]]; then
        popd
    fi

    # Execute clean-up and clear the list so it won't get called again on trap teardown
    eunmount --all --recursive --delete ${cleanup_files[@]}
    unset cleanup_files
}

opt_usage archive_extract <<'END'
Extract a previously constructed archive image. This works on all of our supported archive types.
Also takes an optional list of find(1) glob patterns to limit what files are extracted from the
archive. If no files are provided it will extract all files from the archive.
END
archive_extract()
{
    $(opt_parse \
        "+ignore_missing i | Ignore missing files instead of failing and returning non-zero." \
        "+nice n           | Be nice and use non-parallel compressors and only a single core." \
        ":type t           | Override automatic type detection and use explicit archive type." \
        "src               | Source archive to extract." \
        "dest              | Location to place the files extracted from that archive.")
    
    local files=( "${@}" )
    local src_type=$(archive_type --type "${type}" "${src}")

    mkdir -p "${dest}"

    edebug "Extracting $(lval src dest src_type files ignore_missing)"

    # SQUASHFS + ISO
    # Neither of the tools for these archive formats support extracting a list
    # of globs patterns. So we mount them first and use find.
    if [[ ${src_type} == @(squashfs|iso) ]]; then

        # NOTE: Do this in a subshell to ensure traps perform clean-up.
        (
            local mnt=$(mktemp --tmpdir --directory archive-extract-XXXXXX)
            mount --read-only "${src}" "${mnt}"
            trap_add "eunmount --recursive --delete ${mnt}"

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

    # TAR or CPIO
    elif [[ ${src_type} == @(tar|cpio) ]]; then

        # By default the files to extract from the archive is all the files requested.
        # If files is an empty array this will evaluate to an empty string and all files
        # will be extracted.
        local includes=$(array_join files)

        # If ignore_missing flag was enabled filter out list of files in the archive to
        # only those which the caller requested. This will ensure we are essentially 
        # getting the intersection of actual files in the archive and the list of files 
        # the caller asked for (which may or may not actually be in the archive).
        #
        # NOTE: Replace newlines in output from archive_list to spaces so that they are 
        #       all on a single line. This will prevent problems when we later eval
        #       the command where newlines could cause the eval'd command to be 
        #       interpreted incorrectly.
        if array_not_empty files && [[ ${ignore_missing} -eq 1 ]]; then
            includes=$(archive_list "${src}" | grep -P "($(array_join files '|'))" | tr '\n' ' ' || true)

            # If includes is EMPTY there's nothing to do because none of the requested
            # files exist in the archive and we're ignoring missing files.
            if [[ -z ${includes} ]]; then
                edebug "Nothing to extract -- returning success"
                return 0
            fi
        fi

        # Do the actual extracting.
        local src_real=$(readlink -m "${src}")
        pushd "${dest}"
        
        local cmd=""
        local prog=$(archive_compress_program --nice=${nice} --type "${type}" "${src_real}")
        if [[ -n "${prog}" ]]; then
            cmd="${prog} --decompress --stdout < ${src_real} | "
        fi 

        if [[ ${src_type} == tar ]]; then
            cmd+="tar --extract --wildcards --no-anchored"
        else
            cmd+="cpio --quiet --extract --preserve-modification-time --make-directories --no-absolute-filenames --unconditional"
        fi

        # Give list of files to extract.
        cmd+=" ${includes}"

        # Conditionally feed it the archive file to extract via stdin.
        if [[ -z "${prog}" ]]; then
            cmd+=" < "${src_real}""
        fi

        edebug "$(lval cmd)"
        eval "${cmd}" |& edebug

        # cpio doesn't return an error if included files are missing. So do another check to see if
        # all requested files were found. Redirect stdout to /dev/null, so any errors (due to missing files)
        # will show up on STDERR. And that's the return code we'll propogate.
        #
        # NOTE: Purposefully NO quotes around ${includes} because if given -x="file1 file2" then 
        #       find would look for a file named "file1 file2" and fail.
        if [[ ${src_type} == cpio ]]; then
            find . ${includes} >/dev/null
        fi
        
        popd
    fi
}

opt_usage archive_list "Simple function to list the contents of an archive image."
archive_list()
{
    $(opt_parse \
        ":type t | Override automatic type detection and use explicit archive type." \
        "src     | Archive whose contents should be listed.")

    local src_type=$(archive_type --type "${type}" "${src}")
    edebug "File: $(file "${src}") $(lval type src_type)"

    # The code below calls out to the various archive format specific tools to dump
    # their contents. There's a little sed on each command's output to normalize the
    # tools output as much as possible to make them all have a consistent output.
    # Then we sort the whole thing at the end to ensure consistent ordering.
    if [[ ${src_type} == squashfs ]]; then
        unsquashfs -ls "${src}" | grep "^squashfs-root" | sed -e 's|^squashfs-root[/]*||' -e '/^\s*$/d'
    elif [[ ${src_type} == iso ]]; then
        # NOTE: Suppress stderr because isoinfo spews messages to stderr that can't be turned
        # of such as 'Setting input-charset to 'UTF-8' from locale.'
        isoinfo -J -i "${src}" -f 2>/dev/null | sed -e 's|^/||'
    elif [[ ${src_type} == tar ]]; then
        tar --list --file "${src}" | sed -e "s|^./||" -e '/^\/$/d' -e 's|/$||'
    elif [[ ${src_type} == cpio ]]; then

        # Do decompression first
        local cmd=""
        local prog=$(archive_compress_program --type "${type}" "${src}")
        if [[ -n "${prog}" ]]; then
            ${prog} --decompress --stdout < ${src} | cpio --quiet -it
        else
            cpio --quiet -it < "${src}"
        fi | sed -e "s|^.$||" 

    fi | sort --unique | sed '/^$/d'
}

opt_usage archive_append <<'END'
Append a given list of paths to an existing archive atomically. The way this is done atomically is
to do all the work on a temporary file and only move it over to the final file once all the append
work is complete. The reason we do this atomically is to ensure that we never have a corrupt or
half written archive which would be unusable.
END
archive_append()
{
    $(opt_parse \
        "+ignore_missing i | Ignore missing files instead of failing and returning non-zero." \
        "dest              | Archive to append files to." \
        "@srcs             | Source paths to archive.")

    edebug "Appending to archive $(lval srcs dest ignore_missing)"
    assert_exists "${dest}"

    # Mount the archive using overlayfs so we have a writeable mount point to copy the new files into.
    local unified=$(mktemp --tmpdir --directory archive-append-XXXXXX)
    overlayfs_mount "${dest}" "${unified}"
    trap_add "eunmount --all --recursive --delete ${unified}"

    # Now bind mount the new sources into the overlayfs mount point.
    opt_forward ebindmount_into ignore_missing -- "${unified}" "${srcs[@]}"

    # Write the changes back out to the original archive
    overlayfs_commit --no-dedupe "${unified}"
}

#---------------------------------------------------------------------------------------------------
# CONVERSIONS
#---------------------------------------------------------------------------------------------------

opt_usage archive_convert <<'END'
Convert given source file into the requested destination type. This is done by figuring out the
source and destination types using archive_type. Then it mounts the source file into a temporary
file, then calls archive_create on the temporary directory to write it out to the new destination
type.
END
archive_convert()
{
    $(opt_parse src dest)
    local src_type=$(archive_type "${src}")
    local dest_real=$(readlink -m "${dest}")
    edebug "Converting $(lval src src_type dest dest_real)"

    # Temporary directory for mounting
    (
        local mnt="$(mktemp --tmpdir --directory archive-convert-XXXXXX)"
        trap_add "eunmount --recursive --delete ${mnt}"

        # Mount (if possible) or extract the archive image if mounting is not supported.
        archive_mount "${src}" "${mnt}"

        # Now we can create a new archive from 'mnt'
        cd ${mnt}
        archive_create . "${dest_real}"
    )
}

#---------------------------------------------------------------------------------------------------
# MISC UTILITIES
#---------------------------------------------------------------------------------------------------

# Diff two or more archive images.
archive_diff()
{
    # Put body in a subshell to ensure traps perform clean-up.
    (
        local mnts=()
        local src
        for src in "${@}"; do
            
            local mnt="$(mktemp --tmpdir --directory archive-diff-XXXXXX)"
            trap_add "eunmount --recursive --delete ${mnt}"
            local src_type=$(archive_type "${src}")
            mnts+=( "${mnt}" )

            # Mount (if possible) or extract the archive if mounting is not supported.
            archive_mount "${src}" "${mnt}"
        done

        diff --recursive --unified "${mnts[@]}"
    )
}

opt_usage archive_mount <<'END'
Mount a given archive type to a temporary directory read-only if mountable and if not extract it to
the destination directory.
END
archive_mount()
{
    $(opt_parse src dest)
    local src_type=$(archive_type "${src}")

    # Create destination directory in case it doesn't exist
    mkdir -p "${dest}"

    # SQUASHFS or ISO can be directly mounted
    if [[ ${src_type} == @(squashfs|iso) ]]; then
        mount --read-only "${src}" "${dest}"
    
    # TAR+CPIO files need to be extracted manually :-[
    elif [[ ${src_type} == @(tar|cpio) ]]; then
        archive_extract "${src}" "${dest}"
    fi
}

return 0
