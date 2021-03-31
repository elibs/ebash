# Logging Framework

## Logging Functions

ebash provides a few standard functions intended for logging output to the screen. `einfo` is intended for standard
informational messages. `ewarn` indicate non-fatal warnings that might warrant user attention. `eerror` is typically
used for errors and failure cases. All of these produce their output on stderr.

These commands are invoked in the same way as you might call `echo`. Here's an example:

```shell
einfo "einfo"
ewarn "ewarn"
eerror "eerror"
```

I'm not going to try to reproduce color in this guide, but by default the output looks like this, with green color for
info-level messages, yellow for warning, and red for errors.

```shell
>> einfo
>> ewarn
>> eerror
```

For more details see documentation:
* [einfo](modules/emsg.md#func-einfo)
* [ewarn](modules/emsg.md#func-ewarn)
* [eerror](modules/emsg.md#func-eerror)
* [emsg](modules/emsg.md#func-emsg)

## Customizing Log Format

The output can be customized in a number of ways. If you set `EFUNCS_COLOR=0` then all color will be completely disabled
for this and all ebash code.

Extensive customization is supported via the `EMSG_PREFIX` environment variable. The advantage to this being an
environment variable instead of option flags to each of the logging functions is that it allows you to globally alter
the logging format for _all logging messages_ with a single environment variable. This is super helpful to set inside a
CI/CD build system for example.

For example, you might want to show timestamps on all log messages:

```shell
$ EMSG_PREFIX=time ~/ebash_guide
[Nov 12 13:31:16] einfo
[Nov 12 13:31:16] ewarn
[Nov 12 13:31:16] eerror
```

Or, to request all information that ebash will produce, you can set `EMSG_PREFIX` to `all`:

```shell
$ EMSG_PREFIX=all ./ebash_guide
[Nov 12 13:24:19|INFO|ebash_guide:6:main] einfo
[Nov 12 13:24:19|WARN|ebash_guide:7:main] ewarn
[Nov 12 13:24:19|ERROR|ebash_guide:8:main] eerror
```

Here you can see the timestamp, log level, function name, line number, and filename of the code that generated the
message.There's a lot more you can do which are fully documented in [emsg documentation](modules/emsg.md#func-emsg).

## Banner

Another useful built-in output tool is [ebanner](modules/emsg.md#func-ebanner). This displays a very prominent banner
with a provided message which may be multi-line as well as the ability to provide an arbitrary number of extra arguments
which will be included in the banner in a pretty printed `tag: value` optionally uppercasing the keys for consistency.
All of this is implemented with [print_value](modules/emsg.md#func-print_value) for consistency in logging different
types.

```shell
$ ebanner "Here’s a banner"
+------------------------------------------------------------------------------------------------+
|
| Here's a banner
|
+------------------------------------------------------------------------------------------------+
```

Here's an example with additional arguments to display:

```shell
$ ebanner "Hello world" HOME USER PWD
+------------------------------------------------------------------------------------------------+
|
| Hello world
|
| • HOME  :: "/home/marshall"
| • PWD   :: "/home/marshall/code/ebash"
| • USER  :: "marshall"
|
+------------------------------------------------------------------------------------------------+
```

## `lval` for simple verbose logging

Because we frequently found ourselves typing things like `rc=${rc}` in our `edebug` and other logging statements, we
created a function called [lval](modules/emsg.md#func-lval) to help with this. If you instead use `$(lval rc)`, it will
produce the same output.

It also prints the output in a consistent format that makes it clear what is in your variable, even when it contains
whitespace. And it knows about bash types like arrays and associative arrays and handles them appropriately. You might
use it like this. You can, of course, use it with any tool that outputs an arbitrary string.

```shell
declare -A aa
aa[foo]=1
aa[bar]=2
local var="hello world"
array[0]=alpha
array[1]=beta
echo "$(lval aa var array)"

# Output:
aa=([bar]="2" [foo]="1" ) var="hello world" array=("alpha" "beta")
```

## Table

We frequently found ourselves wanting to generate nicely formatted tables show information or results of an operation.
For that we created [etable](modules/etable.md).

etable is designed to be able to easily produce a nicely formatted ASCII, HTML or "box-drawing" or "boxart" tables with
columns and rows. The input passed into this function is essentially a variadic number of strings, where each string
represents a row in the table.  Each entry provided has the columns encoded with a vertical pipe character separating
each column.

For example, suppose you wanted to produce this ASCII table:

```shell
+------+-------------+-------------+
| Repo | Source      | Target      |
+------+-------------+-------------+
| api  | develop-2.5 | release-2.5 |
| os   | release-2.4 | develop-2.5 |
| ui   | develop-2.5 | release-2.5 |
+------+-------------+-------------+
```

The raw input you would need to pass is as follows:

```shell
bin/etable \
  "Repo|Source|Target"          \
  "api|develop-2.5|release-2.5" \
  "os|release-2.4|develop-2.5"  \
  "ui|develop-2.5|release-2.5"
```

## Progress Bar

We frequently have to run very long-running tasks which can take tens of minutes. This makes the user wonder if the
process has hung or if it's still making progress. So we invented [eprogress](modules/emsg.md#func-eprogress) to make
this very easy to do in a very configurable manner.

This shows an animated spinner and a time counter:

```shell
$ eprogress "Doing stuff"
>> Doing stuff [00:00:02]
```

The ticker can be very customized:

* Disabled entirely using `EPROGRESS=0`
* Show on the left or right via `--align`
* Change how often it is printed via `--delay`
* Show the **timer** but not the **spinner** via `--no-spinner`
* Display contents of a **file** on each iteration
