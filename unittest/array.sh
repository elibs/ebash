#!/usr/bin/env bash

ETEST_array_size_empty_and_undefined()
{
    declare -a empty_array
    declare -A empty_aa

    assert_eq 0 $(array_size empty_array)
    assert_eq 0 $(array_size empty_aa)

    empty_string=""
    assert array_empty empty_string
    assert_false array_not_empty empty_string

    unset C
    assert_eq 0 $(array_size C)
}

ETEST_array_that_is_holey()
{
    A=(1 2 3 4)
    unset A[0]
    unset A[2]

    assert_false array_empty A
}

ETEST_array_size_zero()
{
    # NOTE: there is no distinction in bash between empty arrays and unset
    # variables.  Really.
    V=()

    size=$(array_size V)
    [[ ${size} -eq 0 ]] || die "Size was wrong $(lval size)"
}

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

ETEST_array_init_json()
{
    array_init_json arr '[ "Immanual Kant", "Thomas Hobbes", "John Locke" ]'
    declare -p arr
    assert_eq 3 $(array_size arr)

    assert_eq "Immanual Kant" "${arr[0]}"
    assert_eq "Thomas Hobbes" "${arr[1]}"
    assert_eq "John Locke"    "${arr[2]}"
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
    array_init arr "a%b c%d"
    declare -p arr

    assert_true array_contains arr "a%b"
    assert_true array_contains arr "c%d"
    assert_eq 2 $(array_size arr)

    # Append more elements with a different delimiter contained in existing elements
    array_add arr 'e%f' '%'
    declare -p arr

    assert_true array_contains arr "a%b"
    assert_true array_contains arr "c%d"
    assert_true array_contains arr "e"
    assert_true array_contains arr "f"
    assert_eq 4 $(array_size arr)
}

ETEST_array_join()
{
    local input="a b c d" output=""
    array_init arr "${input}"
    declare -p arr

    output=$(array_join arr)
    assert_eq "${input}" "${output}"
}

ETEST_array_join_nl()
{
    local input=$'a\nb\tc d  e' output=""
    array_init_nl arr "${input}"
    declare -p arr

    output=$(array_join_nl arr)
    assert_eq "${input}" "${output}"
}

ETEST_array_join_custom()
{
    local input="a b|c d|e f" output=""
    array_init arr "${input}" "|"
    declare -p arr

    output=$(array_join arr "|")
    assert_eq "${input}" "${output}"
}

ETEST_array_remove()
{
    local input="a b c d"
    array_init array "${input}"
    declare -p array

    array_remove array b
    assert_eq "a c d" "$(array_join array)"
}

ETEST_array_remove_all()
{
    local input="a b a c a d a e"
    array_init array "${input}"
    declare -p array

    etestmsg "Removing all a(s)"
    array_remove -a array a
    declare -p array

    assert_eq "b c d e" "$(array_join array)"
}

ETEST_array_remove_multiple_all()
{
    local input="1 2 3 4 1 2 3 4"
    array_init array "${input}"
    declare -p array

    array_remove -a array 1 3
    assert_eq "2 4 2 4" "$(array_join array)"
}

ETEST_array_remove_whitespace()
{
    local input=$'a\nb\nc d  e'
    array_init_nl array "${input}"
    declare -p array

    array_remove array "c d  e"
    assert_eq $'a\nb' "$(array_join_nl array)"
}

ETEST_array_sort()
{
    array=(a c b "f f" 3 5)
    array_sort array
    assert_eq "3|5|a|b|c|f f" "$(array_join array '|')"
}

ETEST_array_sort_unique()
{
    array=(a c b a)
    array_sort -u array
    assert_eq "a|b|c" "$(array_join array '|')"
}

ETEST_array_sort_version()
{
    local array=(a.1 a.2 a.100)
    array_sort -V array
    assert_eq "a.1|a.2|a.100" "$(array_join array '|')"
}

ETEST_array_sort_rtfi()
{
    local keep_paths=( "/sf/etc/origin.json" "bar" "foo" )
    array_sort -u keep_paths
    export SF_KEEP_PATHS="${keep_paths[@]}"
    assert_eq "bar foo /sf/etc/origin.json" "${SF_KEEP_PATHS}"
}

