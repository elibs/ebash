#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# emock
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage emock <<'END'
emock is a mocking framework for bash. It integrates well into the rest of ebash and etest in particular to make it very
easy to mock out real system binaries and replace them with mock instances which do something else. It is very flexible
in the behavior of the mocked function utilizing the many provided option flags.

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

END
emock()
{
    $(opt_parse \
        ":return_code r=0                   | What return code should the mock script use. By default this is 0."      \
        ":stdout      o                     | What standard output should be returned by the mock."                    \
        ":stderr      e                     | What standard error should be returned by the mock."                     \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "+delete      d                     | Delete existing mock state inside statedir from prior mock invocations." \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode). This
                                              must match the calling convention at the call site."                     \
        "?body                              | This allows fine-grained control over the body of the mocked function that
                                              is created. Instead of using return_code, stdout, and stderr, you can
                                              directly provide the entire body of the script in this string. The syntax
                                              of this is single quotes with enclosing curly braces. This is identical
                                              to what you would use with override_function."                           \
    )

    statedir+="/$(basename "${name}")"
    if [[ "${delete}" -eq 1 ]]; then
        efreshdir "${statedir}"
    else
        mkdir -p "${statedir}"
    fi

    local base_body='
        nodie_on_error
        disable_die_parent
        override_function die "{ true; }"
        set +u

        # Update call count
        mkdir -p '${statedir}'
        called=0
        if [[ -e "'${statedir}'/called" ]]; then
            called=$(cat "'${statedir}'/called")
            (( called++ ))
        fi
        echo ${called} > '${statedir}'/called

        # Create directory to store files in for this invocation
        mkdir -p '${statedir}'/${called}

        # Save off argument array
        printf "\"%s\" " "${@}" > '${statedir}'/${called}/args
    '

    # Create the mock
    if [[ -z "${body}" ]]; then
        body='
        {
            '${base_body}'

            # Save off stdout and stderr
            echo -n "'${stdout}'" > '${statedir}'/${called}/stdout
            echo -n "'${stderr}'" > '${statedir}'/${called}/stderr

            # Write stdout and stderr to streams
            echo -n "'${stdout}'" >&1
            echo -n "'${stderr}'" >&2

            # Return
            return '${return_code}'
        }'
    else
        body='
        {
            '${base_body}'
            '${body}'
        }'
    fi

    # Create _real function wrapper to call the real, unmodified function
    edebug "Creating ${name}_real function"
    if command ${name} &>/dev/null; then
        eval "${name}_real () { command ${name} \"\${@}\"; }"
    else
        local real
        real="$(declare -f ${name})"
        eval "${name}_real${real#${name}}"
    fi

    eval "declare -f ${name}_real"

    # Create a function wrapper to call our mock function instead of the real function.
    edebug "Creating ${name} mock function with $(lval body)"
    eval "${name} () ${body}"
    eval "declare -f ${name}"
}

opt_usage unmock <<'END'
eunmock is used in tandem with emock to remove a mock that has previosly been created. This essentially removes the
wrapper functions we create and also cleans up the on-disk statedir for the mock.
END
eunmock()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
    )

    edebug "Removing ${name} mock function"
    unset -f "${name}_real"
    unset -f "${name}"

    edebug "Removing ${name} mock state"
    rm -rf "${statedir}/$(basename "${name}")"
}

opt_usage emock_called <<'END'
emock_called make it easier to check how many times a mock has been called. This is tracked on-disk in the statedir in
the file named "called". While it's easy to manually retrieve from this file, this function should always be used to
provide a clean abstraction.

Just like a typical array in any language, the size, or count of the number of times that the
mock has been called is 1-based but the actual index values we use to store the state files for each invocation is
zero-based (again, just like an array).

So if this has never been called, then emock_called will return 0, and there will be no on-disk state directory. The
first time you call it, emock_called will return 1, and there will be a ${statedir}/0 directory storing the state files
for that invocation.
END
emock_called()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
    )

    statedir+="/$(basename "${name}")"
    local called=0
    if [[ -e "${statedir}/called" ]]; then
        called="$(cat "${statedir}/called")"
    fi

    echo -n "${called}"
}

opt_usage emock_stdout <<'END'
emock_stdout is a utility function to make it easier to get the standard output from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
standard output.
END
emock_stdout()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard output for."                         \
    )

    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_called statedir -- ${name})
    fi

    statedir+="/$(basename "${name}")"
    local actual=""
    if [[ -e "${statedir}/${num}/stdout" ]]; then
        actual="$(cat "${statedir}/${num}/stdout")"
    fi

    echo -n "${actual}"
}

opt_usage emock_stderr <<'END'
emock_stderr is a utility function to make it easier to get the standard error from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
standard error.
END
emock_stderr()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard error for."                          \
    )

    statedir+="/$(basename "${name}")"
    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_called statedir -- ${name})
    fi

    local actual=""
    if [[ -e "${statedir}/${num}/stderr" ]]; then
        actual="$(cat "${statedir}/${num}/stderr")"
    fi

    echo -n "${actual}"
}

opt_usage emock_args <<'END'
emock_args is a utility function to make it easier to get the argument array from a particular invocation of a mocked
function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to provide a
clean abstraction. If the call number is not provided, this will default to the most recent invocation's argument array.

Inside the statedir, the argument array is stored with each argument fully quoted so that whitespace encapsulated
arguments preserve whitespace. To convert this back into an array, the best thing to do is to use array_init:

    # array_init args "$(emock_args func)"

Alternatively, the helper idiom assert_emock_called_with is an extremely useful way to validate the arguments passed
into a particular invocation.
END
emock_args()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard error for."                          \
    )

    statedir+="/$(basename "${name}")"
    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_called statedir -- ${name})
    fi

    if [[ -e "${statedir}/${num}/args" ]]; then
        cat "${statedir}/${num}/args"
    fi
}

#-----------------------------------------------------------------------------------------------------------------------
#
# emock asserts
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage assert_emock_called <<'END'
assert_emock_called is used to assert that a mock is called the expected number of times. For example:

    # assert_emock_called "func" 25

END
assert_emock_called()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "times                              | Number of times we expect the mock to have been called."                 \
    )

    assert_eq "${times}" "$(opt_forward emock_called statedir -- ${name})"
}

opt_usage assert_emock_stdout <<'END'
assert_emock_stdout is used to assert that a particular invocation of a mock produced the expected standard output.
For example:

    # assert_emock_stdout "func" 0 "This is the expected standard output for call #0"
    # assert_emock_stdout "func" 1 "This is the expected standard output for call #1"
END
assert_emock_stdout()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "stdout                             | The expected stdandard output."                                          \
    )

    assert_eq "${stdout}" "$(opt_forward emock_stdout statedir -- ${name} ${num})"
}

opt_usage assert_emock_stderr <<'END'
assert_emock_stderr is used to assert that a particular invocation of a mock produced the expected standard error.
For example:

    # assert_emock_stderr "func" 0 "This is the expected standard error for call #0"
    # assert_emock_stderr "func" 1 "This is the expected standard error for call #1"
END
assert_emock_stderr()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "stderr                             | The expected stdandard error."                                           \
    )

    assert_eq "${stderr}" "$(opt_forward emock_stderr statedir -- ${name} ${num})"
}

opt_usage assert_emock_called_with <<'END'
assert_emock_called_with is used to assert that a particular invocation of a mock was called with the expected arguments.
All arguments are fully quoted to ensure whitepace is properly perserved.

For example:

    # assert_emock_called_with "func" 0 "1" "2" "3" "docks and cats" "Anarchy"
    # expected=( "1" "2" "3" "dogs and cats" "Anarchy" )
    # assert_emock_caleld_with "func" 1 "${expected[@]}"
END
assert_emock_called_with()
{
    $(opt_parse \
        ":statedir=.emock                   | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "@args                              | Argument array we expect the mock function to have been called with."    \
    )

    local actual=""
    array_init actual "$(opt_forward emock_args statedir -- ${name} ${num})"
    diff --unified <(printf "\"%s\" " "${args[@]}") <(echo -n "${actual[@]} ")
}
