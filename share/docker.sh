#!/bin/bash
#
# Copyright 2020, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Docker
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage running_in_docker <<'END'
Check if we are running inside docker or not.
END
running_in_docker()
{
    [[ -f "/.dockerenv" ]] || grep -qw docker /proc/$$/cgroup 2>/dev/null
}

EBASH_DOCKER_REGISTRY="index.docker.io"
EBASH_DOCKER_AUTO_TAG=":auto:"
: ${DOCKER_REGISTRY:=${EBASH_DOCKER_REGISTRY}}

opt_usage docker_build <<'END'
docker_build is used to intelligently build a docker image from a Dockerfile.

This adds some intelligence around a vanilla docker build command so that we only build when absolutely necessary.
This is smarter than docker's built-in layer caching mechanism since that will always go to the cache and still build the
image even if it's already been built. Moreover, a vanilla docker build command doesn't try to pull before it builds.
This result in every developer having to do an initial build locally even if we've published it remotely to dockerhub.

The algorithm we employ is as follows:

    1) Look for the image locally
    2) Try to download the image from docker repository
    3) Build the docker image from scratch

This entire algorithm is built on a simple idea of essentially computingour own simplistic sha256 which corresponds to
the content of the provided Dockerfile as well as any files which are dynamically copied or added via COPY or ADD
directives in the Dockerfile. We then simply use that dynamically generated tag to easily be able to look for the image
before we try to build.

This function will create some output state files underneath ${workdir}/docker that are super useful. These are all
prefixed by ${name} which defaults to $(basename ${repo}).

    1) ${name}.options           : Options passed into docker_build
    2) ${name}.history           : Contains output of 'docker history'
    3) ${name}.inspect           : Contains output of 'docker inspect'
    4) ${name}.dockerfile        : Contains original dockerfile with all environment variables interpolated
    5) ${name}.${shafunc}        : Contains full content based sha of the dependencies to create the docker image
    6) ${name}.${shafunc}_short  : Contains first 12 characters of the full SHA of the dependencies of the image
    7) ${name}.${shafunc}_detail : Contains a detailed listing of all the dependencies that led to the creation of the
                                   docker image along with THEIR respective SHAs.

NOTE: If you want to push any tags you need to provide --username and --password arguments or have DOCKER_USERNAME and
DOCKER_PASSWORD environment variables set.

END
docker_build()
{
    $(opt_parse \
        "&build_arg                         | Build arguments to pass into lower level docker build --build-arg."      \
        ":file=Dockerfile                   | The docker file to use. Defaults to Dockerfile."                         \
        ":name                              | Name to use for generated artifacts. Defaults to the basename of repo."  \
        "+pull                              | Pull the image from the remote registry/repo."                           \
        "&push                              | List of tags to push to remote registry/repo. There is a special value
                                              '${EBASH_DOCKER_AUTO_TAG}' you can use to indicate you want to push the
                                              content-based tag ebash auto generates. Multiple tags can be space
                                              delimited inside this array."                                            \
        "+pretend                           | Do not actually build the docker image. Return 0 if image already exists
                                              and 1 if the image does not exist and a build is required."              \
        "=repo                              | Name of docker registry/repository for remote images."                   \
        ":shafunc=sha256                    | SHA function to use. Default to sha256."                                 \
        "&tag                               | Additional tags to assign to the image in addition to the builtin content
                                              based SHA generated by ebash. Thease are of the form name:tag. This allows
                                              you to actually tag and push to multiple remote repositories in one
                                              operation. Multiple tags can be space delimited inside this array."      \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
        ":workdir=.work/docker              | Temporary work directory to save output files to."                       \
    )

    mkdir -p "${workdir}"
    assert_exists "${file}"

    : ${name:="$(basename "${repo}")"}
    local options="${workdir}/${name}.options"
    local history="${workdir}/${name}.history"
    local inspect="${workdir}/${name}.inspect"
    local shafile="${workdir}/${name}.${shafunc}"
    local shafile_short="${workdir}/${name}.${shafunc}_short"
    local shafile_detail="${workdir}/${name}.${shafunc}_detail"
    opt_dump | sort > "${options}"

    # Add any build arguments into sha_detail
    local entry="" build_arg_keys=() build_arg_key="" build_arg_val=""
    for entry in "${build_arg[@]}"; do
        build_arg_key="${entry%%=*}"
        build_arg_val="${entry#*=}"
        edebug "buildarg: $(lval entry build_arg_key build_arg_val)"

        eval "export ${build_arg_key}=${build_arg_val}"
        build_arg_keys+=( "\$${build_arg_key}" )
        build_arg_vals+=( "--build-arg ${entry}" )
    done

    local dockerfile="${workdir}/${name}.dockerfile"
    envsubst "$(array_join build_arg_keys ,)" < "${file}" > "${dockerfile}"

    # Strip out ARGs that we've interpolated
    for entry in "${build_arg[@]}"; do
        build_arg_key="${entry%%=*}"
        edebug "stripping buildarg: $(lval entry build_arg_key)"
        sed -i -e "/ARG ${build_arg_key}/d" "${dockerfile}"
    done

    # Dynamically compute dependency SHA of dockerfile
    depends=(
        ${dockerfile}
        $(grep -P "^(ADD|COPY) " "${dockerfile}" | awk '{$1=$NF=""}1' | sed 's|"||g' || true)
    )

    edebug "$(lval depends)"
    local sha_detail=""
    if array_not_empty build_arg_vals; then
        sha_detail="$(array_join_nl build_arg_vals)"
        sha_detail+=$'\n'
    fi
    sha_detail+="$(find ${depends[@]} -type f -print0 \
        | sort -z \
        | xargs -0 "${shafunc}sum" \
        | awk '{print $2"'@${shafunc}:'"$1}'
    )"

    edebug "$(lval sha_detail)"
    echo "${sha_detail}" > "${shafile_detail}"
    echo "${sha_detail}" | "${shafunc}sum" | awk '{print "'${shafunc}':"$1}' > "${shafile}"
    sha=$(cat "${shafile}")
    sha_short="$(string_truncate 12 "${sha#*:}")"
    echo "${sha_short}" > "${shafile_short}"

    # Image we should look for
    image="${repo}:${sha_short}"
    edebug $(lval      \
        build_arg      \
        build_arg_keys \
        build_arg_vals \
        dockerfile     \
        file           \
        history        \
        image          \
        inspect        \
        pretend        \
        push           \
        repo           \
        sha            \
        sha_short      \
        shafile        \
        shafile_detail \
        shafile_short  \
        shafunc        \
        tag            \
        workdir        \
    )

    # Look for image locally first
    if [[ -n "$(docker images --quiet "${image}" 2>/dev/null)" ]]; then
        checkbox "Using local ${image}"
        docker inspect "${image}" > "${inspect}"
        return 0
    elif [[ "${pull}" -eq 1 ]]; then
        if docker pull "${image}" 2>/dev/null; then
            checkbox "Using pulled ${image}"
            docker inspect "${image}" > "${inspect}"
            return 0
        fi
    elif [[ "${pull}" -eq 0 && -n "${username}" && -n "${password}" ]]; then

        edebug "Checking remote manifest"

        opt_forward docker_login registry username password

        if DOCKER_CLI_EXPERIMENTAL=enabled docker manifest inspect "${repo}/${sha_short}" &>/dev/null; then
            checkbox "Remote exists ${image}"
            return 0
        fi

        edebug "Remote manifest does not exist"
    fi

    if [[ "${pretend}" -eq 1 ]]; then
        ewarn "Build required for $(lval image) but pretend=1"
        return 1
    fi

    eprogress "Building docker $(lval image additional_tags=tag)"

    docker build --tag "${image}" --file "${dockerfile}" . | edebug

    eprogress_kill

    # Parse tag accumulator
    local entry entries
    array_init entries "${tag[*]}"
    array_sort --unique entries
    edebug "$(lval tag entries)"

    # Tag them all
    for entry in "${entries[@]}"; do
        [[ -z "${entry}" ]] && continue
        einfo "Tagging with custom $(lval tag=entry)"
        docker build --tag "${entry}" --file "${dockerfile}" . | edebug
    done

    einfo "Size"
    docker images "${image}"

    einfo "Layers"
    docker history "${image}" | tee "${history}"

    if array_not_empty push; then

        opt_forward docker_login registry username password

        # Parse push accumulator
        array_init entries "${push[*]}"
        array_sort --unique entries
        edebug "Pushing $(lval push entries)"

        # Push all tags
        for entry in "${entries[@]}"; do

            if [[ "${entry}" == "${EBASH_DOCKER_AUTO_TAG}" ]]; then
                entry="${image}"
            else
                assert array_contains tag "${entry}"
            fi

            # Make sure the provided tag they want us to push is one we built
            einfo "Pushing $(lval tag=entry)"
            docker push "${entry}"
        done
    fi

    # Only create inspect (stamp) file at the very end after everything has been done.
    einfo "Creating stamp file ${inspect}"
    docker inspect "${image}" > "${inspect}"
}

opt_usage docker_login <<'END'
docker_login is a wrapper around native "docker login" command which checks if we aleady have a cached login auth token
for the desired registry. By default it will assume that token is still valid. If you pass in --force it will logout of
the registry before it does the actual login.
END
docker_login()
{
    $(opt_parse \
        "+force                             | If force is enabled explicitly invalidate existing login via an explicit
                                              logout before trying to login."                                          \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
    )

    argcheck registry username password

    token=$(jq --raw-output '.auths."'${registry}'".auth' "${HOME}/.docker/config.json" || true)
    edebug "Checking if logged into docker $(lval registry username token force)"

    if [[ ${force} -eq 1 ]]; then
        opt_forward docker_logout registry
    elif [[ -n "${token}" && "${token}" != "null" ]]; then
        edebug "Auth token exists"
        return 0
    fi

    edebug "Logging into $(lval registry username)"
    echo "${password}" | docker login "${registry}" --username "${username}" --password-stdin
}

opt_usage docker_logout <<'END'
docker_logout is a thin wrapper around "docker logout" largely for symmetry with docker_login function. Provides better
testability and logging and traceability as a wrapper.
END
docker_logout()
{
     $(opt_parse \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
    )

    argcheck registry
    edebug "Logging out of docker $(lval registry)"
    docker logout "${registry}"
}
