#!/bin/bash
#
# Copyright 2011-2016, SolidFire, Inc. All rights reserved.
#

opt_usage emount_realpath <<'END'
Helper method to take care of resolving a given path or mount point to its realpath as well as
remove any errant '\040(deleted)' which may be suffixed on the path. This can happen if a device's
source mount point is deleted while the destination path is still mounted.
END
emount_realpath()
{
    $(opt_parse path)
    path="${path//\\040\(deleted\)/}"

    # Despite what readlink's manpage says, it can fail if the
    # top-level path doesn't exist. In that case we'd still want
    # to return the original input path rather than an empty string.
    if ! readlink -m ${path} 2>/dev/null; then
        echo -n "${path}"
    fi
}

opt_usage emount_regex "Echo the emount regex for a given path"
emount_regex()
{
    $(opt_parse path)
    echo -n "(^| )${path}(\\\\040\\(deleted\\))* "
}

opt_usage emount_count "Echo the number of times a given directory is mounted."
emount_count()
{
    $(opt_parse path)
    path=$(emount_realpath ${path})
    local num_mounts=$(list_mounts | grep --count --perl-regexp "$(emount_regex ${path})" || true)
    echo -n ${num_mounts}
}

opt_usage emount_type "Get the mount type of a given mount point."
emount_type()
{
    $(opt_parse path)
    path=$(emount_realpath ${path})
    list_mounts | grep --perl-regexp "$(emount_regex ${path})" | sort --unique | awk '{print $3}'
}

emounted()
{
    $(opt_parse path)
    path=$(emount_realpath ${path})
    [[ -z ${path} ]] && { edebug "Unable to resolve $(lval path) to check if mounted"; return 1; }

    [[ $(emount_count "${path}") -gt 0 ]]
}

opt_usage ebindmount <<'END'
Bind mount $1 over the top of $2.  Ebindmount works to ensure that all of your mounts are private
so that we don't see different behavior between systemd machines (where shared mounts are the
default) and everywhere else (where private mounts are the default)

Source and destination MUST be the first two parameters of this function. You may specify any
other mount options after them.
END
ebindmount()
{
    $(opt_parse \
        "src" \
        "dest" \
        "@mount_options")

    # In order to avoid polluting other mount points that we recursively bind, we want to make sure
    # that our mount points are "private" (not seen by other mount namespaces).  For example, that
    # prevents one chroot from messing with another's mounts.
    #
    # We must make sure the source mount is private first, because otherwise when we bind mount our
    # location into our mount namespace, it will start off as shared.  And the shared version will
    # be seen across _other_ mount namespaces.  Sure, we can subsequently mark it private in our
    # own, but that action won't actually affect the others.
    #
    # stat --format %m <file> lists the mount point that a particular file is on.
    local source_mountpoint="$(stat -c %m "${src}")"

    # Then we look in the mount table to make sure we can access the mount point.  We might not be
    # able to see it if we're in a chroot, for instance.
    local mountinfo_entry=$(awk '$5 == "'${source_mountpoint}'"' /proc/self/mountinfo)

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
Bind mount a list of paths into the specified directory. The syntax for the source files to bind
mount support specifying an alternate path to mount the source file at using a colon to delimit
the source path and the desired bind mount path inside the directory. For example, 
'/var/log/kern.log:kern.log' would mount the file '/var/log/kern.log' into the top of the directory
at path 'kern.log' instead of using the fully qualified path beneath the destination directory.
Without using the ':' mounting syntax, the destination directory would have this file located at
'var/log/kern.log'.

The path mapping syntax also supports bind mounting the contents of a directory rather than a
directory itself at an alternative path using scp like syntax. For example, if you wanted the
contents of /var/log mounted into a directory, you could use this syntax: '/var/log/.'. The
trailing '/.' indicates the contents of the directory should be bind mounted rather than the
directory itself. You can also map that into a different path via '/var/log/.:logs'.
END
ebindmount_into()
{
    $(opt_parse \
        "+ignore_missing i  | Ignore missing files instead of failing and returning non-zero." \
        "dest               | The destination directory to mount the specified list of paths into." \
        "@srcs              | The list of source paths to bind mount into the specified destination.")

    # Create destination directory if it doesn't exist.
    mkdir -p "${dest}"

    # This flag is used to keep track if we've bind mounted the contents of a source path 
    # into the target directory or not. This is an optimization to avoid having to bind
    # mount all the contents of a directory if only a single directory's contents are 
    # being bind mounted. If the caller passes in 'foo/.' and 'bar/.' then we can do 
    # a very efficient bind mount of foo/. into the target directory, and then we only
    # have to iterate and bind mount the contents of bar instead of both foo and bar.
    local flatten=0

    # Iterate over each entry and parse optional ':' in the entry and then bind mount
    # the source path into the specified destination path.
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

        # Create path inside unified directory then bind mount it read-only.
        #
        # NOTE: If the path ends with '/.' then we want the contents of the directory
        # rather than the directory itself
        if [[ -d "${src}" && "${src: -2}" == "/." ]]; then

            # If we've already bind mounted the contents of a directory then we must flatten
            # the contents of this directory manually to avoid shadow mounting over the
            # earlier one.
            if [[ ${flatten} -eq 1 ]]; then
                pushd "${src}"
                opt_forward ebindmount_into ignore_missing -- "$(readlink -m ${dest}/${src}/..)" $(find . -maxdepth 1 -printf '%P\n')
                popd
            else
                pushd "${src}"
                ebindmount "." "${dest}/."
                popd
            fi

            flatten=1
            continue

        elif [[ -d "${src}" ]]; then
            mkdir -p "${dest}/${mnt}"
        else
            mkdir -p "$(dirname "${dest}/${mnt}")"
            touch "${dest}/${mnt}"
        fi

        ebindmount "${src}" "${dest}/${mnt}"
    done
}

opt_usage emount <<'END'
Mount a filesystem.

WARNING: Do not use opt_parse in this function as then we don't properly pass the options into mount
         itself. Since this is just a passthrough operation into mount you should see mount(8)
         manpage for usage.
END
emount()
{
    if edebug_enabled || [[ "${@}" =~ (^| )(-v|--verbose)( |$) ]]; then
        einfos "Mounting $@"
    fi
    
    mount "${@}"
}

eunmount_internal()
{
    $(opt_parse \
        "+verbose v | Verbose output.")

    local mnt
    for mnt in $@; do

        # Skip if not mounted.
        emounted "${mnt}" || continue

        local mnt_type=$(emount_type ${mnt})
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
Recursively unmount a list of mount points. This function iterates over the provided argument list
and will unmount each provided mount point if it is mounted. It is not an error to try to unmount
something which is already unmounted as we're already in the desired state and this is more useful
in cleanup code. 
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
    for mnt in $@; do

        # If empty string just skip it
        [[ -z "${mnt}" ]] && continue

        edebug "Unmounting $(lval mnt recursive delete all)"
        
        # WHILE loop to **optionally** continue unmounting until no more matching
        # mounts are detected. The body of the while loop will break out when 
        # there are no more mounts to unmount. If -a=0 was passed in, then this
        # will always break after only a single iteration.
        while true; do

            # NOT RECURSIVE
            if [[ ${recursive} -eq 0 ]]; then

                # If it's not mounted break out of the loop otherwise unmount it.
                emounted "${mnt}" || break

                opt_forward eunmount_internal verbose -- "${mnt}"
        
            # RECURSIVE 
            else

                # If this path is directly mounted or anything BENEATH it is mounted then proceed
                local matches=( $(efindmnt "${mnt}" | sort --unique --reverse) )
                array_empty matches && break
                
                # Optionally log what is being unmounted
                local nmatches=$(echo "${matches[@]}" | wc -l)
                [[ ${verbose} -eq 1 ]] && einfo "Recursively unmounting ${mnt} (${nmatches})"
                edebug "$(lval matches nmatches)"

                # Lazily unmount all mounts
                local match
                for match in ${matches[@]}; do
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
            local mounts=( $(efindmnt "${mnt}") )
            if ! array_empty mounts; then
                die "Cannot remove $(lval directory=mnt) with mounted filesystems:"$'\n'"$(array_join_nl mounts)"
            fi

            local rm_opts="--force"
            [[ ${recursive} -eq 1 ]] && rm_opts+=" --recursive"

            rm ${rm_opts} "${mnt}"
        fi

    done
}

# Platform agnostic mechanism for listing mounts.
list_mounts()
{
    if [[ ${__BU_OS} == Linux ]] ; then
        cat /proc/self/mounts

    elif [[ ${__BU_OS} == Darwin ]] ; then
        mount

    else
        die "Cannot list mounts for unsupported OS $(lval __BU_OS)"
    fi
}

opt_usage efindmnt <<'END'
Recursively find all mount points beneath a given root. This is like findmnt with a few additional
enhancements:
    1. Automatically recusrive
    2. findmnt doesn't find mount points beneath a non-root directory
END
efindmnt()
{
    $(opt_parse path)
    path=$(emount_realpath ${path})

    # First check if the requested path itself is mounted
    emounted "${path}" && echo "${path}" || true

    # Now look for anything beneath that directory
    list_mounts | grep --perl-regexp "(^| )${path}[/ ]" | awk '{print $2}' | sed '/^$/d' || true
}

return 0
