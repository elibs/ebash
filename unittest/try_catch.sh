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
            return 0
        }

        die "catch block should have returned"
    ) &

    # Give it a second to get going then kill it
    local pid=$!
    einfo "Waiting for $(lval pid)"
    sleep 1s
    kill -TERM ${pid}
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
# NOTE: There are two outer try/catches in etest before this function is called
# so our starting array should have (1 1)
# [0]="global_teardown; die [UnhandledError]" [1]="exit \$?"
ERR_TRAP_DIE="die [UnhandledError]"
ERR_TRAP_EXIT="__EFUNCS_DIE_ON_ERROR_RC=\$? ; die [ExceptionCaught]; exit \${__EFUNCS_DIE_ON_ERROR_RC}"
ERR_TRAP_TEST="global_teardown; ${ERR_TRAP_DIE}"
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
    assert_stack_eq TEST EXIT

    # Add some more try-catches with various enable/disable
    die_on_error_enabled || die "ERR trap should be enabled"
    nodie_on_error
    ! die_on_error_enabled || die "ERR trap should be disabled"

    try
    {
        die_on_error_enabled || die "ERR trap should be enabled"
        assert_stack_eq TEST EXIT NONE

        try
        {
            die_on_error_enabled || die "ERR trap should be enabled"
            assert_stack_eq TEST EXIT NONE EXIT
           
            try
            {
                die_on_error_enabled || die "ERR trap should be enabled"
                assert_stack_eq TEST EXIT NONE EXIT EXIT
           
                # Disable
                nodie_on_error
                ! die_on_error_enabled || die "ERR trap should be disabled"
                try
                {
                    die_on_error_enabled || die "ERR trap should be enabled"
                    assert_stack_eq TEST EXIT NONE EXIT EXIT NONE
           
                    false
                    die "try block should have thrown"
                }
                catch
                {
                    ! die_on_error_enabled || die "ERR trap should be disabled"
                    assert_stack_eq TEST EXIT NONE EXIT EXIT
                }
                
                ! die_on_error_enabled || die "ERR trap should be disabled"
                assert_stack_eq TEST EXIT NONE EXIT EXIT
                
                false
                true
            }
            catch
            {
                die "try block should not have thrown"
            }
     
            die_on_error_enabled || die "ERR trap should be enabled"
            assert_stack_eq TEST EXIT NONE EXIT
            false
            die "try block should have thrown"
        }
        catch
        {
            assert_stack_eq TEST EXIT NONE
        }
        
        die_on_error_enabled || die "ERR trap should be enabled"
        assert_stack_eq TEST EXIT NONE
        false
        die "try block should have thrown"
    }
    catch
    { 
        assert_stack_eq TEST EXIT
    }
            
    ! die_on_error_enabled || die "ERR trap should be disabled"
    assert_stack_eq TEST EXIT
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
