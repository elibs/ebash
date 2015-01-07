ETEST_setvars_basic()
{
    local file="setvars_basic.txt"
    local name="Immanual Kant"
    echo "name=[__name__]" > "${file}"
    trap_add "erm ${file}" EXIT

    setvars "${file}"
    expect_eq "name=[${name}]" "$(cat ${file})"
}

ETEST_setvars_multi()
{
    local file="setvars_multi"
    local arg1="Foo"
    local arg2="Bar"
    echo "__arg1__ __arg2__" > "${file}"
    trap_add "erm ${file}" EXIT

    setvars "${file}"
    expect_eq "${arg1} ${arg2}" "$(cat ${file})"
}

# Test when variables are not fully expanded that setvars fails.
ETEST_setvars_error()
{
    local file="setvars_multi"
    local arg1="Foo"
    echo "__arg1__ __arg2__" > "${file}"
    trap_add "erm ${file}" EXIT

    expect_false SETVARS_FATAL=0 SETVARS_WARN=0 setvars "${file}"
}

