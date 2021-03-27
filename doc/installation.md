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
$ echo "PATH+=:${HOME}/code/ebash/bin/ebash" >> ~/.bashrc
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
