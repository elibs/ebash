# etest Test Framework

## Overview

etest is an extensible test framework provided by ebash. It supports executing any arbitrary executable scripts in any
language in which case it functions as a simple test driver. But the really nice features provided by etest are realized
when you group your tests into test suites where each suite is encapsulated into a *.etest file. Each unit test is a
function inside the *.etest file.

ebash has a fairly extensive test suite at this point, containing over 700 tests that cover pretty much all of the
important functionality, and we try to add more any time we discover a problem so that it doesn't return. Every test
is run on every commit against a massive [matrix](compatibility.md) of Linux Distros and MacOS machines.

## Features

* Unit tests are grouped into test suites or modules
* Unit tests can share common setup and teardown code via a `setup` function which gets run before each unit test and a
  `teardown` function which gets run after each unit test.
* Test suites can share common suite-wide setup and teardown code via `suite_setup` function which gets run once before
  the entire test suite and a `suite_teardown` function which gets run after the last test in the test suite.
* Each unit test runs in its own subshell to ensure process-level isolation
* Each unit test is run inside a cgroup (if running on Linux) for process, mount, and pid isolation.
* Each unit test is monitored for process leaks and mount leaks
* Tests can be repeated, filtered, traced, skipped, debugged, etc.
* Xunit output is generated for every test run to integrate into CI/CD frameworks.

## Usage

See [etest usage](binaries/etest.md)

## Asserts

ebash and etest provide an extremely rich interface for testing code via various `assert` functions. If an assertion
fails, the test fails and a stack trace is printed to show you the cause and location of the failure. The complete list
of assertions is available in [assert](modules/assert.md) but some of the most useful are:

* `assert`
* `assert_true`
* `assert_false`
* `assert_eq`
* `assert_ne`
* `assert_lt`
* `assert_le`
* `assert_gt`
* `assert_ge`
* `assert_match`
* `assert_not_match`
* `assert_zero`
* `assert_not_zero`
* `assert_empty`
* `assert_not_empty`
* `assert_var_empty`
* `assert_exists`
* `assert_not_exists`
* `assert_archive_contents`
* `assert_directory_contents`
* `assert_int`
* `assert_num`
* `assert_num_eq`
* `assert_num_lt`
* `assert_num_le`
* `assert_num_gt`
* `assert_num_ge`

## Creating your own etests

Over time, `etest` has become a fairly robust way to run tests for anything that you can call from bash. Today, we
have `etest` suites for several tools outside of ebash, too. It's designed so that it's easy to create your own by
creating one or more test files. Here's an entire (simple) test file. Filesnames should end in `.etest`.

```shell
#!/bin/bash
ETEST_will_pass()
{
    true
}

ETEST_will_fail()
{
    false
}
```

Both of the functions here will be executed as individual tests because their names start with `ETEST_`. Note that
although this file isn't executed directly, it needs a shebang line at the top that includes the word `bash` because
that's one of the ways etest determines whether it can execute a file. Plus it makes editors happier as they can do
syntax highlighting.

```shell
$ ./etest -f=mytest.etest
>> Starting tests in /home/modell/sf/ebash/mytest.etest
   - ETEST_will_fail                                             [ !! ]
   - ETEST_will_pass                                             [ ok ]

>> Finished testing ebash b8ceaa772b6a+. 1/2 tests passed in 7 seconds.

>> FAILED TESTS:
      will_fail
```

Here we ran just the tests in my new file (which I named `mytest.etest`). The `-f` on that line is used to specify a
filter. The filter is a bash regular expression or a whitespace separated list of terms. If it is specified, it must
match either the filename or the function name of the test. I could've chosen either single test by running
`./etest -f=fail` or `./etest -f=pass`.

`etest` also has options to repeat tests (`--repeat` / `-r`), break on error (`--break` / `-b`), exclude tests that
match a pattern (`--exclude` / `-x`), and more.

There are literally thousands of tests to look at for examples [here](https://github.com/elibs/ebash/tree/master/tests).

## Test verbosity

That listing of test passes and failures looks nice, but when your test fails, it's not particularly helpful.But
there's more available. We just have to look for it in the log file, or turn it on with `etest --verbose` or `etest -v`.

Before we try that, I'll replace my tests with something (slightly) more complicated. I'll replace `ETEST_will_pass`
with this:

```shell
ETEST_will_pass()
{
    etestmsg "Step 1"
    echo "hi from step 1"
    etestmsg "Step 2"
    echo "hi from step 2"
    etestmsg "Step 3"
}
```

Non-verbose mode would look the same, so we'll run it in verbose mode:

```shell
$ ./etest -f=pass -v
+-----------------------------------------------------------------+
|
| ETEST_will_pass
|
| • REPEAT  :: ""
|
+-----------------------------------------------------------------+
## Calling test
## Step 1
hi from step 1
## Step 2
hi from step 2
## Step 3

>> ETEST_will_pass PASSED.

>> Finished testing ebash b8ceaa772b6a+. 1/1 tests passed in 5 seconds.
```

Even when your individual steps write more to the screen than a simple echo, the messages produced by `etestmsg` are
colored so as to stand out against all the other text. Since all of this (and the regular output) is hidden when running
default test runs, in verbose we tend to dump lots of text to the screen.Don't hesitate to put that json blob or file
contents that might later make it a lot easier to figure out what went wrong.

All of this verbose output is actually available all the time. It's stored in a log file. After your (verbose or
non-verbose) `etest` run, look at `etest.log`.

## Mocking

ebash supports an extensive mocking framework called emock. It integrates well into the rest of ebash and etest in
particular to make it very easy to mock out real system binaries and replace them with mock instances which do something
else. It is very flexible in the behavior of the mocked function utilizing the many provided option flags.

This is an absolutely indispensable test strategy. Please see [mocking](modules/emock.md) for all the details.

## Long Running Commands

One common thing we have to frequently do to harden our tests is to _wait_ for something to complete before moving onto
the next part of the test. There are a few things of interest to point out:

* We don't want to have an arbitrary sleep 5 in our test code. This is bad for so many reasons. How do we know that 5
seconds is enough? Will this make the test flaky? Is there some real condition we could check instead of waiting an
arbitrary amount of time?
* We don't want to wait an indefinite amount of time on a condition which may never happen or we'll have a "runaway train"
test which will eat up all our build minutes. So we'd like to timeout the check at some point.
* We'd like some progress output to indicate what the test is doing so we don't think it is hung.

All of these requirements can be easily addressed with [eretry](modules/eretry.md). In it's simplest form all you have to
do is prefix your normal bash command with `eretry`. By default, it will try the command 5 times, with a sleep of 1
second between each iteration. If the command returns success then it will stop retrying. If the condition never becomes
true, then the test will fail!

You can get super fancy with `eretry` if you'd like to customize how long it runs for and give more frequent diagnostic
outputs and change the color, etc.

<details><summary>Complex example</summary>
<p>

```shell
etestmsg "Installing into ubuntu18.04 container"
container_id=$(docker run \
                    --env "DEBIAN_FRONTEND=noninteractive"           \
                    --detach                                         \
                    --volume "${builds}:${builds}"                   \
                    --volume "${install_script}:${install_script}"   \
                    --workdir "${builds}"                            \
                    ubuntu:18.04                                     \
                    "${install_script}")
```
</p>
</details>
