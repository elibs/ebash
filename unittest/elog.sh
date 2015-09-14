#!/usr/bin/env bash

ETEST_elogrotate()
{
    touch foo

    elogrotate foo
    assert_exists foo foo.1
    assert_not_exists foo.2

    elogrotate foo
    assert_exists foo foo.{1..2}
    assert_not_exists foo.3

    elogrotate foo
    assert_exists foo foo.{1..3}
    assert_not_exists foo.4

    elogrotate foo
    assert_exists foo foo.{1..4}
    assert_not_exists foo.5
}

ETEST_elogrotate_custom()
{
    touch foo
    elogrotate -m=2 foo
    find . | sort --version-sort
    assert_exists foo foo.1
    assert_not_exists foo.2

    elogrotate -m=2 foo
    find . | sort --version-sort
    assert_exists foo foo.1
    assert_not_exists foo.{2..3}
}

ETEST_elogrotate_prune()
{
    touch foo foo.{1..20}
    find . | sort --version-sort

    elogrotate -m=3 foo
    assert_exists foo foo.{1..2}
    assert_not_exists foo.{3..20}
}

# Ensure we only delete files matching our prefix exactly with optional numerical suffixes.
ETEST_elogrotate_exact()
{
    touch fooXXX foo. foo foo.{1..20}
    einfo "Before log rotation"
    find . | sort --version-sort

    elogrotate -m=3 foo
    einfo "After log rotation"
    find . | sort --version-sort
    assert_exists fooXXX foo. foo foo.{1..2}
    assert_not_exists foo.{3..20}
}

# Ensure we don't try to delete directories
ETEST_elogrotate_nodir()
{
    touch fooXXX foo foo.{1..20}
    mkdir foo.21
    einfo "Before log rotation"
    find . | sort --version-sort

    elogrotate -m=3 foo
    einfo "After log rotation"
    find . | sort --version-sort
    assert_exists fooXXX foo foo.{1..2} foo.21
    assert_not_exists foo.{3..20}
}

# Ensure no recursion when deleting
ETEST_elogrotate_norecursion()
{
    mkdir bar
    touch foo foo.{1..10} bar/foo.{1..10}
    einfo "Before log rotation"
    find . | sort --version-sort

    elogrotate -m=3 foo
    einfo "After log rotation"
    find . | sort --version-sort
    assert_exists foo foo.{1..2} bar/foo.{1..10}
    assert_not_exists foo.{3..10}
}

ETEST_elogfile()
{
    (
        elogfile ${FUNCNAME}.log
        echo >&1 "stdout"
        echo >&2 "stderr"
    )

    einfo "LOG file contents"
    cat ${FUNCNAME}.log
    assert_eq "stdout"$'\n'"stderr" "$(cat ${FUNCNAME}.log)"
}

# Create a log running process writing to a file then kill it ane ensure it
# properly shuts down.
ETEST_elogfile_term()
{
    (
        elogfile ${FUNCNAME}.log
        
        while true; do
            echo ${SECONDS}
            sleep 1
        done

    ) &

    local pid=$!

    eprogress "Running background process for 3 seconds"
    sleep 3
    ekill ${pid}
    eprogress_kill
    assert_false process_running ${pid}

    einfo "Showing output"
    cat ${FUNCNAME}.log
}

ETEST_elogfile_nostderr()
{
    (
        elogfile -e=0 ${FUNCNAME}.log
        
        echo "stdout" >&1
        echo "stderr" >&2
    )

    einfo "Verifying file"
    cat ${FUNCNAME}.log
    assert_eq "stdout" "$(cat ${FUNCNAME}.log)"
}

ETEST_elogfile_nostdout()
{
    (
        elogfile -o=0 ${FUNCNAME}.log
        
        echo "stdout" >&1
        echo "stderr" >&2
    )

    einfo "Verifying file"
    cat ${FUNCNAME}.log
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

    einfo "Verifying file"
    cat ${FUNCNAME}.log
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

    ls -l1 --sort=version ${FUNCNAME}.log*
    assert_exists ${FUNCNAME}.log ${FUNCNAME}.log.{1,2}
    assert_not_exists ${FUNCNAME}.log.{3,4,5,6,7}

    einfo "LOG file contents"
    cat ${FUNCNAME}.log
    assert_eq "stdout"$'\n'"stderr" "$(cat ${FUNCNAME}.log)"
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

    einfo "LOG file contents"
    cat ${logname}
    assert_eq "stdout"$'\n'"stderr" "$(cat ${logname})"
}

ETEST_elogfile_truncation()
{
    > ${FUNCNAME}.log
    
    (
        elogfile ${FUNCNAME}.log
        
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

# Validate efetch doesn't cause log truncation.
ETEST_elogfile_truncation_efetch()
{
    echo "source" >src

    (
        elogfile ${FUNCNAME}.log
        einfo "Test"
        efetch file://src dst
    )

    grep --quiet "Test" ${FUNCNAME}.log || die "Logfile was truncated" 
}
