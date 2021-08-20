#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Try/Catch
#
#-----------------------------------------------------------------------------------------------------------------------

DIE_MSG_KILLED='[Killed]'
DIE_MSG_CAUGHT='[ExceptionCaught pid=$BASHPID cmd=$(string_truncate -e 60 ${BASH_COMMAND})]'
DIE_MSG_UNHERR='[UnhandledError pid=$BASHPID cmd=$(string_truncate -e 60 ${BASH_COMMAND})]'

opt_usage try <<'END'
The below aliases allow us to support rich error handling through the use of the try/catch idom typically found in
higher level languages. Essentially the 'try' alias creates a subshell and then turns on implicit error handling
through "die_on_error" (which essentially just enables 'set -e'). Since this runs in a subshell with fatal error
handling enabled, the subshell will immediately exit on failure. The catch block which immediately follows the try
block captures the exit status of the subshell and if it's not '0' it will invoke the catch block to handle the error.

NOTE: We have nested subshells here to solve a very particular use case where where try/catch could not be used inside
      main but only worked inside a function or subshell. To solve that corner case we simply always put the entire
      try/catch in an extra subshell so that it is safe to use directly inside main. This of course adds a negligible
      overhead but is worth it for this corner case being fixed.
END
__EBASH_DIE_ON_ERROR_TRAP_STACK=()
alias try="
    (
        __EBASH_DIE_ON_ERROR_TRAP=\"\$(trap -p ERR | sed -e 's|trap -- ||' -e 's| ERR||' -e \"s|^'||\" -e \"s|'$||\" || true)\"
        : \${__EBASH_DIE_ON_ERROR_TRAP:=-}
        __EBASH_DIE_ON_ERROR_TRAP_STACK+=( \"\${__EBASH_DIE_ON_ERROR_TRAP}\" )
        nodie_on_error

        (
            __EBASH_INSIDE_TRY=1
            declare __EBASH_DISABLE_DIE_PARENT_PID=\${BASHPID}
            enable_trace
            die_on_abort
            trap 'die -r=\$? ${DIE_MSG_CAUGHT}' ERR
    "

opt_usage catch <<'END'
Catch block attached to a preceeding try block. This is a rather complex alias and it's probably not readily obvious
why it jumps through the hoops it is jumping through but trust me they are all important. A few important notes about
this alias:

1) Note that the ");" ends the preceeding subshell created by the "try" block. Which means that a try block on it's
   own will be invalid syntax to try to force try/catch to always be used properly.

2) All of the "|| true" stuff in this alias is extremely important. Without it the implicit error handling will kick
   in and the process will be terminated immediately instead of allowing the catch() block to handle the error.

3) It's often really convenient for the catch block to know what the error code was inside the try block. But that's
   actually kinda of hard to get right. So here we capture the error code, and then we employ a curious "( exit $rc; )
   ||" to create a NEW subshell which exits with the original try block's status. If it was 0 this will do nothing.
   Otherwise it will call the catch block handling code. If we didn't care about the nesting
    levels this wouldn't be necessary and we could just simplify the catch alias to "); ||". But knowing the nesting
    level is really important.

4) The dangling "||" here requries the caller to put something after the catch block which sufficiently handles the
   error or the code won't be valid.
END
alias catch=" );
    __EBASH_TRY_CATCH_RC=\$?
    __EBASH_DIE_ON_ERROR_TRAP=\"\${__EBASH_DIE_ON_ERROR_TRAP_STACK[@]:(-1)}\"
    unset __EBASH_DIE_ON_ERROR_TRAP_STACK[\${#__EBASH_DIE_ON_ERROR_TRAP_STACK[@]}-1]
    trap \"\${__EBASH_DIE_ON_ERROR_TRAP}\" ERR
    exit \${__EBASH_TRY_CATCH_RC} ) || "

opt_usage throw <<'END'
Throw is just a simple wrapper around exit but it looks a little nicer inside a 'try' block to see 'throw' instead of
'exit'.
END
throw()
{
    exit $1
}

opt_usage inside_try <<'END'
Returns true (0) if the current code is executing inside a try/catch block and false otherwise.
END
inside_try()
{
    [[ ${__EBASH_INSIDE_TRY:-0} -eq 1 ]]
}

opt_usage tryrc <<'END'
Tryrc is a convenience wrapper around try/catch that makes it really easy to execute a given command and capture the
command's return code, stdout and stderr into local variables. We created this idiom because if you handle the failure
of a command in any way then bash effectively disables `set -e` that command invocation REGARDLESS OF DEPTH. **Handling
the failure** includes putting it in a while or until loop, part of an if/else statement or part of a command executed
in a `&&` or `||`.

Consider a function call chain such as:

    foo->bar->zap

and you want to get the return value from foo, you might (wrongly) think you could safely use this and safely bypass set
`set -e` explosion:

```shell
foo || rc=$?
```

The problem is bash effectively disables `set -e` for this command when used in this context. That means even if `zap`
encounteres an unhandled error `die` will NOT get implicitly called (explicit calls to `die` would still get called of
course).

Here is the insidious documentation from `man bash` regarding this obscene behavior:

    The ERR trap is not executed if the failed command is part of the command list immediately following a while or
    until keyword, part of the test in an if statement, part of a command executed in a && or ||  list  except the
    command following the final && or ||, any command in a pipeline but the last, or if the command's return value is
    being inverted using !.

What's not obvious from that statement is that this applies to the entire expression including any functions it may call
not just the top-level expression that had an error. Ick.

Thus we created `tryrc` to allow safely capturing the return code, stdout and stderr of a function call WITHOUT bypassing
`set -e` safety!

This is invoked using the "eval command invocation string" idiom so that it is invoked in the caller's envionment. For
example:

```shell
$(tryrc some-command)
```
END
tryrc()
{
    $(opt_parse \
        ":rc r=rc  | Variable to assign the return code to."                                                           \
        ":stdout o | Write stdout to the specified variable rather than letting it go to stdout. The special value '_'
                     means to discard it entirely by sending it to /dev/null."                                         \
        ":stderr e | Write stderr to the specified variable rather than letting it go to stderr. The special value '_'
                     means to discard it entirely by sending to to /dev/null."                                         \
        "+global g | Make variables created global rather than local"                                                  \
        "@cmd      | Command to run, along with any arguments."                                                        \
    )

    # Determine flags to pass into declare
    local dflags=""
    [[ ${global} -eq 1 ]] && dflags="-g"

    # Temporary directory to hold stdout and stderr
    local tmpdir
    tmpdir=$(mktemp --tmpdir --directory tryrc-XXXXXX)
    trap_add "rm --recursive --force ${tmpdir}"

    # Create temporary file for stdout and stderr
    local stdout_file="${tmpdir}/stdout" stderr_file="${tmpdir}/stderr"
    [[ "${stdout}" == "_" ]] && stdout_file="/dev/null"
    [[ "${stderr}" == "_" ]] && stderr_file="/dev/null"

    # We're creating an "eval command string" inside the command substitution that the caller is supposed to wrap around
    # tryrc.
    #
    # Command substitution really can only run one big command. In other words, everything after the first command
    # inside it is passed as an argument to the first command. But you can separate multiple commands by semicolons
    # inside an eval, so we put an eval around the entire output of tryrc.
    #
    # Later you'll see we also put eval around the inside commands. We basically quote everything twice and then make
    # up for it by eval-ing everything twice in order to convince everything to keep whitespace as it is.
    echo eval

    # Need to first make sure we've emitted code to set our output variables in the event we are interrupted
    echo eval "declare ${dflags} ${rc}=1;"
    [[ -n ${stdout} ]] && echo eval "declare ${dflags} ${stdout}="";"
    [[ -n ${stderr} ]] && echo eval "declare ${dflags} ${stderr}="";"

    # Execute actual command in try/catch so that any fatal errors in the command properly terminate execution of the
    # command then capture off the return code in the catch block. Send all stdout and stderr to respective pipes which
    # will be read in by the above background processes.
    local actual_rc=0
    try
    {
        if [[ -n "${cmd[*]:-}" ]]; then

            # Redirect subshell's STDOUT and STDERR to requested locations
            exec >${stdout_file}
            [[ -n ${stderr} ]] && exec 2>${stderr_file}

            # Run command
            quote_eval "${cmd[@]}"
        fi
    }
    catch
    {
        actual_rc=$?
    }

    # Emit commands to assign return code
    echo eval "declare ${dflags} ${rc}=${actual_rc};"

    # Emit commands to assign stdout but ONLY if a stdout file was actually created. This is because the file is only
    # created on first write. And we don't want this to fail if the command didn't write any stdout. This is also SAFE
    # because we initialize stdout and stderr above to empty strings.
    if [[ -s ${stdout_file} ]]; then
        local actual_stdout
        actual_stdout="$(pipe_read_quote ${stdout_file})"
        if [[ -n ${stdout} ]]; then
            echo eval "declare ${dflags} ${stdout}=${actual_stdout};"
        else
            echo eval "echo ${actual_stdout} >&1;"
        fi
    fi

    # Emit commands to assign stderr
    if [[ -n ${stderr} && -s ${stderr_file} ]]; then
        local actual_stderr
        actual_stderr="$(pipe_read_quote ${stderr_file})"
        echo eval "declare ${dflags} ${stderr}=${actual_stderr};"
    fi

    # Remote temporary directory
    rm --recursive --force ${tmpdir}
}

# We need to include disable_die_parent in trycatch.sh as it is included at the top of ebash.sh to ensure that the alias
# is expanded BEFORE functions which use it are sourced. Otherwise this alias never gets expanded.
opt_usage disable_die_parent <<'END'
Prevent an error or other die call in the _current_ shell from killing its parent. By default with ebash, errors
propagate to the parent by sending the parent a sigterm.

You might want to use this in shells that you put in the background if you don't want an error in them to cause you to
be notified via sigterm.
END
alias disable_die_parent="declare __EBASH_DISABLE_DIE_PARENT_PID=\${BASHPID}"
