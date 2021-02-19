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

opt_usage docker_build <<'END'
docker_build is used to intelligently build a docker image from a Dockerfile.

This adds some intelligence around a vanilla docker build command so that we only build when absolutely necessary.
This smarter than docker's built-in layer caching mechanism since that will always go to the cache and still build the
image even if it's already been built. Moreover, a vanilla docker build command doesn't try to pull before it builds.
This result in every developer having to do an initial build locally even if we've published it remotely to dockerhub.

The algorithm we employ is as follows:

    1) Look for the image locally
    2) Try to download the image from docker repository
    3) Build the docker image from scratc

This entire algorithm is built on a simple idea of essentially computingour own simplistic sha256 which corresponds to
the content of the provided Dockerfile as well as any files which are dynamically copied or added via COPY or ADD
directives in the Dockerfile. We then simply use that dynamically generated tag to easily be able to look for the image
before we try to build.

This function will create some output state files underneath ${workdir} that are super useful. These are all prefixed by
the required ${docker_repo}.

    1) ${docker_repo}.history           : Contains output of 'docker history'
    2) ${docker_repo}.inspect           : Contains output of 'docker inspect'
    3) ${docker_repo}.dockerfile        : Contains original dockerfile with all environment variables interpolated
    3) ${docker_repo}.${shafunc}        : Contains full content based sha of the dependencies to create the docker image
    4) ${docker_repo}.${shafunc}_short  : Contains first 12 characters of the full SHA of the dependencies of the image
    5) ${docker_repo}.${shafunc}_detail : This contains a detailed listing of all the dependencies that lead to the
                                          creation of the docker image along with THEIR respective SHAs.

NOTE: If you want to publish via --publish then you need to provide --username and --password arguments as well.

END
docker_build()
{
    $(opt_parse \
        "&build_arg                     | Build arguments to pass into lower level docker build --build-arg."          \
        "=docker_registry               | Name of docker registry for remote images."                                  \
        "=docker_repo                   | Name of docker repository for remote images."                                \
        ":docker_tags_url_base          | Base docker URL to use to check for a tag. By default this uses dockerhub and
                                          will appending your registry and repo to the base URL. By default the base URL
                                          we use is 'https://hub.docker.com/v2/repositories' and we append a suffix of
                                          '/tags'. For example, given a registry of 'liqid' and a repo of 'liqid' by
                                          default we use 'https://hub.docker.com/v2/repositories/liqid/liqid/tags'"    \
        ":docker_tags_url_full          | In the event you need more control over the URL used for looking up a docker
                                          tag than offered by docker_tags_url_base, you can give the fully qualified URL
                                          we should use for looking up docker tagss."                                  \
        ":file=Dockerfile               | The docker file to use. Defaults to Dockerfile."                             \
        "+publish                       | If we build a new image, also publish it to the remote registry."            \
        "+pull                          | Pull the image from the remote registry."                                    \
        "+pretend                       | Do not actually build the docker image. Return 0 if image already exists and 1
                                          if the image does not exist and a build is required."                        \
        ":shafunc=sha256                | SHA function to use. Default to sha256."                                     \
        "&tag                           | Optional tags to assign to the image in addition to the content based SHA.
                                          Unlike normal docker, this is JUST the tag NOT name:tag."                    \
        ":username=${DOCKER_USERNAME:-} | Username for publishing the image to the docker registry. Defaults to
                                          DOCKER_USERNAME environment variable"                                        \
        ":password=${DOCKER_PASSWORD:-} | Password for publishing the image to the docker registry. Defaults to
                                          DOCKER_PASSWORD environment variable"                                        \
        ":workdir=.work/docker          | Temporary work directory to save output files to."                           \
    )

    mkdir -p "${workdir}"
    assert_exists "${file}"

    local history="${workdir}/${docker_repo}.history"
    local inspect="${workdir}/${docker_repo}.inspect"
    local shafile="${workdir}/${docker_repo}.${shafunc}"
    local shafile_short="${workdir}/${docker_repo}.${shafunc}_short"
    local shafile_detail="${workdir}/${docker_repo}.${shafunc}_detail"

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

    local dockerfile="${workdir}/${docker_repo}.dockerfile"
    envsubst "$(array_join build_arg_keys ,)" < "${file}" > "${dockerfile}"

    # Strip out ARGs that we've interpolated
    for entry in "${build_arg[@]}"; do
        build_arg_key="${entry%%=*}"
        edebug "stripping buildarg: $(lval entry build_arg_key)"
        sed -i -e "/ARG ${build_arg_key}/d" "${dockerfile}"
    done

    # Show the interpolated file
    edebug "envsubst expanded: $(lval file dockerfile)"
    cat "${dockerfile}" | edebug

    # Dynamically compute dependency SHA of dockerfile
    depends=(
        ${dockerfile}
        $(grep -P "^(ADD|COPY) " "${dockerfile}" | awk '{$1=$NF=""}1' | sed 's|"||g' || true)
    )

    edebug "$(lval depends)"
    sha_detail="$(array_join_nl build_arg_vals)
    $(find ${depends[@]} -type f -print0 \
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
    image="${docker_registry}/${docker_repo}:${sha_short}"
    edebug $(lval            \
        build_arg            \
        build_arg_keys       \
        build_arg_vals       \
        docker_registry      \
        docker_repo          \
        docker_tags_url_base \
        docker_tags_url_full \
        dockerfile           \
        file                 \
        history              \
        image                \
        inspect              \
        publish              \
        pretend              \
        sha                  \
        sha_short            \
        shafile              \
        shafile_detail       \
        shafile_short        \
        shafunc              \
        tag                  \
        workdir              \
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
    elif [[ "${pull}" -eq 0 ]]; then

        local docker_url=""
        if [[ -n "${docker_tags_url_full}" ]]; then
            docker_url="${docker_tags_url_full}/${sha_short}/"
        elif [[ -n "${docker_tags_url_base}" ]]; then
            docker_url="${docker_tags_url_base}/${docker_registry}/${docker_repo}/tags/${sha_short}/"
        else
            docker_url="https://hub.docker.com/v2/repositories/${docker_registry}/${docker_repo}/tags/${sha_short}/"
        fi

        edebug "Checking remote $(lval docker_url)"

        if curl --silent -f --head -lL "${docker_url}" &>/dev/null; then
            checkbox "Remote exists ${image}"
            return 0
        fi
    fi

    if [[ "${pretend}" -eq 1 ]]; then
        ewarn "Build required for $(lval image) but pretend=1"
        return 1
    fi

    eprogress "Building docker $(lval image)"

    docker build \
        ${build_arg_vals[@]} \
        --tag "${image}"     \
        --file "${dockerfile}" . | edebug

    eprogress_kill

    # Also tag with custom tags if requested
    if array_not_empty tag; then
        local entry
        for entry in "${tag[@]}"; do
            einfo "Tagging with custom $(lval tag=entry)"
            docker build \
                ${build_arg_vals[@]}  \
                --tag "${docker_registry}/${docker_repo}:${entry}" \
                --file "${dockerfile}" .
        done
    fi

    einfo "Size"
    docker images "${image}"

    einfo "Layers"
    docker history "${image}" | tee "${history}"

    if [[ ${publish} -eq 1 ]]; then
        einfo "Pushing ${image}"

        argcheck username password
        echo "${password}" | docker login --username "${username}" --password-stdin

        docker push "${image}"

        if [[ -n "${tag}" ]]; then
            docker push "${tag}"
        fi
    fi

    # Only create inspect (stamp) file at the very end after everything has been done.
    einfo "Creating stamp file ${inspect}"
    docker inspect "${image}" > "${inspect}"
}
