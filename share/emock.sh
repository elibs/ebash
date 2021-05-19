#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
opt_usage module_emock <<'END'
`emock` is a [mocking](https://en.wikipedia.org/wiki/Mock_object) framework for bash. It integrates well into the rest
of ebash and etest in particular to make it very easy to mock out real system binaries and replace them with mock
instances which do something else. It is very flexible in the behavior of the mocked function utilizing the many
provided option flags.

If you aren't familiar with mocking, it is by far one of the most powerful test strategies and is not not limited to
just higher-level object-oriented languages. It’s actually really powerful for low-level OS testing as well where you
basically want to test just your code and not the entire OS. The typical strategy here is to essentially create a mock
function or script which gets called instead of the real OS level
component.

In bash you could simply create a function in order to mock out external binaries. But doing this manually all over the
place is tedious and error-prone and not very feature rich. `emock` makes this both easier and far more powerful.

The simplest invocation of `emock` is to simply supply the name of the binary you wish to mock, such as:

```shell
emock "dmidecode"
```

This will create and export a new function called `dmidecode` that can be invoked instead of the real `dmidecode`
binary at `/usr/bin/dmidecode`. This also creates a function named `dmidecode_real` which can be invoked to get access
to the real underlying dmidecode binary at `/usr/sbin/dmidecode`.

By default, this mock function will simply return `0` and produce no stdout or stderr. This behavior can be customized
via `--return`, `--stdout`, and `--stderr`.

Mocking a real binary with a simplex name like this is the simplest, but doesn't always work. In particular, if at the
call site you call it with the fully-qualified path to the binary, as in `/usr/sbin/dmidecode`, then our mocked function
won't be called. In this scenario, you need to  mock it with the fully qualified path just as you would invoke it at the
call site. For example:

```shell
emock "/usr/sbin/dmidecode"
```

Just as before, this will create and export a new function named `/usr/sbin/dmidecode` (yes, function names in bash CAN
have slashes in them!!) which will be called in place of the real `dmidecode` binary. It will also create a new
function `/usr/sbin/dmidecode_real` which will call the real binary in case you need to call it instead.

`emock` tracks various metadata about mocked binaries for easier testability. This includes the number of times a mock is
called, as well as the arguments, return code, stdout, and stderr for each invocation. By default this is created in a
local hidden directory named '.emock-$$' (where $$ is the current process PID) and there will be a directory beneath
that for each mock:

```shell
${PWD}/.emock-$$/dmidecode/called
${PWD}/.emock-$$/dmidecode/mode
${PWD}/.emock-$$/dmidecode/0/{args,return_code,stdin,stdout,stderr,timestamp}
${PWD}/.emock-$$/dmidecode/1/{args,return_code,stdin,stdout,stderr,timestamp}
```

Finally, you can pass in the `--filesystem` option and emock will write out the mock to the filesystem itself rather than
only creating an in-memory mock. This facilitates more complex testing where the mock is called by a 3rd party script
and we want to still be able to mock things out properly.
END
#-----------------------------------------------------------------------------------------------------------------------

opt_usage emock <<'END'
`emock` is used to mock out a real function or external binary with a fake instance which we control the return code,
stdandard output, and standard error.

The simplest invocation of `emock` is to simply supply the name of the binary you wish to mock, such as:

```shell
emock "dmidecode"
```

This will create and export a new function called `dmidecode` that can be invoked instead of the real `dmidecode`
binary at `/usr/bin/dmidecode`. This also creates a function named `dmidecode_real` which can be invoked to get access
to the real underlying dmidecode binary at `/usr/sbin/dmidecode`.

By default, this mock function will simply return `0` and produce no stdout or stderr. This behavior can be customized
via `--return`, `--stdout`, and `--stderr`.

You can also mock out binaries that are invoked using fully-qualified paths, as in:

```shell
emock "/usr/sbin/dmidecode"
```

Just as before, this will create and export a new function named `/usr/sbin/dmidecode` (yes, function names in bash CAN
have slashes in them!!) which will be called in place of the real `dmidecode` binary. It will also create a new
function `/usr/sbin/dmidecode_real` which will call the real binary in case you need to call it instead.
END
emock()
{
    $(opt_parse \
        ":return_code return rc r=0         | What return code should the mock script use. By default this is 0."      \
        "+stdin       i                     | Mock should read from standard input and store it into a file."          \
        ":stdout      o                     | What standard output should be returned by the mock."                    \
        ":stderr      e                     | What standard error should be returned by the mock."                     \
        "+filesystem  f                     | Write out the mock to the filesystem."                                   \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the return code, stdout, and stderr for each invocation."     \
        "+reset       r                     | Reset existing mock state inside statedir from prior mock invocations."  \
        "+textfile    t                     | Treat the body as a simple text file rather than a shell script. In this
                                              mode there will be no generated stdin, stdout or stderr and the mock will
                                              not be executable. The additional tracking emock does around how many times
                                              a mock is called is also disabled when in this mode. This is suitable for
                                              mocking out simple text files which your code will read or write to."    \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode). This
                                              must match the calling convention at the call site."                     \
        "?body                              | This allows fine-grained control over the body of the mocked function that
                                              is created. Instead of using return_code, stdout, and stderr, you can
                                              directly provide the entire body of the script in this string. The syntax
                                              of this is single quotes with enclosing curly braces. This is identical
                                              to what you would use with override_function."                           \
    )

    # Prepare statedir
    statedir+="/$(basename "${name}")"
    if [[ "${reset}" -eq 1 ]]; then
        efreshdir "${statedir}"
    else
        mkdir -p "${statedir}"
    fi

    # Create called file if it doesnt' exist.
    if [[ ! -e "${statedir}/called" ]]; then
        echo "0" > "${statedir}/called"
    fi

    # Prepare the base of the mock function body. We have to put a proper interpreter if we're in filesystem mode
    # and otherwise we need to prepare the function by removing some of our ebash protections.
    local base_body="" return_statement=""
    if [[ "${filesystem}" -eq 1 ]]; then
        base_body="#!/bin/bash"
        return_statement="exit"
    else
        base_body='
            nodie_on_error
            disable_die_parent
            override_function die "{ true; }"
            set +u
        '
        return_statement="return"
    fi

    # Next part of the body will update the called count along with timestamp and saving off our arguments
    base_body+='
        # Create state directory
        statedir="'${statedir}'"

        # Get current call count for all our state files. Then update called count inside the file.
        # Do not modify our local variable as that would cause us to write out to the wrong state files.
        called=$(cat "${statedir}/called")
        echo "$(( called + 1 ))" > "${statedir}/called"

        # Create directory to store files in for this invocation
        mkdir -p "${statedir}/${called}"

        # Save off timestamp and argument array
        echo -en $(date "+%FT%TZ") > "${statedir}/${called}/timestamp"
        printf "%s\n" "${@}" > "${statedir}/${called}/args"

        # Optionally read from standard input and store into a file
        > "${statedir}/${called}/stdin"
        if [[ "'${stdin}'" -eq 1 ]]; then
            timeout 5s cat > "${statedir}/${called}/stdin" || true
        fi
    '

    # Create the mock
    if [[ -z "${body}" ]]; then
        body='
        (
            '${base_body}'

            # Save off stdout and stderr
            echo -n "'${stdout}'" > "${statedir}/${called}/stdout"
            echo -n "'${stderr}'" > "${statedir}/${called}/stderr"

            # Write stdout and stderr to streams
            echo -n "'${stdout}'" >&1
            echo -n "'${stderr}'" >&2

            # Return / Exit
            echo -n '${return_code}' > "${statedir}/${called}/return_code"
            '${return_statement}' '${return_code}'
        )'
    else

        # Figure out how far the second line is indented in the provided body. Then we strip that number of leading
        # characters of whitespace from every line in the provided body. This way when the body is indented inside a
        # function to align with its surrounding code it will be indented as intended in the final script.
        #
        # WARNING: Try to avoid as many external tools as possible here since they may have been mocked out!
        #          So we convert the input into an array and then we can directly get the number of lines and 2nd line
        #          without any reliance on external tools.
        local lines
        array_init_nl lines "${body}"
        if [[ "${#lines[@]}" -gt 1 ]]; then
            local secondline="${lines[1]}"
            local indent="${secondline%%[^ ]*}"
            lines=( "${lines[@]/${indent}/}" )
            body="$(array_join_nl lines)"
        fi

        if [[ "${textfile}" -eq 0 ]]; then
            body='
            (
                '${base_body}'
                ( '${body}' ; )

                # Return / Exit
                return_code=$?
                echo -n ${return_code} > "${statedir}/${called}/return_code"
                '${return_statement}' ${return_code}
            )'
        fi
    fi

    # Now, if we're in filesystem mode, creat the mock on-disk. Otherwise create in-memory mocks.
    if [[ "${filesystem}" -eq 0 ]]; then
        edebug "Creating function mocks"
        echo "function" > "${statedir}/mode"

        # Create _real function wrapper to call the real, unmodified binary, function or builtin.
        local real_type
        real_type=$(type -t ${name} || true)
        edebug "Creating real function wrapper ${name}_real with $(lval real_type)"
        case "${real_type}" in
            file)
                echo "true" > "${statedir}/real.exists"
                eval "${name}_real () { command ${name} \"\${@}\"; }"
                ;;

            builtin)
                echo "true" > "${statedir}/real.exists"
                eval "${name}_real () { builtin ${name} \"\${@}\"; }"
                ;;

            function)
                echo "true" > "${statedir}/real.exists"
                local real
                real="$(declare -f ${name})"
                eval "${name}_real${real#${name}}"
                ;;

            *)
                # If it wasn't any of the above then still create a real, just route it to a dummy failing function.
                # This will allow you to mock out things that do NOT exist at all.
                echo "false" > "${statedir}/real.exists"
                eval "${name}_real () { false; }"
                ;;
        esac

        eval "declare -f ${name}_real"

        # Create a function wrapper to call our mock function instead of the real function.
        edebug "Creating mock function with $(lval name body)"
        eval "${name} () ${body}"
        eval "declare -f ${name}"

    else
        edebug "Writing mock to filesystem"
        echo "filesystem" > "${statedir}/mode"

        # If _real already exists do NOT replace it as this just means the caller is re-mocking
        if [[ ! -e "${name}_real" ]]; then
            edebug "Saving ${name} -> ${name}_real"

            # If the original file doesn't exist then still create a _real just make it a symlink that points to
            # /bin/false so that it can still be executed with expected failure.
            if [[ ! -e "${name}" ]]; then
                edebug "${name} does not exist -- creating symlink to /bin/false"
                echo "false" > "${statedir}/real.exists"
                ln -s "/bin/false" "${name}"
                ls -l "${name}"
            else
                echo "true" > "${statedir}/real.exists"
            fi

            mv "${name}" "${name}_real"
        fi

        echo "${body}" > "${name}"
        chmod +x "${name}"
    fi
}

opt_usage unmock <<'END'
`eunmock` is used in tandem with `emock` to remove a mock that has previosly been created. This essentially removes the
wrapper functions we create and also cleans up the on-disk statedir for the mock.
END
eunmock()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
    )

    statedir+="/$(basename "${name}")"

    # If the mock was written out to disk remove it
    local mode
    mode=$(cat "${statedir}/mode")
    if [[ "${mode}" == "filesystem" ]]; then

        local exists
        exists=$(cat "${statedir}/real.exists")

        if [[ "${exists}" == "true" ]]; then
            edebug "Removing filesystem mock"
            mv "${name}_real" "${name}"
        else
            edebug "Removing dummy real"
            rm -f "${name}" "${name}_real"
        fi

    elif [[ "${mode}" == "function" ]]; then
        edebug "Removing ${name} mock function"
        unset -f "${name}_real"
        unset -f "${name}"
    fi

    edebug "Removing ${name} mock state"
    rm -rf "${statedir}/$(basename "${name}")"
}

opt_usage emock_called <<'END'
`emock_called` makes it easier to check how many times a mock has been called. This is tracked on-disk in the statedir
in the file named `called`. While it's easy to manually retrieve from this file, this function should always be used to
provide a clean abstraction.

Just like a typical array in any language, the size, or count of the number of times that the mock has been called is
1-based but the actual index values we use to store the state files for each invocation is zero-based (again, just like
an array).

So if this has never been called, then `emock_called` will echo `0`, and there will be no on-disk state directory. The
first time you call it, `emock_called` will echo `1`, and there will be a `${statedir}/0` directory storing the state
files for that invocation.
END
emock_called()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
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

opt_usage emock_indexes <<'END'
`emock_indexes` makes it easier to get the call indexes for the mock invocations. Think of this as the array
indexes where the first call will have a call index of `0`, the second call will have a call index of `1`, etc. This is
different than `emock_called` which a 1-based count. This is a 0-based list of call invocation numbers.

So if this has never been called, then `emock_indexes` will echo an empty string. If it has been called 3 times then
this will echo `0 1 2`. These corresponding to the directories: `${statedir}/0 ${statedir}/1 ${statedir}/2`.
END
emock_indexes()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "+last                              | Display the LAST index only rather than all indexes."                    \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
    )

    local path base indexes=()
    statedir+="/$(basename "${name}")"
    for path in "${statedir}"/*; do
        base=$(basename "${path}")
        if [[ -d "${path}" ]] && is_int "${base}"; then
            indexes+=( "${base}" )
        fi
    done

    # If there was nothing found just return immediately.
    if array_empty indexes; then
        return 0
    fi

    array_sort --version indexes

    if [[ ${last} -eq 0 ]]; then
        echo "${indexes[@]}"
    else
        echo "${indexes[-1]}"
    fi
}

opt_usage emock_stdin <<'END'
`emock_stdin` is a utility function to make it easier to get the standard input that was provided to a particular
invocation of a mocked function. This is stored on-disk and is easy to manually retrieve, but this function should
always be used to provide a clean abstraction. If the call number is not provided, this will default to the most recent
invocation's standard output.
END
emock_stdin()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard output for."                         \
    )

    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_indexes statedir -- --last ${name})
    fi

    statedir+="/$(basename "${name}")"
    local actual=""
    if [[ -e "${statedir}/${num}/stdin" ]]; then
        actual="$(cat "${statedir}/${num}/stdin")"
    fi

    echo -n "${actual}"
}

opt_usage emock_stdout <<'END'
`emock_stdout` is a utility function to make it easier to get the standard output from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
standard output.
END
emock_stdout()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard output for."                         \
    )

    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_indexes statedir -- --last ${name})
    fi

    statedir+="/$(basename "${name}")"
    local actual=""
    if [[ -e "${statedir}/${num}/stdout" ]]; then
        actual="$(cat "${statedir}/${num}/stdout")"
    fi

    echo -n "${actual}"
}

opt_usage emock_stderr <<'END'
`emock_stderr` is a utility function to make it easier to get the standard error from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
standard error.
END
emock_stderr()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard error for."                          \
    )

    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_indexes statedir -- --last ${name})
    fi

    statedir+="/$(basename "${name}")"
    local actual=""
    if [[ -e "${statedir}/${num}/stderr" ]]; then
        actual="$(cat "${statedir}/${num}/stderr")"
    fi

    echo -n "${actual}"
}

opt_usage emock_args <<'END'
`emock_args` is a utility function to make it easier to get the argument array from a particular invocation of a mocked
function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to provide a
clean abstraction. If the call number is not provided, this will default to the most recent invocation's argument array.

Inside the statedir, the argument array is stored as a newline separated file so that whitespace is preserved.
To convert this back into an array, the best thing to do is to use array_init_nl:

```shell
array_init_nl args "$(emock_args func)"
```

Alternatively, the helper `assert_emock_called_with` is an extremely useful way to validate the arguments passed
into a particular invocation.
END
emock_args()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard error for."                          \
    )

    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_indexes statedir -- --last ${name})
    fi

    statedir+="/$(basename "${name}")"
    if [[ -e "${statedir}/${num}/args" ]]; then
        cat "${statedir}/${num}/args"
    fi
}

opt_usage emock_return_code <<'END'
`emock_return_code` is a utility function to make it easier to get the return code from a particular invocation of a
mocked function. This is stored on-disk and is easy to manually retrieve, but this function should always be used to
provide a clean abstraction. If the call number is not provided, this will default to the most recent invocation's
return code.
END
emock_return_code()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "?num                               | The call number to get the standard error for."                          \
    )

    if [[ -z "${num}" ]]; then
        num=$(opt_forward emock_indexes statedir -- --last ${name})
    fi

    statedir+="/$(basename "${name}")"
    if [[ -e "${statedir}/${num}/return_code" ]]; then
        cat "${statedir}/${num}/return_code"
    fi
}

opt_usage emock_mode <<'END'
`emock_mode` is a utility function to make it easier to get the mocking mode that a mock was created with. This is stored
on-disk and is easy to manually retrieve, but this function should always be used to provide a clean abstraction. The
mocking mode will be one of either `function` or `filesystem`.
END
emock_mode()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
    )

    statedir+="/$(basename "${name}")"
    cat "${statedir}/mode"
}

#-----------------------------------------------------------------------------------------------------------------------
#
# emock asserts
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage assert_emock_called <<'END'
`assert_emock_called` is used to assert that a mock is called the expected number of times.

For example:

```shell
assert_emock_called "func" 25
```
END
assert_emock_called()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "times                              | Number of times we expect the mock to have been called."                 \
    )

    assert_eq "${times}" "$(opt_forward emock_called statedir -- ${name})"
}

opt_usage assert_emock_stdin <<'END'
`assert_emock_stdin` is used to assert that a particular invocation of a mock was provided the expected standard input.

For example:

```shell
assert_emock_stdin "func" 0 "This is the expected standard input for call #0"
assert_emock_stdin "func" 1 "This is the expected standard input for call #1"
```
END
assert_emock_stdin()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "stdin                              | The expected stdandard input."                                           \
    )

    diff --unified <(echo "${stdin}") <(echo "$(opt_forward emock_stdin statedir -- ${name} ${num})")
}

opt_usage assert_emock_stdout <<'END'
`assert_emock_stdout` is used to assert that a particular invocation of a mock produced the expected standard output.

For example:

```shell
assert_emock_stdout "func" 0 "This is the expected standard output for call #0"
assert_emock_stdout "func" 1 "This is the expected standard output for call #1"
```
END
assert_emock_stdout()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "stdout                             | The expected stdandard output."                                          \
    )

    assert_eq "${stdout}" "$(opt_forward emock_stdout statedir -- ${name} ${num})"
}

opt_usage assert_emock_stderr <<'END'
`assert_emock_stderr` is used to assert that a particular invocation of a mock produced the expected standard error.

For example:

```shell
assert_emock_stderr "func" 0 "This is the expected standard error for call #0"
assert_emock_stderr "func" 1 "This is the expected standard error for call #1"
```
END
assert_emock_stderr()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "stderr                             | The expected stdandard error."                                           \
    )

    assert_eq "${stderr}" "$(opt_forward emock_stderr statedir -- ${name} ${num})"
}

opt_usage assert_emock_return_code <<'END'
`assert_emock_return_code` is used to assert that a particular invocation of a mock produced the expected return code.

For example:

```shell
assert_emock_return_code "func" 0 0
assert_emock_return_code "func" 0 1
```
END
assert_emock_return_code()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "return_code=0                      | The expected return code."                                               \
    )

    assert_eq "${return_code}" "$(opt_forward emock_return_code statedir -- ${name} ${num})"
}

opt_usage assert_emock_called_with <<'END'
`assert_emock_called_with` is used to assert that a particular invocation of a mock was called with the expected
arguments. All arguments are fully quoted to ensure whitepace is properly perserved.

For example:

```shell
assert_emock_called_with "func" 0 "1" "2" "3" "docks and cats" "Anarchy"
expected=( "1" "2" "3" "dogs and cats" "Anarchy" )
assert_emock_called_with "func" 1 "${expected[@]}"
```
END
assert_emock_called_with()
{
    $(opt_parse \
        ":statedir=${PWD}/.emock-$$         | This directory is used to track state about mocked binaries. This will
                                              hold metadata information such as the number of times the mock was called
                                              as well as the exit code, stdout, and stderr for each invocation."       \
        "name                               | Name of the binary to mock (e.g. dmidecode or /usr/sbin/dmidecode)."     \
        "num                                | The call number to look at the arguments for."                           \
        "@expect                            | Argument array we expect the mock function to have been called with."    \
    )

    local actual=""
    array_init_nl actual "$(opt_forward emock_args statedir -- ${name} ${num})"

    if edebug_enabled; then
        edebug "EXPECT: $(lval expect)"
        edebug "ACTUAL: $(lval actual)"
    fi

    diff <(printf "%s\n" "${expect[@]}") <(printf "%s\n" "${actual[@]}")
}
