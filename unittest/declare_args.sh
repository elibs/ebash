ETEST_DECLARE_ARGS_OPTIONAL=1

do_declare_args()
{
    local args=( ${1:-} ); shift || true
    local vals=( "${@}" )
    einfo "$(lval args vals)"
    $(declare_args ${args[@]:-})
    
    # declare_args should be consuming positional arguments
    # This assumes none of the unit tests are passing more than
    # ten arguments into this helper method.
    assert_eq 0 ${#@}

    [[ $(array_size args) -eq 0 ]] && return 

    local arg val idx
    for (( idx=0; idx <= ${#args}; idx++ )); do
        arg=${args[$idx]}; arg=${arg#\?}
        val=${vals[$idx]}
        einfo "$(lval idx arg val)"
        
        [[ ${arg} == "_" ]] && continue
        
        eval "assert_eq \"${val}\" \"\$${arg}\""
    done
}

# Ensure if we failed to pass in all the required arguments that declare_args 
# properly dies. To avoid the test from dying we put it in a subshell and also
# set EFUNCS_FATAL to 0. We overide our global setting of making all args optional
# so that our helper method will not prefix each argument with a '?'
ETEST_declare_args_fatal()
{
    try
    {
        ETEST_DECLARE_ARGS_OPTIONAL=0 do_declare_args "a1"
    
        # Should never get here!
        die "declare_args should have thrown an error due to missing arguments"
    }
    catch
    {
        return 0
    }

    die "should have returned"
}

ETEST_declare_args_basic()
{
    do_declare_args "a1 a2 a3" 1 2 3
    do_declare_args "a1 a2 a3 a4" aristotle kant hobbes rosseau
}

ETEST_declare_args_whitespace()
{
    do_declare_args "a1 a2 a3" "arg1 with spaces" "arg2 prefers Gentoo 2-1!" "arg3 is an stubuntu lover"
}

ETEST_declare_args_noargs()
{
    do_declare_args
}

ETEST_declare_args_optional_args()
{
    do_declare_args "a1 ?a2 a3" apples "" coffee
}

# Verify if we pass in a variable name of _ that it drops it on the floor
# ignoring anything in that position.
ETEST_declare_args_anonymous()
{
    do_declare_args "a1 _ a3" apples foobar pillows
}

ETEST_declare_args_global()
{
    $(declare_args -g ?V1)
    V1="VAR1"

    assert_eq 'declare -- V1="VAR1"' "$(declare -p V1)"
}

# Verify if we declare a GLOBAL EXPORTED variable it can be seen in a external process
ETEST_declare_args_export()
{
    $(declare_args -g ?V1)
    $(declare_args -e ?V2)
    V1="VAR1"
    V2="VAR2"

    assert_eq 'declare -- V1="VAR1"' "$(declare -p V1)"
    assert_eq 'declare -x V2="VAR2"' "$(declare -p V2)"
}

do_declare_args_legacy()
{
    local args=( ${1} ); shift
    local vals=( "${@}" )
    einfo "$(lval args vals)"
    eval $(declare_args ${args[@]})
    
    # declare_args should be consuming positional arguments
    # This assumes none of the unit tests are passing more than
    # ten arguments into this helper method.
    assert_eq 0 ${#@}

    [[ ${#args} -eq 0 ]] && return

    local arg val idx
    for (( idx=0; idx <= ${#args}; idx++ )); do
        arg=${args[$idx]}; arg=${arg#\?}
        val=${vals[$idx]}
        einfo "$(lval idx arg val)"
        
        [[ ${arg} == "_" ]] && continue
        
        eval "assert_eq \"${val}\" \"\$${arg}\""
    done
}

# Verify if legacy code calls eval $(declare_args ...) it still does the right thing
ETEST_declare_args_legacy()
{
    do_declare_args_legacy "a1 a2 a3" 1 2 3
    do_declare_args_legacy "a1 a2 a3 a4" aristotle kant hobbes rosseau
}
