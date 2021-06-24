# Installation

## Clone

The simplest mechanism for installing ebash is to simply clone it from Github:

```shell
git clone https://github.com/elibs/ebash.git ~/code/ebash
```

Alternatively you can download an archive from [ebash releases](https://github.com/elibs/ebash/releases).

## Update PATH

Next we need to update your `${PATH}` variable so that you can invoke `ebash` from the command-line from anywhere.
This means you need to add `ebash` into `${PATH}` inside your shell's configuration files.

For example:

```shell
$ echo "PATH+=:${HOME}/code/ebash/bin" >> ~/.bashrc
$ source ~/.bashrc
$ which ebash
/home/marshall/code/ebash/bin/ebash
```

## Alternative: Git Submodule

A very attractive way to use ebash is to embed it within another project as a [git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules).

Here is how you would set this up:

```shell
git submodule add https://github.com/elibs/ebash.git .ebash
```

## Dependencies

To help with installing the dependencies that ebash requires, check out the scripts in the `install` directory. All of
these scripts install packages through the appropriate package manager on your OS/Distro. These work on all the OS/Distros
that ebash supports as documented in [compatibility](compatibility.md).

- **all**: This is used to install all the dependencies installed by `depends` and `recommends` and also the `docker-config`.
- **depends**: This is used to install only the core dependencies that ebash absolutely requires to run properly. This
  is the absolute minimum set of packages that need to be installed. If you have failures in ebash from packages not
  being installed you definitely want to run this script.
- **recommends**: This is a set of packages that it is recommended to install to more fully utilize all of ebash functionality.
  Generally these are optional packages that are used by various ebash modules. Examples of these are things like `tar`,
  `gzip`, `mksquashfs` and `docker`. If you get errors from some of ebash's modules about programs not being installed
  then you should definitely run this script.
- **docker-config**: This script is generally not needed by anyone. It's sole purpose is to setup docker to work properly
  inside our CI/CD pipeline.
