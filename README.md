[![CI/CD](https://github.com/elibs/ebash/workflows/CI/CD/badge.svg?branch=master)](https://github.com/elibs/ebash/actions?query=workflow%3ACI%2FCD+branch%3Amaster)

<p align="center">
    <img alt="Bash" src="https://raw.githubusercontent.com/odb/official-bash-logo/master/assets/Logos/Identity/PNG/BASH_logo-transparent-bg-color.png">
</p>

# Overview

ebash is an open source project developed at [SolidFire](https://www.solidfire.com) for 8 years under the name `bashutils`. It was forked and
renamed to ebash by the original [developer](https://github.com/marshall-mcmullen) upon his departure after successful acquisition by NetApp. The primary goal of
ebash is to significantly enhance bash code and make it more *robust*, *feature rich* and *simple* which greatly
accelerates developer productivity.

## Why _bash_

Bash is the ideal language of choice for writing low-level shell scripts and tools requiring direct shell access
invoking simple shell commands on a system for a number of reasons:

* Prolific. Installed on every UNIX machine, minimizing dependencies, install complexity and size.
* Lightweight with low memory and CPU requirements suitable for appliances and embedded systems.
* Ideal for tasks running shell commands as it is native, and simpler than in higher level languages.

## Why _ebash_

Because bash is a lower level language, it lacks some of the features and more advanced data structures typically found
in higher level languages. ebash aims to be _the_ answer to this problem. The most important and compelling feature of
ebash is [implicit error detection](doc/implicit-error-detection.md). This typically results in bash scripts being 75% shorter due to removal of explicit
error handling and the ability to leverage extensive [ebash modules](doc/module/index).

* [Implicit error detection](doc/implicit-error-detection.md)
* [Logging framework](doc/logging.md)
* [Debugging](doc/debugging.md)
* [Data structures](doc/data-structures.md)
* [Option parsing](doc/opt.md)
* [Testing](doc/etest.md)
* [Mocking](doc/emock.md)
* [Linting](doc/binaries/bashlint.md)
* [Benchmarking](doc/binaries/ebench.md)
* [Compatibility](doc/compatibility.md)

## Quick Start

* [Installation](doc/installation.md)
* [Usage](doc/usage.md)
* [Porting](doc/porting.md)
* [Modules documentation](doc/modules/index.md)
* [Binaries documentation](doc/binaries/index.md)
* [Style Guide](doc/style.md)
* [Bash Gotchas](doc/gotchas.md)
* [Bash Resources](doc/links.md)
