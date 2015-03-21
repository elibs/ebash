ETEST_DECLARE_ARGS_OPTIONAL=1

do_declare_args()
{
    local args=( ${1} ); shift
    local vals=( "${@}" )
    edebug "$(lval args vals)"
    $(declare_args ${args[@]})
    
    # declare_args should be consuming positional arguments
    # This assumes none of the unit tests are passing more than
    # ten arguments into this helper method.
    expect_eq 0 ${#@}

    [[ ${#args} -eq 0 ]] && return 0

    local arg val idx
    for (( idx=0; idx <= ${#args}; idx++ )); do
        arg=${args[$idx]}; arg=${arg#\?}
        val=${vals[$idx]}
        edebug "$(lval idx arg val)"
        
        [[ ${arg} == "_" ]] && continue
        
        eval "expect_eq \"${val}\" \"\$${arg}\""
    done
}

# Ensure if we failed to pass in all the required arguments that declare_args 
# properly dies. To avoid the test from dying we put it in a subshell and also
# set EFUNCS_FATAL to 0. We overide our global setting of making all args optional
# so that our helper method will not prefix each argument with a '?'
ETEST_declare_args_fatal()
{
    ( EFUNCS_FATAL=0 ETEST_DECLARE_ARGS_OPTIONAL=0 do_declare_args "a1"; ) &>/dev/null
    expect_not_zero $?
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

# Verify if we declare a GLOBAL variable in one function we can see it in another.
do_declare_global()
{
    $(declare_globals ?G1)
    G1="GLOBAL1"
}

ETEST_declare_args_global()
{
    do_declare_global
    expect_eq "GLOBAL1" ${G1}
}

do_declare_export()
{
    $(declare_exports ?G2)
    G2="GLOBAL2"
}

# Verify if we declare a GLOBAL EXPORTED variable it can be seen in a external process
ETEST_declare_args_export()
{
    local file="declare_args_export.sh"
    echo "[[ -z \${G1} ]] || { echo 'G1=[\${G1}] should not be exported'; exit 1; }" >  ${file}
    echo "[[ -n \${G2} ]] || { echo 'G2=[\${G2}] should be exported';     exit 2; }" >> ${file}
    echmod +x ${file}
    edebug "$(cat ${file})"

    do_declare_global
    do_declare_export
    ./${file}
}

do_declare_args_legacy()
{
    local args=( ${1} ); shift
    local vals=( "${@}" )
    edebug "$(lval args vals)"
    eval $(declare_args ${args[@]})
    
    # declare_args should be consuming positional arguments
    # This assumes none of the unit tests are passing more than
    # ten arguments into this helper method.
    expect_eq 0 ${#@}

    [[ ${#args} -eq 0 ]] && return 0

    local arg val idx
    for (( idx=0; idx <= ${#args}; idx++ )); do
        arg=${args[$idx]}; arg=${arg#\?}
        val=${vals[$idx]}
        edebug "$(lval idx arg val)"
        
        [[ ${arg} == "_" ]] && continue
        
        eval "expect_eq \"${val}\" \"\$${arg}\""
    done
}

# Verify if legacy code calls eval $(declare_args ...) it still does the right thing
ETEST_declare_args_legacy()
{
    do_declare_args_legacy "a1 a2 a3" 1 2 3
    do_declare_args_legacy "a1 a2 a3 a4" aristotle kant hobbes rosseau
}
