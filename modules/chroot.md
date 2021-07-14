# Module chroot


## func chroot_install_check

Check if all the packages listed can be installed

## func chroot_kill


Send a signal to processes inside _this_ CHROOT (designated by ${CHROOT}) that match the given regex. [note: regex
support is identical to pgrep]

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --kill-after, -k <value>
         Also send SIGKILL to processes that are still alive after this duration.  (Does not block)

   --signal, -s <value>
         The signal to send to killed pids.


ARGUMENTS

   regex
         Pgrep regex that should match processes you'd like to signal. If none is specified,
         all processes in the chroot will be killed.

```

## func chroot_pids


Get a listing of all the pids running inside a chroot (if any). It is not an error for there to be no pids running in
a chroot so this will not return an error in that scenario.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --regex <value>
         Pgrep regex that should match processes you'd like returned. If none is specified,
         all processes in the chroot will be listed.

```

## func chroot_readlink


Read a symlink inside a CHROOT and give full path to the symlink OUTSIDE the chroot. For example, if inside the CHROOT
you have `/a` -> `/b` then:

```shell
$ chroot_readlink "/a"
"${CHROOT}/b"
```

```Groff
ARGUMENTS

   path
        path

```

## func mkchroot


Create an UBUNTU based CHROOT using debootstrap.

```Groff
ARGUMENTS

   CHROOT
        CHROOT

   UBUNTU_RELEASE
        UBUNTU_RELEASE

   UBUNTU_ARCH
        UBUNTU_ARCH

```
