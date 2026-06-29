# Implicit Error Detection

## Problem

Bash is a strange beast. It can be an interactive shell, in which case you'd like to be notified of failures but not for
them to be catastrophic. And when you write scripts, it's easy to be torn about what you want. Sometimes you want
failures to be ignored, and other times you want to be very sure that a command doesn't fail.

The standard bash answer to this question is that you should always check for errors if you care about them. But
sometimes commands fail that you don't expect to fail. What happens when you've left out a test in that case because
that could never happen, right? Or perhaps you have taken extreme care to check for errors in all possible cases. Now
your code is long, complex and very difficult to follow.

## Solution

With ebash, we have decided to make scripts detect errors implicitly. If an error occurs, ebash will always detect it
and your script will immediately exit with an informative stack trace with precise indication of the cause and location
of the failure. You can specifically ignore such failures when you know it's safe, but the default is to make failures
as obvious as possible.

This is in **opposition** to all bash defaults. And, frankly, it's a bit difficult to force bash into exiting on **all**
failures. But we do our best with a multi-layered approach. As long as you use the typical ebash idioms and follow a
small set of conventions, we believe that any time an error occurs in your ebash code, you'll hear about it.

### Multi-layered ebash solution

* First, we use bash's error trap functionality. This behaves just like `set -e`, except that we get to choose what runs
when an error occurs. Basically, we call the `die` function on any error. This causes a stack trace to be generated which
will have `[UnhandledError]` in its message.

* Second, we ensure that the error trap is inherited by all subshells, because sometimes you need them, and often it's
difficult to know where there will actually be a subshell.
<!-- -->
Sometimes bash really wants to ignore a return code. For instance, if command substitution isn't part of the first
command on a line, as in both of the following lines of code, bash will ignore any return code of `cmd`.
<!-- -->
```shell
echo "$(cmd)"
local var=$(cmd)
```
<!-- -->
ebash enhances bash's error detection to catch this case. The error trap is inherited by the shell inside the command
substitution, and when it calls `die`, it will actually send a signal to its parent shell. When the parent shell
receives that signal, it generates a stack trace and blows up, which is exactly what we were looking for.

* Third, we establish coding conventions to avoid common pitfalls in bash that subvert error detection. These are in the
  next section.

## Conventions

### Avoid short-circuit `||` and `&&`

Typically, you can count on bash's built in error detection (i.e. `set -e`, which we enable by default) to blow up if a
command you run exits with a non-zero exit code. Sometimes that's not what you want as some commands are expected to
fail. The most common is `grep` which returns a non-zero error code if it has no matches. In that case, the right thing
to do is generally put an `|| true` after the command, as in:

```shell
grep pattern file || true
```

However, using `||` has an insidious effect when used around a **bash function call**. Specifically, it disables `set -e`
error detection for the **entire call stack**. For that reason, we avoid it whenever possible on bash functions. Notice
that this is perfectly save when calling external binaries.

Consider:

```shell
func()
{
    command1
    command2
}
func
```

When this code is executed, if `command1` fails, then the script will blow up immediately and will not execute `command2`.
In ebash, this is what we want and expect. But, given the same `func`, the following commands all work very differently:

```shell
func && echo "success" || echo "failure"
if func; then ; something ; fi
while func; do ; something ; done
```

Because `func` is part of a command list containing either `&&` or `||`, bash turns off its error detection behavior for
all code that is called, not just the code written on this line. So what happens in this case is that `func` runs just
as before and calls `command1`, which fails. But since bash's error detection behavior is off, it **goes on** to call
`command2` (which would not be allowed with ebash). Suppose that `command2` succeeds and returns `0`. The final return
value from `func` would thus be `0` and the failure from `command1` is masked!!

As you can see, this can dramatically affect the way code runs, and we've come across large issues that were masked by
this behavior. So our standard on these is to only use `||` or `&&` on simple statements including only bash builtins
or external binaries or executables.

### Use `try` / `catch` to handle errors

Since ebash forces you to be explicit about when you'd like to ignore errors in your bash script, it also gives you ways
to do that. First off is the `try` / `catch` construct. This looks frighteningly like the C++ construct.

```shell
try
{
    cmd1
    cmd2
}
catch
{
   echo "Caught return code $?"
}
```

It also behaves a lot like you'd expect from familiarity with other languages. Code in the try block is executed until
the end of the block or until an error is encountered. At the point an error is detected, no further code in the block
will execute. So if `cmd1` fails in the above block, `cmd2` will never be executed.

The catch block is only executed if a failure is detected in the try block. So if either `cmd1` or `cmd2` fail, the catch
block will be executed. At the beginning of the catch block, the value of `$?` will be the return code of the failing
command.

The most difficult caveat of using `try` and `catch` in ebash is that the code in the `try` block is its own subshell.
This means that **variable assignments that you make inside this block will not be seen outside**. It's impossible to
set a variable in a parent shell from its subshell. Note that this is only true of `try`. Catch executes in the same
shell as surrounding code.

One workaround is to write data to a file inside the block and read it outside. Another alternative is `tryrc`.

For more details about `try` and `catch` see the documentation in [try](modules/try_catch.md#alias-try) and [catch](modules/try_catch.md#alias-catch) and the many examples in the
[tests](https://github.com/elibs/ebash/blob/master/tests/try_catch.etest).

### Use `tryrc` to handle errors in simple commands

Sometimes you just need to run a single command and then perform different behavior depending on its return code. For
external commands, the bash `if` statement or short circuit logical operators (`||` and `&&`) handle this nicely, but if
you're calling bash functions it is a bad idea to use them in this way.

`tryrc` is the ebash solution to this issue. It runs a function (or external command, basically any single statement bash
can execute) and captures its return code into a variable for later examination. Its simplest usage looks like this:

```shell
$(tryrc foo)
if [[ ${rc} -eq 0 ]] ; then
    # Normal case
else
    # Error case
fi
```

The `tryrc` call will execute the `foo` function or command, and save its return code in a new local variable (created by
`tryrc`) named `rc`. Error detection in code called by `foo` is still enabled, but regardless of the return code, the
`tryrc` statement will not fail. Then you're able to handle the return code as you like.

`tryrc` is also capable of capturing the output (stdout) and/or error (stderr) of the executed command into variables
that you specify at invocation time. Here's are a couple more complicated examples:


```shell
$(tryrc -r=cmd_rc -o=cmd_out -e=cmd_err cmd)
$(tryrc --rc=cmd_rc --stdout=cmd_out --stderr=cmd_err cmd)
```

This invocation will execute cmd and create three local variables. cmd_rc
will contain the return code of cmd. cmd_out and cmd_err will contain stdout and stderr, respectively. This gives you
the functionality of command substitution along with the ability to choose what happens with errors.

This functionality is important, because it's difficult to use redirection with commands that are executed in tryrc. If
you need use redirection in way that can't be solved by something like the following, it's best to use try / catch
instead of tryrc.

```shell
$(tryrc -o=out -e=err cmd)
echo "${out}"
echo "${err}" >&2
```

## Further Details

- [tryrc documentation](modules/try_catch.md#func-tryrc)
- Examples in [tests](https://github.com/elibs/ebash/blob/master/tests/try_catch.etest)
