#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Filesystem
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage pushd <<'END'
Wrapper around pushd to suppress its noisy output.
END
pushd()
{
    builtin pushd "${@}" >/dev/null
}

opt_usage popd <<'END'
Wrapper around popd to suppress its noisy output.
END
popd()
{
    builtin popd "${@}" >/dev/null
}

opt_usage echmodown <<'END'
echmodown is basically chmod and chown combined into one function.
END
echmodown()
{
    $(opt_parse \
        "mode   | Filesystem mode bit flag to pass into chmod." \
        "owner  | Owner to pass into chown"                     \
        "@files | The files to perform the operations on."      \
    )

    chmod ${mode}  "${files[@]}"
    chown ${owner} "${files[@]}"
}

opt_usage efreshdir <<'END'
Recursively unmount the named directories and remove them (if they exist) then create new ones.

> **_NOTE:_** Unlike earlier implementations, this handles multiple arguments properly.
END
efreshdir()
{
    local mnt
    for mnt in "${@}"; do

        [[ -z "${mnt}" ]] && continue

        eunmount -a -r -d "${mnt}"
        mkdir -p ${mnt}

    done
}

opt_usage ebackup <<'END'
Copies the given file to *.bak if it doesn't already exist.
END
ebackup()
{
    $(opt_parse src)

    [[ -e "${src}" && ! -e "${src}.bak" ]] && cp -arL "${src}" "${src}.bak" || true
}

opt_usage erestore <<'END'
Copies files previously backed up via ebackup to their original location.
END
erestore()
{
    $(opt_parse src)

    [[ -e "${src}.bak" ]] && mv "${src}.bak" "${src}"
}

opt_usage directory_empty <<'END'
Check if a directory is empty
END
directory_empty()
{
    $(opt_parse dir)
    ! find "${dir}" -mindepth 1 -print -quit | grep -q .
}

opt_usage directory_not_empty <<'END'
Check if a directory is not empty
END
directory_not_empty()
{
    $(opt_parse dir)
    find "${dir}" -mindepth 1 -print -quit | grep -q .
}
