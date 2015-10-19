#!/usr/bin/env bash

ETEST_stacktrace()
{
    local stack=()
    array_init_nl stack "$(stacktrace)"
    einfo "$(lval stack)"

    assert_eq 4 $(array_size stack)
    assert_eq "ETEST_stacktrace"       "$(echo "${stack[0]}" | awk '{print $2}')"
    assert_eq "run_single_test"        "$(echo "${stack[1]}" | awk '{print $2}')"
    assert_eq "run_all_tests_in_file"  "$(echo "${stack[2]}" | awk '{print $2}')"
    assert_eq "main"                   "$(echo "${stack[3]}" | awk '{print $2}')"
}

# Same as above but start at a specified frame number
ETEST_stacktrace_frame()
{
    local stack=()
    array_init_nl stack "$(stacktrace -f=1)"
    einfo "$(lval stack)"

    assert_eq 3      "$(array_size stack)"
    assert_eq "run_single_test" "$(echo "${stack[0]}" | awk '{print $2}')"
}

# Test stacktrace_array which populates an array with a stacktrace.
ETEST_stacktrace_array()
{
    local stack=()
    stacktrace_array stack
    einfo "$(lval stack)"

    assert_eq 4 $(array_size stack)
    assert_eq "ETEST_stacktrace_array" "$(echo "${stack[0]}" | awk '{print $2}')"
    assert_eq "run_single_test"        "$(echo "${stack[1]}" | awk '{print $2}')"
    assert_eq "run_all_tests_in_file"  "$(echo "${stack[2]}" | awk '{print $2}')"
    assert_eq "main"                   "$(echo "${stack[3]}" | awk '{print $2}')"
}

# Test eerror_stacktrace
ETEST_stacktrace_error()
{
    local stack=()
    array_init_nl stack "$(EFUNCS_COLOR=0 eerror_stacktrace 'Boo' 2>&1)"
    einfo "$(lval stack)"

    assert_eq 5 $(array_size stack)
    assert_eq ">> Boo"                 "$(echo "${stack[0]}")"
    assert_eq "ETEST_stacktrace_error" "$(echo "${stack[1]}" | awk '{print $4}')"
    assert_eq "run_single_test"        "$(echo "${stack[2]}" | awk '{print $4}')"
    assert_eq "run_all_tests_in_file"  "$(echo "${stack[3]}" | awk '{print $4}')"
    assert_eq "main"                   "$(echo "${stack[4]}" | awk '{print $4}')"
}
