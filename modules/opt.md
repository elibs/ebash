# Module opt


### Terminology

First a quick bit of background on the terminology used for ebash parameter parsing. Different well-meaning folks use
different terms for the same things, but these are the definitions as they apply within ebash documentation.

First, here's an example command line you might use to search for lines that do not contain "alpha" within a file named
"somefile".

```shell
grep --word-regexp -v alpha somefile
```

In this case `--word-regexp` and `-v` are **options**. That is to say, they're optional flags to the command whose names
start with hyphens. Options follow the GNU style in that single character options have one hyphen before their name,
while long options have two hyphens before their name.

Typically, a single functionality within a tool can be controlled by the caller's choice of either a long option or a
short option. For instance, grep considers `-v` and `--invert` to be equivalent options.

**Arguments** are the positional things that must occur on the command line following all of the options. If you're ever
concerned that there could be ambiguity, you can explicitly separate the two with a pair of hyphens on their own. The
following is equivalent to the first example.

```shell
grep --word-regex -v -- alpha somefile
```

To add to the confusing terminology, some options accept their own arguments. For example, grep can limit the number of
matches with the `--max-count` option. This will print the first line in somefile that matches alpha.

```shell
grep --max-count 1 alpha somefile.
```

So we say that if `--max-count` is specified, it requires an **argument**.

### Arguments

The simplest functions frequently just take an argument or two. We discovered early in the life of ebash a frequent
pattern:

```shell
foo()
{
    local arg1=$1
    local arg2=$2
    shift 2
    argcheck arg1 arg2

    # Do some stuff here with ${arg1} and ${arg2}
}
```

But we wanted to make it more concise. Enter `opt_parse`. This is equivalent to those four lines of argument handling
code in `foo()`. That is, it creates two local variables (`arg1` and `arg2`) and then verifies that both of them are
non-empty by calling `argcheck` on them.

```shell
$(opt_parse arg1 arg2)
```

As a best practice, we suggest documenting said arguments within the `opt_parse` declaration. Note that each quoted
string passed to `opt_parse` creates a single argument or option. Pipe characters separate sections, and whitespace near
the pipe characters is discarded. This, too, is equivalent.

```shell
$(opt_parse \
    "arg1 | This is what arg1 means." \
    "arg2 | This is what arg2 means.")
```

Note that `argcheck` in the original example ensures that your function will blow up if either `arg1` or `arg2` is
empty. This is pretty handy for bash functions, but not always what you want. You can specify that a given argument
_may_ be empty by putting a question mark before its name.

```shell
$(opt_parse \
    "arg1  | This argument must contain at least a character." \
    "?arg2 | This argument may be empty.")
```

You may also specify a default value for an argument.

```shell
$(opt_parse \
    "file=filename.json | This argument defaults to filename.json")
```

Note that having a default value is a separate concern from the check that verifies that the value is non-empty.

```shell
$(opt_parse \
    "a    | Default is empty, blows up if it is called with no value" \
    "?b   | Default is empty, doesn't mind being called with no value" \
    "c=1  | Default is 1, if called with '', will blow up" \
    "?d=1 | Default is 1, will still be happy if '' is specified")
```

But maybe you need a variable number of arguments. `opt_parse` always passes those back as `$@`, but you can request that
they be put in an array for you. The biggest benefit is that you can add a docstring which will be included in the
generated help statement. For example:

```shell
$(opt_parse \
    "first  | This will get the first thing passed on the command line" \
    "@rest  | This will get everything after that.")
```

This will create a standard bash array named `rest` that will contain all of the items remaining on the command line
after other arguments are consumed. This may be zero or more, opt_parse does no valiation on the number . Note that
you may only use this in the final argument position.

### Options

Options are specified in a similar form to arguments. The biggest difference is that options may have multiple names.
Both short and long options are supported.

```shell
$(opt_parse \
    "+word_regex w | if specified, match only complete words" \
    "+invert v     | if specified, match only lines that do NOT contain the regex.")

[[ ${word_regex} -eq 1 ]] && # do stuff for words
[[ ${invert}     -eq 1 ]] && # do stuff for inverting
```

As with arguments, `opt_parse` creates a local variable for each option. The name of that variable is always the
_first_ name given.

This means that `-w` and `--word-regex` are equivalent, and so are `--invert` and `-v`. Note that there's a translation
here in the name of the option. By convention, words are separated with hyphens in option names, but hyphens are not
allowed to be characters in bash variables, so we use underscores in the variable name and automatically translate that
to a hyphen in the option name.

At present, ebash supports the following types of options:

### Boolean Options

Word_regex and invert in the example above are both boolean options. That is, they're either on the command line (in
which case opt_parse assigns 1 to the variable) or not on the command line (in which case opt_parse assigns 0 to the
variable).

You can also be explicit about the value you'd like to choose for an option by specifying =0 or =1 at the end of the
option. For instance, these are equivalent and would enable the word_regex option and disable the invert option.

```shell
cmd --invert=0 --word-regex=1
cmd -i=0 -w=1
```

Note that these two options are considered to be boolean. Either they were specified on the command line or they were
not. When specified, the value of the variable will be `1`, when not specified it will be zero.

The long option versions of boolean options also implicitly support a negation by prepending the option name with no-.
For example, this is also equivalent to the above examples.

```shell
cmd --no-invert --word-regex
```

### String Options

Opt_parse also supports options whose value is a string. When specified on the command line, these _require_ an
argument, even if it is an empty string. In order to get a string option, you prepend its name with a colon character.

```shell
func()
{
    $(opt_parse ":string s")
    echo "STRING="${string}""
}

$ func --string "alpha"
STRING="alpha"
$ func --string ""
STRING=""

$ func --string=alpha
STRING="alpha"
func --string=
STRING=""
```

### Required Non-Empty String Options

Opt_parse also supports required options whose value is a non-empty string. This is identical to a normal `:` string
option only it is more strict in two ways:

- The option and argument MUST be provided
- The string argument must be non-empty

In order to use this option, prepend its name with an equal character.

```shell
func()
{
    $(opt_parse "=string s")
    echo "STRING="${string}""
}

$ func --string "alpha"
STRING="alpha"
$ func --string ""
error: option --string requires a non-empty argument.

$ func --string=alpha
STRING="alpha"
$ func --string=
error: option --string requires a non-empty argument.

$ func
error: option --string is required.
```

### Accumulator Values

Opt parse also supports the ability to accumulate string values into an array when the option is given multiple times.
In order to use an accumulator, you prepend its name with an ampersand character. The values placed into an accumulated
array cannot contain a newline character.

```shell
func()
{
    $(opt_parse "&files f")
    echo "FILES: ${files[@]}"
}

$ func --files "alpha" --files "beta" --files "gamma"
FILES: alpha beta gamma
```

### Default Values

By default, the value of boolean options is false and string options are an empty string, but you can specify a default
in your definition just as you would with arguments.

```shell
$(opt_parse \
    "+boolean b=1        | Boolean option that defaults to true" \
    ":string s=something | String option that defaults to "something")
```

### Automatic Help

Opt_parse automatically supports --help option and corresponding short option -? option for you, which will display a
usage statement using the docstrings that you provided for each of the options and arguments.

Functions called with --help/-? as processed by opt_parse will not perform their typical operation and will instead
return successfully after printing this usage statement.

