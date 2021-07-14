# Module emsg


## func ebanner


Display a very prominent banner with a provided message which may be multi-line as well as the ability to provide any
number of extra arguments which will be included in the banner in a pretty printed tag=value optionally uppercasing the
keys if requested. All of this is implemented with print_value to give consistency in how we log and present information.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --lowercase, --lower, -l
         If enabled, keys will be all lowercased.

   --uppercase, --upper, -u
         If enabled, keys will be all uppercased.

```

## func eclear

`eclear` is used to clear the screen. But it's more portable than the standard `clear` command as it uses `tput` to
lookup the correct escape sequence needed to clear your terminal.

## func ecolor

`ecolor` is used to take a human color term such as `black` or with descriptors such as `bold black` and emit the ANSII
escape sequences needed to print to the screen to produce the desired color. Since we use a LOT of color messages
through ebash, this function caches the color codes in an associative array to avoid having to lookup the same values
repeatedly.

> **_NOTE:_** If `EFUNCS_COLOR` is set to `0`, this function is disabled and will not return any ANSII escape sequences.

## func ecolor_code

`ecolor_code` is used to map human color names like `black` to the corresponding ANSII color escape code (e.g. `0`).
This function supports the full 256 ANSII color code space.

## func edebug

`edebug` is a powerful debugging mechanism to conditionally emit **selective** debugging messages that are statically
in the source code based on the `EDEBUG` environment variable. By default, `edebug` messages will not produce any output.
Moreover, they do not add any overhead to the code as we return immediately from the `edebug` function if debugging is
not enabled.

For example, suppose I have the following in my source code:

```shell
edebug "foo just borked rc=${rc}"
```

You can activate the output from these `edebug` statements either wholesale or selectively by setting an environment
variable. Setting `EDEBUG=1` will turn on all `edebug` output everywhere. We use this pervasively, so that is probably
going to way too much noise.

Instead of turning everything on, you can turn on `edebug` just for code in certain files or functions. For example,
using `EDEBUG="dtest dmake"` will turn on debugging for any `edebug` statements in any scripts named `dtest` or `dmake`
or any functions named `dtest` or `dmake`.

Another powerful feature `edebug` supports is to send the entire output of another command into `edebug` without having
to put an `if` statement around it and worrying about sending the output to STDERR. This is super easy to do:

```shell
cmd | edebug
```

The value of `EDEBUG` is actually a space-separated list of terms. If any of those terms match the filename (just
basename) **or** the name of the function that contains an `edebug` statement, it will generate output.

## func edebug_disabled

`edebug_disabled` is the logical analogue of `edebug_enabled`. It returns success (0) if debugging is disabled and
failure (1) if it is enabled.

## func edebug_enabled

`edebug_enabled` is a convenience function to check if edebug is currently enabled for the context the caller is calling
from. This will return success (0) if `edebug` is enabled, and failure (1) if not. This can then be used to perform
conditional code depending on if debugging is enabled or not.

For example:

```shell
if edebug_enabled; then
    dmesg > dmesg.out
    ip    > ip.out
fi
```

## func eend


`eend` is used to print an informational ending message suitable to be called after an `emsg` function. The format of
this message is dependent upon the `return_code`. If `0`, this will print `[ ok ]` and if non-zero it will print `[ !! ]`.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --inline, -n
         Display eend inline rather than outputting a leading newline. The reason we emit a leading
         newline by default is to work properly with emsg functions (e.g. einfo, ewarn, eerror) as
         they all emit a message and then a trailing newline to move to the next line. When paired
         with an eend, we want that eend message to show up on the SAME line. So we emit some
         terminal magic to move up a line, and then right justify the eend message. This doesn't
         work very well for non-interactive displays or in CI/CD output so you can disable it.

   --inline-offset, -o <value>
         Number of characters to offset inline mode by.


ARGUMENTS

   return_code
         Return code of the command that last ran. Success (0) will cause an 'ok' message and
         any non-zero value will emit '!!'.

```

## func eerror

`eerror` is used to log error messages to STDERR. They are prefixed with `!!` in `COLOR_ERROR` which is `red` by
default. `eerror` is called just like you would normally call `echo`.

## func eerror_stacktrace


Print an error stacktrace to stderr. This is like stacktrace only it pretty prints the entire stacktrace as a bright red
error message with the funct and file:line number nicely formatted for easily display of fatal errors.

Allows you to optionally pass in a starting frame to start the stacktrace at. 0 is the top of the stack and counts up.
See also stacktrace and eerror_stacktrace.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --color, -c <value>
         Use the specified color for output messages.

   --frame, -f <value>
         Frame number to start at. Defaults to 2, which skips this function and its caller.

   --skip, -s
         Skip the initial error message. Useful if the caller already displayed it.

```

## func efuncs_color

Determine value to use for efuncs_color. If `EFUNCS_COLOR` is empty then set it based on if STDERR is attached to a
console or not.

## func efuncs_color_as_bool

Get efuncs_color as a boolean string.

## func einfo

`einfo` is used to log informational messages to STDERR. They are prefixed with `>>` in `COLOR_INFO` which is `green` by
default. `einfo` is called just like you would normally call `echo`.

## func einfos

`einfos` is used to log informational **sub** messages to STDERR. They are intdented and prefixed with a `-` in
`COLOR_INFOS` which is `cyan` by default. `einfos` is called just like you would normally call `echo`. This is designed
to line up underneath `einfo` messages to show submessages.

## func einteractive

Check if we are "interactive" or not. For our purposes, we are interactive if STDERR is attached to a terminal or not.
This is checked via the bash idiom "[[ -t 2 ]]" where "2" is STDERR. But we can override this default check with the
global variable EINTERACTIVE=1.

## func einteractive_as_bool

Get einteractive value as a boolean string

## func emsg

`emsg` is a common function called by all logging functions inside ebash to allow a very configurable and extensible
logging format throughout all ebash code. The extremely configrable formatting of all ebash logging is controllable via
the `EMSG_PREFIX` environment variable.

Here are some examples showcasing how configurable this is:

```shell
$ EMSG_PREFIX=time ~/ebash_guide
[Nov 12 13:31:16] einfo
[Nov 12 13:31:16] ewarn
[Nov 12 13:31:16] eerror

$ EMSG_PREFIX=all ./ebash_guide
[Nov 12 13:24:19|INFO|ebash_guide:6:main] einfo
[Nov 12 13:24:19|WARN|ebash_guide:7:main] ewarn
[Nov 12 13:24:19|ERROR|ebash_guide:8:main] eerror
```

In the above you can the timestamp, log level, function name, line number, and filename of the code that generated the
message.

Here's the full list of configurable things you can turn on:
- time
- level
- caller
- pid
- all

## func eprogress


`eprogress` is used to print a progress bar to STDERR in a highly configurable format. The typical use case for this is
to handle very long-running commands and give the user some indication that the command is still in-progress rather than
hung. The ticker can be customized:

- Disabled entirely using `EPROGRESS=0`
- Show on the left or right via `--align`
- Change how often it is printed via `--delay`
- Show the **timer** but not the **spinner** via `--no-spinner`
- Display contents of a **file** on each iteration

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --align <value>
         Where to align the tickker to (valid options are 'left' and 'right').

   --delay <value>
         Optional delay between tickers to avoid flooding the screen. Useful for automated CI/CD
         builds where we are not writing to an actual terminal but want to see periodic updates.

   --delete, -d
         Delete file when eprogress completes if one was specified via --file.

   --file, -f <value>
         A file whose contents should be continually updated and displayed along with the
         ticker. This file will be deleted by default when eprogress completes.

   --inline
         Display message, timer and spinner all inline. If you disable this the full message
         and timer is printed on a separate line on each iteration instead.  This is useful for
         automated CI/CD builds where we are not writing to an actual terminal.

   --spinner
         Display spinner inline with the message and timer.

   --style <value>
         Style used when displaying the message. You might want to use, for instance, einfos or
         ewarn or eerror instead.

   --time
         As long as not turned off with --no-time, the amount of time since eprogress start will
         be displayed next to the ticker.


ARGUMENTS

   message
         A message to be displayed once prior to showing a time ticker. This will occur before
         the file contents if you also use --file.
```

## func eprogress_kill


Kill the most recent eprogress in the event multiple ones are queued up. Can optionally pass in a specific list of
eprogress pids to kill.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --all, -a
         If set, kill ALL known eprogress processes, not just the current one

   --rc, --return-code, -r <value>
         Should this eprogress show a mark for success or failure?

```

## func etestmsg

`etestmsg` is used to log informational testing related messages to STDERR. This is typically used inside `etest` test
code. These log messages are prefixed with `##` in `cyan`. `etestmsg` is called just like you would normally call
`echo`.

## func etrace

`etrace` is an extremely powerful debugging technique. It essentially allows you to selectively emit a colorized
debugging message for **every line of code executed by ebash** without having to modify the source code and sprinkle it
with lots of explicit debugging messages. This means you can dynamically debug code in the field without having to make
and source code changes.

This is similar to the builtin bash `set -x` option. But ebash takes this a little further by using selective controls
for command tracing rather than blanket turning on `set -x` for the entire process lifetime. Additionally, the messages
are prefixed with a configurable color message showing the filename, line number, function name, and PID of the caller.
The color can be configured via `${COLOR_TRACE}`.

For example, suppose I have the following script:

```shell
#!/bin/bash

$(etrace --source)

echo "Hi"
a=alpha
b=beta
echo "$(lval a b)"
```

You can now run the above script with `etrace` enabled and get the following output. Not that rather than just the
**command** being printed as you'd get with `set -x`, etraces emits the file, line number and process PID:

```shell
$ ETRACE=etrace_test ./etrace_test
[etrace_test:6:main:24467] echo "Hi"
Hi
[etrace_test:7:main:24467] a=alpha
[etrace_test:8:main:24467] b=beta
[etrace_test:9:main:24467] echo "$(lval a b)"
[etrace_test:9:main:25252] lval a b
a="alpha" b="beta"
```

Like `EDEBUG`, `ETRACE` is a space-separated list of patterns which will be matched against your current filename and
function name. The etrace functionality has a much higher overhead than does running with edebug enabled, but it can be
immensely helpful when you really need it.

One caveat: you can’t change the value of ETRACE on the fly. The value it had when you sourced ebash is the one that
will affect the entire runtime of the script.

## func ewarn

`ewarn` is used to log warning messages to STDERR. They are prefixed with `>>` in `COLOR_WARN` which is `yellow` by
default. `ewarn` is called just like you would normally call `echo`.

## func ewarns

`ewarns` is used to log warning **sub** messages to STDERR. They are intdented and prefixed with a `-` in `COLOR_WARNS`
which is `yellow` by default. `ewarns` is called just like you would normally call `echo`. This is designed to line up
underneath `einfo` or `ewarn` messages to show submessages.

## func expand_vars


Iterate over arguments and interpolate them as-needed and store the resulting "key" and "value" into a provided
associative array. For each entry, if a custom "key=value" syntax is used, then "value" is checked to see if it refers
to another variable. If so, then it is expanded/interpolated using the `print_value` function. If it does not reference
another variable name, then it will be used as-is. This implementation allows for maximum flexibility at the call-site
where they want to have some variables reference other variables underlying values, as in:

```shell
expand_vars details DIR=PWD
```

But also sometimes want to be able to just directly provide the string literal to use, as in:

```shell
expand_vars details DIR="/home/marshall"
```

The keys may optionally be uppercased for consistency and quotes may optionally be stripped off of the resulting value
we load into the associative array.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --lowercase
         Lowercase the keys for consistency

   --quotes
         Include quotation marks around value.

   --uppercase
         Uppercase the keys for consistency


ARGUMENTS

   __details
         Name of the associative array to load the key=value pairs into.

   entries
         Variadic list of variables to interpolate and load the resulting values into the
         details array.
```

## func lval

Log a list of variable in tag="value" form similar to our C++ logging idiom. This function is variadic (takes variable
number of arguments) and will log the tag="value" for each of them. If multiple arguments are given, they will be
separated by a space, as in: tag="value" tag2="value2" tag3="value3"

This is implemented via calling print_value on each entry in the argument list. The one other really handy thing this
does is understand our C++ LVAL2 idiom where you want to log something with a _different_ key. So you can say nice
things like:

```shell
$(lval PWD=$(pwd) VARS=myuglylocalvariablename)
```

You can optionally pass in -n or --no-quotes and it will omit the outer-most quotes used on simple variables such as
strings and numbers. But array and associative array values are still quoted to avoid ambiguity.

## func noansi


Noansi filters out ansi characters such as color codes. It can modify files in place if you specify any. If you do not,
it will assume that you'd like it to operate on stdin and repeat the modified output to stdout.

```Groff
ARGUMENTS

   files
         Files to modify. If none are specified, operate on stdin and spew to stdout.
```

## func print_value

Print the value for the corresponding variable using a slightly modified version of what is returned by declare -p. This
is the lower level function called by lval in order to easily print tag=value for the provided arguments to lval. The
type of the variable will dictate the delimiter used around the value portion. Wherever possible this is meant to
generally mimic how the types are declared and defined.

Specifically:
  1) Strings: delimited by double quotes.
  2) Arrays and associative arrays: Delimited by ( ).
  3) Packs: You must preceed the pack name with a percent sign (i.e. %pack)

Examples:
  1) String: `"value1"`
  2) Arrays: `("value1" "value2 with spaces" "another")`
  3) Associative Arrays: `([key1]="value1" [key2]="value2 with spaces" )`

## func tput

`tput` is a wrapper around the real `tput` command that allows us more control over how to deal with `COLUMNS` not being
set properly in non-interactive environments such as our CI/CD build system. We also allow explicitly setting `COLUMNS`
to something and honoring that and bypassing calling `tput`. This is useful in our CI/CD build systems where we do not
have a console so `tput cols` would return an error. This also gracefully handles the scenario where tput isn't installed
at all as in some super stripped down docker containers.
