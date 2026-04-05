#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# VERSION HELPERS
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage cicd_version <<'END'
cicd_version outputs the current version string with build date. It checks sources in this order:
1. git describe + commit date (preferred - includes commit offset and dirty state)
2. VERSION file (fallback for installed systems without git)

Always includes "-dirty" suffix if there are uncommitted changes. Format: "version (YYYY-MM-DD)"
END
cicd_version()
{
    $(opt_parse \
        ":file f           | Path to VERSION file to read (fallback if git not available)." \
        ":tag_match=v*.*.* | Git tag pattern for semantic versioning."                      \
    )

    # Prefer git describe if we're inside ebash repo because it's more accurate for development (includes commit offset)
    # Use explicit --git-dir and --work-tree to handle containers/copied repos with different ownership (CVE-2022-24765)
    local git="git --git-dir=${PWD}/.git --work-tree=${PWD}"
    if command -v git &>/dev/null && ${git} rev-parse --is-inside-work-tree &>/dev/null; then
        local origin
        origin=$(${git} remote get-url origin 2>/dev/null) || true
        if [[ "${origin}" == *ebash* ]]; then
            local ver date
            ver=$(${git} describe --always --tags --match "${tag_match}" --abbrev=10 --dirty 2>/dev/null)
            date=$(${git} log -1 --format=%cs 2>/dev/null)
            if [[ -n "${ver}" ]]; then
                [[ -n "${date}" ]] && ver+=" (${date})"
                echo "${ver}"
                return 0
            fi
        fi
    fi

    # Fall back to VERSION file (for installed systems without git)
    if [[ -n "${file}" && -r "${file}" ]]; then
        local ver
        read -r ver < "${file}"
        if [[ -n "${ver}" ]]; then
            echo "${ver}"
            return 0
        fi
    fi

    echo "unknown"
}

opt_usage cicd_version_update <<'END'
cicd_version_update writes the current git describe version and build date to a VERSION file. This is typically called
during the release process to embed the version in the release artifact. Format: "version (YYYY-MM-DD)"
END
cicd_version_update()
{
    $(opt_parse \
        ":file f=VERSION   | Path to VERSION file to write."           \
        ":tag_match=v*.*.* | Git tag pattern for semantic versioning." \
    )

    local ver date
    ver=$(git describe --always --tags --match "${tag_match}" --abbrev=10 --dirty 2>/dev/null) || ver="unknown"
    date=$(git log -1 --format=%cs 2>/dev/null) || date=""

    local output="${ver}"
    [[ -n "${date}" ]] && output+=" (${date})"

    einfo "Writing ${output} to ${file}"
    echo "${output}" > "${file}"
}

#-----------------------------------------------------------------------------------------------------------------------
#
# CI/CD INFO
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage cicd_info <<'END'
cicd_info is used to collect all CI/CD information about the current Git repository. This includes such things as:
* branch
* build number
* commit SHA
* Semantic versioning as major, minor, patch, and build components.
* Origin URL
* Version, version tag and next version tag

This information is populated into a provided pack and then the caller can use the information inside the pack. For
example:

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
        ":tag_match=v*.*.* | Git tag pattern for semantic versioning."       \
        "pack              | Name of the pack to fill in with CICD details." \
    )

    # Parse the version_tag using the provided tag_match pattern. If we are unable to find a match use a
    # corresponding default tag.
    local version_tag version base_tag
    if ! version_tag=$(git describe --tags --match "${tag_match}" --abbrev=10 2>/dev/null); then
        version_tag="${tag_match//\*/0}"
    fi

    # Now we can safely parse out the component version parts
    local parts=()
    version="${version_tag#v}"
    base_tag="${version_tag%%-*}"
    array_init parts "${version%%-*}" "."
    edebug "$(lval parts)"

    # Extract suffix (everything after base version, e.g. "-rc1" or "-rc1-1-g5a8ea80568")
    local suffix="${version_tag#${base_tag}}"

    # Determine next version tag. If the suffix matches -rc*, do NOT increment the patch - just use it with the -rc*
    # stripped off. This allows RC releases to naturally lead to the final release version.
    local version_tag_next
    if ! is_int "${parts[2]}"; then
        version_tag_next=""
        edebug "Cannot increment non-integer patch component -- setting version_tag_next to an empty string"
    elif [[ "${suffix}" =~ ^-rc[0-9]+ ]]; then
        version_tag_next="v${parts[0]}.${parts[1]}.${parts[2]}"
        edebug "Detected RC suffix -- not incrementing patch $(lval suffix version_tag_next)"
    else
        version_tag_next="v${parts[0]}.${parts[1]}.$(( ${parts[2]:-0} + 1 ))"
    fi

    pack_set "${pack}" \
        base_tag="${base_tag}"                                                      \
        branch="$(git rev-parse --abbrev-ref HEAD)"                                 \
        commit="$(git rev-parse HEAD)"                                              \
        commit_short="$(string_truncate 10 $(git rev-parse HEAD))"                  \
        major="${parts[0]}"                                                         \
        minor="${parts[1]}"                                                         \
        patch="${parts[2]}"                                                         \
        offset="$(git rev-list ${base_tag}..HEAD --count 2>/dev/null || echo 0)"    \
        origin_url="$(git config --get remote.origin.url)"                          \
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
        "+json j           | Instead of printing in simple key/value, this will instead print in JSON." \
        ":tag_match=v*.*.* | Git tag pattern for semantic versioning."                                  \
        "+uppercase u      | Print keys in uppercase."                                                  \
    )

    local info=""
    cicd_info --tag-match "${tag_match}" info
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
semantic versioning with the following named version components: ${major}.${minor}.${patch}. When this function
is called, it will utilize the `cicd_info` function which figures out what the next version tag would be by simply
taking `${patch} + 1`. This is then created and optionally pushed.

By default, this function requires being on the `main` branch. Use `--branch` to specify a different branch.
END
cicd_create_next_version_tag()
{
    local _message="[Build Automation] Auto tagged by automation pipeline"
    $(opt_parse \
        ":branch b=main       | Branch where tags are created. Must be on this branch." \
        ":message=${_message} | Message to use for commit of new version tag."          \
        "+push                | Push the resulting new tag."                            \
        ":tag_match=v*.*.*    | Git tag pattern for semantic versioning."               \
    )

    # Save expected branch before pack_import overwrites the variable
    local expected_branch="${branch}"

    local info=""
    cicd_info --tag-match "${tag_match}" info
    $(pack_import info)

    if edebug_enabled; then
        einfo "CI/CD Version Info"
        pack_to_json info | jq .
    fi

    # Verify we are on the expected branch
    if [[ "${branch}" != "${expected_branch}" ]]; then
        die "Must be on ${expected_branch} branch to create next version tag (currently on ${branch})"
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

opt_usage cicd_update_version_files <<'END'
cicd_update_version_files is used to update version strings in project files as part of a release process. It can update
a VERSION file with the version string, and optionally update a README with a version badge. Changes can optionally be
committed to git.

Example usage:
```shell
cicd_update_version_files --tag "v1.2.3" --version-file share/VERSION --readme README.md --commit
```
END
cicd_update_version_files()
{
    $(opt_parse \
        "+commit       | Commit the changes to git."                                                  \
        ":message      | Commit message (default: '[Build Automation] Update version to TAG')."      \
        ":readme       | Path to README.md to update with version badge."                            \
        ":release_url  | URL for the version badge link (e.g. https://github.com/org/repo/releases)." \
        "=tag t        | Version tag string to set (e.g. v1.2.3)."                                   \
        ":version_file f | Path to VERSION file to update."                                          \
    )

    local files_updated=()

    # Update VERSION file if specified
    if [[ -n "${version_file}" ]]; then
        einfo "Updating ${version_file} to ${tag}"
        echo "${tag}" > "${version_file}"
        files_updated+=("${version_file}")
    fi

    # Update README.md version badge if specified
    if [[ -n "${readme}" && -f "${readme}" ]]; then
        einfo "Updating ${readme} with version ${tag}"
        local badge_url="https://img.shields.io/badge/version-${tag}-blue"
        local link_url="${release_url:-}"

        if grep -q "^\[!\[Version\]" "${readme}"; then
            # Update existing version badge
            if [[ -n "${link_url}" ]]; then
                sed -i "s|\[!\[Version\]([^)]*)\]([^)]*)|\[!\[Version\](${badge_url})\](${link_url})|" "${readme}"
            else
                sed -i "s|\[!\[Version\]([^)]*)\]|\[!\[Version\](${badge_url})\]|" "${readme}"
            fi
        else
            # Add version badge after CI badge line (if CI badge exists)
            local badge_line="[![Version](${badge_url})]"
            if [[ -n "${link_url}" ]]; then
                badge_line+="(${link_url})"
            fi
            if grep -q "^\[!\[CI" "${readme}"; then
                sed -i "/^\[!\[CI/a ${badge_line}" "${readme}"
            else
                # Prepend to file if no CI badge
                sed -i "1i ${badge_line}\n" "${readme}"
            fi
        fi
        files_updated+=("${readme}")
    fi

    # Commit changes if requested
    if [[ "${commit}" -eq 1 && ${#files_updated[@]} -gt 0 ]]; then
        : ${message:="[Build Automation] Update version to ${tag} [skip ci]"}
        einfo "Committing version updates"
        git add "${files_updated[@]}"
        git commit -m "${message}"
    fi
}

opt_usage cicd_release <<'END'
cicd_release is used to push from one branch to another (e.g., develop to main). This is useful for projects that use
a two-branch workflow where development happens on one branch and releases are pushed to another.

For single-branch workflows (where --from and --to are the same), this function is a no-op and returns successfully.

Example usage:
```shell
# Two-branch workflow: push develop to main
cicd_release --from develop --to main

# Single-branch workflow: no-op (already on release branch)
cicd_release --from main --to main
```
END
cicd_release()
{
    $(opt_parse \
        ":from=main | Source branch to release from. Must be on this branch." \
        ":to=main   | Target branch to push to."                              \
    )

    # Single-branch model: no-op
    if [[ "${from}" == "${to}" ]]; then
        einfo "Single-branch model: already on release branch ${to}"
        return 0
    fi

    local info=""
    cicd_info info
    $(pack_import info)

    # Verify we are on the source branch
    if [[ "${branch}" != "${from}" ]]; then
        die "Must be on ${from} branch to release to ${to} (currently on ${branch})"
    fi

    einfo "Pushing ${from} -> ${to}"
    git push origin HEAD:${to}
}
