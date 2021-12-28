#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

# Global configuration which can be overriden by the caller
: ${EBASH_CICD_TAG_MATCH:="v*.*.*.*"}
: ${EBASH_CICD_DEVELOP_BRANCH="develop"}
: ${EBASH_CICD_RELEASE_BRANCH="main"}

opt_usage cicd_info <<'END'
cicd_info is used to collect all CI/CD information about the current Git repository. This includes such things as:
* branch
* build number
* commit SHA
* Semantic versioning as major, minor, patch, and build components.
* Origin URL
* Version, version tag and next version tag

This information is populated into a provided pack and then the caller can use the information inside the pack. For
exmaple:

```bash
local info=""
cicd_info info
branch=$(pack_get info branch)
```

Or you can easily import everything in the CI/CD info pack into variables you can use locally within your function:

```
local info=""
cicd_info info
$(pack_import info)

echo "Branch=${branch}"
echo "Tag=${major}.${minor}.${patch}.${build}"
```
END
cicd_info()
{
    $(opt_parse \
        "pack | Name of the pack to fill in with CICD details." \
    )

    # Parse the version_tag using the provided EBASH_CICD_TAG_MATCH. If we are unable to find a match use a
    # corresponding default tag.
    local version_tag version base_tag
    if ! version_tag=$(git describe --tags --match "${EBASH_CICD_TAG_MATCH}" --abbrev=10 2>/dev/null); then
        version_tag="${EBASH_CICD_TAG_MATCH//\*/0}"
    fi

    # Now we can safely parse out the component version parts
    local parts=()
    version="${version_tag#v}"
    base_tag="${version_tag%%-*}"
    array_init parts "${version%%-*}" "."
    edebug "$(lval parts)"

    # If the build is not numeric we can't increment it later
    local version_tag_next
    if ! is_int "${parts[3]}"; then
        version_tag_next=""
        edebug "Cannot increment non-integer build -- setting version_tag_next to an empty string"
    else
        version_tag_next="v${parts[0]}.${parts[1]}.${parts[2]}.$(( ${parts[3]:-0} + 1 ))"
    fi

    pack_set "${pack}" \
        base_tag="${base_tag}"                                                      \
        branch="$(git rev-parse --abbrev-ref HEAD)"                                 \
        build="${parts[3]:-0}"                                                      \
        commit="$(git rev-parse HEAD)"                                              \
        commit_short="$(string_truncate 10 $(git rev-parse HEAD))"                  \
        major="${parts[0]}"                                                         \
        minor="${parts[1]}"                                                         \
        offset="$(git rev-list ${base_tag}..HEAD --count 2>/dev/null || echo 0)"    \
        origin_url="$(git config --get remote.origin.url)"                          \
        patch="${parts[2]}"                                                         \
        repo_slug="$(basename "$(git config --get remote.origin.url)" ".git")"      \
        series="${parts[0]}.${parts[1]}"                                            \
        version="${version}"                                                        \
        version_tag="${version_tag}"                                                \
        version_tag_next="${version_tag_next}"
}

opt_usage cicd_print <<'END'
cicd_print is used to import all CI/CD info for the current Git repository and then print that information to the screen.
By default this prints as a simple key/value list but options can be used to modify the output as desired.
END
cicd_print()
{
    $(opt_parse \
        "+json      j | Instead of printing in simple key/value, this will instead print in JSON." \
        "+uppercase u | Print keys in uppercase."                                                  \
    )

    local info=""
    cicd_info info
    $(pack_import info)

    if [[ "${json}" -eq 1 ]]; then
        pack_to_json info | jq .
    elif [[ "${uppercase}" -eq 1 ]]; then
        pack_print_key_value info | sed -E 's|([^=]+)=(.*)|\U\1\E=\2|g'
    else
        pack_print_key_value info
    fi
}

opt_usage cicd_create_next_version_tag <<'END'
cicd_create_next_version_tag is used to create the next version tag for a given Git repository. This operates using
semantic versioning with the following named version components: ${major}.${minor}.${patch}.${build}. When this function
is called, it will utilize the `cicd_info` function which figures out what the next version tag would be by simply
taking `${build} + 1`. This is then created and optionally pushed.
END
cicd_create_next_version_tag()
{
    local _message="[Build Automation] Auto tagged by automation pipeline"
    $(opt_parse \
        "+push                | Push the resulting new tag."                             \
        ":message=${_message} | Message to use for commit of new version tag."           \
    )

    local info=""
    cicd_info info
    $(pack_import info)
    if edebug_enabled; then
        einfo "CI/CD Version Info"
        pack_to_json info | jq .
    fi

    # Verify we are on develop branch
    if [[ "${branch}" != "${EBASH_CICD_DEVELOP_BRANCH}" ]]; then
        die "Must be on ${EBASH_CICD_DEVELOP_BRANCH} branch to create next version tag"
    fi

    # Verify version_tag_next was determined properly
    if [[ -z "${version_tag_next}" ]]; then
        die "Cannot create empty next version tag"
    fi

    # Create a new version tag
    git tag -am "${message}" "${version_tag_next}"

    if [[ "${push}" -eq 1 ]]; then
        einfo "Pushing"
        git push origin "${branch}" "${version_tag_next}"
    fi
}

opt_usage cicd_release <<'END'
cicd_release is used to push the develop branch into the release branch. Typically the develop branch is named `develop`
and the release branch is named `master` or `main`. These can be configured via these two variables:
* `EBASH_CICD_DEVELOP_BRANCH`
* `EBASH_CICD_RELEASE_BRANCH`

It is an error to try to release code when not on the `DEVELOP` branch.
END
cicd_release()
{
    local info=""
    cicd_info info
    $(pack_import info)

    # Verify we are on develop branch
    if [[ "${branch}" != "${EBASH_CICD_DEVELOP_BRANCH}" ]]; then
        die "Must be on ${EBASH_CICD_DEVELOP_BRANCH} branch to release to ${EBASH_CICD_RELEASE_BRANCH}"
    fi

    einfo "Pushing ${EBASH_CICD_DEVELOP_BRANCH} -> ${EBASH_CICD_RELEASE_BRANCH}"
    git push origin HEAD:${EBASH_CICD_RELEASE_BRANCH}
}
