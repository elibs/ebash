#!/bin/bash
# vim: textwidth=120 colorcolumn=120
#
# Copyright 2011-2020, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage emetadata <<'END'
`emetadata` is used to output various metadata information about the provided file to STDOUT. By default this outputs a
number of common metadata and digest information about the provided file such as Filename, MD5, Size, SHA1, SHA256, etc.
It can also optionally emit a bunch of Git related metadata using the `--git` option. This will then emit additional
fields such as `GitOriginUrl`, `GitBranch`, `GitVersion`, and `GitCommit`. Finally, all additional arugments provided
after the filename are interpreted as additional `tag=value` fields to emit into the output.

Here is example output:

```shell
BuildDate=2020-11-25T03:36:44UTC
Filename=foo
GitBranch=develop
GitCommit=f59a8535afd05b816cf891ec09bddd19fca92ebd
GitOriginUrl=http://github.com/elibs/ebash
GitVersion=v1.6.4
MD5=864ec6157c1eea88acfef44d0f34d219
SHA1=75490a32967169452c10c937784163126c4e9753
SHA256=8297aefe5bb7319ab5827169fce2e664fe9cd7b88c9b31c40658ab55fcae3bfe
Size=2192793069
```
END
emetadata()
{
    $(opt_parse \
        "+build_date  b=1   | Include the current UTC date as BuildDate." \
        "+git         g=1   | Include common Git metadata such as GitBranch, GitCommit, GitOriginUrl, GitVersion." \
        ":keyphrase k       | The keyphrase to use for the specified private key." \
        ":private_key p     | Also check the PGP signature based on this private key." \
        "path               | Path of the filename to generate metadata for." \
        "@entries           | Additional tag=value entries to emit.")

    local rpath
    rpath=$(readlink -m "${path}")
    assert_exists "${rpath}" "${path}"

    {
        echo "Filename=$(basename ${path})"
        echo "Size=$(stat --printf="%s" "${rpath}")"

        # Optionally include BuildDate
        if [[ "${build_date}" -eq 1 ]]; then
            echo "BuildDate=$(date "+%FT%T%Z")"
        fi

        # Optionally include Git metadata if Git command is installed and we're in a git working tree.
        if [[ "${git}" -eq 1 ]] && command_exists git && git rev-parse --is-inside-work-tree &>/dev/null; then
            echo "GitOriginUrl=$(git config --get remote.origin.url || true)"
            echo "GitBranch=$(git rev-parse --abbrev-ref HEAD)"
            echo "GitVersion=$(git describe --always --tags --match "v*.*.*" --abbrev=10)"
            echo "GitCommit=$(git rev-parse HEAD)"
        fi

        # Optionally add in any additional tag=value entries
        local entry
        for entry in "${entries[@]:-}"; do
            [[ -z ${entry} ]] && continue

            local _tag="${entry%%=*}"
            : ${_tag:=${entry}}
            local _val="${entry#*=}"
            _tag=${_tag#%}

            echo "${_tag}=${_val}"
        done

        # Now output MD5, SHA256, SHA512
        local ctype
        for ctype in MD5 SHA256 SHA512; do
            echo "${ctype}=$(eval ${ctype,,}sum "${rpath}" | awk '{print $1}')"
        done

        # If PGP signature is NOT requested we can simply return
        [[ -n ${private_key} ]] || return 0

        # Needs to be in /tmp rather than using $TMPDIR because gpg creates a socket in this directory and the complete
        # path can't be longer than 108 characters. gpg also expands relative paths, so no getting around it that way.
        local gpg_home
        gpg_home=$(mktemp --directory /tmp/gpghome-XXXXXX)
        trap_add "rm -rf ${gpg_home}"

        # If using GPG 2.1 or higher, start our own gpg-agent. Otherwise, GPG will start one and leave it running.
        local gpg_version
        gpg_version=$(gpg --version 2>/dev/null | awk 'NR==1{print $NF}')
        if compare_version "${gpg_version}" ">=" "2.1"; then
            local agent_command="gpg-agent --homedir ${gpg_home} --quiet --daemon --allow-loopback-pinentry"
            ${agent_command}
            trap_add "pkill -f \"${agent_command}\""
        fi

        # Import that into temporary secret keyring
        local keyring="" keyring_command=""
        keyring=$(mktemp --tmpdir emetadata-keyring-XXXXXX)
        trap_add "rm --force ${keyring}"

        keyring_command="--no-default-keyring --secret-keyring ${keyring}"
        if compare_version "${gpg_version}" ">=" "2.1"; then
            keyring_command+=" --pinentry-mode loopback"
        fi
        GPG_AGENT_INFO="" GNUPGHOME="${gpg_home}" gpg ${keyring_command} --batch --import ${private_key} |& edebug

        # Get optional keyphrase
        local keyphrase_command=""
        [[ -z ${keyphrase} ]] || keyphrase_command="--batch --passphrase ${keyphrase}"

        # Output PGPSignature encoded in base64
        echo "PGPKey=$(basename ${private_key})"
        echo "PGPSignature=$(GPG_AGENT_INFO="" GNUPGHOME="${gpg_home}" gpg --no-tty --yes ${keyring_command} --sign --detach-sign --armor ${keyphrase_command} --output - ${rpath} 2>/dev/null | base64 --wrap 0)"

    } | sort
}

opt_usage emetadata_check <<'END'
`emetadata_check` is used to validate an exiting source file against a companion *.meta file which contains various
checksum fields. The list of checksums is optional but at present the supported fields we inspect are: `Filename`,
`Size`, `MD5`, `SHA1`, `SHA256`, `SHA512`, `PGPSignature`.

For each of the above fields, if they are present in the .meta file, validate it against the source file. If any of them
fail this function returns non-zero. If NO validators are present in the info file, this function returns non-zero.
END
emetadata_check()
{
    $(opt_parse \
        "+quiet q      | If specified, produce no output. Return code reflects whether check was good or bad." \
        ":public_key p | Path to a PGP public key that can be used to validate PGPSignature in .meta file."     \
        "path")

    local rpath="" meta=""
    rpath=$(readlink -m "${path}")
    meta="${path}.meta"
    assert_exists "${rpath}" "${path}" "${meta}"

    local metapack="" digests=() validated=() expect="" actual="" ctype="" rc=0 pgpsignature=""
    pack_set metapack $(cat "${meta}")
    pgpsignature=$(pack_get metapack PGPSignature | base64 --decode)

    # Figure out what digests we're going to validate
    for ctype in Size MD5 SHA1 SHA256 SHA512; do
        pack_contains metapack "${ctype}" && digests+=( "${ctype}" )
    done
    [[ -n ${public_key} && -n ${pgpsignature} ]] && digests+=( "PGP" )

    if edebug_enabled; then
        edebug "Verifying integrity of $(lval path metadata=digests)"
        pack_print metapack |& edebug
    fi

    if [[ ${quiet} -eq 0 ]]; then
        einfo "Verifying integrity of $(basename ${path})"
        eprogress --style einfos "$(lval metadata=digests)"
    fi

    # Fail if there were no digest validation fields to check
    if array_empty digests; then
        die "No digest validation fields found: $(lval path)"
    fi

    # Callback function for use in the below block of code. The reason we can't just call die() inline when one of the
    # associated checks fail is because they are backgrounded processes. Calling die() in backgrounded processes
    # sometimes causes glibc stack smashing corruption.
    fail()
    {
        EMSG_PREFIX="" emsg "${COLOR_ERROR}" "   -" "ERROR" "$@"
        exit 1
    }

    # Now validate all digests we found
    local pids=()
    local ctype
    for ctype in ${digests[@]}; do

        expect=$(pack_get metapack ${ctype})

        if [[ ${ctype} == "Size" ]]; then
            actual=$(stat --printf="%s" "${rpath}")
            if [[ "${expect}" != "${actual}" ]]; then
                fail "Size mismatch: $(lval path expect actual)"
            fi
        elif [[ ${ctype} == @(MD5|SHA1|SHA256|SHA512) ]]; then
            actual=$(eval ${ctype,,}sum ${rpath} | awk '{print $1}')
            if [[ "${expect}" != "${actual}" ]]; then
                fail "${ctype} mismatch: $(lval path expect actual)"
            fi
        elif [[ ${ctype} == "PGP" && -n ${public_key} && -n ${pgpsignature} ]]; then

            # Setup a cgroup to track the gpg agent that we're going to spawn so we can ensure it gets killed. If
            # cgroups are not supported, then we'll fallback to using ekill below.
            local cgroup=""
            if cgroup_supported ; then
                cgroup="ebash/$$"
                trap_add "cgroup_kill_and_wait ${cgroup} ; cgroup_destroy -r ${cgroup}"
                cgroup_create ${cgroup}
            fi

            (
                # Move this subshell into the cgroup that we're going to kill so that the gpg agent we start gets
                # killed. If cgroups are not supported then use simpler ekilltree as a fallback.
                if [[ -n "${cgroup}" ]]; then
                    cgroup_move ${cgroup} ${BASHPID}
                else
                    trap_add "ekilltree ${BASHPID}"
                fi

                local keyring
                keyring=$(mktemp --tmpdir emetadata-keyring-XXXXXX)
                trap_add "rm --force ${keyring}"
                GPG_AGENT_INFO="" gpg --no-default-keyring --secret-keyring ${keyring} --import ${public_key} &> /dev/null
                if ! GPG_AGENT_INFO="" echo "${pgpsignature}" | gpg --verify - "${rpath}" &> /dev/null; then
                    fail "PGP verification failure: $(lval path)"
                fi
            )

        fi &

        pids+=( $! )
    done

    # Wait for all pids and then assert the return code was zero.
    wait ${pids[@]} && rc=0 || rc=$?
    if [[ ${quiet} -ne 1 ]]; then
        eprogress_kill -r=${rc}
    fi
    assert_eq 0 "${rc}"
}

opt_usage emd5sum <<'END'
`emd5sum` is a wrapper around computing the md5sum of a file to output just the filename instead of the full path to the
filename. This is a departure from normal `md5sum` for good reason. If you download an md5 file with a path embedded
into it then the md5sum can only be validated if you put it in the exact same path. `emd5sum` is more flexible.
END
emd5sum()
{
    $(opt_parse path)

    local dname="" fname=""
    dname=$(dirname  "${path}")
    fname=$(basename "${path}")

    pushd "${dname}"
    md5sum "${fname}"
    popd
}

opt_usage emd5sum_check <<'END'
`emd5sum_check` is a wrapper around checking an md5sum file regardless of the path used when the file was originally
created. If someone unwittingly said `md5sum /home/foo/bar` and then later moved the file to `/home/zap/bar`, and ran
`md5sum -c` on the relocated file it would fail. This works around this silly problem by assuming that the md5 file is a
sibling to the original source file and ignores the path specified in the md5 file. Then it manually compares the MD5
from the file with the actual MD5 of the source file.
END
emd5sum_check()
{
    $(opt_parse path)

    echo "$(awk '{print $1}' "${path}".md5)" "${path}" | md5sum -c - | edebug
}
