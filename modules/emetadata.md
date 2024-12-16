# Module emetadata


## func emd5sum

`emd5sum` is a wrapper around computing the md5sum of a file to output just the filename instead of the full path to the
filename. This is a departure from normal `md5sum` for good reason. If you download an md5 file with a path embedded
into it then the md5sum can only be validated if you put it in the exact same path. `emd5sum` is more flexible.

```Groff
ARGUMENTS

   path
        path

```

## func emd5sum_check

`emd5sum_check` is a wrapper around checking an md5sum file regardless of the path used when the file was originally
created. If someone unwittingly said `md5sum /home/foo/bar` and then later moved the file to `/home/zap/bar`, and ran
`md5sum -c` on the relocated file it would fail. This works around this silly problem by assuming that the md5 file is a
sibling to the original source file and ignores the path specified in the md5 file. Then it manually compares the MD5
from the file with the actual MD5 of the source file.

```Groff
ARGUMENTS

   path
        path

```

## func emetadata

`emetadata` is used to output various metadata information about the provided file to STDOUT. By default this outputs a
number of common metadata and digest information about the provided file such as Filename, MD5, Size, SHA1, SHA256, etc.
It can also optionally emit a bunch of Git related metadata using the `--git` option. This will then emit additional
fields such as `GitOriginUrl`, `GitBranch`, `GitVersion`, and `GitCommit`. Finally, all additional arugments provided
after the filename are interpreted as additional `tag=value` fields to emit into the output.

Here is example output:

```shell
BuildDate=2020-11-25T03:36:44UTC
Filename=foo
GitBranch=develop
GitCommit=f59a8535afd05b816cf891ec09bddd19fca92ebd
GitOriginUrl=http://github.com/elibs/ebash
GitVersion=v1.6.4
MD5=864ec6157c1eea88acfef44d0f34d219
SHA1=75490a32967169452c10c937784163126c4e9753
SHA256=8297aefe5bb7319ab5827169fce2e664fe9cd7b88c9b31c40658ab55fcae3bfe
Size=2192793069
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --build-date, -b
         Include the current UTC date as BuildDate.

   --git, -g
         Include common Git metadata such as GitBranch, GitCommit, GitOriginUrl, GitVersion.

   --keyphrase, -k <value>
         The keyphrase to use for the specified private key.

   --private-key, -p <value>
         Also check the PGP signature based on this private key.


ARGUMENTS

   path
         Path of the filename to generate metadata for.

   entries
         Additional tag=value entries to emit.
```

## func emetadata_check

`emetadata_check` is used to validate an exiting source file against a companion *.meta file which contains various
checksum fields. The list of checksums is optional but at present the supported fields we inspect are: `Filename`,
`Size`, `MD5`, `SHA1`, `SHA256`, `SHA512`, `PGPSignature`.

For each of the above fields, if they are present in the .meta file, validate it against the source file. If any of them
fail this function returns non-zero. If NO validators are present in the info file, this function returns non-zero.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --public-key, -p <value>
         Path to a PGP public key that can be used to validate PGPSignature in .meta file.

   --quiet, -q
         If specified, produce no output. Return code reflects whether check was good or bad.


ARGUMENTS

   path
        path

```
