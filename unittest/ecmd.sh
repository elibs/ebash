
ecmd_quoting_func()
{
    local args
    args=("${@}")
    einfo "$(lval args)"
    assert_eq "a"     "$1"
    assert_eq "b c"   "$2"
    assert_eq "d e f" "$3"

    assert_eq 3 $#
}

ETEST_ecmd_quoting()
{
    ecmd ecmd_quoting_func "a" "b c" "d e f"
}

ecmd_dies_on_failure_func()
{
    return 3
}

ETEST_ecmd_dies_on_failure()
{
    EFUNCS_FATAL=0

    output=$(
        (
            ecmd ecmd_dies_on_failure_func
        ) 2>&1
    )

    assert_eq 1 $?
    assert_true 'echo "$output" | grep -q ecmd_dies_on_failure_func'
}

ETEST_ecmd_try_quoting()
{
    ecmd_try ecmd_quoting_func "a" "b c" "d e f"
}
