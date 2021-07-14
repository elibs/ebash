# Module filesystem


## func directory_empty


Check if a directory is empty

```Groff
ARGUMENTS

   dir
        dir

```

## func directory_not_empty


Check if a directory is not empty

```Groff
ARGUMENTS

   dir
        dir

```

## func ebackup


Copies the given file to *.bak if it doesn't already exist.

```Groff
ARGUMENTS

   src
        src

```

## func echmodown


echmodown is basically chmod and chown combined into one function.

```Groff
ARGUMENTS

   mode
         Filesystem mode bit flag to pass into chmod.

   owner
         Owner to pass into chown

   files
         The files to perform the operations on.
```

## func efreshdir

Recursively unmount the named directories and remove them (if they exist) then create new ones.

> **_NOTE:_** Unlike earlier implementations, this handles multiple arguments properly.

## func erestore


Copies files previously backed up via ebackup to their original location.

```Groff
ARGUMENTS

   src
        src

```

## func popd

Wrapper around popd to suppress its noisy output.

## func pushd

Wrapper around pushd to suppress its noisy output.
