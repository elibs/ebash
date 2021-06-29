#!/bin/bash

# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
opt_usage module_archive << 'END'
archive.sh is a generic module for dealing with various archive formats in a generic and consistent manner. It also
provides some really helpful and missing functionality not provided by upstream tools.

At present the list of supported archive formats is as follows:

- **SQUASHFS**: Squashfs is a compressed read-only filesystem for Linux. Squashfs intended for general read-only filesystem
use, for archival use and in constrained block device/memory systems where low overhead is needed. Squashfs images are
rapidly becoming a very common medium used throughout our build, install, test and upgrade code due to their high
compressibility, small resultant size, massive parallelization on both create and unpack and that they can be directly
mounted and booted into.

- **ISO**: An ISO image is an archive file of an optical disc, a type of disk image composed of the data contents from every
written sector on an optical disc, including the optical disc file system. The name ISO is taken from the ISO
9660 file system used with CD-ROM media, but what is known as an ISO image can contain other file systems.

- **TAR**: A tar file is an archive file format that may or may not be compressed. The archive data sets created by tar
contain various file system parameters, such as time stamps, ownership, file access permissions, and directory
organization. Our archive_compress_program function is used to generalize our use of tar so that compression format is
handled seamlessly based on the file extension in a way which picks the best compression program at runtime.

- **CPIO**: "cpio is a general file archiver utility and its associated file format. It is primarily installed on Unix-like
computer operating systems. The software utility was originally intended as a tape archiving program as part of the
Programmer's Workbench (PWB/UNIX), and has been a component of virtually every Unix operating system released
thereafter. Its name is derived from the phrase copy in and out, in close description of the program's use of standard
input and standard output in its operation. All variants of Unix also support other backup and archiving programs,
such as tar, which has become more widely recognized.[1] The use of cpio by the RPM Package Manager, in the initramfs
program of Linux kernel 2.6, and in Apple Computer's Installer (pax) make cpio an important archiving tool"
(https://en.wikipedia.org/wiki/Cpio).
END
#-----------------------------------------------------------------------------------------------------------------------

opt_usage archive_suffixes <<'END'
Echo a list of the supported archive suffixes for the optional provided type. If no type is given it returns a unified
list of all the supported archive suffixes supported. By default the list of the supported suffixes is echoed as a
whitespace separated list. But using the --pattern option it will instead echo the result in a pattern-list which is a
list of one or more patterns separated by a '|'. This can then be used more seamlessly inside extended glob matching.
END
archive_suffixes()
{
    $(opt_parse \
        "+pattern p  | Echo the results using pattern-list syntax instead of whitespace separated." \
        "+wildcard w | Add wildcard * before each suffix." \
        "@types      | Filter the list of supported suffixes to the given archive types.")

    local results=()
    if array_empty types; then
        types=( "squashfs" "iso" "tar" "cpio" )
    fi

    local entry
    for entry in "${types[@]}"; do
        if [[ ${entry} == "squashfs" ]]; then
            results+=( ".squashfs" )
        elif [[ ${entry} == "iso" ]]; then
            results+=( ".iso" )
        elif [[ ${entry} == "tar" ]]; then
            results+=( ".tar" ".tar.gz" ".tgz" ".taz" ".tar.bz2" ".tz2" ".tbz2" ".tbz" ".tar.xz" ".txz" ".tar.lz" ".tlz" )
        elif [[ ${entry} == "cpio" ]]; then
            results+=( ".cpio" ".cpio.gz" ".cgz" ".caz" ".cpio.bz2" ".cz2" ".cbz2" ".cbz" ".cpio.xz" ".cxz" ".cpio.lz" ".clz" )
        else
            die "Unsupported $(lval entry types)"
        fi
    done

    # If wildcard was requested replace each leading '.' with "*.'
    if [[ ${wildcard} -eq 1 ]]; then
        results=( "${results[@]/./*.}" )
    fi

    # If pattern-list was requested convert the result to a pattern-list. NOTE: Use sed here instead of array_join
    # because it is an order of magnitude faster, the array is well-formed without holes, and we don't need additional
    # functionality offered by array_join.
    if [[ ${pattern} -eq 1 ]]; then
        echo "${results[@]}" | sed -e 's/ /|/g'
    else
        echo "${results[@]}"
    fi
}

opt_usage archive_type <<'END'
Determine archive format based on the file suffix. You can override type detection by passing in explicit -t=type where
type is one of the supported file extension types (e.g. squashfs, iso, tar, tgz, cpio, cgz, etc). --no-die will make
archive_type output the type of archive or nothing, rather than dieing.
END
archive_type()
{
    $(opt_parse \
        ":type t  | Override automatic type detection and use explicit archive type." \
        "+die d=1 | die on error." \
        "src      | Archive file name.")

    # Allow overriding type detection based on suffix and instead use provided type providing it's a valid type we know
    # about. To unify the code as much as possible this accepts any of our known suffixes.
    if [[ -n ${type} ]]; then
        src=".${type}"
    fi

    # Detect type based on suffix
    local entry
    for entry in squashfs iso tar cpio; do
        if [[ ${src} == @($(archive_suffixes --pattern --wildcard ${entry})) ]]; then
            echo "${entry}"
            return 0
        fi
    done

    # If we got here then we never found a valid archive type.
    if [[ ${die} -eq 1 ]] ; then
        die "Unsupported fstype $(lval src)"
    fi
}

opt_usage archive_compress_program <<'END'
Determine the best compress programm to use based on the archive suffix.

Uses the following algorithm based on filename suffix:

    *.bz2|*.tz2|*.tbz2|*.tbz)
        use first available from ( lbzip2 pbzip2 bzip2 )
    *.gz|*.tgz|*.taz|*.cgz)
        use first available from ( pigz gzip )
    *.lz|*.xz|*.txz|*.tlz|*.cxz|*.clz)
        use first available from ( lzma xz )
END
archive_compress_program()
{
    $(opt_parse \
        "+nice n | Be nice and use non-parallel compressors and only a single core." \
        ":type t | Override automatic type detection and use explicit archive type." \
        "fname   | Archive file name.")

    # Allow overriding type detection based on suffix and instead use provided type providing it's a valid type we know
    # about. To unify the code as much as possible this accepts any of our known suffixes.
    if [[ -n ${type} ]]; then
        fname=".${type}"
    fi

    if [[ ${fname} == @(*.bz2|*.tz2|*.tbz2|*.tbz) ]]; then
        progs=( lbzip2 pbzip2 bzip2 )
        [[ ${nice} -eq 1 ]] && progs=( bzip2 )
    elif [[ ${fname} == @(*.gz|*.tgz|*.taz|*.cgz) ]]; then
        progs=( pigz gzip )
        [[ ${nice} -eq 1 ]] && progs=( gzip )
    elif [[ ${fname} == @(*.lz|*.xz|*.txz|*.tlz|*.cxz|*.clz) ]]; then
        progs=( lzma xz )
    else
        edebug "No suitable compress program for $(lval fname)"
        return 0
    fi

    # Look for matching installed program using which and head -1 to select the first matching program. If progs is
    # empty, this will call 'which ""' which is an error. which returns the number of failed arguments so we have to
    # look at the output and not rely on the return code.
    which "${progs[@]:-}" 2>/dev/null | head -1 || true
}

opt_usage tar_ignored_modified_files <<'END'
Tar has a pecularity with return codes that is inconsistent with the other archive formats. It returns 1 if any files
were modified during creation. This isn't something we want to guard against as it's extremely frequent when archiving
files for them to be modified during archival. Moreover, since none of the other archive formats have this behavior
ignoring this error helps to unify archive_create across all its supported formats.
END
tar_ignore_modified_files()
{
    try
    {
        command tar "${@}"
    }
    catch
    {
        rc=$?

        if [[ ${rc} -eq 1 ]]; then
            edebug "Ignoring tar error resulting from files being modified during archive creation"
            return 0
        else
            return ${rc}
        fi
    }
}

# NOTE: More advanced functions rely on bindmounting which only works on Linux
if [[ ${__EBASH_OS} != "Linux" ]] ; then
    return 0
fi

opt_usage archive_create <<'END'
Generic function for creating an archive file of a given type from the given list of source paths and write it out to
the requested destination directory. This function will intelligently figure out the correct archive type based on the
suffix of the destination file.

This function suports the `PATH_MAPPING_SYNTAX` as described in [mount](mount.md).

You can also optionally exclude certain paths from being included in the resultant archive. Unfortunately, each of the
supported archive formats have different levels of support for excluding via filename, glob or regex. So, to provide a
common interface in archive_create, we pre-expand all exclude paths using find(1).

This function also provides a uniform way of dealing with multiple source paths. All of the various archive formats
handle this differently so the uniformity is important. Essentially, any path provided will be the name of a top-level
entry in the archive with the entire directory structure intact. This is essentially how tar works but different from
how mksquashfs and mkiso normally behave.

A few examples will help clarify the behavior:

Example #1: Suppose you have a directory `a` with the files `1,2,3` and you call `archive_create a dest.squashfs`.
archive_create will then yield the following:

```shell
a/1
a/2
a/3
```

Example #2: Suppose you have these files spread out across three directories: `a/1` `b/2` `c/3` and you call
`archive_create a b c dest.squashfs`. `archive_create` will then yield the following:

```shell
a/1
b/2
c/3
```

In the above examples note that the contents are consistent regardless of whether you provide a single file, single
directory or list of files or list of directories.
END
archive_create()
{
    $(opt_parse \
        "+best             | Use the best compression (level=9)." \
        "+bootable boot b  | Make the ISO bootable (ISO only)." \
        "+delete           | Delete the source files after successful archive creation." \
        "+dereference      | Dereference (follow) symbolic links (tar only)." \
        ":directory dir  d | Directory to cd into before archive creation." \
        ":exclude x        | List of paths to be excluded from archive." \
        "+fast             | Use the fastest compression (level=1)." \
        "+ignore_missing i | Ignore missing files instead of failing and returning non-zero." \
        ":level l=9        | Compression level (1=fast, 9=best)." \
        "+nice n           | Be nice and use non-parallel compressors and only a single core." \
        ":type t           | Override automatic type detection and use explicit archive type." \
        ":volume v         | Optional volume name to use (ISO only)." \
        "dest              | Destination path for resulting archive." \
        "@srcs             | Source paths to archive.")

    # Parse options
    local dest_real="" dest_dname="" dest_name="" dtest_tmp="" dest_type="" excludes=() cmd=""
    dest_real=$(readlink -m "${dest}")
    dest_dname=$(dirname "${dest_real}")
    dest_name=$(basename "${dest_real}")
    dest_tmp="${dest_dname}/.pending-${dest_name}"
    dest_type=$(archive_type --type "${type}" "${dest}")
    excludes=( ${exclude} )

    # Set the compression level
    if [[ ${best} -eq 1 ]]; then
        level=9
    elif [[ ${fast} -eq 1 ]]; then
        level=1
    fi

    # Blow up if pass in --dereference flag for a non-tar format
    if [[ ${dereference} -eq 1 ]]; then
        assert_eq "${dest_type}" "tar" "--dereference option only valid for tar archive format"
    fi

    edebug "Creating archive $(lval directory srcs dest dest_real dest_dname dest_name dest_tmp dest_type excludes ignore_missing nice level)"
    mkdir -p "$(dirname "${dest}")"

    # List of files to clean-up
    local cleanup_files=( "${dest_tmp}" )
    trap_add "array_not_empty cleanup_files && eunmount --all --recursive --delete \${cleanup_files[@]}"

    # If requested change directory first
    if [[ -n ${directory} ]]; then
        pushd "${directory}"
    fi

    # Create excludes file
    local exclude_file=""
    exclude_file=$(mktemp --tmpdir archive-create-exclude-XXXXXX)
    cleanup_files+=( "${exclude_file}" )

    # Also exclude any of our sources which would incorrectly contain the destination
    local exclude_prefix=""
    if [[ ${dest_type} == iso ]]; then
        exclude_prefix="./"
    fi

    # In case including and excluding something excludes take precedence.
    if array_not_empty excludes; then
        array_remove srcs "${excludes[@]}"
    fi

    # Always exclude the destination file. Need to canonicalize it and then remove any illegal prefix characters (/, ./,
    # ../)
    echo "${dest_tmp#${PWD}/}" | sed "s%^\(/\|./\|../\)%%" > ${exclude_file}

    # Provide a common API around excludes, use find to pre-expand all excludes.
    local entry="" src="" mnt="" src_norm=""
    for entry in "${srcs[@]}"; do

        # Parse optional ':' in the entry to be able to bind mount at alternative path. If not present default to full
        # path.
        src="${entry%%:*}"
        mnt="${entry#*:}"
        : ${mnt:=${src}}

        src_norm=$(readlink -m "${src}")
        if [[ ${dest_tmp} == ${src_norm}/* ]]; then
            echo "${dest_tmp#${src_norm}/}" | sed "s%^\(/\|./\|../\)%%"
        fi

        if array_not_empty excludes; then
            find "${excludes[@]}" -maxdepth 0 2>/dev/null | sed "s|^|${exclude_prefix}|" || true
        fi

    done | sort --unique >> "${exclude_file}"

    edebug $'Exclude File:\n'"$(cat ${exclude_file})"

    # In order to provide a common interface around all the archive formats we must deal with inconsistencies in how
    # multiple mount points are handled. mksquashfs would use the basename of each provided path, whereas mkisofs would
    # merge them all into a flat directory while tar would preserve the entire directory structure for each provided
    # path. In order to make them all work the same we bind mount each provided source into a single unified directory.
    # This isn't strictly necessary if a single source path is given but it drastically simplifies the code to treat it
    # the same and the overhead of a bind mount is so small that it is justified by the simpler code path.
    local unified
    unified=$(mktemp --tmpdir --directory archive-create-unified-XXXXXX)
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

        cmd="mksquashfs . ${dest_tmp} ${mksquashfs_flags} -ef ${exclude_file}"

    # ISO
    elif [[ ${dest_type} == iso ]]; then

        local mkisofs
        if command_exists mkisofs; then
            mkisofs=mkisofs
        elif command_exists genisoimage; then
            mkisofs=genisoimage
        elif command_exists xorrisofs; then
            mkisofs=xorrisofs
        else
            eerror "no mkisofs-compatible program found"
            return 1
        fi

        cmd="${mkisofs} -r -V "${volume}" -cache-inodes -iso-level 3 -J -joliet-long -o "${dest_tmp}" -exclude-list ${exclude_file}"

        if [[ ${bootable} -eq 1 ]]; then
            cmd+=" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table"
        fi

        cmd+=" ."

    # TAR
    elif [[ ${dest_type} == tar ]]; then

        cmd="tar_ignore_modified_files --exclude-from ${exclude_file} --create"

        if [[ ${dereference} -eq 1 ]]; then
            cmd+=" --dereference"
        fi

        local prog
        prog=$(archive_compress_program --nice=${nice} --type "${type}" "${dest_tmp}")
        if [[ -n "${prog}" ]]; then
            cmd+=" --file - . | ${prog} -${level} > ${dest_tmp}"
        else
            cmd+=" --file ${dest_tmp} ."
        fi

    # CPIO
    elif [[ ${dest_type} == cpio ]]; then

        cmd="find . | grep --invert-match --word-regexp --file ${exclude_file} | cpio --quiet -o -H newc"
        local prog
        prog=$(archive_compress_program --nice=${nice} --type "${type}" "${dest_tmp}")
        if [[ -n "${prog}" ]]; then
            cmd+=" | ${prog} -${level} > ${dest_tmp}"
        else
            cmd+=" --file ${dest_tmp}"
        fi
    fi

    # Execute command
    edebug "$(lval cmd)"
    $(tryrc -r=archive_create_rc -o=archive_create_stdout -e=archive_create_stderr "eval ${cmd}")

    # Bootable ISO: Postprocess ISO to put it into hybrid mode. isohybrid modifies the ISO in-place to give it a MBR.
    # From http://www.syslinux.org/wiki/index.php?title=Isohybrid: ISO 9660 filesystems created by the mkisofs command
    # as described in the ISOLINUX article will boot via BIOS firmware, but only from optical media like CD, DVD, or BD.
    # The isohybrid feature enhances such filesystems by a Master Boot Record (MBR) for booting via BIOS from disk
    # storage devices like USB flash drives.
    if [[ ${archive_create_rc} -eq 0 && ${dest_type} == iso && ${bootable} -eq 1 ]]; then
        $(tryrc -r=archive_create_rc -o=isohybrid_stdout -e=isohybrid_stderr isohybrid "${dest_tmp}")
        archive_create_stdout+="${isohybrid_stdout}"
        archive_create_stderr+="${isohybrid_stderr}"
    fi

    # Pop out of the unified directory
    popd

    # If requested change directory
    if [[ -n ${directory} ]]; then
        popd
    fi

    # If we successfully created the archive then atomically move the temporary version to the final version.
    if [[ ${archive_create_rc} -eq 0 ]]; then
        edebug "Atomically moving $(lval dest_tmp dest_real)"
        mv "${dest_tmp}" "${dest_real}"
    fi

    # Execute clean-up and clear the list so it won't get called again on trap teardown
    eunmount --all --recursive --delete "${cleanup_files[@]}"
    unset cleanup_files

    # Propogate any errors
    if [[ ${archive_create_rc} -ne 0 ]]; then
        printf "${archive_create_stdout}"
        eerror "${archive_create_stderr}"
        return "${archive_create_rc}"
    fi

    # Delete source files if requested. Eunmount doesn't support path mapping syntax so strip it off of each path.
    if [[ ${delete} -eq 1 ]]; then
        eunmount --all --recursive --delete "${srcs[@]%%:*}"
    fi

    return 0
}

opt_usage archive_extract <<'END'
Extract a previously constructed archive image. This works on all of our supported archive types. Also takes an
optional list of find(1) glob patterns to limit what files are extracted from the archive. If no files are provided it
will extract all files from the archive.
END
archive_extract()
{
    $(opt_parse \
        "+ignore_missing i         | Ignore missing files instead of failing and returning non-zero." \
        "+nice n                   | Be nice and use non-parallel compressors and only a single core." \
        ":strip_components strip=0 | Strip this number of leading components from file names on extraction." \
        ":type t                   | Override automatic type detection and use explicit archive type." \
        "src                       | Source archive to extract." \
        "dest                      | Location to place the files extracted from that archive.")

    assert_num_ge "${strip_components}" "0" "--strip-components must be >= 0"

    local files=( "${@}" ) src_type="" dest_real=""
    src_type=$(archive_type --type "${type}" "${src}")
    mkdir -p "${dest}"
    dest_real=$(readlink -m "${dest}")

    edebug "Extracting $(lval src dest dest_real src_type files ignore_missing)"

    # SQUASHFS + ISO
    # Neither of the tools for these archive formats support extracting a list of globs patterns. So we mount them first
    # and use find.
    if [[ ${src_type} == @(squashfs|iso) ]]; then

        # NOTE: Do this in a subshell to ensure traps perform clean-up.
        (
            local mnt=""
            mnt=$(mktemp --tmpdir --directory archive-extract-XXXXXX)
            mount --read-only "${src}" "${mnt}"
            trap_add "eunmount --recursive --delete ${mnt}"

            cd "${mnt}"

            if array_empty files; then
                cp --archive --recursive . "${dest_real}"
            else

                local includes=( ${files[@]} )
                if [[ ${ignore_missing} -eq 1 ]]; then
                    includes=( $(find -wholename ./$(array_join files " -o -wholename ./")) )
                fi

                # If includes is EMPTY and we are ignoring missing files then there's nothing to do because none of the
                # requested files exist in the archive. In this case we can just return success. Otherwise if includes
                # is empty and we are not ignoring missing files then that's an error.
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
                cp --archive --recursive --parents "${includes[@]}" "${dest_real}"
            fi
        )

    # TAR or CPIO
    elif [[ ${src_type} == @(tar|cpio) ]]; then

        # By default the files to extract from the archive is all the files requested. If files is an empty array this
        # will evaluate to an empty string and all files will be extracted.
        local includes=""
        includes=$(array_join files)

        # If ignore_missing flag was enabled filter out list of files in the archive to only those which the caller
        # requested. This will ensure we are essentially getting the intersection of actual files in the archive and the
        # list of files the caller asked for (which may or may not actually be in the archive).
        #
        # NOTE: Replace newlines in output from archive_list to spaces so that they are all on a single line. This will
        #       prevent problems when we later eval the command where newlines could cause the eval'd command to be
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
        local src_real=""
        src_real=$(readlink -m "${src}")
        pushd "${dest}"

        local cmd="" prog=""
        prog=$(archive_compress_program --nice=${nice} --type "${type}" "${src_real}")
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
        $(tryrc -r=archive_extract_rc -o=archive_extract_stdout -e=archive_extract_stderr "eval ${cmd}")

        # cpio doesn't return an error if included files are missing. So do another check to see if all requested files
        # were found. Redirect stdout to /dev/null, so any errors (due to missing files) will show up on STDERR. And
        # that's the return code we'll propogate.
        #
        # NOTE: Purposefully NO quotes around ${includes} because if given -x="file1 file2" then find would look for a
        #       file named "file1 file2" and fail.
        if [[ ${src_type} == cpio ]]; then
            find . ${includes} >/dev/null
        fi

        popd

        # Propogate any errors
        if [[ ${archive_extract_rc} -ne 0 ]]; then
            printf "${archive_extract_stdout}"
            eerror "${archive_extract_stderr}"
            return "${archive_extract_rc}"
        fi
    fi

    # If the caller requested us to strip leading components from extracted paths then we have to do so now. We cannot
    # do this in a uniform way with the various archive formats because this is something only supported by tar. But it
    # is super useful so we support it generically across all archive formats.
    if [[ ${strip_components} -gt 0 ]]; then
        pushd "${dest_real}"

        # First we need to delete any files or empty directories less than the strip components value.
        find . -maxdepth ${strip_components} \( -type f -o -type d -empty \) -delete

        # The find command below will find all files and directories that are one path node below the strip component
        # depth. These are the ones which need to be moved up to the current directory (which is the new dest_real that
        # we extracted everything to). We add -print so that we can capture a list of the directories that we affected
        # so we can do a second pass to remove the orphaned directories afterwards.
        local move_level=0 orphans=()
        move_level=$((strip_components+1))
        orphans=( $(find .              \
            -mindepth ${move_level}     \
            -maxdepth ${move_level}     \
            -print0 -exec mv --backup=numbered {} . \; \
            | xargs --null --no-run-if-empty --max-lines=1 dirname | sort --unique)
        )

        # Now recursively delete the orhpans. There's no good way to do this inline so it's just easier and safer to
        # do it separately.
        edebug "Deleting $(lval orphans)"
        if array_not_empty orphans; then

            # rmdir is noisy about being unable to delete "." but it's not a failure. So use tryrc to capture the
            # return code but only show stderr if the find failed.
            $(tryrc -r=find_rc -o=find_out -e=find_err find "${orphans[@]}" -depth -type d -exec rmdir --parents {} \;)
            assert_zero "${find_rc}" "${find_err}"
        fi

        popd
    fi
}

opt_usage archive_list <<'END'
Simple function to list the contents of an archive image.
END
archive_list()
{
    $(opt_parse \
        ":type t | Override automatic type detection and use explicit archive type." \
        "src     | Archive whose contents should be listed.")

    local src_type
    src_type=$(archive_type --type "${type}" "${src}")
    edebug "File: $(file "${src}") $(lval type src_type)"

    # The code below calls out to the various archive format specific tools to dump their contents. There's a little sed
    # on each command's output to normalize the tools output as much as possible to make them all have a consistent
    # output. Then we sort the whole thing at the end to ensure consistent ordering.
    if [[ ${src_type} == squashfs ]]; then
        unsquashfs -ls "${src}" | grep "^squashfs-root" | sed -e 's|^squashfs-root[/]*||' -e '/^\s*$/d'
    elif [[ ${src_type} == iso ]]; then
        # NOTE: Suppress stderr because isoinfo spews messages to stderr that can't be turned
        # of such as 'Setting input-charset to 'UTF-8' from locale.'
        isoinfo -J -i "${src}" -f 2>/dev/null | sed -e 's|^/||'

    # TAR
    elif [[ ${src_type} == tar ]]; then

        # Do decompression first
        local cmd="" prog=""
        prog=$(archive_compress_program --type "${type}" "${src}")
        if [[ -n "${prog}" ]]; then
            cmd="${prog} --decompress --stdout < ${src} | "
        fi

        # Build up the rest of the command to execute.
        cmd+="tar --list"
        [[ -z "${prog}" ]] && cmd+=" --file \"${src}\""
        cmd+=" | sed -e 's|^./||' -e '/^\/$/d' -e 's|/$||'"
        edebug "$(lval cmd)"
        eval "${cmd}"

    # CPIO
    elif [[ ${src_type} == cpio ]]; then

        # Do decompression first
        local cmd="" prog=""
        prog=$(archive_compress_program --type "${type}" "${src}")
        if [[ -n "${prog}" ]]; then
            cmd="${prog} --decompress --stdout < ${src} | "
        fi

        # Build up the rest of the command to execute.
        cmd+="cpio --quiet -it"
        [[ -z "${prog}" ]] && cmd+=" < \"${src}\""
        cmd+=" | sed -e 's|^.$||'"
        edebug "$(lval cmd)"
        eval "${cmd}"

    fi | sort --unique | sed '/^$/d'
}

opt_usage archive_append <<'END'
Append a given list of paths to an existing archive atomically. The way this is done atomically is to do all the work on
a temporary file and only move it over to the final file once all the append work is complete. The reason we do this
atomically is to ensure that we never have a corrupt or half written archive which would be unusable. If the destination
archive does not exist this will implicitly call archive_create much like 'cat foo >> nothere'.

This function suports the `PATH_MAPPING_SYNTAX` as described in [mount](mount.md).

> **_NOTE:_** The implementation of this function purposefully doesn't use native `--append` functions in the archive
formats as they do not all support it. The ones which do support append do not implement in a remotely sane manner. You
might ask why we don't use overlayfs for this. First, overlayfs with bindmounting and chroots on older kernels causes
some serious problems wherein orphaned mounts become unmountable and the file systems containing them cannot be
unmounted later due to reference counts not being freed in the kernel. Additionally, if compression is used (which it
almost always is) we are forced to decompress and recompress the archive regardless so overlayfs doesn't save us
anything. If you're really concerned about performance just ensure TMPDIR is in memory as that is where all the work is
performed.
END
archive_append()
{
    $(opt_parse \
        "+best             | Use the best compression (level=9)." \
        "+bootable boot b  | Make the ISO bootable (ISO only)." \
        "+delete           | Delete the source files after successful archive creation." \
        "+dereference      | Dereference (follow) symbolic links (tar only)." \
        "+fast             | Use the fastest compression (level=1)." \
        "+ignore_missing i | Ignore missing files instead of failing and returning non-zero." \
        ":level l=9        | Compression level (1=fast, 9=best)." \
        "+nice n           | Be nice and use non-parallel compressors and only a single core." \
        ":volume v         | Optional volume name to use (ISO only)." \
        "dest              | Archive to append files to." \
        "@srcs             | Source paths to append to the archive.")

    # Parse options
    local dest_name="" dest_real=""
    dest_name=$(basename "${dest}")
    dest_real=$(readlink -m "${dest}")

    # If the destination to append to doesn't exist reroute this call to archive_append instead
    # of blowing up.
    if [[ ! -e "${dest}" ]]; then
        edebug "Destination archive doesn't exist -- forwarding call to archive_create"
        opt_forward archive_create best bootable delete dereference fast ignore_missing level nice volume -- "${dest}" "${srcs[@]}"
        return 0
    fi

    edebug "Appending to archive $(lval dest srcs ignore_missing)"

    # Extract the archive into tmpfs directory
    local unified
    unified=$(mktemp --tmpdir --directory archive-append-unified-XXXXXX)
    opt_forward archive_extract nice -- "${dest}" "${unified}"

    # Bind mount all src paths being appended to the archive into unified directory.
    opt_forward ebindmount_into ignore_missing -- "${unified}" "${srcs[@]}"
    trap_add "eunmount --recursive --delete ${unified}"

    # Create an archive of the unified directory. It's important that this temporary file:
    # 1) Is created in the same directory as the final destination we will move it to in order to guarantee atomicity.
    # 2) Ends in the same exact suffix as the original file so that we'll use the correct compression.
    #
    # Note: if src_name contains any captiol X's, it will either cause mktemp to fail completely or put the randomness
    # in the wrong place. Converting to lowercase solves this problem.
    local appended
    appended=$(mktemp $(dirname ${dest_real})/archive-append-XXXXXX-${dest_name,,})
    opt_forward archive_create best bootable dereference fast ignore_missing level nice volume -- "${appended}" "${unified}/."

    # Now move the append archive over the original.
    mv "${appended}" "${dest}"
    eunmount --recursive --delete "${unified}"

    # Delete source files if requested. Eunmount doesn't support path mapping syntax so strip it off of each path.
    if [[ ${delete} -eq 1 ]]; then
        eunmount --all --recursive --delete "${srcs[@]%%:*}"
    fi
}

#-----------------------------------------------------------------------------------------------------------------------
# CONVERSIONS
#-----------------------------------------------------------------------------------------------------------------------

opt_usage archive_convert <<'END'
Convert given source file into the requested destination type. This is done by figuring out the source and destination
types using archive_type. Then it mounts the source file into a temporary file, then calls archive_create on the
temporary directory to write it out to the new destination type.
END
archive_convert()
{
    $(opt_parse src dest)

    local src_type="" dest_real=""
    src_type=$(archive_type "${src}")
    dest_real=$(readlink -m "${dest}")
    edebug "Converting $(lval src src_type dest dest_real)"

    # Temporary directory for mounting
    (
        local mnt=""
        mnt="$(mktemp --tmpdir --directory archive-convert-XXXXXX)"
        trap_add "eunmount --recursive --delete ${mnt}"

        # Mount (if possible) or extract the archive image if mounting is not supported.
        archive_mount "${src}" "${mnt}"

        # Now we can create a new archive from 'mnt'
        cd ${mnt}
        archive_create "${dest_real}" .
    )
}

#-----------------------------------------------------------------------------------------------------------------------
# MISC UTILITIES
#-----------------------------------------------------------------------------------------------------------------------

opt_usage archive_diff <<'END'
Diff two or more archive images.
END
archive_diff()
{
    # Put body in a subshell to ensure traps perform clean-up.
    (
        local mnts=() src="" mnt="" src_type=""
        for src in "${@}"; do

            mnt="$(mktemp --tmpdir --directory archive-diff-XXXXXX)"
            trap_add "eunmount --recursive --delete ${mnt}"
            src_type=$(archive_type "${src}")
            mnts+=( "${mnt}" )

            # Mount (if possible) or extract the archive if mounting is not supported.
            archive_mount "${src}" "${mnt}"
        done

        diff --recursive --unified "${mnts[@]}"
    )
}

opt_usage archive_mount <<'END'
Mount a given archive type to a temporary directory read-only if mountable and if not extract it to the destination
directory.
END
archive_mount()
{
    $(opt_parse src dest)

    local src_type=""
    src_type=$(archive_type "${src}")

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
