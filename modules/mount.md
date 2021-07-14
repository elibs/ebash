# Module mount

The mount module deals with various filesystem related mounting operations which generally add robustness and additional
features over and above normal `mount` operations.

Many functions in this module support the `PATH_MAPPING_SYNTAX` idiom. Path mapping syntax is a generic idiom used to
map one path to another using a colon to delimit source and destination paths. This is a convenient idiom often used by
functions which need to have a source file and use it in an alternative location inside the function. For example,
`/var/log/kern.log:kern.log` specifies a source file of `/var/log/kern.log` and a destination file of `kern.log`.

The path mapping syntax also supports referring to the contents of a directory rather than the directory itself using
scp like syntax. For example, if you wanted to refer to the contents of `/var/log` instead of the directory `/var/log`,
you would say `/var/log/.`. The trailing `/.` indicates the contents of the directory should be used rather than the
directory itself. You can also map the contents of that directory into an alternative destination path using
`/var/log/.:logs`.

## func ebindmount


Bind mount $1 over the top of $2. Ebindmount works to ensure that all of your mounts are private so that we don't see
different behavior between systemd machines (where shared mounts are the default) and everywhere else (where private
mounts are the default).

Source and destination MUST be the first two parameters of this function. You may specify any other mount options after
them.

```Groff
ARGUMENTS

   src
        src

   dest
        dest

   mount_options
        @mount_options
```

## func ebindmount_into


Bind mount a list of paths into the specified directory. This function will iterate over all the source paths provided
and bind mount each source path into the provided destination directory. This function will merge the contents all into
the final destination path much like cp or rsync would but without the overhead of actually copying the files. To fully
cleanup the destination directory created by ebindmount_into you should use `eunmount --all --recursive`.

If there are files with the same name already in the destination directory the new version will be shadow mounted over
the existing version. This has the effect of merging the contents but allowing updated files to effectively replace what
is already in the directory. This property holds true for files as well as directories. Consider the following example:

```shell
echo "src1" >src1/file1
echo "src2" >src2/file1
ebindmount_into dest src1/. src2/.
cat dest/file1
src2
```

Notce that since `file1` existed in both `src1` and `src2` and we bindmount `src2` after `src1`, we will see the contents
of `src2/file1` inside `dest/file1` instead of `src1/file1`. The last one wins.

This example is true of directories as well with the important caveat that the directory's contents are still MERGED but
files shadow over one another. Consider the following example:

```shell
$ echo "src1" >src1/foo/file0
$ echo "src1" >src1/foo/file1
$ echo "src2" >src2/foo/file1
$ ebindmount_into dest src1/. src2/.
$ cat dest/foo/file1
src2
$ ls dest
foo/file0 foo/file1
```

Again, notice that since `file1` existed in both `src1/foo` and `src2/foo` and we bindmount `src2` after `src1`, we see
`src2` in the file instead of `src1`. Also, notice that the bindmount of the directory `src2/foo` did not hide the
contents of the existing `src1/foo` directory that we already bind mounted into dest.

`ebindmount_into` also supports `PATH_MAPPING_SYNTAX_DOC` described above.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --ignore-missing, -i
         Ignore missing files instead of failing and returning non-zero.


ARGUMENTS

   dest
         The destination directory to mount the specified list of paths into.

   srcs
         The list of source paths to bind mount into the specified destination.
```

## func efindmnt


Recursively find all mount points beneath a given root. This is like findmnt with a few additional enhancements:
- Automatically recusrive
- findmnt doesn't find mount points beneath a non-root directory

```Groff
ARGUMENTS

   path
        path

```

## func emount

Mount a filesystem.

**WARNING**: Do not use opt_parse in this function as then we don't properly pass the options into mount itself. Since
this is just a passthrough operation into mount you should see mount(8) manpage for usage.

## func emount_count


Echo the number of times a given directory is mounted.

```Groff
ARGUMENTS

   path
        path

```

## func emount_realpath


Helper method to take care of resolving a given path or mount point to its realpath as well as remove any errant
'\040(deleted)' which may be suffixed on the path. This can happen if a device's source mount point is deleted while the
destination path is still mounted.

```Groff
ARGUMENTS

   path
        path

```

## func emount_regex


Echo the emount regex for a given path.

```Groff
ARGUMENTS

   path
        path

```

## func emount_type


Get the mount type of a given mount point.

```Groff
ARGUMENTS

   path
        path

```

## func eunmount


Recursively unmount a list of mount points. This function iterates over the provided argument list and will unmount each
provided mount point if it is mounted. It is not an error to try to unmount something which is already unmounted as
we're already in the desired state and this is more useful in cleanup code.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --all, -a
         Unmount all copies of mount points instead of a single instance.

   --delete, -d
         Delete mount points after unmounting.

   --recursive, -r
         Recursively unmount everything beneath mount points.

   --verbose, -v
         Verbose output.

```

## func list_mounts

Platform agnostic mechanism for listing mounts.
