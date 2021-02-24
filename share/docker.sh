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

EBASH_DOCKER_REGISTRY="https://index.docker.io/v1/"
: ${DOCKER_REGISTRY:=${EBASH_DOCKER_REGISTRY}}

opt_usage docker_build <<'END'
docker_build is used to intelligently build a docker image from a Dockerfile using an external cache docker registry/repo
which may be the same or different from the production registry/repo. For example, we typically have a dedicated
registry/repo for CI/CD images which are treated only as a cache and can be prunned or blown away entirely as needed. We
have a separate registry/repo for our official released builds which we want to keep uncluttered.

The main functionality added by docker_build is to avoid building redudant, identical docker images. The most common use
case here is lots of git branches all trying to build and tag docker images which are essentially identical. Even with
docker's built-in layer caching mechanism, "docker build" always hits the cache and does a new build even on 100% cache
hits. Granted the build will be _fast_, but it's still unecessary if we've already built it with identical content but a
different tag. Moreover, vanilla "docker build" command is not distributed. Every developer is forced to do a build even
if another developer has already built and published. Ebash's "docker_build" addresses this problem using the cach repo.

The algorithm we employ is as follows:

    1) Look for the image locally
    2) Try to download the underlying content-based SHA image from docker cache repository
    3) Build the docker image from scratch

This entire algorithm is built on a simple idea of essentially computing our own simplistic sha256 dependency SHA which
captures the content of the provided Dockerfile as well as any files which are dynamically copied or added via COPY/ADD
directives in the Dockerfile as well as any build arguements. We then simply use that dynamically generated content
based tag to easily be able to look for the image in the cache repository. For more details see docker_depends_sha.

NOTE: If you want to push any tags you need to provide --username and --password arguments or have DOCKER_USERNAME and
DOCKER_PASSWORD environment variables set.
END
docker_build()
{
    $(opt_parse \
        "&build_arg                         | Build arguments to pass into lower level docker build --build-arg."      \
        "=cache_repo                        | Name of docker cache registry/repository for cached remote images."      \
        ":file=Dockerfile                   | The docker file to use. Defaults to Dockerfile."                         \
        ":name                              | Name to use for generated artifacts. Defaults to the basename of repo."  \
        "+pull                              | Pull the image from the remote registry/repo."                           \
        "&push                              | List of tags to push to remote registry/repo. Multiple tags can be space
                                              delimited inside this array."                                            \
        "+pretend                           | Do not actually build the docker image. Return 0 if image already exists
                                              and 1 if the image does not exist and a build is required."              \
        ":shafunc=sha256                    | SHA function to use. Default to sha256."                                 \
        "&tag                               | Tags to assign to the image of the form registry/repo:tag. This allows you
                                              to actually tag and push to multiple remote repositories in one operation.
                                              Multiple tags can be space delimited inside this array."                 \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
        ":workdir=.work/docker              | Temporary work directory to save output files to."                       \
    )

    mkdir -p "${workdir}"
    assert_exists "${file}"

    # Compute dependency SHA
    : ${name:="$(basename "${cache_repo}")"}
    $(__docker_depends_sha_variables)
    __docker_depends_sha
    local sha_short=$(cat "${shafile_short}")

    # Image we should look for
    image="${cache_repo}:${sha_short}"
    edebug $(lval      \
        build_arg      \
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

    # Parse tag accumulator
    array_init tag "${tag[*]}"
    array_sort --unique tag
    edebug "$(lval tag tags=tags)"

    # Look for image locally first
    if [[ -n "$(docker images --quiet "${image}" 2>/dev/null)" ]]; then

        checkbox "Using local ${image}"
        docker history "${image}" > "${history}"
        docker inspect "${image}" > "${inspect}"
        __docker_build_create_tags

        return 0

    # If pull is requested
    elif [[ "${pull}" -eq 1 ]]; then

        if docker pull "${image}" 2>/dev/null; then
            checkbox "Using pulled ${image}"
            docker history "${image}" > "${history}"
            docker inspect "${image}" > "${inspect}"
            __docker_build_create_tags

            return 0
        fi

    # If pull is NOT requested, and credentials are provided, simply check if the remote image exists.
    elif [[ "${pull}" -eq 0 && -n "${username}" && -n "${password}" ]]; then

        echo "${password}" | docker login --username "${username}" --password-stdin "${registry}"

        if docker_image_exists "${cache_repo}:${sha_short}"; then
            checkbox "Remote exists ${image}"
            return 0
        fi
    fi

    if [[ "${pretend}" -eq 1 ]]; then
        ewarn "Build required for $(lval image) but pretend=1"
        return 1
    fi

    eprogress "Building docker $(lval image tags=tag)"

    docker build --tag "${image}" --file "${dockerfile}" . | edebug

    eprogress_kill

    __docker_build_create_tags

    einfo "Size"
    docker images "${image}"

    einfo "Layers"
    docker history "${image}" | tee "${history}"

    if array_not_empty push; then
        push=( "${image}" "${push[@]}" )
        opt_forward docker_push push registry username password
    fi

    # Only create inspect (stamp) file at the very end after everything has been done.
    einfo "Creating stamp file ${inspect}"
    docker inspect "${image}" > "${inspect}"
}

## TODO: DOCSTRING
docker_push()
{
    $(opt_parse \
        "&push                              | List of tags to push to remote registry/repo. Multiple tags can be space
                                              delimited inside this array."                                            \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
    )

    if array_empty push; then
        return 0
    fi

    if ! argcheck registry username password; then
        edebug "Push disabled because one or more required arguments are missing"
        return 1
    fi

    echo "${password}" | docker login --username "${username}" --password-stdin "${registry}"

    # Parse push accumulator
    local entries
    array_init entries "${push[*]}"
    array_sort --unique entries
    edebug "Pushing $(lval push entries)"

    # Push all tags
    for entry in "${entries[@]}"; do
        einfo "Pushing $(lval tag=entry)"
        docker push "${entry}"
    done
}

opt_usage docker_image_exists <<'END'
docker_image_exists is a simple function to easily check if a remote docker image exists. This makes use of an
experimental feature in docker cli to be able to inspect a remote manifest without having to first pull it.
END
docker_image_exists()
{
    $(opt_parse \
        "tag | Docker tag to check for the existance of in the form of name:tag.")

    DOCKER_CLI_EXPERIMENTAL=enabled docker manifest inspect "${tag}"
}

opt_usage __docker_build_create_tags <<'END'
Internal helper method to expose reuseable code for adding an additional tag to a previously built docker image.
This is an internal function used only by docker_build function. As such the parameters are internal variables set
within that function.
END
__docker_build_create_tags()
{
    for entry in "${tag[@]}"; do
        [[ -z "${entry}" ]] && continue
        einfo "Creating $(lval tag=entry)"
        docker build --tag "${entry}" --file "${dockerfile}" . | edebug
    done
}

opt_usage docker_depends_sha <<'END'
docker_depends_sha is used to compute the dependency SHA for a dockerfile as well as any additional files it copies into
the resulting docker image and also and build arguments used to create it. This is used by docker_build to avoid
building docker images when none of the dependencies have changed.

This function will create some output state files underneath ${workdir}/docker that are used by docker_build and are
also useful for callers. These are prefixed by ${name} which defaults to $(basename ${cache_repo}).

    1) ${name}.options           : Options passed into docker_build
    2) ${name}.history           : Contains output of 'docker history'
    3) ${name}.inspect           : Contains output of 'docker inspect'
    4) ${name}.dockerfile        : Contains original dockerfile with all environment variables interpolated
    5) ${name}.${shafunc}        : Contains full content based sha of the dependencies to create the docker image
    6) ${name}.${shafunc}_short  : Contains first 12 characters of the full SHA of the dependencies of the image
    7) ${name}.${shafunc}_detail : Contains a detailed listing of all the dependencies that led to the creation of the
                                   docker image along with THEIR respective SHAs.
END
__docker_depends_sha()
{
    mkdir -p "${workdir}"
    assert_exists "${file}"

    : ${name:="$(basename "${cache_repo}")"}
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

    envsubst "$(array_join build_arg_keys ,)" < "${file}" > "${dockerfile}"

    # Strip out ARGs that we've interpolated
    for entry in "${build_arg[@]}"; do
        build_arg_key="${entry%%=*}"
        edebug "stripping buildarg: $(lval entry build_arg_key)"
        sed -i -e "/ARG ${build_arg_key}/d" "${dockerfile}"
    done

    # Dynamically compute dependency SHA of dockerfile
    local depends
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

    local sha sha_short
    sha=$(cat "${shafile}")
    sha_short="$(string_truncate 12 "${sha#*:}")"
    echo "${sha_short}" > "${shafile_short}"
}

## TODO: Add docstring
__docker_depends_sha_variables()
{
    echo eval
    echo 'eval local dockerfile="${workdir}/${name}.dockerfile"; '
    echo 'eval local options="${workdir}/${name}.options"; '
    echo 'eval local history="${workdir}/${name}.history"; '
    echo 'eval local inspect="${workdir}/${name}.inspect"; '
    echo 'eval local shafile="${workdir}/${name}.${shafunc}"; '
    echo 'eval local shafile_short="${workdir}/${name}.${shafunc}_short"; '
    echo 'eval local shafile_detail="${workdir}/${name}.${shafunc}_detail"; '
}

## TODO: DOCSTRING
docker_depends_sha()
{
    $(opt_parse \
        "&build_arg                         | Build arguments to pass into lower level docker build --build-arg."      \
        "=cache_repo                        | Name of docker cache registry/repository for cached remote images."      \
        ":file=Dockerfile                   | The docker file to use. Defaults to Dockerfile."                         \
        ":name                              | Name to use for generated artifacts. Defaults to the basename of repo."  \
        ":shafunc=sha256                    | SHA function to use. Default to sha256."                                 \
        ":workdir=.work/docker              | Temporary work directory to save output files to."                       \
    )

    mkdir -p "${workdir}"
    assert_exists "${file}"

    : ${name:="$(basename "${cache_repo}")"}
    $(__docker_depends_sha_variables)
    __docker_depends_sha
}
