# Module assert


## func assert

Executes a command (simply type the command after assert as if you were running it without assert) and calls die if
that command returns a bad exit code.

For example:

```shell
assert test 0 -eq 1
```

There's a subtlety here that I don't think can easily be fixed given bash's semantics. All of the arguments get
evaluated prior to assert ever seeing them. So it doesn't know what variables you passed in to an expression, just
what the expression was. This is pretty handy in cases like this one:

```shell
a=1 b=2 assert test "${a}" -eq "${b}"
```

Because assert will tell you that the command that it executed was

```shell
test 1 -eq 2
```

There it seems ideal. But if you have an empty variable, things get a bit annoying. For instance, this command will
exit with a failure because inside assert bash will try to evaluate [[ -z ]] without any arguments to -z. (Note -- it
still exits with a failure, just not in quite the way you'd expect)

```shell
empty="" assert test -z ${empty}
```

To make this particular case easier to deal with, we also have assert_empty which you could use like this:

```shell
assert_empty empty
```

> **_NOTE:_** `assert` doesn't work with bash double-bracket expressions. The simplest solution is to use `test` as in
`assert test <expression>` or just leave off the `assert` entirely since it's largely syntactic convenience and just use
`[[ ... ]]`

## func assert_archive_contents


Assert that the provided archive contains the expected content. If there are any additional files in the archive not
specified on the list of expected files then this assertion will fail.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --type, -t <value>
         Override automatic type detection and use explicit archive type.


ARGUMENTS

   archive
         Archive whose contents should be listed.

```

## func assert_docker_image_exists


This function asserts that a docker image exists locally.

```Groff
ARGUMENTS

   image
        image

```

## func assert_docker_image_not_exists


This function asserts that a docker image does not exists locally.

```Groff
ARGUMENTS

   image
        image

```

## func assert_empty

All arguments passed to assert_empty must be empty strings or else it will die and display the first that is not.

## func assert_exists

Accepts any number of filenames. Blows up if any of the named files do not exist.

## func assert_not_empty

All arguments passed to assert_not_empty must be non-empty strings or else it will die and display the first that is
not.

## func assert_not_exists

Accepts any number of filenames. Blows up if any of the named files exist.

## func assert_valid_ip


This function asserts that the provided string is a valid IPv4 IP Address.

```Groff
ARGUMENTS

   input
        input

   msg
        ?msg

```

## func assert_var_empty

Accepts variable names as parameters. All passed in variable names must be either unset or must contain only an empty
string.

Note: there is not an analogue assert_var_not_empty. Use argcheck instead.
