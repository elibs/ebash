#!/usr/bin/env bash

ETEST_edebug_one_and_zero()
{
    EDEBUG=1 edebug_enabled || die "edebug should be enabled"
    EDEBUG=0 edebug_enabled && die "edebug should not be enabled" || true
}

ETEST_edebug_enabled_matcher()
{
    EDEBUG="${FUNCNAME}"                edebug_enabled
    EDEBUG="edebug"                     edebug_enabled
    EDEBUG="something else entirely"    edebug_disabled
    EDEBUG="else and edebug"            edebug_enabled
    EDEBUG=""                           edebug_disabled
}

ETEST_edebug_and_etrace()
{
    EDEBUG=""            ETRACE="${FUNCNAME}"   edebug_enabled
    EDEBUG="${FUNCNAME}" ETRACE=""              edebug_enabled
    EDEBUG="${FUNCNAME}" ETRACE=0               edebug_enabled
    EDEBUG=1             ETRACE=""              edebug_enabled
    EDEBUG=1             ETRACE=0               edebug_enabled
    EDEBUG=""            ETRACE=1               edebug_enabled
    EDEBUG=0             ETRACE=1               edebug_enabled

    EDEBUG=""            ETRACE=""              edebug_disabled
    EDEBUG=0             ETRACE=0               edebug_disabled
    EDEBUG="NOT"         ETRACE="HERE"          edebug_disabled
}

ETEST_edebug_enabled_skips_edebug_in_stack_frame()
{
    local output=$(EDEBUG=${FUNCNAME}; edebug "hello" 2>&1)
    assert_like "${output}" "hello"
}

ETEST_edebug_pipe_input()
{
    local output=$(EDEBUG=${FUNCNAME}; echo "foo" | edebug 2>&1)
    assert_like "${output}" "foo"
}

ETEST_edebug_pipe_empty()
{
    local output=$(EDEBUG=${FUNCNAME}; true | edebug 2>&1)
    assert_empty "${output}"
}

ETEST_edebug_pipe_multiple_lines()
{
    local input="$(dmesg)"
    local output=$(EFUNCS_COLOR=0; EDEBUG=${FUNCNAME}; echo -en "${input}" | edebug 2>&1 | sed "s|\[$(basename ${BASH_SOURCE[0]}):${LINENO}:${FUNCNAME}\] ||")
    diff --unified <(echo -en "${input}") <(echo -en "${output}")
}

ETEST_edebug_pipe_return_code()
{
    try
    {
        false |& edebug
        throw 100
    }
    catch
    {
        [[ $? -eq 100 ]] && die "edebug suppressed a failure"
        return 0
    }

    die "Test should have thrown or returned"
}
