TICK_FILE=${TEST_DIR_OUTPUT}/ticks

do_eprogress()
{
    local tick=0
    rm -f ${TICK_FILE}

    while [[ true ]]; do
        echo "${tick}" >> ${TICK_FILE}
        (( tick++ )) || true
        sleep 0.10   || true
    done
}

ETEST_eprogress_ticks()
{
    eprogress "Waiting 1 second"
    sleep 1
    eprogress_kill
    cat ${TICK_FILE}
    [[ $(tail -1 ${TICK_FILE}) -ge 9 ]] || die
}

ETEST_eprogress_ticks_reuse()
{
    eprogress "Waiting for Ubuntu to stop sucking"
    sleep 1
    eprogress_kill
    cat ${TICK_FILE}
    [[ $(tail -1 ${TICK_FILE}) -ge 5 ]] || die
    
    eprogress "Waiting for Gentoo to replace Ubuntu"
    sleep 1
    eprogress_kill
    cat ${TICK_FILE}
    [[ $(tail -1 ${TICK_FILE}) -ge 5 ]] || die
}
