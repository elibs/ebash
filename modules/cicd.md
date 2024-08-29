# Module cicd


## func cicd_create_next_version_tag

cicd_create_next_version_tag is used to create the next version tag for a given Git repository. This operates using
semantic versioning with the following named version components: ${major}.${minor}.${patch}.${build}. When this function
is called, it will utilize the `cicd_info` function which figures out what the next version tag would be by simply
taking `${build} + 1`. This is then created and optionally pushed.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --message <value>
         Message to use for commit of new version tag.

   --push
         Push the resulting new tag.

```

## func cicd_info

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

```Groff
ARGUMENTS

   pack
         Name of the pack to fill in with CICD details.

```

## func cicd_print

cicd_print is used to import all CI/CD info for the current Git repository and then print that information to the screen.
By default this prints as a simple key/value list but options can be used to modify the output as desired.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --json, -j
         Instead of printing in simple key/value, this will instead print in JSON.

   --uppercase, -u
         Print keys in uppercase.

```

## func cicd_release

cicd_release is used to push the develop branch into the release branch. Typically the develop branch is named `develop`
and the release branch is named `master` or `main`. These can be configured via these two variables:
* `EBASH_CICD_DEVELOP_BRANCH`
* `EBASH_CICD_RELEASE_BRANCH`

It is an error to try to release code when not on the `DEVELOP` branch.
