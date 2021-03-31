# Debugging

## Debugging with `edebug`

Despite the best of intentions, everyone writing code eventually needs to starting printing things out to figure out
what on earth is happening. In addition to the normal logging level functions `einfo`, `ewarn`, `eerror`, we also have
`edebug` that is a little different. By default, the `edebug` logging "level" is hidden. So by default, this statement
won't produce any output:

```shell
edebug "foo just borked rc=${rc}"
```

But you can activate the output from these `edebug` statements either wholesale or selectively by setting an environment
variable. Setting `EDEBUG=1` will turn on all `edebug` output globally. We use it pretty pervasively, so that might be a
lot and probably counter-productive for complex systems. Instead of turning everything on, you can turn on `edebug` just
for code in certain files or functions. For example, using `EDEBUG="dtest dmake"` will turn on debugging for any
`edebug` statements in any file or function with `dtest` or `dmake` as part of their names.

Another super powerful feature of `edebug` is that you can **pipe** output into it and it will simply discard the output
if debugging is not enabled. For example:

```shell
cmd |& edebug
```

The value of `EDEBUG` is actually a space-separated list of terms. If any of those terms match the filename (just
basename) or the name of the function that contains an `edebug` statement, it will generate output.

## Beyond debugging with `etrace`

But maybe you've looked at all the debugging output you can find and you still need more information about what is going
on. You may be aware that you can get bash to print each command before it executes it by turning on the `set -x`
option. ebash takes this a little further by using selective controls for command tracing rather than blanket turning on
`set -x` for the entire script. For instance, I have the following script that on my machine is named `etrace_test`.

```shell
1 #!/usr/bin/env bash
2
3 # Pull in ebash
4 $(ebash --source)
5
6 echo "Hi"
7 a=alpha
8 b=beta
9 echo "$(lval a b)"
```

I ran the script with `etrace` enabled and got this output. Note that rather than just the command (as `set -x` would
give you), `etrace` adds the file, line number, and current process PID.

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

Like `EDEBUG,` `ETRACE` is a space-separated list of patterns which will be matched against your current filename and
function name. The `etrace` functionality has a much higher overhead than does running with `edebug` enabled, but it can
be immensely helpful when you really need it.

One caveat: you can't change the value of `ETRACE` on the fly. The value it had when you sourced `ebash` is the one that
will affect the entire runtime of the script.
