# Module os


## func command_exists

Helper function to check if a command exists. The actual implementation could be a function in our environment or an
external program.

## func edistro

edistro is a generic way to figure out what "distro" we are running on. This is largely only a Linux concept so on MacOS
this produces "darwin" as per `uname` output. Otherwise, Linux generically supports getting the Distro by looking in
`/etc/os-release`. This is lighter weight than having to ensure that lsb_release is installed on all clients. If we have
to, we'll fall back to lsb_release and finally just use raw `uname` output if nothing is available.

## func os_pretty_name

Get a prety name for this OS in the form of:

```shell
${DISTRO} ${OS} ${RELEASE}
```

For example:
```
Gentoo Linux 2.7
Alpine Linux 3.11
Darwin 10.15.7
```

## func os_release


Get the released version of the currently running OS or distribution, OR check whether that is in a list of release
versions that you specify.

```Groff
ARGUMENTS

   args
         If specified, as long as the release of the current OS or distro is one of those in
         the list, the command will succeed. If unspecified, the current release will simply
         be printed.
```

## func require

Helper function to validate that a list of commands are all installed in our PATH.
