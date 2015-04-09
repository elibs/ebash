ETEST_array_empty()
{
    array_init arr "" "\n"
    declare -p arr

    assert_eq 0 $(array_size arr)
}

ETEST_array_empty_reuse()
{
    array_init arr "alpha|beta|delta" "|"
    declare -p arr
    assert_eq 3 $(array_size arr)

    array_init arr ""
    declare -p arr
    assert_eq 0 $(array_size arr)
}

ETEST_array_init()
{
    array_init arr "alpha|beta|delta" "|"
    declare -p arr

    assert_eq "alpha" "${arr[0]}"
    assert_eq "beta"  "${arr[1]}"
    assert_eq "delta" "${arr[2]}"
    assert_eq 3       "${#arr[@]}"
    assert_eq 3       $(array_size arr)
}

ETEST_array_init_nl1()
{
    array_init_nl arr $'a b\nc\td\ne f'
    declare -p arr

    assert_eq "a b"   "${arr[0]}"
    assert_eq $'c\td' "${arr[1]}"
    assert_eq "e f"   "${arr[2]}"
    assert_eq 3       "${#arr[@]}"
    assert_eq 3       $(array_size arr)
}

ETEST_array_init_nl2()
{
    array_init_nl arr "Foo
Bar"
    declare -p arr

    assert_eq "Foo" "${arr[0]}"
    assert_eq "Bar" "${arr[1]}"
    assert_eq 2     "${#arr[@]}"
    assert_eq 2     $(array_size arr)
}

ETEST_array_init_multiple_delim()
{
    array_init arr "a1b2c3d4e" "4321"
    declare -p arr

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq "c" "${arr[2]}"
    assert_eq "d" "${arr[3]}"
    assert_eq "e" "${arr[4]}"
    assert_eq 5   "${#arr[@]}"
    assert_eq 5   $(array_size arr)
}

ETEST_array_init_ulgy_delim()
{
    array_init arr "a(b)c" "()"
    declare -p arr

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq "c" "${arr[2]}"
    assert_eq 3   "${#arr[@]}"
    assert_eq 3   $(array_size arr)
}

ETEST_array_init_quote_delim()
{
    array_init arr "a'b" "'"
    declare -p arr

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq 2   "${#arr[@]}"
    assert_eq 2   $(array_size arr)

    array_init arr 'a"b' '"'
    declare -p arr

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq 2   "${#arr[@]}"
    assert_eq 2   $(array_size arr)
}

ETEST_array_init_default_delim()
{
    # NOTE: Bash splits when the delimiter is whitespace just lump all of the
    # delimiters together and remove them, while splits with non-whitespace
    # generate a field between every two delimiters, even if they're
    # sequential.
    array_init arr $'a\nb\tc d  e'
    declare -p arr

    assert_eq "a" "${arr[0]}"
    assert_eq "b" "${arr[1]}"
    assert_eq "c" "${arr[2]}"
    assert_eq "d" "${arr[3]}"
    assert_eq "e" "${arr[4]}"
    assert_eq 5   $(array_size arr)
}

ETEST_array_contains()
{
    array_init arr "a b c d"
    declare -p arr

    assert_true  array_contains arr "a"
    assert_true  array_contains arr "b"
    assert_true  array_contains arr "c"
    assert_true  array_contains arr "d"
    assert_false array_contains arr "e"
}

ETEST_array_add()
{
    array_init arr "a b c d"
    declare -p arr

    assert_true  array_contains arr "a"
    assert_true  array_contains arr "b"
    assert_true  array_contains arr "c"
    assert_true  array_contains arr "d"
    assert_false array_contains arr "e"
    assert_eq 4  $(array_size arr)

    # Add another element
    array_add arr "e"

    assert_true  array_contains arr "a"
    assert_true  array_contains arr "b"
    assert_true  array_contains arr "c"
    assert_true  array_contains arr "d"
    assert_true  array_contains arr "e"
    assert_eq 5  $(array_size arr)
}

ETEST_array_add_nl()
{
    array_init_nl arr $'a\nb\nc\nd'
    declare -p arr

    assert_true  array_contains arr "a"
    assert_true  array_contains arr "b"
    assert_true  array_contains arr "c"
    assert_true  array_contains arr "d"
    assert_false array_contains arr "e"
    assert_eq 4  $(array_size arr)

    # Add another element
    array_add_nl arr "e"
    declare -p arr

    assert_true  array_contains arr "a"
    assert_true  array_contains arr "b"
    assert_true  array_contains arr "c"
    assert_true  array_contains arr "d"
    assert_true  array_contains arr "e"
    assert_eq 5  $(array_size arr)

    # Add multiple elements
    array_add_nl arr $'f\ng'
    declare -p arr

    assert_true  array_contains arr "a"
    assert_true  array_contains arr "b"
    assert_true  array_contains arr "c"
    assert_true  array_contains arr "d"
    assert_true  array_contains arr "e"
    assert_true  array_contains arr "f"
    assert_true  array_contains arr "g"
    assert_eq 7  $(array_size arr)
}

ETEST_array_add_different_delim()
{
    array_init arr "a b"
    declare -p arr

    assert_true array_contains arr "a"
    assert_true array_contains arr "b"
    assert_eq 2 $(array_size arr)

    # Append a couple more elements with different delimiter
    array_add_nl arr $'c\nd'
    declare -p arr

    assert_true array_contains arr "a"
    assert_true array_contains arr "b"
    assert_true array_contains arr "c"
    assert_true array_contains arr "d"
    assert_eq 4 $(array_size arr)
}

ETEST_array_add_different_delim_noresplit()
{
    array_init arr "a|b c|d"
    declare -p arr

    assert_true array_contains arr "a|b"
    assert_true array_contains arr "c|d"
    assert_eq 2 $(array_size arr)

    # Append more elements with a different delimiter contained in existing elements
    array_add arr 'e|f' '|'
    declare -p arr

    assert_true array_contains arr "a|b"
    assert_true array_contains arr "c|d"
    assert_true array_contains arr "e"
    assert_true array_contains arr "f"
    assert_eq 4 $(array_size arr)
}
