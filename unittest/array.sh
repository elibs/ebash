ETEST_array_empty()
{
    array_set arr "" "\n"
    assert_eq 0 $(array_size arr)
}

ETEST_array_set()
{
    array_set arr "alpha|beta|delta" "|"

    assert_eq "alpha" "${arr[0]}"
    assert_eq "beta"  "${arr[1]}"
    assert_eq "delta" "${arr[2]}"
    assert_eq 3       "${#arr[@]}"
    assert_eq 3       $(array_size arr)
}

ETEST_array_set_nl1()
{
    array_set_nl arr $'a b\nc\td\ne f'

    assert_eq "a b"   "${arr[0]}"
    assert_eq $'c\td' "${arr[1]}"
    assert_eq "e f"   "${arr[2]}"
    assert_eq 3       "${#arr[@]}"
    assert_eq 3       $(array_size arr)
}

ETEST_array_set_nl2()
{
    array_set_nl arr "Foo
Bar"

    edebug $(lval arr)

    assert_eq "Foo" "${arr[0]}"
    assert_eq "Bar" "${arr[1]}"
    assert_eq 2     "${#arr[@]}"
    assert_eq 2     $(array_size arr)
}

ETEST_array_set_multiple_delim()
{
    array_set arr "a1b2c3d4e" "4321"

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq "c" "${arr[2]}"
    assert_eq "d" "${arr[3]}"
    assert_eq "e" "${arr[4]}"
    assert_eq 5   "${#arr[@]}"
    assert_eq 5   $(array_size arr)
}

ETEST_array_set_ulgy_delim()
{
    array_set arr "a(b)c" "()"

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq "c" "${arr[2]}"
    assert_eq 3   "${#arr[@]}"
    assert_eq 3   $(array_size arr)
}

ETEST_array_set_quote_delim()
{
    array_set arr "a'b" "'"

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq 2   "${#arr[@]}"
    assert_eq 2   $(array_size arr)


    array_set arr 'a"b' '"'

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq 2   "${#arr[@]}"
    assert_eq 2   $(array_size arr)
}

ETEST_array_set_default_delim()
{
    # NOTE: Bash splits when the delimiter is whitespace just lump all of the
    # delimiters together and remove them, while splits with non-whitespace
    # generate a field between every two delimiters, even if they're
    # sequential.
    array_set arr $'a\nb\tc d  e'

    declare -p arr

    assert_eq 'a' "${arr[0]}"
    assert_eq 'b' "${arr[1]}"
    assert_eq 'c' "${arr[2]}"
    assert_eq 'd' "${arr[3]}"
    assert_eq 'e' "${arr[4]}"
    assert_eq 5 $(array_size arr)
}

