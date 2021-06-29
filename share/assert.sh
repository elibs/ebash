#!/bin/bash
#
# Copyright 2016-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2016-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage assert <<'END'
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
END
assert()
{
    "${@}"
}

assert_true()
{
    "${@}"
}

assert_false()
{
    local cmd=( "${@}" )

    local rc=0
    try
    {
        "${cmd[@]}"
    }
    catch
    {
        rc=$?
    }
    [[ ${rc} -ne 0 ]] || die "assert failed (rc=${rc}) :: ${cmd[*]}"
}

assert_eq()
{
    $(opt_parse \
        "+hexdump h | If there is a failure, display contents of both values through a hex dump tool." \
        "?expected  | The first of two values you expect to be equivalent." \
        "?actual    | The second of two values you expect to be equivalent." \
        "?msg       | Optional message to display in the output if there is a failure")

    if [[ "${expected}" != "${actual}" ]] ; then

        if [[ ${hexdump} -eq 1 ]] ; then
            eerror "expected:"
            echo "${expected}" | hexdump -C >&2
            eerror "actual:"
            echo "${actual}" | hexdump -C >&2
            die "assert_eq failed [${msg:-}]"

        else
            die "assert_eq failed [${msg:-}] :: $(lval expected actual)"
        fi
    fi
}

assert_ne()
{
    $(opt_parse "?lh" "?rh" "?msg")
    [[ ! "${lh}" == "${rh}" ]] || die "assert_ne failed [${msg:-}] :: $(lval lh rh)"
}

assert_lt()
{
    $(opt_parse "?lh" "?rh" "?msg")
    assert compare "${lh}" "<" "${rh}" || die "assert_lt failed [${msg:-}] :: $(lval lh rh)"
}

assert_le()
{
    $(opt_parse "?lh" "?rh" "?msg")
    assert compare "${lh}" "<=" "${rh}" || die "assert_le failed [${msg:-}] :: $(lval lh rh)"
}

assert_gt()
{
    $(opt_parse "?lh" "?rh" "?msg")
    assert compare "${lh}" ">" "${rh}" || die "assert_gt failed [${msg:-}] :: $(lval lh rh)"
}

assert_ge()
{
    $(opt_parse "?lh" "?rh" "?msg")
    assert compare "${lh}" ">=" "${rh}" || die "assert_ge failed [${msg:-}] :: $(lval lh rh)"
}

assert_match()
{
    $(opt_parse "?text" "?regex" "?msg")
    [[ "${text}" =~ ${regex} ]] || die "assert_match failed [${msg:-}] :: $(lval text regex)"
}

assert_not_match()
{
    $(opt_parse "?text" "?regex" "?msg")
    [[ ! "${text}" =~ ${regex} ]] || die "assert_not_match failed [${msg:-}] :: $(lval text regex)"
}

assert_zero()
{
    [[ ${1:-0} -eq 0 ]] || die "assert_zero received $1 instead of zero."
}

assert_not_zero()
{
    [[ ${1:-1} -ne 0 ]] || die "assert_not_zero received ${1}."
}

opt_usage assert_empty <<'END'
All arguments passed to assert_empty must be empty strings or else it will die and display the first that is not.
END
assert_empty()
{
    local _arg
    for _arg in "$@" ; do
        [[ -z "${_arg}" ]] || die "${FUNCNAME} received $(lval _arg)"
    done
}

opt_usage assert_not_empty <<'END'
All arguments passed to assert_not_empty must be non-empty strings or else it will die and display the first that is
not.
END
assert_not_empty()
{
    local _arg
    for _arg in "$@" ; do
        [[ -n ${_arg} ]] || die "${FUNCNAME} received $(lval _arg)"
    done
}

opt_usage assert_var_empty <<'END'
Accepts variable names as parameters. All passed in variable names must be either unset or must contain only an empty
string.

Note: there is not an analogue assert_var_not_empty. Use argcheck instead.
END
assert_var_empty()
{
    local _arg
    for _arg in "$@" ; do
        [[ "${!_arg:-}" == "" ]] || die "${FUNCNAME} received $(lval _arg)"
    done
}

opt_usage assert_exists <<'END'
Accepts any number of filenames. Blows up if any of the named files do not exist.
END
assert_exists()
{
    local name
    for name in "${@}"; do
        [[ -e "${name}" ]] || die "'${name}' does not exist"
    done
}

opt_usage assert_not_exists <<'END'
Accepts any number of filenames. Blows up if any of the named files exist.
END
assert_not_exists()
{
    local name
    for name in "${@}"; do
        [[ ! -e "${name}" ]] || die "'${name}' exists"
    done
}

opt_usage assert_archive_contents <<'END'
Assert that the provided archive contains the expected content. If there are any additional files in the archive not
specified on the list of expected files then this assertion will fail.
END
assert_archive_contents()
{
    $(opt_parse \
        ":type t | Override automatic type detection and use explicit archive type." \
        "archive | Archive whose contents should be listed.")

    edebug "Validating $(lval archive type)"

    local expect=() actual=() expect_tmp="" actual_tmp=""

    expect=( "${@}" )
    array_sort expect

    assert_exists "${archive}"
    actual=( $(opt_forward archive_list type -- ${archive}) )

    expect_tmp=$(mktemp --tmpdir assert_directory_contents-expect-XXXXXX)
    echo "$(array_join_nl expect)" | sort --unique > "${expect_tmp}"

    actual_tmp=$(mktemp --tmpdir assert_directory_contents-actual-XXXXXX)
    echo "$(array_join_nl actual)" | sort --unique > "${actual_tmp}"

    assert diff --unified "${expect_tmp}" "${actual_tmp}"
}

assert_directory_contents()
{
    $(opt_parse directory)
    edebug "Validating $(lval directory)"

    local expect=() actual=() expect_tmp="" actual_tmp=""

    expect=( "${@}" )
    array_sort expect

    assert_exists "${directory}"
    actual=( $(find "${directory}" -printf '%P\n' | sort) )

    expect_tmp=$(mktemp --tmpdir assert_directory_contents-expect-XXXXXX)
    echo "$(array_join_nl expect)" | sort --unique > "${expect_tmp}"

    actual_tmp=$(mktemp --tmpdir assert_directory_contents-actual-XXXXXX)
    echo "$(array_join_nl actual)" | sort --unique > "${actual_tmp}"

    assert diff --unified "${expect_tmp}" "${actual_tmp}"
}

assert_int()
{
    local _arg
    for _arg in "$@" ; do
        assert is_int "${_arg}"
    done
}

assert_num()
{
    local _arg
    for _arg in "$@" ; do
        assert is_num "${_arg}"
    done
}

assert_num_eq()
{
    $(opt_parse "lh" "rh" "?msg")
    assert_num "${lh}" "${rh}"
    assert compare "${lh}" "==" "${rh}" || die "assert_num_eq failed [${msg:-}] :: $(lval lh rh)"
}

assert_num_ne()
{
    $(opt_parse "lh" "rh" "?msg")
    assert_num "${lh}" "${rh}"
    assert compare "${lh}" "!=" "${rh}" || die "assert_num_ne failed [${msg:-}] :: $(lval lh rh)"
}

assert_num_lt()
{
    $(opt_parse "lh" "rh" "?msg")
    assert_num "${lh}" "${rh}"
    assert_lt "${lh}" "${rh}" "${msg}"
}

assert_num_le()
{
    $(opt_parse "lh" "rh" "?msg")
    assert_num "${lh}" "${rh}"
    assert_le "${lh}" "${rh}" "${msg}"
}

assert_num_gt()
{
    $(opt_parse "lh" "rh" "?msg")
    assert_num "${lh}" "${rh}"
    assert_gt "${lh}" "${rh}" "${msg}"
}

assert_num_ge()
{
    $(opt_parse "lh" "rh" "?msg")
    assert_num "${lh}" "${rh}"
    assert_ge "${lh}" "${rh}" "${msg}"
}

opt_usage assert_docker_image_exists <<'END'
This function asserts that a docker image exists locally.
END
assert_docker_image_exists()
{
    $(opt_parse image)
    docker inspect --type image --format . "${image}" &> /dev/null || die "docker $(lval image) does not exist"
}

opt_usage assert_docker_image_not_exists <<'END'
This function asserts that a docker image does not exists locally.
END
assert_docker_image_not_exists()
{
    $(opt_parse image)
    ! docker inspect --type image --format . "${image}" &> /dev/null || die "docker $(lval image) exists and should not"
}

opt_usage assert_valid_ip <<'END'
This function asserts that the provided string is a valid IPv4 IP Address.
END
assert_valid_ip()
{
    $(opt_parse "input" "?msg")

    valid_ip "${input}" || die "assert_valid_ip failed [${msg:-}] :: $(lval input)"
}
