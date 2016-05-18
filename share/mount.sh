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
# Bind mount $1 over the top of $2.  Ebindmount works to ensure that all of your mounts are private
# so that we don't see different behavior between systemd machines (where shared mounts are the
# default) and everywhere else (where private mounts are the default)
#
# Source and destination MUST be the first two parameters of this function. You may specify any
# other mount options after them.
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
    mount --make-rprivate "$(stat -c %m "${src}")"
    emount --rbind "${@}" "${src}" "${dest}"
    mount --make-rprivate "${dest}" 
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
                die "Cannot remove $(lval directory=mnt) with mounted filesystems:\n$(array_join_nl mounts)"
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
