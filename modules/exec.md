# Module exec


## alias reexec

reexec re-executes our shell script along with all the arguments originally provided to it on the command-line
optionally as the root user and optionally inside a mount namespace.

## func quote_eval

Ever want to evaluate a bash command that is stored in an array?  It's mostly a great way to do things. Keeping the
various arguments separate in the array means you don't have to worry about quoting. Bash keeps the quoting you gave it
in the first place. So the typical way to run such a command is like this:

```shell
> cmd=(echo "\$\$")
> "${cmd[@]}"
$$
```

As you can see, since the dollar signs were quoted as the command was put into the array, so the quoting was retained
when the command was executed. If you had instead used eval, you wouldn't get that behavior:

```shell
> cmd=(echo "\$\$")
> "${cmd[@]}"
53355
```

Instead, the argument gets "evaluated" by bash, turning it into the current process id. So if you're storing commands in
an array, you can see that you typically don't want to use eval.

But there's a wrinkle, of course. If the first item in your array is the name of an alias, bash won't expand that alias
when using the first syntax. This is because alias expansion happens in a stage _before_ bash expands the contents of
the variable.

So what can you do if you want alias expansion to happen but also want things in the array to be quoted properly?  Use
`quote_array`. It will ensure that all of the arguments don't get evaluated by bash, but that the name of the command
_does_ go through alias expansion.

```shell
> cmd=(echo "\$\$")
> quote_eval "${cmd[@]}"
$$
```

## func reexec


reexec re-executes our shell script along with all the arguments originally provided to it on the command-line
optionally as the root user and optionally inside a mount namespace.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --mount-ns
         Create a new mount namespace to run in.

   --sudo
         Ensure this process is root, and use sudo to become root if not.

```
