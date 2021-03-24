[![CI/CD](https://github.com/elibs/ebash/workflows/CI/CD/badge.svg?branch=master)](https://github.com/elibs/ebash/actions?query=workflow%3ACI%2FCD+branch%3Amaster)

<p align="center">
    <img alt="Bash" src="https://raw.githubusercontent.com/odb/official-bash-logo/master/assets/Logos/Identity/PNG/BASH_logo-transparent-bg-color.png">
</p>

# ebash Guide

## Overview

Bash is the ideal language of choice for writing low-level shell scripts and tools requiring direct shell access
invoking simple shell commands on a system for a number of reasons:

1. Prolific and already installed on nearly every *NIX machine out of the box which minimizes dependencies and
   installation complexity and size.
2. Extremely lightweight with very low memory and CPU requirements suitable for appliances and embedded systems.
3. Ideal for tasks involving running lots of shell commands as it is simpler than in higher level languages. This is,
   after all, bash's primary native role. As such, it does not require complex objects or frameworks for executing
   or interacting with shell commands.

That said, because bash is a lower level language, it lacks some of the features and more advanced data structures
typically found in higher level languages. As such, the goal of ebash is to provide a layer of robustness and more
advanced features on top of vanilla bash.

## Compatibility

Ebash aims for extreme compatibility with the intention that it "just works" on just about any *NIX OS. While it is not
feasible to test ebash on _every_ OS/Distro, we nonetheless test it many popular combinations on every single build. You
can view the build status any time using the build batch at the top of this README or by going here:
[Builds](https://github.com/elibs/ebash/actions?query=workflow%3APipeline+branch%3Amaster).

Here is a table showing all the currently test and validated OS/Distro
combinations:

| OS    | Disto  | Version |
| ----- | -------| ------- |
| Linux | Alpine | 3.13    |
| Linux | Alpine | 3.12    |
| Linux | Arch   | rolling |
| Linux | CentOS | 8       |
| Linux | CentOS | 7       |
| Linux | Debian | 10      |
| Linux | Debian | 9       |
| Linux | Fedora | 33      |
| Linux | Fedora | 32      |
| Linux | Gentoo | rolling |
| Linux | Ubuntu | 20.04   |
| Linux | Ubuntu | 18.04   |
| MacOS | N/A    |  11.0   |
| MacOS | N/A    | 10.15   |

## Why ebash?

### Implicit Error Detection

Bash is a strange beast.  It can be an interactive shell, in which case you’d like to be notified of failures but not
for them to be catastrophic.  And when you write scripts, it’s easy to be torn about what you want.  Sometimes you want
failures to be ignored, and other times you want to be very sure that a command doesn’t fail.

The standard bash answer to this question is that you should always check for errors if you care about them.  But
sometimes commands fail that you don’t expect to fail.  What happens when you’ve left out a test in that case because
that could never happen, right?  Or perhaps you have taken extreme care to check for errors in all possible cases.  Now
your code is wordy and more difficult to follow.

With ebash, we have decided to make scripts detect errors implicitly.  If an error occurs, you’ll detect it and your
script will blow up.  You can specifically ignore such failures when you know it’s safe, but the default is to make the
failure as obvious as possible.

This is in opposition to all bash defaults.  And, frankly, it’s a bit difficult to force bash into really blowing up on
all failures.  But we do our best with a multi-layered approach.  As long as you use the typical ebash idioms and follow
a small set of styles we prescribe, we believe that any time an error occurs in your ebash code, you’ll hear about it.

First, we use bash’s error trap functionality.  This behaves just like `set -e`, except that we get to choose what runs
when an error occurs.  Basically, we call the die function on any error.  This causes a stack trace to be generated
which will have `[UnhandledError]` in its message.  Second, we ensure that the error trap is inherited by all subshells,
because sometimes you need them, and often it’s difficult to know where there will actually be a subshell.

But sometimes bash really wants to ignore a return code.  For instance, if command substitution isn’t part of the first
command on a line, as in both of the following lines of code, bash will ignore any return code of `cmd`.

    echo "$(cmd)"
    local var=$(cmd)

But ebash enhances bash’s error detection to catch this case.  The error trap is inherited by the shell inside the
command substitution, and when it calls die, it will actually send a signal to its parent shell.  When the parent shell
receives that signal, it generates a stack trace and blows up, which is exactly what we were looking for.

However, despite the best efforts of ebash, bash allows you to shoot yourself in the foot in subtle ways that mask error
handling.  The final component of our efforts to make errors implicitly detected are some styles to avoid.

### Using || or && masks errors

Typically, you can count on bash’s built in error detection (i.e. `set -e`, which we enable by default) to blow up if a
command you run exits with a non-zero exit code.  Sometimes that’s not what you want.  For one example, see `grep`
returns a bad exit code if it has no matches.

But using `||` has a more insidious effect when used around a bash function call, and for that reason we avoid it
whenever possible on bash functions.  Consider:

    func()
    {
        command1
        command2
    }
    func


When this code is executed, if `command1` fails, then the script will blow up immediately and will not execute
`command2`.  In ebash, this is what we want and expect.  But, given the same `func`, the following command works
differently:

    func && echo "success" || echo "failure"

Because `func` is part of a command list containing either `&&` or `||`, bash turns off its error detection behavior for
all code that is called, not just the code written on this line.  So what happens in this case is that `func`runs.  It
calls `command1`, which fails.  But since bash’s error detection behavior is off, it goes on to call `command2` which
passes and thus the overall result of `func` is success.

As you can see, this can dramatically affect the way code runs, and we’ve come across large issues that were masked by
this behavior.  So our standard on these is to only use `||` or `&&` on simple statements including only bash builtins
or executables.

If you need to ignore errors in bash functions that you call, instead use `tryrc` or `try` / `catch`. They make sure
that error detection is enabled for all called code.

### Calling bash functions in the if or loop conditional masks errors

This issue is similar to Using `||` or `&&` masks errors.  If you assume the same `func` as in that item, issues called
in `func` will also be masked by either of the following types of code:

    if func; then ; something ; fi

    while func; do ; something ; done

That is to say, any errors in anything `func` calls will be suppressed, so it is likely that the behavior and return
value of `func` isn’t want you want expect it to be.  One way around this is to use `tryrc`.  The following is
equivalent to the above if code, except that it causes `func` to detect errors properly.

    $(tryrc func)
    if [[ ${rc} -eq 0 ]] ; then
        something
    fi

### Use try / catch to handle errors

Since ebash forces you to be explicit about when you’d like to ignore errors in your bash script, it also gives you ways
to do that.  First off is the `try` / `catch` construct.  This looks frighteningly like the C++ construct.

    try
    {
        cmd1
        cmd2
    }
    catch
    {
       echo "Caught return code $?"
    }

It also behaves a lot like you’d expect from familiarity with other languages.  Code in the try block is executed until
the end of the block or until an error is encountered.  At the point an error is detected, no further code in the block
will execute.  So if `cmd1` fails in the above block, `cmd2` will never be executed.

The catch block is only executed if a failure is detected in the try block.  So if either `cmd1` or `cmd2` fail, the
catch block will be executed.  At the beginning of the catch block, the value of `$?` will be the return code of the
failing command.

The most difficult caveat of using `try` and `catch` in ebash is that the code in the `try` block is its own subshell.
This means that variable assignments that you make inside this block will not be seen outside.  It’s impossible to set a
variable in a parent shell from its subshell.  Note that this is only true of `try`.  `Catch` executes in the same shell
as surrounding code.

One workaround is to write data to a file inside the block and read it outside.  Another alternative is `tryrc`.

### Use tryrc to mask errors in simple commands

Sometimes you just need to run a single command and then perform different behavior depending on its return code.  For
external commands, the bash if statement or shortcutting logical operators (`||` and `&&`) handle this nicely, but if
you’re calling functions it is a bad idea to use them in this way.

`Tryrc` is the ebash solution to this issue.  It runs a function (or external command, basically any single statement
bash can execute) and captures its return code for later examination.  Its simplest usage looks like this:

    $(tryrc foo)
    if [[ ${rc} -eq 0 ]] ; then
        # Normal case
    else
        # Error case
    fi

The `tryrc` call will execute the foo function or command, and save its return code in a new local variable (created by
`tryrc`) named `rc`.  Error detection in code called by `foo` is still enabled, but regardless of the return code, the
`tryrc` statement will not fail.  Then you’re able to handle the return code as you like.

`tryrc` is also capable of capturing the stdout and/or stderr of the executed command into variables that you specify
during at invocation time.  Here’s a more complicated usage:

    $(tryrc -r=cmd_rc -o=cmd_out -e=cmd_err cmd)

This invocation will execute cmd and create three local variables.  `Cmd_rc` will contain the return code of `cmd`.
`Cmd_out` and `cmd_err` will contain stdout and stderr, respectively.  This gives you the functionality of command
substitution along with the ability to choose what happens with errors.

This functionality is important, because it’s difficult to use redirection with commands that are executed in `tryrc`.
If you need use redirection in way that can’t be solved by something like the following, it’s best to use `try` /
`catch` instead of `tryrc`.

    $(tryrc -o=out -e=err cmd)
    echo "${out}"
    echo "${err}" >&2

Note that if `cmd` produces interleaved output on stdout and stderr, this will change the ordering of the output.

### Handling commands that fail or hang

The ebash `eretry` function can be used to run other commands that you expect to sometimes fail, but from which you
eventually expect a positive response.  Suppose I have a tool named `foo` that frequently fails in flaky ways.  When I
call it with no options, `eretry` will run `foo` until it passes, with up to 5 attempts.

    eretry foo args

`Eretry` can also simply keep retrying as many times as it takes to reach a certain time period that you specify.  If
I’m pretty sure `foo` will pass within a total of 5 seconds, I can call it like this:

    eretry -T=5s foo args

`Eretry` will keep running `foo` until 5 seconds have elapsed.  If it hasn’t passed yet at that point, `foo` will be
killed and `eretry` will return a failing exit code.  Further, you can restrict how long each attempt at running `foo`
will take.  So the following command will run for up to a total (-T) of 5 seconds, allowing individual attempts to take
as much as 1 second (-t)

    eretry -T=5s -t=1s foo args

Or, if you simply need to run a command once, but make sure it doesn’t hang for too long, you can use `etimeout`.  In
the following call, `etimeout` allow `foo` to run for one minute, but if it hasn’t completed at that point, `foo` will
be killed and an error code will be returned.

    etimeout -t=60s foo

### `grep` returns a bad exit code if it has no matches

When you use `grep`, be aware that it will return a bad exit code if it finds no matches.  And when it does, the ebash
error detection code will blow your script up to let you know that there was an error.  But sometimes that isn’t what
you want.

    var=$(some_command | grep pattern)

The above will work in your testing, but suppose there isn’t a match.  In that case, your script will blow up with a
stack trace.  If it’s okay for there to be an error, just use `|| true` to mask it.

    var=$(some_command | grep pattern || true)

### Unset variables don’t invoke the error trap

They do, however, exit immediately.  This is unfortunately how bash’s `nounset` option works.  I can’t imagine a very
good explanation as to why bash wouldn’t invoke its error trap if there is one, but that’s how life is.

As long as you handle your cleanup in an `EXIT` trap, which is what `trap_add` does by default, it’ll be fine.

## Common Logging and Output Styles

### A standard, styleable output format

ebash provides a few standard functions intended for logging output to the screen.  `Einfo` is intended for standard
flow information in the typical case.  `Ewarn` indicate non-fatal things that might warrant user attention.  `Eerror`
are typically used for failure cases.  All of these produce their output on stderr.

These commands are invoked in the same way as you might call `echo`.  Here’s a script that uses them.

    #!/usr/bin/env bash

    : ${EBASH:=/home/modell/sf/ebash}
    source ${EBASH}/ebash.sh || exit 1

    einfo "einfo"
    ewarn "ewarn"
    eerror "eerror"

I’m not going to try to reproduce color in this guide, but by default the
output looks like this, with green color for info-level messages, yellow for
warning, and red for errors.

    >> einfo
    >> ewarn
    >> eerror

But the output can be modified in a few ways.  One way to customize it is to set `EFUNCS_COLOR=0`, which turns of color
for this and all ebash tools.  Another is that you can request timestamps.

    > EMSG_PREFIX=time ~/ebash_guide
    [Nov 12 13:31:16] einfo
    [Nov 12 13:31:16] ewarn
    [Nov 12 13:31:16] eerror

Or, to request all information that ebash will produce, you can set `EMSG_PREFIX` to all.

    > EMSG_PREFIX=all ./ebash_guide
    [Nov 12 13:24:19|INFO|ebash_guide:6:main] einfo
    [Nov 12 13:24:19|WARN|ebash_guide:7:main] ewarn
    [Nov 12 13:24:19|ERROR|ebash_guide:8:main] eerror

Here you can see the timestamp, log level, function name, line number, and filename of the code that generated the
message.  There’s more information on emsg customization in this other guide.

Another built-in output tool is `ebanner`.  It helps you separate high-level sections of the output of a process.  The
bars above and below your text will span the entire width of the terminal.

    > ebanner "Here’s a banner"
    +--------------------------------------+
    |
    | Here's a banner
    |
    +--------------------------------------+

### Use `edebug` and `lval` for more verbose logging

Despite the best of intentions, everyone writing bash code eventually needs to starting printing things out to figure
out what on earth is happening.  For user-level logging, ebash includes `einfo`, `ewarn`, and `eerror` commands that
present messages of varying importance in a consistent manner.

But back to debugging, we also have an `edebug` (which we pronounce "ee-debug") command that is a little different.  By
default, the `edebug` logging "level" is hidden.  So by default, this statement won’t produce any output:

    edebug "foo just borked rc=${rc}"

But you can activate the output from these `edebug` statements either wholesale or selectively by setting an environment
variable.  Setting `EDEBUG=1` will turn on all `edebug` output.  We use it pretty pervasively, so that might be a lot.
Instead of turning everything on, you can turn on `edebug` just for code in certain files or functions.  For example,
using `EDEBUG="dtest dmake"` will turn on debugging for any `edebug` statements in the `dtest` or `dmake` scripts.

What if you want to send the entire output of another tool to `edebug`?  You can do that, too.

    cmd |& edebug

The value of `EDEBUG` is actually a space-separated list of terms.  If any of those terms match the filename (just
basename) or the name of the function that contains an `edebug` statement, it will generate output.

Because we frequently found ourselves typing things like `rc=${rc}` in our `edebug` and other logging statements, we
also created a function called `lval` to help with this.  If you instead use `$(lval rc)`, it will produce the same
output.

It also prints the output in a format that makes it clear what is in your variable, even when it contains whitespace.
And it knows about bash types like arrays and associative arrays and handles them appropriately.  You might use it like
this.  You can, of course, use it with any tool that outputs an arbitrary string.

    declare -A aa
    aa[foo]=1
    aa[bar]=2
    local var="hello world"
    array[0]=alpha
    array[1]=beta
    echo "$(lval aa var array)"
    # Produces:
    # aa=([bar]="2" [foo]="1" ) var="hello world" array=("alpha" "beta")

### Debugging beyond logging: `ETRACE`

But maybe you’ve looked at all the debugging output you can find and you still need more information about what is going
on.  You may be aware that you can get bash to print each command before it executes it by turning on the `set -x`
option. ebash takes this a little further by using selective controls for command tracing rather than blanket turning on
`set -x` for the entire script.  For instance, I have the following script that on my machine is named `etrace_test`.

    #!/usr/bin/env bash

    : ${EBASH:=/usr/local/share/ebash-1.1.8}
    source ${EBASH}/ebash.sh

    echo "Hi"
    a=alpha
    b=beta
    echo "$(lval a b)"

I ran the script with etrace enabled and got this output.  Note that rather than just the command (as `set -x` would
give you), etrace adds the file, line number, and current pid.

    > ETRACE=etrace_test ./etrace_test
    [etrace_test:6:main:24467] echo "Hi"
    Hi
    [etrace_test:7:main:24467] a=alpha
    [etrace_test:8:main:24467] b=beta
    [etrace_test:9:main:24467] echo "$(lval a b)"
    [etrace_test:9:main:25252] lval a b
    a="alpha" b="beta"

Like `EDEBUG,` `ETRACE` is a space-separated list of patterns which will be matched against your current filename and
function name.  The etrace functionality has a much higher overhead than does running with edebug enabled, but it can be
immensely helpful when you really need it.

One caveat: you can’t change the value of `ETRACE` on the fly.  The value it had when you sourced ebash is the one that
will affect the entire runtime of the script.

## Data Structures

### Array Helpers

In `array.sh`, there are several helpers for dealing with standard bash arrays.  These are helpers for dealing with
standard bash arrays.  The best place to get information on these right now is in the documentation headers above each
function in the source file.  But I’ll point out a few interesting functions.

For example, since you don’t want to change `IFS`, you might be interested in a function that can initialize an array by
splitting on a particular separator.  For example:

    > array_init array "one|two|three" "|"
    > declare -p array
    declare -a array='([0]="one" [1]="two" [2]="three")'
    > array_init array "aJbJcJd" "J"
    > declare -p array
    declare -a array='([0]="a" [1]="b" [2]="c" [3]="d")'

The default separator is any whitespace.  If you’d like to split up a file by line (retaining whitespace within
individual lines), you can use `array_init_nl`.  There’s also an `array_init_json` function to help you slurp json data
into an array.

You can use `array_contains` to find out if a specific value is in an array, `array_sort` to sort an array, and
`array_remove` to pull specific items out of an array.  Take a minute and glance through that section of `array.sh`.
And if there’s a particular helper you’d like to see, let’s get it added!

### Packs

Packs are intended as a new data type for bash.  They’re pretty similar to associative arrays, but have compelling
benefits in a few cases.  The best one is that you can store packs inside an array or associative array, so you can more
easily keep track of multidimensional data.

There are also downsides.  The key for data stored in your pack must not contain an equal sign or whitespace.  And the
value for data stored in the pack is not allowed to contain newline or null characters.

So how do you use it?

    > pack_set my_pack A=1 B=2 C=3
    > pack_get my_pack A
    1
    > pack_get my_pack B
    2

You can continue to change values in the pack over time in the same way.

    > pack_set my_pack B=40 pack_get my_pack A
    1
    > pack_get my_pack B
    40

But sometimes that gets cumbersome.  When you want to work with a lot of the variables, sometimes it’s easier to store
them as local variables while you’re working, and then put them all back in the pack when you’re done.  `Pack_import`
and `pack_export` were designed for just such a case.

    > $(pack_import my_pack) echo $A
    1
    > echo $B
    40
    > A=15
    > B=20
    > pack_export my_pack A B
    > pack_get my_pack A
    15
    > pack_get my_pack B
    20

You can see that after `pack_import,` `A` and `B` were local variables that had values that were extracted from the
pack.  After the `pack_export`, the values inside the pack were synced back to the values that had been assigned to the
local variables.  You could certainly do this by hand with `pack_set` and `pack_get,` but sometimes `pack_import` and
`pack_export` are more convenient.

One more quick tool for using packs.  Our `lval` knows how to read them explicitly, but you must tell it that the
variable is a pack by prepending it with a percent sign.

    > echo "$(lval %my_pack)"
    my_pack=([C]="3" [A]="15" [B]="20" )

## Other Common Tasks

There are several other utilities in ebash that help with the plumbing you need as you write bash code day to day.

### Use `opt_parse` to read parameters

Early in the life of ebash, we found ourselves writing the same pattern over and over in our functions.

    foo()
    {
        local arg1=$1
        local arg2=$2
        shift 2
        argcheck arg1 arg2

        # Do some stuff here with arg1 and arg2
    }

`Argcheck` is a tool that can verify that the named variables contained some value.  But the rest of this felt a little
too much like boilerplate.  For short functions, this argument parsing amounted to more than the actual work that the
function performed, so we decided to try to reduce the noise.

So we replaced it.  The following code is exactly equivalent to what is above.  It creates two local variables (`arg1`
and `arg2`) and then verifies that neither is empty by calling `argcheck` against them.

    foo()
    {
        $(opt_parse arg1 arg2)

        # Do stuff here with arg1 and arg2
    }

Later, we added the ability to document options within this declaration.

    $(opt_parse \
        "arg1 | Meaning of arg1 option" \
        "arg2 | Meaning of arg2 option")

And the ability to give arguments default values.

    $(opt_parse \
        "arg1=a | Argument that defaults to a" \
        "arg2=b | Argument that defaults to b)

`opt_parse` can even deal with short and gnu-style long options.  There's much more information in its documentation,
but here's an example to whet your appetite:

    $(opt_parse \
        ":long_option l | Option that is called -l or --long-option" \
        ":file=file.txt | Option whose value has a default" \
        "+bool b        | Boolean option (value of 1 or 0)" \
        "arg            | Positional argument")

#### Boolean Options

`opt_parse` supports boolean options. That is, they're either on the command line (in which case opt_parse assigns 1 to
the variable) or not on the command line (in which case opt_parse assigns 0 to the variable).

You can also be explicit about the value you'd like to choose for an option by specifying =0 or =1 at the end of the
option. For instance, these are equivalent and would enable the word_regex option and disable the invert option.

    cmd --invert=0 --word-regex=1
    cmd -i=0 -w=1

Note that these two options are considered to be boolean. Either they were specified on the command line or they were
not. When specified, the value of the variable will be 1, when not specified it will be zero.

The long option versions of boolean options also implicitly support a negation by prepending the option name with no-.
For example, this is also equivalent to the above examples.

    cmd --no-invert --word-regex

#### String Options

`opt_parse` also supports options whose value is a string. When specified on the command line, these _require_ an
argument, even if it is an empty string. In order to get a string option, you prepend its name with a colon character.

    func()
    {
        $(opt_parse ":string s")
        echo "STRING="${string}""
    }

    func --string "alpha"
    # output: STRING="alpha"
    func --string ""
    # output: STRING=""

    func --string=alpha
    # output: STRING="alpha"
    func --string=
    # output: STRING=""

#### Non-Empty String Options

`opt_parse` also supports options whose value is a non-empty string. This is identical to a normal `:` string option
only it is more strict since the string argument must be non-empty. In order to use this option, prepend its name with
an equal character.

    func()
    {
        $(opt_parse "=string s")
        echo "STRING="${string}""
    }

    func --string "alpha"
    # output: STRING="alpha"
    func --string ""
    # error: option --string requires a non-empty argument.

    func --string=alpha
    # output: STRING="alpha"
    func --string=
    # error: option --string requires a non-empty argument.

#### Accumulator Values

`opt_parse` also supports the ability to accumulate string values into an array when the option is given multiple times.
In order to use an accumulator, you prepend its name with an ampersand character. The values placed into an accumulated
array cannot contain a newline character.

    func()
    {
        $(opt_parse "&files f")
        echo "FILES: ${files[@]}"
    }

    func --files "alpha" --files "beta" --files "gamma"
    # output -- FILES: alpha beta gamma

#### Default Values

By default, the value of boolean options is false and string options are an empty string, but you can specify a default
in your definition just as you would with arguments.

    $(opt_parse \
        "+boolean b=1        | Boolean option that defaults to true" \
        ":string s=something | String option that defaults to "something")


#### Automatic --help / -?

`opt_parse` automatically supports --help option and corresponding short option -? option for you, which will display a
usage statement using the docstrings that you provided for each of the options and arguments.

Functions called with --help/-? as processed by opt_parse will not perform their typical operation and will instead
return successfully after printing this usage statement.

### Clean up after yourself

If bash scripts are doing anything useful, it typically involves side effects of some sort.  (We don’t just write these
things to make the CPU hot, right?) Some are important, but often we generate temporary files or directories or
processes or whatever that should be taken care of when we’re done running.

But recall that ebash will cause scripts to generate a stack trace and terminate if they encounter an error.  You still
want to be sure that those things got cleaned up.  The right way to handle this is to use traps.  But please don’t use
bash’s built in `trap` command to set the traps, because then you might overwrite the cleanup code that someone else
already created.  We have a `trap_add` command for this purpose.

We use it all over the place.  Our most typical idiom is to put the cleanup code right next to whatever created the
temporary resource.

    local temp_file=$(mktemp --tmpdir /tmp/somefile-XXXX)
    trap_add "rm -f \"${temp_file}\""

When the shell exits, whether through error or normal termination, the trap will be executed and `temp_file` will get
cleaned up.

### Done with a process?  Nuke it

That subprocess you created and backgrounded can run for a long time.  And if it started children, you want to be sure
that they’re all gone.  `Ekilltree` is created for this purpose.  Kill a process and everything it has started.  For
instance, to send a `sigterm` to `old_pid` and all of its children, you just need to:

    ekilltree ${old_pid}

You can specify a different signal, too, so if you want to be really sure they’re dead:

    ekilltree -s=KILL ${old_pid}

Remember, though, that if you send a process `sigkill` it will not have a chance to clean up after itself.  So be kind
and send it `sigterm` first.  Most everything honors `sigterm` anyway.

## Unit Tests

As ebash grew, we found that it was sometimes difficult to keep everything working the way we expected and realized that
we needed a way to automatically test it.  In a few hours, `etest` was born.

ebash has a fairly extensive test suite at this point, containing over 300 tests that cover pretty much all of the
important functionality, and we try to add more any time we discover a problem so that it doesn’t return.  It’s run on
every commit.

You can run this test suite easily on your machine, too.  Just hop into the ebash directory and run:

    ./etest

### Creating your own etests

Over time, `etest` has become a fairly robust way to run unit tests for anything that you can call from bash.  Today, we
have `etest` suites for several tools outside of ebash, too.  It’s designed so that it’s easy to create your own by
creating one or more test files.  Here’s an entire (simple) test file.  We expect the filenames to end in `.etest`.

    #!/usr/bin/env bash
    ETEST_will_pass()
    {
        true
    }

    ETEST_will_fail()
    {
        false
    }

Both of the functions here will be executed as individual unit tests because their names start with `ETEST_`.   Note
that although this file isn’t executed directly, it needs a shebang line at the top that includes the word "bash"
because that’s one of the ways etest determines whether it can execute a file.

    > ./etest -f=mytest.sh
    >> Starting tests in /home/modell/sf/ebash/mytest.sh
       - ETEST_will_fail                                             [ !! ]
       - ETEST_will_pass                                             [ ok ]

    >> Finished testing ebash b8ceaa772b6a+. 1/2 tests passed in 7 seconds.

    >> FAILED TESTS:
          will_fail

Here we ran just the tests in my new file (which I named `mytest.sh`). The `-f` on that line is used to specify a
filter.  The filter is a bash regular expression, and if it is specified, it must match either the filename or the
function name of the test.  I could’ve chosen either single test by running `./etest -f=fail` or `./etest -f=pass`.

`Etest` also has options to repeat tests (`-r`), break on error (`-b`), exclude tests that match a pattern (`-x`), and
more.

### Test verbosity

That listing of test passes and failures looks nice, but when your test fails, it’s not particularly helpful.  But
there’s more available.  We just have to look for it in the log file, or turn it on with `etest -v`.

Before we try that, I’ll replace my tests with something (slightly) more complicated.  I’ll replace `ETEST_will_pass`
with this:

    ETEST_will_pass()
    {
        etestmsg "Step 1"
        echo "hi from step 1"
        etestmsg "Step 2"
        echo "hi from step 2"
        etestmsg "Step 3"
    }

Non-verbose mode would look the same, so we’ll run it in verbose mode:

    > ./etest -f=pass -v
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

Even when your individual steps write more to the screen than a simple echo, the messages produced by `etestmsg` are
colored so as to stand out against all the other text.  Since all of this (and the regular output) is hidden when
running default test runs, in verbose we tend to dump lots of text to the screen.  Don’t hesitate to put that json blob
or file contents that might later make it a lot easier to figure out what went wrong.

All of this verbose output is actually available all the time.  It’s stored in a log file.  After your (verbose or
non-verbose) `etest` run, look at `etest.log`.

## Mocking

Ebash supports an extensive mocking framework called `emock`. It integrates well into the rest of ebash and etest in
particular to make it very easy to mock out real system binaries and replace them with mock instances which do something
else. It is very flexible in the behavior of the mocked function utilizing the many provided option flags.

The simplest invocation of emock is to use the default of function mocking. In this mode, you simply supply the name
of the binary you wish to mock, such as:

    # emock "dmidecode"

This will create and export a new function called 'dmidecode' that can be invoked instead of the real 'dmidecode'
binary at '/usr/bin/dmidecode'. This also creates a function named 'dmidecode_real' which can be invoked to get access
to the real underlying dmidecod binary at "/usr/sbin/dmidecode".

By default, this mock function will simply return '0' and produce no stdout or stderr. This behavior can be customized
using the options --return-code, --stdout, and --stderr.

Mocking a real binary with a simplex name like this is the simplest, but doesn't always work. In particular, if at the
call site you call it with the fully-qualified path to the binary, as in 'usr/sbin/dmidecode', then our mocked function
won't be called. In this scenario, you need to  mock it with the fully qualified path just as you would invoke it at the
call site. For example:

    # emock "/usr/sbin/dmidecode"

Just as before, this will create and export a new function named "/usr/sbin/dmidecode" which will be called in place of
the real dmidecode binary. It will also create a "/usr/sbin/dmidecode_real" function which will point to the real binary
in case you need to call it instead.

emock tracks various metadata about mocked binaries for easier testability. This includes the number of times a mock is
called, as well as the arguments (newline delimieted arg array), exit code, stdout, and stderr for each invocation. By
default this is created in a local hidden directory named '.emock' and there will be a directory beneath that for each
mock:

    # .emock/dmidecode/called
    # .emock/dmidecode/0/{args,exit,stdout,stderr}
    # .emock/dmidecode/1/{args,exit,stdout,stderr}
    # ...


### Mock Utility Functions

There are many utility functions to help with mocking, including:

#### eunmock

eunmock is used in tandem with emock to remove a mock that has previosly been created. This essentially removes the
wrapper functions we create and also cleans up the on-disk statedir for the mock.

#### emock_called

emock_called make it easier to check how many times a mock has been called. This is tracked on-disk in the statedir in
the file named "called". While it's easy to manually retrieve from this file, this function should always be used to
provide a clean abstraction.

Just like a typical array in any language, the size, or count of the number of times that the
mock has been called is 1-based but the actual index values we use to store the state files for each invocation is
zero-based (again, just like an array).

So if this has never been called, then emock_called will return 0, and there will be no on-disk state directory. The
first time you call it, emock_called will return 1, and there will be a ${statedir}/0 directory storing the state files
for that invocation.

#### emock_stdout

emock_stdout is a utility function to make it easier to get the standard output from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
standard output.

#### emock_stderr

emock_stderr is a utility function to make it easier to get the standard error from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
standard error.

#### emock_args

emock_args is a utility function to make it easier to get the argument array from a particular invocation of a mocked
function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to provide a
clean abstraction. If the call number is not provided, this will default to the most recent invocation's argument array.

Inside the statedir, the argument array is stored with each argument fully quoted so that whitespace encapsulated
arguments preserve whitespace. To convert this back into an array, the best thing to do is to use array_init:

`array_init args "$(emock_args func)`

Alternatively, the helper idiom assert_emock_called_with is an extremely useful way to validate the arguments passed
into a particular invocation.

#### emock_return_code

emock_return_code is a utility function to make it easier to get the return code from a particular invocation of a mocked
function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to provide a
clean abstraction. If the call number is not provided, this will default to the most recent invocation's return code.

#### assert_emock_called

assert_emock_called is used to assert that a mock is called the expected number of times. For example:

`assert_emock_called "func" 25`

#### assert_emock_stdout

assert_emock_stdout is used to assert that a particular invocation of a mock produced the expected standard output.

For example:

```
assert_emock_stdout "func" 0 "This is the expected standard output for call #0"
assert_emock_stdout "func" 1 "This is the expected standard output for call #1"
```

#### assert_emock_stderr

assert_emock_stderr is used to assert that a particular invocation of a mock produced the expected standard error.

For example:

```
assert_emock_stderr "func" 0 "This is the expected standard error for call #0"
assert_emock_stderr "func" 1 "This is the expected standard error for call #1"
```

#### assert_emock_return_code

assert_emock_return_code is used to assert that a particular invocation of a mock produced the expected return code.

For example:

```
assert_emock_return_code "func" 0 0
assert_emock_return_code "func" 0 1
```

#### assert_emock_called_with

assert_emock_called_with is used to assert that a particular invocation of a mock was called with the expected arguments.
All arguments are fully quoted to ensure whitepace is properly perserved.

For example:

```
assert_emock_called_with "func" 0 "1" "2" "3" "docks and cats" "Anarchy"
expected=( "1" "2" "3" "dogs and cats" "Anarchy" )
assert_emock_caleld_with "func" 1 "${expected[@]}"
```

### Don’t leak processes

The test framework is strict about leaky processes.  If you start a background process that hasn’t closed by the time
the test finishes (after a slight leeway), the test will fail.  For example:

    ETEST_leak_process()
    {
        sleep 15&
    }

`Etest` notices that a process was leaked (`sleep 15`) and its process ID (24783), and blows up as a result.

    > ./etest -f=leak_process
    >> Starting tests in /home/modell/sf/ebash/mytest.sh
       - ETEST_leak_process                                  [ ok ]

    >> Leaked processes in etest/ebash/14954:
      PID  STARTED NLWP  NI COMMAND
    24783 11:49:05    1   0 sleep 15
       :: etest:122            | assert_no_process_leaks
       :: etest:275            | run_etest_file
       :: etest:313            | main

If you are having trouble with leaky processes, you should probably look into using `ekilltree` and `trap_add`

## And there’s more...

There’s far more in ebash than I can enumerate in this guide.  ebash has many functions intended to help with other
needs.  Most of the ones that are useful at a high-level have documentation as comments above them in the file they’re
defined in.  Don’t be afraid to poke around and see if there’s anything else that can help you.

- Convert arrays, associative arrays, and packs into json (`json.sh`) Create and maintain ubuntu 12.04-based chroot
- environments (`chroot.sh`) Assert statements to blow up if a condition you expect isn’t true
  (`efuncs.sh`)
- Create, track, and move processes between cgroups (`cgroup.sh`) Linux network namespaces (`netns.sh`) Interacting with
- Jenkins (`jenkins.sh`)

# General Bash Gotchas

## Arrays may be holey!

Although conceptually indexed by numbers, bash arrays are not necessarily contiguous.  Really, they’re more like
associative arrays except that bash forces the indexes to be numerical.

For instance:

    > ARRAY=(A B C D) declare -p ARRAY
    declare -a ARRAY='([0]="A" [1]="B" [2]="C" [3]="D")'

    > unset ARRAY[B]
    > unset ARRAY[D]
    > declare -p ARRAY
    declare -a ARRAY='([1]="B" [2]="C" [3]="D")'

Notice how the items in the array don’t get moved or re-indexed.  Hence, just doing math to guess which items exist in a
bash array is a bad idea.

    # DO NOT DO THIS!  It will blow up on an array with holes in it for (( i =
    0; i < ${#ARRAY[@]} ; i++ )) ; do echo "${ARRAY[$i]}" done

Instead, ask bash for the available indexes to the array and iterate over them.  You can do this the same way you would
with an associative array, with "${!array[@}".

    for index in "${!ARRAY[@]}" ; do echo "${ARRAY[$index]}" done

Or, there is a ebash function that does the same thing to help you:

    for index in "$(array_indexes ARRAY)" ; do echo "${ARRAY[$index]}" done

## When in doubt, quote it

Bash likes to do crazy things to the contents of your variables when you don’t quote them.  So unless you’re very sure
that it doesn’t need to be quoted, just put double quotes around the variable and be done with it.  The most
commonly-known case of this relates to filenames and white space.

    filename=contains spaces.txt touch $filename

The above code will produce two separate files: `contains` and `spaces.txt`.  But white space isn’t the only thing that
matters.  For instance, any text that bash could interpret as a glob operator may produce varying output depending on
the contents of your file system:

    > a=[x]
    > echo ${a}
    [x]
    > touch x
    > echo ${a}
    x

At the end of the day, it’s usually easier to just quote everything than to try to guess when it will matter or when it
won’t.

# ebash Style

These are the styles we use when writing code in ebash, and frequently in related code using ebash.

## General Formatting

The top level of code belongs at the far left, and each compound statement deserves an indent of 4 spaces.

    if true; then
        if something_else; then
            something
        fi
    fi

We also try to keep lines under 120 characters and indent for lines that are continuations of the previous the same amount.

    some_really_long_command --with --long --args \
        | grep pattern \
        | tail

Exception: Here docs that use `<<-` must use tabs because that is what bash requires, so they are allowed there.

## Naming

Spell out your words.  Lvng out vwls is cnfsng.  (Leaving out vowels is confusing).  Avoid abbreviations unless they’re
really common (e.g. num for number) or they’re used all over the place (e.g. cmd for command).  Try to name based on the
purpose of something rather than its type (e.g.. string and array aren’t particularly descriptive names).

- Local variables names should use `lower_snake_case`.
- Global variable names should use `UPPER_SNAKE_CASE`.
- Function names should use `lower_snake_case`.

Bash provides no namespaces, so when we have a group of related functions, we’ll frequently use a common term as the
first word of the name to group them and avoid collisions.  For that first word, we do occasionally use abbreviations as
we don’t want them to cause the names to increase to ridiculous lengths.

For instance, you’ll find functions with these names in ebash:

- `cgroup_create`
- `cgroup_destroy`
- `array_size`
- `netns_exec`

## When reading the value of a variable, use curly braces

For example, use `${VAR}` and not `$VAR.`

Exceptions:
- When the variable is an index into an array, we leave the braces off to
  reduce the noise.  For instance `${VAR[$i]}` is good.
- Bash builtin variables with short names.  For instance, we often say `${@},`
  but that’s not required.  We almost always use a simple `$!` or `$?`, and we frequently use `$1` and `$2.`  But bash
  builtins like `${BASHPID}` or `${BASH_REMATCH}` look like global variables and so they should have braces.

Put then and do on the same line as the statement they belong to.  For instance:

    if true; then
        something
    fi

and

    for i in "${array[@]}"; do
        something
    done

## Always use `[[` and `]]` instead of `[` and `]`

Bash provides `[[` because it’s easier to deal with, has more functionality such as regular expression matching, and
reduces the amount of quoting you must do to use it correctly.

`[` is a posix-standard external binary.  `[[` is a bash builtin, so it’s cheaper to run.  The builtin is also able to
give you syntactic niceties.  For instance, you need to quote your variables much less.  This is safe.  Whereas the same
thing with the `[` command would not be.

    [[ -z ${A} ]]

Aside from posix shell compatibility (which is not a concern when using ebash), there is no downside.

## Every variable that can be declared local must be declared local

If you don’t tell bash to use local variables, it assumes that all of the variables you create are global.  If someone
else happens to use the same name for something, one of you is likely to stomp on the value that the other set.

Note that both local and declare create local variables.  ebash helpers such as `opt_parse` and `tryrc` create local
variables for you, too.

One place that it’s really easy to accidentally not use a local variable is with a bash for loop.

    # Note: index here is NOT LOCAL
    for index in "${array[@]}" ; do
        something
    done

You must specifically declare for loop index variables as local.

    local index for index in "${array[@]}" ; do something done

## Do not change `IFS`

Like most other bash code, ebash is written under the assumption that `IFS` is at its default value.  If you change the
value of `IFS` and call any ebash code, expect things to break most likely in subtle ways.

# Other Bash Resources

- The official bash FAQ: http://tiswww.case.edu/php/chet/bash/FAQ
- Another good bash FAQ: http://mywiki.wooledge.org/BashFAQ
- Advanced BASH-Scripting Guide (html): http://www.tldp.org/LDP/abs/html/
- Advanced BASH-Scripting Guide (pdf):
  http://www.tldp.org/LDP/abs/abs-guide.pdf
