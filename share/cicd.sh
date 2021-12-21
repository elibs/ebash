#1/bin/bash

cicd_pack()
{
    $(opt_parse \
        ":tag_match=v*.*.* | Tag match to use" \
        "pack              | Name of the pack to fill in with CICD details." \
    )

    local version_tag version base_tag
    version_tag=$(git describe --always --tags --match "${tag_match}" --abbrev=10)
    version="${version_tag#v}"
    base_tag="${version_tag%%-*}"

    local parts=()
    array_init parts "${version%%-*}" "."
    edebug "$(lval parts)"

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
        version_tag_next="v${parts[0]}.${parts[1]}.${parts[2]}.$(( ${parts[3]:-0} + 1 ))"
}
