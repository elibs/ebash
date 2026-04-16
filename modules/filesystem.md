# Module filesystem


## func directory_empty

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: directory_empty dir 

DESCRIPTION

Check if a directory is empty

```Groff
ARGUMENTS

   dir
        dir

```

## func directory_not_empty

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: directory_not_empty dir 

DESCRIPTION

Check if a directory is not empty

```Groff
ARGUMENTS

   dir
        dir

```

## func ebackup

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: ebackup src 

DESCRIPTION

Copies the given file to *.bak.

This version of ebackup() has been hardened a bit from prior versions. In particular it will now:
(1) assert the requested source file exists
(2) assert the backup file does not exist

This pushes some responsibility to the caller to orchestrate things properly instead of making assumptions about how
ebash will handle this.

```Groff
ARGUMENTS

   src
        src

```

## func echmodown

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: echmodown mode owner [files]...

DESCRIPTION

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

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: erestore src 

DESCRIPTION

Copies files previously backed up via ebackup to their original location.

```Groff
ARGUMENTS

   src
        src

```

## func is_backed_up

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: is_backed_up src 

DESCRIPTION

This is a helper function to check if ebackup was previously run against a source file.
This will mean for any given ${src} file there exists a ${src}.bak.

```Groff
ARGUMENTS

   src
        src

```

## func popd

Wrapper around popd to suppress its noisy output.

## func pushd

Wrapper around pushd to suppress its noisy output.

## func readall

Read entire contents into a variable using the read builtin. This is more efficient than $(cat file) as it avoids
fork/exec overhead. Unlike `read` which reads one line, `readall` reads all content. Usage mirrors the native read
builtin with file redirection:

```shell
readall content < file.txt
readall content < /dev/stdin
readall content <<< "string"
```

Trailing newlines are stripped to match $(cat file) behavior.
Returns success for normal reads (including EOF), failure for actual errors.
