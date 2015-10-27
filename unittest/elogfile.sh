#!/usr/bin/env bash

ETEST_elogfile()
{
    (
        elogfile ${FUNCNAME}.log
        echo >&1 "stdout"
        echo >&2 "stderr"
    )

    etestmsg "LOG file contents"
    eretry cat ${FUNCNAME}.log
    
    # Ensure both stdout and stderr
    grep -q "stdout" ${FUNCNAME}.log
    grep -q "stderr" ${FUNCNAME}.log
}

# Create a log running process writing to a file then kill it ane ensure it
# properly shuts down.
ETEST_elogfile_term()
{
    (
        die_on_abort
        die_on_error

        elogfile ${FUNCNAME}.log
       
        SECONDS=0
        while true; do
            echo ${SECONDS}
            sleep 1
        done

    ) &>/dev/null &

    local pid=$!

    eprogress "Running background process for 3 seconds"
    sleep 3
    eprogress_kill
    
    etestmsg "Killing backgrounded process"
    ekilltree -s=SIGTERM ${pid}

    eretry -T=30s process_not_running ${pid}
    process_not_running ${pid}

    etestmsg "Showing output"
    eretry -T=30s cat ${FUNCNAME}.log
}

ETEST_elogfile_nostderr()
{
    (
        elogfile -e=0 ${FUNCNAME}.log
        
        echo "stdout" >&1
        echo "stderr" >&2
    )

    etestmsg "Verifying file"
    eretry cat ${FUNCNAME}.log
    assert_eq "stdout" "$(cat ${FUNCNAME}.log)"
}

ETEST_elogfile_nostdout()
{
    (
        elogfile -o=0 ${FUNCNAME}.log
        
        echo "stdout" >&1
        echo "stderr" >&2
    )

    etestmsg "Verifying file"
    eretry cat ${FUNCNAME}.log
    assert_eq "stderr" "$(cat ${FUNCNAME}.log)"
}

ETEST_elogfile_none()
{
    touch ${FUNCNAME}.log

    (
        elogfile -o=0 -e=0 ${FUNCNAME}.log
        
        echo "stdout" >&1
        echo "stderr" >&2
    )

    etestmsg "Verifying file"
    eretry cat ${FUNCNAME}.log
    assert_eq "" "$(cat ${FUNCNAME}.log)"
}

# Test elogfile with logrotation.
ETEST_elogfile_rotate()
{
    touch ${FUNCNAME}.log{,.1,.2,.3,.4,.5,.6}
    assert_exists ${FUNCNAME}.log ${FUNCNAME}.log.{1,2,3,4,5,6}

    (
        elogfile -r=3 ${FUNCNAME}.log
        echo "stdout" >&1
        echo "stderr" >&2
    )

    find . | sort --version-sort
    assert_exists ${FUNCNAME}.log ${FUNCNAME}.log.{1,2}
    assert_not_exists ${FUNCNAME}.log.{3,4,5,6,7}

    etestmsg "LOG file contents"
    eretry cat ${FUNCNAME}.log
    grep -q "stdout" ${FUNCNAME}.log
    grep -q "stderr" ${FUNCNAME}.log
}

# Test elogfile with logrotation.
ETEST_elogfile_rotate_multi()
{
    touch ${FUNCNAME}-{1,2}.log{,.1,.2,.3,.4,.5,.6}
    assert_exists ${FUNCNAME}-{1,2}.log ${FUNCNAME}-{1,2}.log.{1,2,3,4,5,6}

    (
        elogfile -r=3 ${FUNCNAME}-{1,2}.log
        echo "stdout" >&1
        echo "stderr" >&2
    )

    find . | sort --version-sort
    assert_exists ${FUNCNAME}-{1,2}.log ${FUNCNAME}-{1,2}.log.{1,2}
    assert_not_exists ${FUNCNAME}-{1,2}.log.{3,4,5,6,7}

    etestmsg "LOG file contents"
    eretry cat ${FUNCNAME}-{1,2}.log
    grep -q "stdout" ${FUNCNAME}-1.log
    grep -q "stdout" ${FUNCNAME}-2.log
    grep -q "stderr" ${FUNCNAME}-1.log
    grep -q "stderr" ${FUNCNAME}-2.log
}

# Test elogfile when the file has a path component
ETEST_elogfile_path()
{
    local logname="var/log/${FUNCNAME}.log"
    mkdir -p $(dirname ${logname})

    (
        elogfile -r=3 ${logname}

        echo "stdout" >&1
        echo "stderr" >&2
    )

    etestmsg "LOG file contents"
    eretry cat ${logname}
    grep -q "stdout" ${logname}
    grep -q "stderr" ${logname}
}

ETEST_elogfile_truncate()
{
    > ${FUNCNAME}.log
    
    (
        elogfile ${FUNCNAME}.log
        EDEBUG=1 

        echo "/dev/stdout" >/dev/stdout
        echo "/dev/stderr" >/dev/stderr
        echo "/dev/fd/1"   >/dev/fd/1
        echo "/dev/fd/2"   >/dev/fd/2
        echo "edebug_out"  >$(edebug_out)
        echo "&1"          >&1
        echo "&2"          >&2
    )

    for match in "/dev/stdout" "/dev/stderr" "/dev/fd/1" "/dev/fd/2" "edebug_out" "&1" "&2"; do
        grep --quiet "${match}" ${FUNCNAME}.log || die "Logfile was truncated"
    done
}

# Validate efetch doesn't cause log truncate.
ETEST_elogfile_truncate_efetch()
{
    echo "source" >src

    (
        elogfile ${FUNCNAME}.log
        etestmsg "Test"
        efetch file://src dst
    )

    grep --quiet "Test" ${FUNCNAME}.log || die "Logfile was truncated" 
}

# Verify we can send logfile to multiple output files
ETEST_elogfile_multiple()
{
    (
        elogfile ${FUNCNAME}1.log ${FUNCNAME}2.log
        etestmsg "Test"
    )

    for fname in ${FUNCNAME}{1,2}.log; do
        assert_exists ${fname}
        grep --quiet "Test" ${fname}
    done
}

# Verify elogfile doesn't blow up if given no files.
ETEST_elogfile_nofiles()
{
    (
        elogfile
        etestmsg "Test"
    )
}

ETEST_elogfile_multiple_spaces()
{
    local fname1="foo 1.log"
    local fname2="foo 2.log"

    (
        elogfile "${fname1}" "${fname2}"
        etestmsg "Test"
    )

    for fname in "${fname1}" "${fname2}"; do
        assert_exists "${fname}"
        grep --quiet "Test" "${fname}"
    done
}

ETEST_elogfile_devices()
{
    local mlog="${FUNCNAME}.log"

    (
        elogfile -r=1 ${mlog} "/dev/stdout" "/dev/stderr"
        etestmsg "Test"
    )
}

ETEST_elogfile_double_fork()
{
    (
        etestmsg "Ensuring tee processes are not in our process tree"
        elogfile -r=1 ${FUNCNAME}.log
        pstree -p $$
        assert_empty $(pstree -p ${BASHPID} | grep tee)
    )
}

ETEST_elogfile_hang_ekilltree()
{
    EDEBUG=ekill

    local mlog="${FUNCNAME}.log"
    trap_add "ewarn AIEEEEE"

    elogfile -r=1 ${mlog}
    etestmsg "Test"
    pstree -p $$
    ekilltree -s=SIGTERM ${BASHPID}
    ekilltree -s=SIGKILL ${BASHPID}
}

ETEST_elogfile_hang_kill_tee()
{
    (
        EDEBUG=ekill 

        local mlog="${FUNCNAME}.log"
        trap_add "ewarn AIEEEEE"

        elogfile -r=1 ${mlog}
        etestmsg "Test"
        pstree -p $$

        etestmsg "Killing tee processes"
        ekilltree -s=SIGKILL $(pstree -p ${BASHPID} | grep tee | grep -o "([[:digit:]]*)" | grep -o "[[:digit:]]*" || true)
        etestmsg "After killing tee"
        $(tryrc pstree -p ${BASHPID})
    )
}

