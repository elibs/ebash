# Module overlayfs

The overlayfs module is the ebash interface around OverlayFS mounts. This is a really useful filesystem that allows
layering mounts into a single unified mount point with read-through semantics. This is the first official kernel
filesystem providing this functionality which replaces prior similar filesystems such as unionfs, aufs, etc.

The implementation of the underlying kernel driver changed somewhat with different kernel versions. The first version
of the kernel which officially supported overlayfs was 3.18. This original API requires specifying the workdir option
for the scratch work performed by overlayfs. Overlayfs was available in older kernel versions but was not official and
did not have this additional "workdir" option.

## func overlayfs_changed


Check if there are any changes in an overlayfs or not.

```Groff
ARGUMENTS

   mnt
        mnt

```

## func overlayfs_commit


Commit all pending changes in the overlayfs write later back down into the lowest read-only layer and then unmount the
overlayfs mount. The intention of this function is that you should call it when you're completely done with an overlayfs
and you want its changes to persist back to the original archive. To avoid doing any unecessary work, this function will
first call overlayfs_dedupe and only if something has changed will it actually write out a new archive.

> **_NOTE:_** You can't just save the overlayfs mounted directory back to the original archive while it's mounted or
you'll corrupt the currently mounted overlayfs. To work around this, we archive the overlayfs mount point to a temporary
archive, then we unmount the current mount point so that we can safely copy the new archive over the original archive.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --color, -c
         Show a color diff if possible.

   --dedupe, -D
         Dedupe contents before commit.

   --diff, -d
         Show a unified diff of the changes.

   --error, -e
         Error out if there is nothing to do.

   --list, -l
         List the changes to stdout.

   --post-commit <value>
         Callback to invoke after commit completes.

   --pre-commit <value>
         Callback to invoke before commit begins.

   --progress, -p
         Show eprogress while committing changes.


ARGUMENTS

   mnt
         The overlayfs mount point.

```

## func overlayfs_dedupe


Dedupe files in overlayfs such that all files in the upper directory which are identical IN CONTENT to the original
ones in the lower layer are removed from the upper layer. This uses 'diff' to compare each file. Even if the upper file
has a newer timestamp it will be removed if its content is otherwise identical.

```Groff
ARGUMENTS

   mnt
        mnt

```

## func overlayfs_diff


Show a unified diff between the lowest and upper layers.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --color, -c
         Display diff in color.


ARGUMENTS

   mnt
         Overlayfs mount.

```

## func overlayfs_enable

Try to enable overlayfs by modprobing the kernel module.

## func overlayfs_layers


Parse an overlayfs mount point and populate a pack with entries for the sources, lowerdirs, lowest, upperdir, workdir,
and src and mnt.

> **_NOTE:_** Because 'lowerdir' may actually be stacked its value may contain multiple whitespace separated entries we
use the key 'lowerdirs' instead of 'lowerdir' to more accurately reflect that it's multiple entries instead of a single
entry. There is an additional 'lowest' key we put in the pack that is the bottom-most 'lowerdir' when we need to
directly access it.

> **_NOTE:_** Depending on kernel version, 'workdir' may be empty as it may not be used.

```Groff
ARGUMENTS

   mnt
         Overlayfs mount point to list the layers for.

   layers_var
         Pack to store the details into.

```

## func overlayfs_list_changes


List the changes in an overlayfs

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --long, -l
         Display long listing format.


ARGUMENTS

   mnt
         The mountpoint to list changes for.

```

## func overlayfs_mount

overlayfs_mount mounts multiple filesystems into a single unified writeable directory with read-through semantics. All
the underlying filesystem layers are mounted read-only (if they are mountable) and the top-most layer is mounted
read-write. Only the top-level layer is mounted read-write.

The most common uses cases for using overlayfs is to mount ISOs or squashfs images with a read-write layer on top of
them. To make this implementation as generic as possible, it deals only with overlayfs mounting semantics. The specific
mounting of ISO or squashfs images are handled by separate dedicated modules.

This function takes multiple arguments where each argument is a layer to mount into the final unified overlayfs image.
The final positional parameter is the final mount point to mount everything at. This final directory will be created if
it doesn't exist.

The versioning around OverlayFS is quite complex. The first version of the kernel which officially supported overlayfs
was 3.18 and the kernel module name is just 'overlay'. Earlier, unofficial versions of the kernel module used the module
name 'overlayfs'. The newer module 'overlay' requires specifying an additional 'workdir' option for the scratch work
performed by overlayfs. 3.19 added support for layering up to two overlayfs mounts on top of one another. 3.20 extended
this support even more by allowing you to chain as many as you'd like in the 'lowerdir' option separated by colons and
it would overlay them all seamlessly. The 3.19 version is not particularly interesting to us due to it's limitation of
only 2 layers so we don't use that one at all.

## func overlayfs_save_changes


Save the top-most read-write later from an existing overlayfs mount into the requested destination file. This file can
be a squashfs image, an ISO, or any supported archive format.

```Groff
ARGUMENTS

   mnt
        mnt

   dest
        dest

```

## func overlayfs_supported

Detect whether overlayfs is supported or not.

## func overlayfs_tree


overlayfs_tree is used to display a graphical representation for an overlayfs mount. The graphical format is meant to
show details about each layer in the overlayfs mount hierarchy to make it clear what files reside in what layers along
with some basic metadata about each file (as provided by find -ls). The order of the output is top-down to clearly
represent that overlayfs is a read-through layer cake filesystem such that things "above" mask things "below" in the
layer cake.

```Groff
ARGUMENTS

   mnt
        mnt

```

## func overlayfs_unmount


overlayfs_unmount will unmount an overlayfs directory previously mounted via overlayfs_mount. It takes multiple
arguments where each is the final overlayfs mount point. In the event there are multiple overlayfs layered into the
final mount image, they will all be unmounted as well.

```Groff
ARGUMENTS

   mnt
        mnt

```
