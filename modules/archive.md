# Module archive

archive.sh is a generic module for dealing with various archive formats in a generic and consistent manner. It also
provides some really helpful and missing functionality not provided by upstream tools.

At present the list of supported archive formats is as follows:

- **SQUASHFS**: Squashfs is a compressed read-only filesystem for Linux. Squashfs intended for general read-only filesystem
use, for archival use and in constrained block device/memory systems where low overhead is needed. Squashfs images are
rapidly becoming a very common medium used throughout our build, install, test and upgrade code due to their high
compressibility, small resultant size, massive parallelization on both create and unpack and that they can be directly
mounted and booted into.

- **ISO**: An ISO image is an archive file of an optical disc, a type of disk image composed of the data contents from every
written sector on an optical disc, including the optical disc file system. The name ISO is taken from the ISO
9660 file system used with CD-ROM media, but what is known as an ISO image can contain other file systems.

- **TAR**: A tar file is an archive file format that may or may not be compressed. The archive data sets created by tar
contain various file system parameters, such as time stamps, ownership, file access permissions, and directory
organization. Our archive_compress_program function is used to generalize our use of tar so that compression format is
handled seamlessly based on the file extension in a way which picks the best compression program at runtime.

- **CPIO**: "cpio is a general file archiver utility and its associated file format. It is primarily installed on Unix-like
computer operating systems. The software utility was originally intended as a tape archiving program as part of the
Programmer's Workbench (PWB/UNIX), and has been a component of virtually every Unix operating system released
thereafter. Its name is derived from the phrase copy in and out, in close description of the program's use of standard
input and standard output in its operation. All variants of Unix also support other backup and archiving programs,
such as tar, which has become more widely recognized.[1] The use of cpio by the RPM Package Manager, in the initramfs
program of Linux kernel 2.6, and in Apple Computer's Installer (pax) make cpio an important archiving tool"
(https://en.wikipedia.org/wiki/Cpio).

## func archive_append


Append a given list of paths to an existing archive atomically. The way this is done atomically is to do all the work on
a temporary file and only move it over to the final file once all the append work is complete. The reason we do this
atomically is to ensure that we never have a corrupt or half written archive which would be unusable. If the destination
archive does not exist this will implicitly call archive_create much like 'cat foo >> nothere'.

This function suports the `PATH_MAPPING_SYNTAX` as described in [mount](mount.md).

> **_NOTE:_** The implementation of this function purposefully doesn't use native `--append` functions in the archive
formats as they do not all support it. The ones which do support append do not implement in a remotely sane manner. You
might ask why we don't use overlayfs for this. First, overlayfs with bindmounting and chroots on older kernels causes
some serious problems wherein orphaned mounts become unmountable and the file systems containing them cannot be
unmounted later due to reference counts not being freed in the kernel. Additionally, if compression is used (which it
almost always is) we are forced to decompress and recompress the archive regardless so overlayfs doesn't save us
anything. If you're really concerned about performance just ensure TMPDIR is in memory as that is where all the work is
performed.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --best
         Use the best compression (level=9).

   --bootable, --boot, -b
         Make the ISO bootable (ISO only).

   --delete
         Delete the source files after successful archive creation.

   --dereference
         Dereference (follow) symbolic links (tar only).

   --fast
         Use the fastest compression (level=1).

   --ignore-missing, -i
         Ignore missing files instead of failing and returning non-zero.

   --level, -l <value>
         Compression level (1=fast, 9=best).

   --nice, -n
         Be nice and use non-parallel compressors and only a single core.

   --volume, -v <value>
         Optional volume name to use (ISO only).


ARGUMENTS

   dest
         Archive to append files to.

   srcs
         Source paths to append to the archive.
```

## func archive_compress_program


Determine the best compress programm to use based on the archive suffix.

Uses the following algorithm based on filename suffix:

    *.bz2|*.tz2|*.tbz2|*.tbz)
        use first available from ( lbzip2 pbzip2 bzip2 )
    *.gz|*.tgz|*.taz|*.cgz)
        use first available from ( pigz gzip )
    *.lz|*.xz|*.txz|*.tlz|*.cxz|*.clz)
        use first available from ( lzma xz )

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --nice, -n
         Be nice and use non-parallel compressors and only a single core.

   --type, -t <value>
         Override automatic type detection and use explicit archive type.


ARGUMENTS

   fname
         Archive file name.

```

## func archive_convert


Convert given source file into the requested destination type. This is done by figuring out the source and destination
types using archive_type. Then it mounts the source file into a temporary file, then calls archive_create on the
temporary directory to write it out to the new destination type.

```Groff
ARGUMENTS

   src
        src

   dest
        dest

```

## func archive_create


Generic function for creating an archive file of a given type from the given list of source paths and write it out to
the requested destination directory. This function will intelligently figure out the correct archive type based on the
suffix of the destination file.

This function suports the `PATH_MAPPING_SYNTAX` as described in [mount](mount.md).

You can also optionally exclude certain paths from being included in the resultant archive. Unfortunately, each of the
supported archive formats have different levels of support for excluding via filename, glob or regex. So, to provide a
common interface in archive_create, we pre-expand all exclude paths using find(1).

This function also provides a uniform way of dealing with multiple source paths. All of the various archive formats
handle this differently so the uniformity is important. Essentially, any path provided will be the name of a top-level
entry in the archive with the entire directory structure intact. This is essentially how tar works but different from
how mksquashfs and mkiso normally behave.

A few examples will help clarify the behavior:

Example #1: Suppose you have a directory `a` with the files `1,2,3` and you call `archive_create a dest.squashfs`.
archive_create will then yield the following:

```shell
a/1
a/2
a/3
```

Example #2: Suppose you have these files spread out across three directories: `a/1` `b/2` `c/3` and you call
`archive_create a b c dest.squashfs`. `archive_create` will then yield the following:

```shell
a/1
b/2
c/3
```

In the above examples note that the contents are consistent regardless of whether you provide a single file, single
directory or list of files or list of directories.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --best
         Use the best compression (level=9).

   --bootable, --boot, -b
         Make the ISO bootable (ISO only).

   --delete
         Delete the source files after successful archive creation.

   --dereference
         Dereference (follow) symbolic links (tar only).

   --directory, --dir, -d <value>
         Directory to cd into before archive creation.

   --exclude, -x <value>
         List of paths to be excluded from archive.

   --fast
         Use the fastest compression (level=1).

   --ignore-missing, -i
         Ignore missing files instead of failing and returning non-zero.

   --level, -l <value>
         Compression level (1=fast, 9=best).

   --nice, -n
         Be nice and use non-parallel compressors and only a single core.

   --type, -t <value>
         Override automatic type detection and use explicit archive type.

   --volume, -v <value>
         Optional volume name to use (ISO only).


ARGUMENTS

   dest
         Destination path for resulting archive.

   srcs
         Source paths to archive.
```

## func archive_diff

Diff two or more archive images.

## func archive_extract


Extract a previously constructed archive image. This works on all of our supported archive types. Also takes an
optional list of find(1) glob patterns to limit what files are extracted from the archive. If no files are provided it
will extract all files from the archive.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --ignore-missing, -i
         Ignore missing files instead of failing and returning non-zero.

   --nice, -n
         Be nice and use non-parallel compressors and only a single core.

   --strip-components, --strip <value>
         Strip this number of leading components from file names on extraction.

   --type, -t <value>
         Override automatic type detection and use explicit archive type.


ARGUMENTS

   src
         Source archive to extract.

   dest
         Location to place the files extracted from that archive.

```

## func archive_list


Simple function to list the contents of an archive image.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --type, -t <value>
         Override automatic type detection and use explicit archive type.


ARGUMENTS

   src
         Archive whose contents should be listed.

```

## func archive_mount


Mount a given archive type to a temporary directory read-only if mountable and if not extract it to the destination
directory.

```Groff
ARGUMENTS

   src
        src

   dest
        dest

```

## func archive_suffixes


Echo a list of the supported archive suffixes for the optional provided type. If no type is given it returns a unified
list of all the supported archive suffixes supported. By default the list of the supported suffixes is echoed as a
whitespace separated list. But using the --pattern option it will instead echo the result in a pattern-list which is a
list of one or more patterns separated by a '|'. This can then be used more seamlessly inside extended glob matching.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --pattern, -p
         Echo the results using pattern-list syntax instead of whitespace separated.

   --wildcard, -w
         Add wildcard * before each suffix.


ARGUMENTS

   types
         Filter the list of supported suffixes to the given archive types.
```

## func archive_type


Determine archive format based on the file suffix. You can override type detection by passing in explicit -t=type where
type is one of the supported file extension types (e.g. squashfs, iso, tar, tgz, cpio, cgz, etc). --no-die will make
archive_type output the type of archive or nothing, rather than dieing.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --die, -d
         die on error.

   --type, -t <value>
         Override automatic type detection and use explicit archive type.


ARGUMENTS

   src
         Archive file name.

```
