#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
opt_usage module_mount <<'END'
The mount module deals with various filesystem related mounting operations which generally add robustness and additional
features over and above normal `mount` operations.

Many functions in this module support the `PATH_MAPPING_SYNTAX` idiom. Path mapping syntax is a generic idiom used to
map one path to another using a colon to delimit source and destination paths. This is a convenient idiom often used by
functions which need to have a source file and use it in an alternative location inside the function. For example,
`/var/log/kern.log:kern.log` specifies a source file of `/var/log/kern.log` and a destination file of `kern.log`.

The path mapping syntax also supports referring to the contents of a directory rather than the directory itself using
scp like syntax. For example, if you wanted to refer to the contents of `/var/log` instead of the directory `/var/log`,
you would say `/var/log/.`. The trailing `/.` indicates the contents of the directory should be used rather than the
directory itself. You can also map the contents of that directory into an alternative destination path using
`/var/log/.:logs`.
END
#-----------------------------------------------------------------------------------------------------------------------

opt_usage emount_realpath <<'END'
Helper method to take care of resolving a given path or mount point to its realpath as well as remove any errant
'\040(deleted)' which may be suffixed on the path. This can happen if a device's source mount point is deleted while the
destination path is still mounted.
END
emount_realpath()
{
    $(opt_parse path)
    path="${path//\\040\(deleted\)/}"

    # Despite what readlink's manpage says, it can fail if the top-level path doesn't exist. In that case we'd still
    # want to return the original input path rather than an empty string.
    if ! readlink -m ${path} 2>/dev/null; then
        echo -n "${path}"
    fi
}

opt_usage emount_regex <<'END'
Echo the emount regex for a given path.
END
emount_regex()
{
    $(opt_parse path)

    local rpath
    rpath=$(emount_realpath "${path}")

    echo -n "(^| )(${path}|${rpath})(\\\\040\\(deleted\\))* "
}

opt_usage emount_count <<'END'
Echo the number of times a given directory is mounted.
END
emount_count()
{
    $(opt_parse path)
    list_mounts | grep --count --perl-regexp "$(emount_regex ${path})" || true
}

opt_usage emount_type <<'END'
Get the mount type of a given mount point.
END
emount_type()
{
    $(opt_parse path)
    path=$(emount_realpath ${path})
    list_mounts | grep --perl-regexp "$(emount_regex ${path})" | sort --unique | awk '{print $3}'
}

emounted()
{
    $(opt_parse path)
    [[ -z ${path} ]] && { edebug "Unable to resolve $(lval path) to check if mounted"; return 1; }
    [[ $(emount_count "${path}") -gt 0 ]]
}

opt_usage ebindmount <<'END'
Bind mount $1 over the top of $2. Ebindmount works to ensure that all of your mounts are private so that we don't see
different behavior between systemd machines (where shared mounts are the default) and everywhere else (where private
mounts are the default).

Source and destination MUST be the first two parameters of this function. You may specify any other mount options after
them.
END
ebindmount()
{
    $(opt_parse \
        "src" \
        "dest" \
        "@mount_options")

    # In order to avoid polluting other mount points that we recursively bind, we want to make sure that our mount
    # points are "private" (not seen by other mount namespaces). For example, that prevents one chroot from messing
    # with another's mounts.
    #
    # We must make sure the source mount is private first, because otherwise when we bind mount our location into our
    # mount namespace, it will start off as shared. And the shared version will be seen across _other_ mount
    # namespaces. Sure, we can subsequently mark it private in our own, but that action won't actually affect the
    # others.
    #
    # stat --format %m <file> lists the mount point that a particular file is on.
    local source_mountpoint
    source_mountpoint="$(stat -c %m "${src}")"

    # Then we look in the mount table to make sure we can access the mount point. We might not be able to see it if
    # we're in a chroot, for instance. NOTE: If /proc/self/mountinfo is not present then we need to mount it.
    if ! emounted /proc; then
        mount -t proc proc /proc
    fi
    local mountinfo_entry
    mountinfo_entry=$(awk '$5 == "'${source_mountpoint}'"' /proc/self/mountinfo)

    # Assuming we can see the mountpoint, make it private
    if [[ -n "${mountinfo_entry}" ]] ; then
        edebug "Making source mountpoint private $(lval source_mountpoint src dest)"
        mount --no-mtab --make-rprivate "${source_mountpoint}"
    fi

    # Last, do the bind mount and make the destination private as well
    emount --rbind "${@}" "${src}" "${dest}"
    mount --no-mtab --make-rprivate "${dest}"
}

opt_usage ebindmount_into <<'END'
Bind mount a list of paths into the specified directory. This function will iterate over all the source paths provided
and bind mount each source path into the provided destination directory. This function will merge the contents all into
the final destination path much like cp or rsync would but without the overhead of actually copying the files. To fully
cleanup the destination directory created by ebindmount_into you should use `eunmount --all --recursive`.

If there are files with the same name already in the destination directory the new version will be shadow mounted over
the existing version. This has the effect of merging the contents but allowing updated files to effectively replace what
is already in the directory. This property holds true for files as well as directories. Consider the following example:

```shell
echo "src1" >src1/file1
echo "src2" >src2/file1
ebindmount_into dest src1/. src2/.
cat dest/file1
src2
```

Notce that since `file1` existed in both `src1` and `src2` and we bindmount `src2` after `src1`, we will see the contents
of `src2/file1` inside `dest/file1` instead of `src1/file1`. The last one wins.

This example is true of directories as well with the important caveat that the directory's contents are still MERGED but
files shadow over one another. Consider the following example:

```shell
$ echo "src1" >src1/foo/file0
$ echo "src1" >src1/foo/file1
$ echo "src2" >src2/foo/file1
$ ebindmount_into dest src1/. src2/.
$ cat dest/foo/file1
src2
$ ls dest
foo/file0 foo/file1
```

Again, notice that since `file1` existed in both `src1/foo` and `src2/foo` and we bindmount `src2` after `src1`, we see
`src2` in the file instead of `src1`. Also, notice that the bindmount of the directory `src2/foo` did not hide the
contents of the existing `src1/foo` directory that we already bind mounted into dest.

`ebindmount_into` also supports `PATH_MAPPING_SYNTAX_DOC` described above.
END
ebindmount_into()
{
    $(opt_parse \
        "+ignore_missing i  | Ignore missing files instead of failing and returning non-zero." \
        "dest               | The destination directory to mount the specified list of paths into." \
        "@srcs              | The list of source paths to bind mount into the specified destination.")

    # Create destination directory if it doesn't exist.
    mkdir -p "${dest}"
    local dest_real
    dest_real=$(readlink -m "${dest}")

    # Iterate over each entry and parse optional ':' in the entry and then bind mount the source path into the specified
    # destination path.
    local entry
    for entry in "${srcs[@]}"; do

        local src="${entry%%:*}"
        local mnt="${entry#*:}"
        [[ -z ${mnt} ]] && mnt="${src}"
        edebug "$(lval entry src mnt)"

        if [[ ! -e "${src}" ]]; then
            if [[ ${ignore_missing} -eq 1 ]]; then
                edebug "Skipping missing file $(lval src)"
                continue
            else
                eerror "Missing file $(lval src)"
                return 1
            fi
        fi

        # If the requested source path is a directory which ends with '/.' then caller wants to bind mount the contents
        # of the directory rather than the directory itself.
        if [[ -d "${src}" && "${src: -2}" == "/." ]]; then

            local parent
            parent="$(readlink -m ${dest_real}/${src}/..)"
            pushd "${src}"

            # If the destination parent directory has already been created then we have to be careful not to shadow
            # mount over as we'd mask it's contents. So if it is there bind mount the contents of the src directory into
            # the parent directory. Otherwise we can simply bind mount the directory into thd destination directory.
            if [[ -d "${parent}" ]]; then
                local contents
                contents=$(find . -maxdepth 1 -printf '%P\n')
                if [[ -n "${contents}" ]]; then
                    opt_forward ebindmount_into ignore_missing -- "${parent}" ${contents}
                fi
            else
                ebindmount "." "${dest_real}/."
            fi

            popd

        # If the destination directory has already been created then we have to be careful not to shadow mount over as
        # we'd mask it's contents. So if it is there bind mount the contents of the src directory into the destination
        # directory.
        elif [[ -d "${dest_real}/${mnt}" ]]; then
            pushd "${src}"

            local contents
            contents=$(find . -maxdepth 1 -printf '%P\n')
            if [[ -n "${contents}" ]]; then
                opt_forward ebindmount_into ignore_missing -- "$(readlink -m ${dest_real}/${src})" ${contents}
            fi

            popd

        # Otherwise check if the source is a symlink and if it is just copy the symlink into the destination tree since
        # we do not follow symlinks. If it's not a symlink, then simply bindmount the source path into the destination
        # path. Taking care to create the proper tree structure inside destination path.
        else

            # If the source path is a symlink, just copy the symlink directly since we do not follow symlinks. There is
            # a 'continue' if it's a symlink because we do not want to do the ebindmount that is outside the if/else
            # statement that we normally do for non-symlinks.
            if [[ -L "${src}" ]]; then
                cp --no-dereference "${src}" "${dest_real}/${mnt}"
                continue
            elif [[ -d "${src}" ]]; then
                mkdir -p "${dest_real}/${mnt}"
            else
                mkdir -p "$(dirname "${dest_real}/${mnt}")"
                touch "${dest_real}/${mnt}"
            fi

            ebindmount "${src}" "${dest_real}/${mnt}"
        fi

    done
}

opt_usage emount <<'END'
Mount a filesystem.

**WARNING**: Do not use opt_parse in this function as then we don't properly pass the options into mount itself. Since
this is just a passthrough operation into mount you should see mount(8) manpage for usage.
END
emount()
{
    if edebug_enabled || [[ "${*}" =~ (^| )(-v|--verbose)( |$) ]]; then
        einfos "Mounting $*"
    fi

    mount "${@}"
}

eunmount_internal()
{
    $(opt_parse \
        "+verbose v | Verbose output.")

    local mnt mnt_type
    for mnt in "$@"; do

        # Skip if not mounted.
        emounted "${mnt}" || continue

        mnt_type=$(emount_type ${mnt})
        [[ ${verbose} -eq 1 ]] && einfo "Unmounting ${mnt} (${mnt_type})"

        # OVERLAYFS: Redirect unmount operation to overlayfs_unmount so all layers unmounted
        if [[ ${mnt_type} =~ overlay ]]; then
            overlayfs_unmount "${mnt}"
        else
            umount -l "$(emount_realpath "${mnt}")"
        fi
    done
}

opt_usage eunmount <<'END'
Recursively unmount a list of mount points. This function iterates over the provided argument list and will unmount each
provided mount point if it is mounted. It is not an error to try to unmount something which is already unmounted as
we're already in the desired state and this is more useful in cleanup code.
END
eunmount()
{
    $(opt_parse \
        "+verbose v   | Verbose output." \
        "+recursive r | Recursively unmount everything beneath mount points." \
        "+delete d    | Delete mount points after unmounting." \
        "+all a       | Unmount all copies of mount points instead of a single instance.")

    if edebug_enabled; then
        verbose=1
    fi

    local mnt
    for mnt in "$@"; do

        # If empty string just skip it
        [[ -z "${mnt}" ]] && continue

        edebug "Unmounting $(lval mnt recursive delete all)"

        # WHILE loop to **optionally** continue unmounting until no more matching mounts are detected. The body of the
        # while loop will break out when there are no more mounts to unmount. If -a=0 was passed in, then this will
        # always break after only a single iteration.
        while true; do

            # NOT RECURSIVE
            if [[ ${recursive} -eq 0 ]]; then

                # If it's not mounted break out of the loop otherwise unmount it.
                emounted "${mnt}" || break

                opt_forward eunmount_internal verbose -- "${mnt}"

            # RECURSIVE
            else

                # If this path is directly mounted or anything BENEATH it is mounted then proceed
                local matches=()
                matches=( $(efindmnt "${mnt}" | sort --unique --reverse) )
                array_empty matches && break

                # Optionally log what is being unmounted
                local nmatches=0
                nmatches=$(echo "${matches[@]}" | wc -l)
                [[ ${verbose} -eq 1 ]] && einfo "Recursively unmounting ${mnt} (${nmatches})"
                edebug "$(lval matches nmatches)"

                # Lazily unmount all mounts
                local match
                for match in "${matches[@]}"; do
                    opt_forward eunmount_internal verbose -- "${match}"
                done
            fi

            # If we're only unmounting a single instance BREAK out of the while loop.
            [[ ${all} -eq 0 ]] && break

        done

        # Optionally delete the mount point
        if [[ ${delete} -eq 1 && -e ${mnt} ]]; then

            [[ ${verbose} -eq 1 ]] && einfo "Deleting $(lval mnt recursive)"

            # Verify there are no mounts beneath this directory
            local mounts
            mounts=( $(efindmnt "${mnt}") )
            if ! array_empty mounts; then
                die "Cannot remove $(lval directory=mnt) with mounted filesystems:"$'\n'"$(array_join_nl mounts)"
            fi

            local rm_opts="--force"
            [[ ${recursive} -eq 1 ]] && rm_opts+=" --recursive"

            rm ${rm_opts} $(readlink -m "${mnt}")
        fi

    done
}

opt_usage list_mounts <<'END'
Platform agnostic mechanism for listing mounts.
END
list_mounts()
{
    if [[ ${__EBASH_OS} == Linux ]] ; then
        cat /proc/self/mounts

    elif [[ ${__EBASH_OS} == Darwin ]] ; then
        mount

    else
        die "Cannot list mounts for unsupported OS $(lval __EBASH_OS)"
    fi
}

opt_usage efindmnt <<'END'
Recursively find all mount points beneath a given root. This is like findmnt with a few additional enhancements:
- Automatically recusrive
- findmnt doesn't find mount points beneath a non-root directory
END
efindmnt()
{
    $(opt_parse path)

    # First check if the requested path itself is mounted
    if emounted "${path}"; then
        echo "${path}"
    fi

    # Now look for anything beneath that directory
    local rpath
    rpath=$(emount_realpath "${path}")
    list_mounts | grep --perl-regexp "(^| )(${path}|${rpath})[/ ]" | awk '{print $2}' | sed '/^$/d' || true
}
