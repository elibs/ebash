#!/usr/bin/env bash

TICK_FILE=${TEST_DIR_OUTPUT}/ticks

# Fake EPROGRESS function body to use in some of the tests which
# don't want the real do_eprogress
FAKE_DO_EPROGRESS='
{
    local tick=0
    rm -f ${TICK_FILE}

    while [[ true ]]; do
        echo "${tick}" >> ${TICK_FILE}
        (( tick++ )) || true
        sleep 0.10   || true
    done
}
'

ETEST_eprogress_ticks()
{
    override_function do_eprogress "${FAKE_DO_EPROGRESS}"

    eprogress "Waiting 1 second"
    sleep 1
    eprogress_kill
    cat ${TICK_FILE}
    assert [[ $(tail -1 ${TICK_FILE}) -ge 9 ]]
}

ETEST_eprogress_ticks_reuse()
{
    override_function do_eprogress "${FAKE_DO_EPROGRESS}"

    eprogress "Waiting for Ubuntu to stop sucking"
    sleep 1
    eprogress_kill
    cat ${TICK_FILE}
    assert [[ $(tail -1 ${TICK_FILE}) -ge 5 ]]
    
    eprogress "Waiting for Gentoo to replace Ubuntu"
    sleep 1
    eprogress_kill
    cat ${TICK_FILE}
    assert [[ $(tail -1 ${TICK_FILE}) -ge 5 ]]
}

# Verify EPROGRESS_TICKER can be used to forcibly enable/disable ticker
ETEST_eprogress_ticker_off()
{
    (
        exec &> >(tee eprogress.out)

        COLUMNS=28
        EFUNCS_COLOR=0
        EDEBUG=0
        ETRACE=0
        EINTERACTIVE=0
        eprogress "Waiting"
        eprogress_kill

    )

    assert_eq ">> Waiting.[ ok ]" "$(cat eprogress.out)"
}

ETEST_eprogress_ticker_on()
{
    (
        exec &> >(tee eprogress.out)

        COLUMNS=28
        EFUNCS_COLOR=0
        EDEBUG=0
        ETRACE=0
        EINTERACTIVE=1
        eprogress "Waiting"
        eprogress_kill

    )

    assert_eq ">> Waiting [00:00:00]  ^H/^H-^H\^H|^H/^H-^H\^H|^H \$"$'\n'"^[M^[[22C[ ok ]\$" "$(cat -evt eprogress.out)"
}

ETEST_eprogress_inside_eretry()
{
    override_function do_eprogress "${FAKE_DO_EPROGRESS}"

    etestmsg "Starting eprogress"
    eprogress "Waiting for eretry"
    $(tryrc eretry -T=1s false)
    eprogress_kill

    etestmsg "Showing tickfile"
    cat ${TICK_FILE}
    assert [[ $(tail -1 ${TICK_FILE}) -ge 9 ]]
}

ETEST_eprogress_kill_before_eprogress()
{
    eprogress_kill
}
