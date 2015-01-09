
ETEST_argcheck()
{
    EFUNCS_FATAL=0

    alpha="notempty"
    output=$(
        ( 
            argcheck alpha beta 2>&1
            expect_true false
        )
    )

    expect_not_zero $?
    expect_true  'echo "$output" | grep -q beta'
    expect_false 'echo "$output" | grep -q alpha'
}
