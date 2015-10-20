#!/usr/bin/env bash

ETEST_ensure_trap_enabled_by_default()
{
    # Simple sanity test to ensure the default setup in efuncs enables
    # ERR trap otherwise all other assumptions in this test suite are
    # invalid.
    einfo "Verifying ERR trap is set"
    trap -p
    die_on_error_enabled || die "ERR trap should be enabled"
}

ETEST_try_catch()
{
    try
    {
        mkdir a
        touch a/1
        mkdir a
        touch a/2
        mkdir a
        touch a/3
    }
    catch 
    {
        true
    }

    # We should bail out on first error - so make sure only a/1 exists
    [[   -d a   ]] || die "a is missing"
    [[   -e a/1 ]] || die "a/1 is missing"
    [[ ! -e a/2 ]] || die "a/2 shouldn't exist"
    [[ ! -e a/3 ]] || die "a/3 shouldn't exist"
}

ETEST_try_catch_rethrow()
{
    try
    {
        try
        {
            mkdir a
            mkdir a
        }
        catch 
        {
            # Rethrow the error
            throw $?
        }

        die "Catch block should have re-thrown"
    }
    catch
    {
        return 0
    }

    die "Exception was not rethrown"
}

# Verify aborts are handled correctly inside internal try/catch subshell
ETEST_try_catch_abort()
{
    (
        try
        {
            sleep infinity
        }
        catch
        {
            return $?
        }

        die "catch block should have returned"
    ) &

    # Give it a second to get going then kill it
    local pid=$!
    einfo "Waiting for $(lval pid)"
    sleep 1s
    ekilltree -s=TERM ${pid}
    wait ${pid} && rc=0 || rc=$?
    einfo "Process killed $(lval pid rc)"
    assert_eq 143 ${rc}
}

# Verify catch gets the exit code the try block throws
ETEST_try_exit_code()
{
    try
    {
        exit 100
    }
    catch
    {
        assert_eq 100 $?
        return 0
    }

    die "Catch block should have returned"
}

# Verify we can disable trap/die on error
ETEST_nodie_on_error()
{
    # First ensure we have our trap set for ERR so that the test actually
    # validates we can disable the trap
    einfo "Verifying ERR trap is set"
    die_on_error_enabled || die "ERR trap should be enabled"

    einfo "Disabling ERR trap"
    nodie_on_error

    einfo "Verifying ERR trap is unset"
    ! die_on_error_enabled || die "ERR trap should be disabled"
   
    einfo "Intentionally causing an error..."
    false
    return 0
}

# Verify we can disable die_on_error and that later using a try-catch
# doesn't incorrectly re-enable it.
ETEST_nodie_on_error_with_try_catch()
{
    # First ensure we have our trap set for ERR so that the test actually
    # validates we can disable the trap
    einfo "Verifying ERR trap is set"
    die_on_error_enabled || die "ERR trap should be enabled"

    einfo "Disabling ERR trap"
    nodie_on_error

    # Verify die on error is not enabled
    einfo "Verifying ERR trap is unset"
    ! die_on_error_enabled || die "ERR trap should be disabled"
    
    try
    {
        throw 100
        die "throw() didn't exit try block"
    }
    catch
    {
        assert_eq 100 $?
    }
   
    # die_on_error should still be disabled
    einfo "Verifying ERR trap is unset after try/catch"
    ! die_on_error_enabled || die "ERR trap should be disabled"
}

# Verify we are building up the try/catch enabled stack correctly.
ERR_TRAP_DIE="die ${DIE_MSG_UNHERR}"
ERR_TRAP_CATCH="die -c=grey19 -r=\$? ${DIE_MSG_CAUGHT} &>\$(edebug_out)"
ERR_TRAP_NONE="-"

assert_stack_eq()
{
    assert_eq $# $(array_size __EFUNCS_DIE_ON_ERROR_TRAP_STACK)

    local frame=0
    for code in "${@}"; do
        eval "local expect="\${ERR_TRAP_${code}}""
        local actual="${__EFUNCS_DIE_ON_ERROR_TRAP_STACK[$frame]}"

        einfo "$(lval frame expect actual)"
        assert_eq "${expect}" "${actual}"
        (( frame+=1 ))
    done
}

ETEST_try_catch_stack()
{
    assert_stack_eq DIE CATCH

    # Add some more try-catches with various enable/disable
    die_on_error_enabled || die "ERR trap should be enabled"
    nodie_on_error
    ! die_on_error_enabled || die "ERR trap should be disabled"

    try
    {
        die_on_error_enabled || die "ERR trap should be enabled"
        assert_stack_eq DIE CATCH NONE

        try
        {
            die_on_error_enabled || die "ERR trap should be enabled"
            assert_stack_eq DIE CATCH NONE CATCH
           
            try
            {
                die_on_error_enabled || die "ERR trap should be enabled"
                assert_stack_eq DIE CATCH NONE CATCH CATCH
           
                # Disable
                nodie_on_error
                ! die_on_error_enabled || die "ERR trap should be disabled"
                try
                {
                    die_on_error_enabled || die "ERR trap should be enabled"
                    assert_stack_eq DIE CATCH NONE CATCH CATCH NONE
           
                    false
                    die "try block should have thrown"
                }
                catch
                {
                    ! die_on_error_enabled || die "ERR trap should be disabled"
                    assert_stack_eq DIE CATCH NONE CATCH CATCH
                }
                
                ! die_on_error_enabled || die "ERR trap should be disabled"
                assert_stack_eq DIE CATCH NONE CATCH CATCH
                
                false
                true
            }
            catch
            {
                die "try block should not have thrown"
            }
     
            die_on_error_enabled || die "ERR trap should be enabled"
            assert_stack_eq DIE CATCH NONE CATCH
            false
            die "try block should have thrown"
        }
        catch
        {
            assert_stack_eq DIE CATCH NONE
        }
        
        die_on_error_enabled || die "ERR trap should be enabled"
        assert_stack_eq DIE CATCH NONE
        false
        die "try block should have thrown"
    }
    catch
    { 
        assert_stack_eq DIE CATCH
    }
            
    ! die_on_error_enabled || die "ERR trap should be disabled"
    assert_stack_eq DIE CATCH
}

etest_deep_error_2()
{
    echo "pre_deep_error"
    false
    echo "post_deep_error"

    die "Should never have gotten here"
}

etest_deep_error_1()
{
    etest_deep_error_2
}

etest_deep_error()
{
    etest_deep_error_1
}

ETEST_try_catch_deep_error()
{
    try
    {
        etest_deep_error
        die "etest_deep_error should have caused a fatal error"
    }
    catch
    {
        return 0
    }

    die "test should have returned"
}

# Verify die_on_error **IS** inherited into subshell since we are now using
# 'set -o errtrace' to ensure our trap is inherited by functions, command 
# substitutions, and commands executed inside subshells.
ETEST_errtrap_inherited_in_subshell()
{
    try
    {
        ( false )
        die "false should have thrown"
    }
    catch
    {
        return 0
    }

    die "Catch block should have returned"
}

# Verify we can use explicit 'throw' to return an error
ETEST_throw()
{
    try
    {
        throw 100
        throw 200
    }
    catch
    {
        assert_eq 100 $?
        return 0
    }
    
    die "Catch block should have returned"
}

# Verify we can disable and then re-enable errors
ETEST_disable_enable_die_on_error()
{
    try
    {
        nodie_on_error
        mkdir foo
        mkdir foo
        die_on_error
        false
    }
    catch
    {
        return 0
    }

    die "Catch block should have returned"
}

#-----------------------------------------------------------------------------
# tryrc
#-----------------------------------------------------------------------------

ETEST_tryrc()
{
    $(tryrc -o=stdout -e=stderr echo "foo")
    einfo "$(lval rc stdout stderr)"

    assert_eq 0     "${rc}"
    assert_eq "foo" "${stdout}"
    assert_eq ""    "${stderr}"
}

ETEST_tryrc_empty_command()
{
    $(tryrc -o=stdout -e=stderr "")

    assert_eq 0  "${rc}"
    assert_eq "" "${stdout}"
    assert_eq "" "${stderr}"
}

ETEST_tryrc_declare()
{
    $(tryrc -o=stdout -e=stderr echo "foo")
    einfo "$(lval rc stdout stderr)"

    assert_eq 'declare -- rc="0"'       "$(declare -p rc)"
    assert_eq 'declare -- stdout="foo"' "$(declare -p stdout)"
    assert_eq 'declare -- stderr=""'    "$(declare -p stderr)"
}

ETEST_tryrc_declare_global()
{
    declare -g rc=1
    declare -g stdout="ORIG"
    declare -g stderr="ORIG"

    call_tryrc()
    {
        $(tryrc -g -o=stdout -e=stderr eval 'echo "foo" >&1; echo "bar" >&2')
        einfo "$(lval rc stdout stderr)"
    }

    call_tryrc

    assert_eq 'declare -- rc="0"'       "$(declare -p rc)"
    assert_eq 'declare -- stdout="foo"' "$(declare -p stdout)"
    assert_eq 'declare -- stderr="bar"' "$(declare -p stderr)"
}

ETEST_tryrc_declare_local()
{
    rc=1
    stdout="ORIG"
    stderr="ORIG"

    call_tryrc()
    {
        $(tryrc -o=stdout -e=stderr eval 'echo "foo" >&1; echo "bar" >&2')
        einfo "$(lval rc stdout stderr)"
    }

    call_tryrc

    assert_eq 'declare -- rc="1"'        "$(declare -p rc)"
    assert_eq 'declare -- stdout="ORIG"' "$(declare -p stdout)"
    assert_eq 'declare -- stderr="ORIG"' "$(declare -p stderr)"
}

ETEST_tryrc_rc_only()
{
    $(tryrc echo "foo") 1>stdout.log 2>stderr.log
    local stdout=$(cat stdout.log)
    local stderr=$(cat stderr.log)
    einfo "$(lval rc stdout stderr)"

    assert_eq 0     "${rc}"
    assert_eq "foo" "${stdout}"
    assert_eq ""    "${stderr}"
}

ETEST_tryrc_command_with_no_output()
{
    $(tryrc false)
    assert_ne 0 "${rc}"

    $(tryrc -o=so -e=se false)
    assert_ne 0 "${rc}"
    assert_eq "" "${so}"
    assert_eq "" "${se}"

    $(tryrc true)
    assert_eq 0 "${rc}"
}

ETEST_tryrc_rc_custom()
{
    local rc=1
    $(tryrc -r=myrc echo ${FUNCNAME})

    assert_eq 1 ${rc}
    assert_eq 0 ${myrc}
}

ETEST_tryrc_failure()
{
    $(tryrc -o=stdout eval "echo pre_false; false; echo post_false")
    einfo "$(lval rc stdout)"

    assert_eq 1 "${rc}"
    assert_eq "pre_false" "${stdout}"
}

ETEST_tryrc_no_output()
{
    $(tryrc false) 1>stdout.log 2>stderr.log
    local stdout=$(cat stdout.log)
    local stderr=$(cat stderr.log)
    einfo "$(lval rc stdout stderr)"

    assert_eq 1 "${rc}"
    assert_empty stdout
    assert_empty stderr
}

ETEST_tryrc_stacktrace()
{
    $(tryrc eerror_stacktrace)
    assert_eq 0 ${rc}
}

ETEST_tryrc_multiple_commands()
{
    $(tryrc -o=stdout -e=stderr eval "mkdir -p foo; echo -n 'zap' > foo/file; echo 'done'")
    einfo "$(lval rc stdout stderr)"

    assert_exists foo foo/file
    assert_eq "zap" "$(cat foo/file)"
    assert_eq "done" "${stdout}"
    assert_eq ""     "${stderr}"
}

ETEST_tryrc_deep_error()
{
    $(tryrc -o=stdout etest_deep_error)
    einfo "$(lval rc stdout)"

    assert_eq 1 "${rc}"
    assert_eq "pre_deep_error" "${stdout}"
}

ETEST_tryrc_deep_error_redirect()
{
    $(tryrc etest_deep_error) 1>stdout.log
    local stdout=$(cat stdout.log)
    einfo "$(lval rc stdout)"

    assert_eq 1 ${rc}
    assert_eq "pre_deep_error" "${stdout}"
}

ETEST_tryrc_deep_error_rc_only()
{
    $(tryrc etest_deep_error)
    einfo "$(lval rc)"

    assert_eq 1 ${rc}
}

ETEST_tryrc_multiline_output()
{
    einfo "Generating input"
    printf "line 1\nline 2\nline 3\n" > input.txt
    cat input.txt
    
    $(tryrc -o=stdout -e=stderr cat input.txt)
    einfo "$(lval rc stdout stderr)"

    assert_eq 0 "${rc}"
    assert_eq "$(cat input.txt)" "${stdout}"
    assert_eq "" "${stderr}"
}

ETEST_tryrc_multiline_output_spaces()
{
    einfo "Generating input"
    echo "a    b     c" >  input.txt
    echo "d    e     f" >> input.txt
    cat input.txt

    $(tryrc -o=stdout -e=stderr cat input.txt)
    einfo "$(lval rc stdout stderr)"

    diff --unified <(cat input.txt) <(echo "${stdout}")
    assert_eq 0  "${rc}"
    assert_eq "" "${stderr}"
}

ETEST_tryrc_stderr_unbuffered()
{
    local pids="${FUNCNAME}.pids"
    local pipe="${FUNCNAME}.pipe"
    rm -f ${pipe}
    mkfifo "${pipe}"
    
    # Background parent to start reading from the pipe
    (
        einfo "Reading from ${pipe}"
        local stderr=""
        read -r stderr < ${pipe}
        
        einfo "$(lval stderr)"
        assert_eq "MESSAGE" "${stderr}"
    ) &
    echo "$!" >> "${FUNCNAME}.pids"

    # Background process to write to the pipe. Do this in the background
    # so we can read from the pipe above. This will emit an error message
    # and we'll ensure we see it BEFORE the process completes.
    einfo "Creating background infinite process writing to stderr"
    (
        $(tryrc eval 'echo "MESSAGE" >&2; sleep infinity') &
        echo "$!" >> "${FUNCNAME}.pids"

    ) 2>${pipe}
    echo "$!" >> "${FUNCNAME}.pids"

    wait

    # Kill any background processes that have survived to this point.
    $(tryrc ekilltree -s=SIGKILL $(cat ${FUNCNAME}.pids))
}

ETEST_tryrc_no_eol()
{
    einfo "Generating input"
    echo -n "a" > input.txt
    cat input.txt

    $(tryrc -o=stdout -e=stderr cat input.txt)
    einfo "$(lval rc stdout stderr)"
    declare -p stdout
    declare -p stderr

    diff --unified <(cat input.txt) <(echo -n "${stdout}")
    assert_eq 0  "${rc}"
    assert_eq "" "${stderr}"
}

ETEST_tryrc_multiline_monster_output()
{
    einfo "Generating input"
    dmesg > input.txt
    einfo "Num lines=$(cat input.txt | wc -l)"

    $(tryrc -o=stdout -e=stderr cat input.txt)
    einfo "$(lval rc stderr)"

    diff --unified <(cat input.txt) <(echo "${stdout}")
    assert_eq 0  "${rc}"
    assert_eq "" "${stderr}"
}

ETEST_tryrc_hang_recreate()
{
    $(tryrc eretry -T=.1s sleep 1)
}
