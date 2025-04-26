# Porting

Porting vanilla bash code over to use ebash is superficially trivial since ebash **IS BASH** code.

Essentially, there are two steps:

1. As explained in [usage](usage.md), add `$(ebash --source)` to the top of your script.
2. Fix any errors in the script that ebash detects. This is obviously the harder part since ebash isn’t tolerant of
   unhandled errors like normal bash. So this will require you to run the script and fix any errors it might expose.

## FAQ

### Error Checking

One of the big changes when you are porting bash code to ebash is that you no longer have to have explicit error checking.
So if you have code that is looking at `$?` and conditionally doing something about it, you probably need to rewrite that
code with ebash idioms in mind.

Consider this code:

```shell
some_command
if [ $? -eq 0 ]
then
    ... success code ...
else
    ... failure code ...
fi
```

Since ebash provides implicit error detection, if the code fails at some_command then we exit immediately and never get
to execute the if/else block at all. The right way to write this is to move some_command into the if statement rather
than looking at the return code, such as:

```shell
if some_command
then
    ... success code ...
else
    ... failure code ...
fi
```

Another very strange variation of this I've seen is:

```shell
some_command
ERR=`/bin/echo $?`
if [ $ERR -eq 0 ]
then
    boot_dev=`grep -H $id /var/dev_* | awk -F : '{print $1}'`
    rm -f $boot_dev
fi
```

This is really just a variation of the prior question. The use of echo here is completely unnecessary since you can get
the exit code via `$?` directly. As before, this can be rewritten as:

```shell
if some_command
then
    ... success code ...
else
    ... failure code ...
fi
```

### Grep

`grep` is particularly challenging at times. Because it returns `0` when something is found and non-zero when it is not
found. In most cases we don't actually care about the output of `grep`, only whether a match was found. Consider this
example:

```shell
output=$(grep pattern some_file)
if [[ -n "${output}" ]]; then
    ... matching code ...
else
    ... non-matching code ...
fi
```

In this example, we don't actually care about output at all, Only whether it was empty or not. Well, we can do that
smarter like so:

```shell
if grep --quiet pattern some_file; then
    ... matching code ...
else
    ... non-matching code ...
fi
```

But sometimes we actually need the output of `grep`, and it's not a failure if no match is found. This case requires us
to basically trick bash into not considering that to be an error. To deal with this scenario, the best thing is to use
`|| true` after the `grep` command. Consider this example:

```shell
output=$(grep pattern some_file)
if [[ -z "${output}" ]]; then
    echo "No match!"
else
    echo "Matched: ${output}"
fi
```

This should be rewritten as:

```shell
output=$(grep pattern some_file || true)
if [[ -z "${output}" ]]; then
    echo "No match!"
else
    echo "Matched: ${output}"
fi
```

### Counter Incrementing / Decrementing

When incrementing an integer variable, ebash regards the `++` or `--` operators as shown to be an unhandled error, as it
returns the incremented value (which generally is non-zero unless you started with a negative number). Generally, the
simplest solution to this is to use this idiom:

```shell
(( i+=1 ))
```

There is a similar problem with `i--` that generally can be solved the same way.

The only time the above idiom fails is when the value gets incremented to zero or decremented to zero. This gets
confusingly reported as an error by bash which ebash will then detect and abort on. The safest idiom to use here, which
works in every scenario, is as follows:

```shell
i=$(( i+= 1 ))
i=$(( i-= 1 ))
```

This is all super cumbersome and easy to get wrong. So ebash provides [increment](modules/integer.md#func-increment) and [decrement](doc/integer.md#func-decrement) functions to make this
trivial.

```shell
increment i
decrement i
```

### Lockfiles

ebash provides a very nice mechanism for handling lockfiles using `elock` and `eunlock`. This is basically an intelligent
wrapper around flock.

Usage is basically `elock <fname>` and `eunlock <fname>`. See [elock](modules/elock.md).

One really cool thing about `elock` is it will automatically unlock for you when the shell exits. You can take
advantage of this to do something slick like this:

```shell
(                                                                                  
    elock "/var/lock/mylock"
    # do things with lock held ...                                                    
)   

# lock is NO longer held !! ...

```

### Interpreter ("shebang")

Some very old scripts have the interpreter (a.k.a. "shebang") at the top of the script as `/bin/sh` instead of `/bin/bash`.
Why is that and what should I do?

`/bin/sh` is usually a symlink to `/bin/bash` on almost all Unix boxes. However, there's a subtle difference between a
script with the interpreter of `/bin/sh` instead of `/bin/bash`. It still runs bash but it runs it in a legacy POSIX
compliance mode. This prevents a lot of the hardening features ebash has from working properly. Thankfully, when ebash
is sourced, it detects this problem and re-executes the script as a real bash script. However, that's an extra fork+exec
that is not necessary.

So, it's better to change the script interpreter from `/bin/sh` to `/bin/bash`

### `let`

`let` is an older way of declaring variables (e.g. `let var=0`). Generally, you can just remove `let` entirely or perhaps
replace with newer `declare` or `local`:

* `let var=0` -> `var=0`
* `let var++` -> `(( var += 1 ))`

If you’re in a function, you might consider

`local var=0` or more generally `declare var=0` which works in both functions and globally.
