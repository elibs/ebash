#1/bin/bash

# Global configuration which can be overriden by the caller
: ${EBASH_CICD_TAG_MATCH:="v*.*.*.*"}
: ${EBASH_CICD_DEVELOP_BRANCH="develop"}
: ${EBASH_CICD_RELEASE_BRANCH="main"}

cicd_info()
{
    $(opt_parse \
        "pack | Name of the pack to fill in with CICD details." \
    )

    local version_tag version base_tag
    version_tag=$(git describe --always --tags --match "${EBASH_CICD_TAG_MATCH}" --abbrev=10)
    version="${version_tag#v}"
    base_tag="${version_tag%%-*}"

    local parts=()
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
        base_tag="${base_tag}"                                                 \
        branch="$(git branch --show-current)"                                  \
        build="${parts[3]:-0}"                                                 \
        commit="$(git rev-parse HEAD)"                                         \
        commit_short="$(string_truncate 10 $(git rev-parse HEAD))"             \
        major="${parts[0]}"                                                    \
        minor="${parts[1]}"                                                    \
        offset="$(git rev-list ${base_tag}..HEAD --count)"                     \
        origin_url="$(git config --get remote.origin.url)"                     \
        patch="${parts[2]}"                                                    \
        repo_slug="$(basename "$(git config --get remote.origin.url)" ".git")" \
        series="${parts[0]}.${parts[1]}"                                       \
        version="${version}"                                                   \
        version_tag="${version_tag}"                                           \
        version_tag_next="${version_tag_next}"
}

cicd_print()
{
    $(opt_parse \
        "+json | Instead of printing in simple key/value, this will instead print in JSON." \
    )

    local info=""
    cicd_info info
    $(pack_import info)

    if [[ "${json}" -eq 1 ]]; then
        pack_to_json info | jq .
    else
        pack_print_key_value info
    fi
}

cicd_create_next_version_tag()
{
    local _message="[Build Automation] Auto tagged by automation pipeline"
    $(opt_parse \
        "+push                | Push the resulting new tag."                             \
        ":set_url             | If provided, set the origin to this URL before pushing." \
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

    if [[ -n "${set_url}" ]]; then
        git remote set-url origin "${set_url}"
    fi

    # Create a new version tag
    git tag -am "${message}" "${version_tag_next}"

    if [[ "${push}" -eq 1 ]]; then
        einfo "Pushing"
        git push origin "${branch}" "${version_tag_next}"
    fi
}

# Push current branch to a release branch. e.g. push develop -> main. Also optionally publish artifacts.
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
