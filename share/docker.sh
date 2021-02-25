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

Overlay Modules
===============

docker_build supports the concept of overlay modules which facilitates copying files into the resulting docker image
that we build. The purpose of this is to provide dockerized versions of things that would otherwise not work properly
inside docker. The best example of this is systemd. Systemd binaries, such as systemctl and journalctl, do not function
properly inside docker because there is no init daemon inside docker containers. To solve this problem, ebash provides a
set of replacements for systemd binaries that simulate their intended functionality. These are generally NOT fully
functional replacements but simple, stripped down replacements that get the job done.

The overlay files are automatically accounted for with the built-in dependency SHA and caching mechanism used by
docker_build.

There are several built-in overlay modules provided by ebash that you can enable via --overlay=<module>. This is an
accumulator so you can pass it in multiple times to enable multiple overlay modules.

    1) systemd

       This provides several critical binary replacements to provide seamless systemd-like functionality:

         a) /usr/local/bin/systemctl: manage multiple ebash controlled daemons. This supports 'start', 'stop', 'status',
            'restart' actions on each daemon.
         b) /usr/local/bin/timedatectl: simulate systemd timedatectl functionality. This supports being called with no
            arguments and it will output something similar to the real timedatectl. It also supports being called with
            "set-timezone ZONE".
         c) /usr/local/bin/journalctl: This does not implement the full journalctl functionality but instead acts as a
            lightweight wrapper around rsyslog logger. By default if you call this with no arguments it will simply cat
            /var/log/messages and pass them into your pager. If you pass in -f or --follow it will tail the log file.

    2) rsyslog

       This is *NOT* a full replacement for rsyslog. Instead it simply provides a custom /etc/rsylog.conf file which
       allows rsyslog to function properly inside docker. You also need to __install__ rsyslog in your container and
       must also start it up as a daemon (probably using ebash controlled init script).

    3) selinux

       This is *NOT* a full replacement for selinux. Instead it simply provides a custom /etc/selinux/config file which
       completely disables selinux entirely as it doesn't work inside docker.

Finally, you can install your own custom overlay files via --overlay-tree=<path>. The entire tree of the provided path
will be copied into the root of the created container. For example, if you had "overlay/usr/local/bin/foo" and you
called "docker_build --overlay-tree overlay" then inside the container you will have "/usr/local/bin/foo".

Notes
=====
(1) If you want to push any tags you need to provide --username and --password arguments or have DOCKER_USERNAME and
DOCKER_PASSWORD environment variables set.

END
docker_build()
{
    $(opt_parse \
        "&build_arg                         | Build arguments to pass into lower level docker build --build-arg."      \
        ":cache_from                        | Images to consider as cache sources. Passthrough into docker build."     \
        ":file=Dockerfile                   | The docker file to use. Defaults to Dockerfile."                         \
        "=name                              | Name of docker image to create. This will also be used as the cache
                                              registry/repository for cached remote images."                           \
        "&overlay                           | Builtin ebash overlay module to install into the image."                 \
        ":overlay_tree                      | Tree of additional local files to copy into the resulting image."        \
        "+pull                              | Pull the image and all tags from the remote registry/repo."              \
        "+push                              | Push the image and all tags to remote registry/repo."                    \
        "+pretend                           | Do not actually build the docker image. Return 0 if image already exists
                                              and 1 if the image does not exist and a build is required."              \
        ":shafunc=sha256                    | SHA function to use. Default to sha256."                                 \
        "&tag                               | Tags to assign to the image of the form registry/repo:tag. This allows you
                                              to actually tag and push to multiple repositories in one operation."     \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
        ":workdir=.work/docker              | Temporary work directory to save output files to."                       \
    )

    mkdir -p "${workdir}"
    assert_exists "${file}"

    # Compute dependency SHA
    $(__docker_depends_sha_variables)
    __docker_depends_sha
    sha_short=$(cat "${shafile_short}")

    # Image we should look for
    image="${name}:${sha_short}"
    edebug $(lval      \
        build_arg      \
        cache_from     \
        dockerfile     \
        file           \
        image          \
        overlay        \
        overlay_tree   \
        pretend        \
        push           \
        repo           \
        sha            \
        sha_short      \
        shafunc        \
        tag            \
        workdir        \
    )

    # Save image name into imagefile
    echo "${image}" > "${imagefile}"

    # Look for image locally first
    if [[ -n "$(docker images --quiet "${image}" 2>/dev/null)" ]]; then

        checkbox "Using local ${image}"
        docker history "${image}" > "${histfile}"
        docker inspect "${image}" > "${inspfile}"

        opt_forward docker_pull registry username password cache_from -- "${tag[@]}"

        return 0

    # If pull is requested
    elif [[ "${pull}" -eq 1 ]]; then

        if docker pull "${image}" 2>/dev/null; then
            checkbox "Using pulled ${image}"
            docker history "${image}" > "${histfile}"
            docker inspect "${image}" > "${inspfile}"

            opt_forward docker_pull registry username password cache_from -- ${tag[@]}

            return 0
        fi

    # If pull is NOT requested, and credentials are provided, simply check if the remote image exists.
    elif [[ "${pull}" -eq 0 && -n "${username}" && -n "${password}" ]]; then

        echo "${password}" | docker login --username "${username}" --password-stdin "${registry}"

        if docker_image_exists "${name}:${sha_short}"; then
            checkbox "Remote exists ${image}"
            return 0
        fi
    fi

    if [[ "${pretend}" -eq 1 ]]; then
        ewarn "Build required for $(lval image) but pretend=1"
        return 1
    fi

    eprogress "Building docker $(lval image tags=tag)"
    docker build --file "${dockerfile}" --tag "${image}" --cache-from "${cache_from}" $(array_join --before tag " --tag ") . | edebug
    eprogress_kill

    einfo "Size"
    docker images "${image}"

    einfo "Layers"
    docker history "${image}" | tee "${histfile}"

    if [[ ${push} -eq 1 ]]; then
        local push_tags
        push_tags=( ${image} ${tag[@]} )
        opt_forward docker_push registry username password -- ${push_tags[@]}
    fi

    # Only create inspect (stamp) file at the very end after everything has been done.
    einfo "Creating stamp file ${inspfile}"
    docker inspect "${image}" > "${inspfile}"
}

opt_usage docker_pull<<'END'
docker_pull is an intelligent wrapper around vanilla "docker pull" which integrates more nicely with ebash. In addition
to the normal additional error checking and hardening the ebash variety brings, this also provide the following
functionality:

    1) Seamlessly login to docker registry before pushing as-needed.
    2) Accepts an array of tags to pull and pulls them all.
    3) Fallback to local build if remote pull fails.
END
docker_pull()
{
    $(opt_parse \
        ":file=Dockerfile                   | The docker file to use. Defaults to Dockerfile."                         \
        ":cache_from                        | Images to consider as cache sources. Passthrough into docker build."     \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
        "+fallback=1                        | If pull fails, build locally."                                           \
        "@tags                              | List of tags to pull from the remote registry/repo."                     \
    )

    if array_empty tags; then
        return 0
    fi

    local login=1
    local tag
    for tag in "${tags[@]}"; do

        # If it is available locally no need to pull!
        if [[ -n "$(docker images --quiet "${tag}" 2>/dev/null)" ]]; then
            checkbox "Using local ${tag}"
            continue
        fi

        if [[ ${login} -eq 1 ]]; then
            argcheck registry username password
            echo "${password}" | docker login --username "${username}" --password-stdin "${registry}"
            login=0
        fi

        einfo "Pulling $(lval tag)"
        if ! docker pull "${tag}"; then

            if [[ ${fallback} -eq 0 ]]; then
                eerror "Failed to pull $(lval tag)"
                return 1
            else
                ewarn "Failed to pull $(lval tag) -- fallback to local build"
                docker build --file "${dockerfile}" --tag "${tag}" --cache-from "${cache_from}" . | edebug
            fi
        fi
    done
}

opt_usage docker_push<<'END'
docker_push is an intelligent wrapper around vanilla "docker push" which integrates more nicely with ebash. In addition
to the normal additional error checking and hardening the ebash variety brings, this also provide the following
functionality:

    1) Seamlessly login to docker registry before pushing as-needed.
    2) Accepts an array of tags to push and pushes them all.
END
docker_push()
{
    $(opt_parse \
        ":registry=${DOCKER_REGISTRY:-}     | Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable
                                              which itself defaults to ${EBASH_DOCKER_REGISTRY} if not set."           \
        ":username=${DOCKER_USERNAME:-}     | Username for registry login. Defaults to DOCKER_USERNAME env variable."  \
        ":password=${DOCKER_PASSWORD:-}     | Password for registry login. Defaults to DOCKER_PASSWORD env variable."  \
        "@tags                              | List of tags to push to remote registry/repo."                           \
    )

    if array_empty tags; then
        return 0
    fi

    if ! argcheck registry username password; then
        edebug "Push disabled because one or more required arguments are missing"
        return 1
    fi

    echo "${password}" | docker login --username "${username}" --password-stdin "${registry}"

    # Push all tags
    local tag
    for tag in "${tags[@]}"; do
        einfo "Pushing $(lval tag)"
        docker push "${tag}"
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

opt_usage docker_depends_sha<<'END'
docker_depends_sha is used to compute the dependency SHA for a dockerfile as well as any additional files it copies into
the resulting docker image (including overlay modules and overlay_tree files) and also and build arguments used to
create it. This is used by docker_build to avoid building docker images when none of the dependencies have changed.

This function will create some output state files underneath ${workdir}/docker/$(basename ${name}) that are used
internally by docker_build but also useful externally.

    - dockerfile : Contains original dockerfile with variables interpolated and overlay information added by ebash
    - history    : Contains output of 'docker history'
    - image      : The full image name including name:sha.
    - inspect    : Contains output of 'docker inspect'
    - options    : Options passed into docker_build
    - sha        : Contains full content based sha of the dependencies to create the docker image
    - sha.detail : Contains details of all the dependencies that affect the image along with their respective SHAs.
    - sha.func   : Contains the SHA function used (e.g. sha256)
    - sha.short  : Contains first 12 characters of the full SHA of the dependencies of the image
}
END
docker_depends_sha()
{
    $(opt_parse \
        "&build_arg                         | Build arguments to pass into lower level docker build --build-arg."      \
        ":file=Dockerfile                   | The docker file to use. Defaults to Dockerfile."                         \
        "=name                              | Name of docker image to create. This will also be used as the cache
                                              registry/repository for cached remote images."                           \
        "&overlay                           | Builtin ebash overlay module to install into the image."                 \
        ":overlay_tree                      | Tree of additional local files to copy into the resulting image."        \
        ":shafunc=sha256                    | SHA function to use. Default to sha256."                                 \
        ":workdir=.work/docker              | Temporary work directory to save output files to."                       \
    )

    mkdir -p "${workdir}"
    assert_exists "${file}"

    $(__docker_depends_sha_variables)
    __docker_depends_sha
}

opt_usage __docker_depends_sha <<'END'
__docker_depends_sha is the internal implementation function implementing the algorithm described in docker_depends_sha.
The actual implementation is broken out into this internal-only function for better code reuse and testability.
END
__docker_depends_sha()
{
    mkdir -p "${workdir}"
    assert_exists "${file}"

    echo "${shafunc}" > "${shafile_func}"
    opt_dump | sort   > "${optfile}"

    # Add any build arguments into sha_detail
    local entry=""
    for entry in "${build_arg[@]:-}"; do
        [[ -z "${entry}" ]] && continue
        local build_arg_key="${entry%%=*}"
        local build_arg_val="${entry#*=}"
        edebug "buildarg: $(lval entry build_arg_key build_arg_val)"

        eval "export ${build_arg_key}=${build_arg_val}"
        build_arg_keys+=( "\$${build_arg_key}" )
        build_arg_vals+=( "--build-arg ${entry}" )
    done

    envsubst "$(array_join build_arg_keys ,)" < "${file}" > "${dockerfile}"

    # Strip out ARGs that we've interpolated
    for entry in "${build_arg[@]:-}"; do
        [[ -z "${entry}" ]] && continue
        build_arg_key="${entry%%=*}"
        edebug "stripping buildarg: $(lval entry build_arg_key)"
        sed -i -e "/ARG ${build_arg_key}/d" "${dockerfile}"
    done

    # Append COPY directives for overlay modules
    local overdir
    overdir="${workdir}/$(basename ${name})/overlay"
    efreshdir "${overdir}"

    # Add COPY directive for overlay_tree if requested.
    local overlay_paths=( "${overlay[@]:-}" )
    if [[ -n "${overlay_tree}" ]]; then
        overlay_paths+=( "file://${overlay_tree}" )
    fi

    # We have to iterate backwards since we're inserting these after the first FROM statement.
    for idx in $(array_rindexes overlay_paths); do
        entry="${overlay_paths[$idx]}"
        edebug "Adding $(lval idx overlay=entry)"

        if [[ "${entry}" == "ebash" ]]; then
            mkdir -p "${overdir}/ebash/opt/ebash" "${overdir}/ebash/usr/local/bin"
            cp -a "${EBASH_HOME}/bin" "${EBASH_HOME}/share" "${overdir}/ebash/opt/ebash"

            local bin
            for bin in ${overdir}/ebash/opt/ebash/bin/*; do
                bin="$(basename "${bin}")"
                ln -s "/opt/ebash/bin/${bin}" "${overdir}/ebash/usr/local/bin/${bin}"
            done

            # Update EBASH_HOME in ebash so it works in the newly installed path.
            sed -i 's|: ${EBASH_HOME:=$(dirname $0)/..}|EBASH_HOME="/opt/ebash"|' "${overdir}/ebash/opt/ebash/bin/ebash"

        elif [[ "${entry}" == file://* ]]; then
            mkdir -p "${overdir}/custom"
            cp -a "${entry:7}/." "${overdir}/custom"
            entry="custom"
        else
            mkdir -p "${overdir}/${entry}"
            cp -a "${EBASH}/docker-overlay/${entry}" "${overdir}"
        fi

        sed -i '\|^FROM .*|a COPY "'${overdir}'/'${entry}'/" "/"' "${dockerfile}"
    done

    # Dynamically compute dependency SHA of dockerfile
    local depends
    depends=(
        ${dockerfile}
        $(grep -P "^(ADD|COPY) " "${dockerfile}" | awk '{$1=$NF=""}1' | sed 's|"||g' || true)
    )
    array_sort --unique depends

    edebug "$(lval depends)"
    local sha_detail=""
    if array_not_empty build_arg_vals; then
        sha_detail="$(array_join_nl build_arg_vals)"
        sha_detail+=$'\n'
    fi
    sha_detail+="$(find ${depends[@]} -follow -type f -print0 \
        | sort -z \
        | xargs -0 "${shafunc}sum" \
        | awk '{print $2"'@${shafunc}:'"$1}'
    )"

    echo "${sha_detail}" > "${shafile_detail}"
    echo "${sha_detail}" | "${shafunc}sum" | awk '{print "'${shafunc}':"$1}' > "${shafile}"

    local sha sha_short
    sha=$(cat "${shafile}")
    sha_short="$(string_truncate 12 "${sha#*:}")"
    echo "${sha_short}" > "${shafile_short}"
}

opt_usage __docker_depends_sha_variables<<'END'
__docker_depends_sha_variables is an internal only function which provides a central function for declaring all the
internally used dependency SHA variables used throughout the docker module.
END
__docker_depends_sha_variables()
{
    echo eval
    echo 'eval local artifactdir; '
    echo 'eval artifactdir="${workdir}/$(basename ${name})"; '
    echo 'eval mkdir -p "${artifactdir}"; '
    echo 'eval local dockerfile="${artifactdir}/dockerfile"; '
    echo 'eval local optfile="${artifactdir}/options"; '
    echo 'eval local histfile="${artifactdir}/history"; '
    echo 'eval local inspfile="${artifactdir}/inspect"; '
    echo 'eval local imagefile="${artifactdir}/image"; '
    echo 'eval local shafile="${artifactdir}/sha"; '
    echo 'eval local shafile_func="${artifactdir}/sha.func"; '
    echo 'eval local shafile_short="${artifactdir}/sha.short"; '
    echo 'eval local shafile_detail="${artifactdir}/sha.detail"; '
    echo 'eval local sha_short; '
}
