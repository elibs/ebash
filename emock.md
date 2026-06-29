# Mocking

## Overview

One of the most effective test strategies used in higher-level object-oriented languages is called [mocking](https://en.wikipedia.org/wiki/Mock_object).
It`s a powerful test strategy that is not limited to just object-oriented languages. It’s actually really powerful for
low-level OS testing as well where you basically want to test just your code and not the entire OS. The typical strategy
here is to essentially create a mock function or script which gets called instead of the real OS level component.

ebash supports an extensive mocking framework called [emock](modules/emock.md). It integrates well into the rest of ebash and etest in
particular to make it very easy to mock out real system binaries and replace them with mock instances which do something
else. It is very flexible in the behavior of the mocked function utilizing the many provided option flags.

## Usage

The simplest invocation of `emock` is to use the default of function mocking. In this mode, you simply supply the name
of the binary you wish to mock, such as:

```shell
emock "dmidecode"
```

This will create and export a new function called `dmidecode` that can be invoked instead of the real `dmidecode`
binary at `/usr/bin/dmidecode`. This also creates a function named `dmidecode_real` which can be invoked to get access
to the real underlying `dmidecode` binary at `/usr/sbin/dmidecode`.

By default, this mock function will simply return `0` and produce no stdout or stderr. This behavior can be customized
using the options `--return-code`, `--stdout`, and `--stderr`.

Mocking a real binary with a simplex name like this is the simplest, but doesn't always work. In particular, if at the
call site you call it with the fully-qualified path to the binary, as in `usr/sbin/dmidecode`, then our mocked function
won't be called. In this scenario, you need to  mock it with the fully qualified path just as you would invoke it at the
call site. For example:

```shell
emock "/usr/sbin/dmidecode"
```

Just as before, this will create and export a new function named `/usr/sbin/dmidecode` which will be called in place of
the real `dmidecode` binary. It will also create a `/usr/sbin/dmidecode_real` function which will point to the real binary
in case you need to call it instead.

`emock` tracks various metadata about mocked binaries for easier testability. This includes the number of times a mock is
called, as well as the arguments (newline delimieted arg array), exit code, stdout, and stderr for each invocation. By
default this is created in a local hidden directory named `.emock` and there will be a directory beneath that for each
mock:

```shell
.emock/dmidecode/called
.emock/dmidecode/0/{args,exit,stdout,stderr}
.emock/dmidecode/1/{args,exit,stdout,stderr}
```

## Mock Utility Functions

There are many utility functions to help with mocking which you can check out in the [emock documentation](modules/emock.md):

* `emock`
* `eunmock`
* `emock_called`
* `emock_stdout`
* `emock_stderr`
* `emock_args`
* `emock_return_code`
* `assert_emock_called`
* `assert_emock_stdout`
* `assert_emock_stderr`
* `assert_emock_return_code`
* `assert_emock_called_with`
