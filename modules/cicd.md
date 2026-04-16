# Module cicd


## func cicd_create_next_version_tag

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_create_next_version_tag [option]... 

DESCRIPTION

cicd_create_next_version_tag is used to create the next version tag for a given Git repository. This operates using
semantic versioning with the following named version components: ${major}.${minor}.${patch}. When this function
is called, it will utilize the `cicd_info` function which figures out what the next version tag would be by simply
taking `${patch} + 1`. This is then created and optionally pushed.

By default, this function requires being on the `main` branch. Use `--branch` to specify a different branch.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --branch, -b <value>
         Branch where tags are created. Must be on this branch.

   --message <value>
         Message to use for commit of new version tag.

   --push
         Push the resulting new tag.

   --tag-match <value>
         Git tag pattern for semantic versioning.

```

## func cicd_info

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_info [option]... pack 

DESCRIPTION

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

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --tag-match <value>
         Git tag pattern for semantic versioning.


ARGUMENTS

   pack
         Name of the pack to fill in with CICD details.

```

## func cicd_print

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_print [option]... 

DESCRIPTION

cicd_print is used to import all CI/CD info for the current Git repository and then print that information to the screen.
By default this prints as a simple key/value list but options can be used to modify the output as desired.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --json, -j
         Instead of printing in simple key/value, this will instead print in JSON.

   --tag-match <value>
         Git tag pattern for semantic versioning.

   --uppercase, -u
         Print keys in uppercase.

```

## func cicd_release

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_release [option]... 

DESCRIPTION

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

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --from <value>
         Source branch to release from. Must be on this branch.

   --to <value>
         Target branch to push to.

```

## func cicd_update_version_files

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_update_version_files (--tag|-t <non-empty value>) [option]... 

DESCRIPTION

cicd_update_version_files is used to update version strings in project files as part of a release process. It can update
a VERSION file with the version string, and optionally update a README with a version badge. Changes can optionally be
committed to git.

Example usage:
```shell
cicd_update_version_files --tag "v1.2.3" --version-file share/VERSION --readme README.md --commit
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --commit
         Commit the changes to git.

   --message <value>
         Commit message (default: '[Build Automation] Update version to TAG').

   --readme <value>
         Path to README.md to update with version badge.

   --release-url <value>
         URL for the version badge link (e.g. https://github.com/org/repo/releases).

   --tag, -t <non-empty value> (*)
         Version tag string to set (e.g. v1.2.3).

   --version-file, -f <value>
         Path to VERSION file to update.

```

## func cicd_version

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_version [option]... 

DESCRIPTION

cicd_version outputs the current version string with build date. It checks sources in this order:
1. git describe + commit date (preferred - includes commit offset and dirty state)
2. VERSION file (fallback for installed systems without git)

Always includes "-dirty" suffix if there are uncommitted changes. Format: "version (YYYY-MM-DD)"

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --file, -f <value>
         Path to VERSION file to read (fallback if git not available).

   --tag-match <value>
         Git tag pattern for semantic versioning.

```

## func cicd_version_update

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: cicd_version_update [option]... 

DESCRIPTION

cicd_version_update writes the current git describe version and build date to a VERSION file. This is typically called
during the release process to embed the version in the release artifact. Format: "version (YYYY-MM-DD)"

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --file, -f <value>
         Path to VERSION file to write.

   --tag-match <value>
         Git tag pattern for semantic versioning.

```
