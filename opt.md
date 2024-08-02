# Option Parsing

## Motivation

Early in the life of ebash, we found ourselves writing the same pattern over and over in our functions.

```shell
foo()
{
    local arg1=$1
    local arg2=$2
    shift 2
    argcheck arg1 arg2

    # Do some stuff here with arg1 and arg2
}
```

[argcheck](modules/opt.md#func-argcheck) verifies that the named variables contained some value. But the rest of this
felt a little too much like boilerplate. For short functions, this argument parsing amounted to more than the actual
work that the function performed, so we decided to try to reduce the noise.

So we replaced it. The following code is exactly equivalent to what is above. It creates two local variables (`arg1`
and `arg2`) and then verifies that neither is empty by calling `argcheck` against them.

```shell
foo()
{
    $(opt_parse arg1 arg2)

    # Do stuff here with arg1 and arg2
}
```

Later, we added the ability to document options within this declaration.

```shell
$(opt_parse \
    "arg1 | Meaning of arg1 option" \
    "arg2 | Meaning of arg2 option")
```

And the ability to give arguments default values.

```shell
$(opt_parse \
    "arg1=a | Argument that defaults to a" \
    "arg2=b | Argument that defaults to b)
```

`opt_parse` can even deal with short and gnu-style long options. There's much more information in the [opt documentation](modules/opt.md)
but here's an example to whet your appetite:

```shell
$(opt_parse \
    ":long_option l | Option that is called -l or --long-option"     \
    ":file=file.txt | Option whose value has a default"              \
    "+bool b        | Boolean option (value of 1 or 0)"              \
    "@file          | Accumalators can be passed in multiple times." \
    "arg            | Positional argument")
```

## Boolean Options

`opt_parse` supports boolean options. That is, they're either on the command line (in which case `opt_parse` assigns `1`
to the variable) or not on the command line (in which case opt_parse assigns `0` to the variable).

You can also be explicit about the value you'd like to choose for an option by specifying `=0` or `=1` at the end of the
option. For instance, these are equivalent and would enable the word_regex option and disable the invert option.

```shell
cmd --invert=0 --word-regex=1
cmd -i=0 -w=1
```

> **_NOTE:_** These two options are considered to be boolean. Either they were specified on the command line or they were
not. When specified, the value of the variable will be `1`, when not specified it will be `0`.

The long option versions of boolean options also implicitly support a negation by prepending the option name with `no-`.
For example, this is also equivalent to the above examples.

```shell
cmd --no-invert --word-regex
```

## String Options

`opt_parse` also supports options whose value is a string. When specified on the command line, these _require_ an
argument, even if it is an empty string. In order to get a string option, you prepend its name with a colon character.

```shell
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
```

## Non-Empty String Options

`opt_parse` also supports options whose value is a non-empty string. This is identical to a normal `:` string option
only it is more strict since the string argument must be non-empty. In order to use this option, prepend its name with
an equal character.

```shell
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
```

## Accumulator Values

`opt_parse` also supports the ability to accumulate string values into an array when the option is given multiple times.
In order to use an accumulator, you prepend its name with an ampersand character. The values placed into an accumulated
array cannot contain a newline character.

```shell
func()
{
    $(opt_parse "&files f")
    echo "FILES: ${files[@]}"
}

func --files "alpha" --files "beta" --files "gamma"
# output -- FILES: alpha beta gamma
```

## Default Values

By default, the value of boolean options is false and string options are an empty string, but you can specify a default
in your definition just as you would with arguments.

```shell
$(opt_parse \
    "+boolean b=1        | Boolean option that defaults to true" \
    ":string s=something | String option that defaults to "something")
```

## Automatic --help / -?

`opt_parse` automatically supports `--help` option and corresponding short option `-?` option for you, which will display
a usage statement using the docstrings that you provided for each of the options and arguments. It will also pull in
any docstring attached to the function via [opt_usage](modules/opt.md#func-opt_usage).

Functions called with `--help` or `-?` as processed by opt_parse will not perform their typical operation and will instead
return successfully after printing this usage statement.

## Further Details

* [opt documentation](modules/opt.md)
