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
    nodie_on_error
    false
    return 0
}

# Verify nodie_on_error is not needed inside a subshell
# since ERR trap is not inherited by subshells.
ETEST_nodie_inside_subshell()
{
    ( false )
    return 0
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
