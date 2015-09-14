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

# Test that we can disable tailing the output
ETEST_elogfile_notail()
{
    (
        exec > ${FUNCNAME}_parent.log

        (
            elogfile -t=0 ${FUNCNAME}_child.log
            
            while true; do
                echo "XXX"
                sleep 1
            done

        ) &
    ) &

    sleep 3
    ekilltree $!

    einfo "Parent output"
    cat ${FUNCNAME}_parent.log
    grep "XXX" ${FUNCNAME}_parent.log && die "Child output should NOT have gone to parent.log"

    einfo "Child output"
    cat ${FUNCNAME}_child.log
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

# Validate logfile truncation behavior when using raw /dev/{stdout,stderr}
# Also ensure truncation happens with /dev/fd/{1,2}
ETEST_elogfile_truncation()
{
    ## STDOUT
    einfo "Testing /dev/stdout"
    (
        pstree -p $PPID
        elogfile ${FUNCNAME}.log
        einfo "Test#1: PID=$$ BASHPID=$BASHPID PPID=$PPID"
        echo "" >/dev/stdout
    )
    assert "" $(cat ${FUNCNAME}.log)
    eend

    ## STDERR
    einfo "Testing /dev/stderr"
    (
        elogfile ${FUNCNAME}.log
        einfo "Test#2 $$ $BASHPID"
        echo "" >/dev/stderr
        exit 0
    )
    assert "" $(cat ${FUNCNAME}.log)
    eend

    ##/dev/fd/1
    einfo "testing /dev/fd/1"
    (
        elogfile ${FUNCNAME}.log
        einfo "Test#3 $$ $BASHPID"
        echo "" >/dev/fd/1
        exit 0
    )
    assert "" $(cat ${FUNCNAME}.log)
    eend

    ##/dev/fd/2
    einfo "Testing /dev/fd/2"
    (
        elogfile ${FUNCNAME}.log
        einfo "Test#4 $$ $BASHPID"
        echo "" >/dev/fd/2
        exit 0
    )
    assert "" $(cat ${FUNCNAME}.log)
    eend

    # Need to sleep for a second to give tail a chance to notice subprocess exit and shutdown properly
    sleep 1
}

# Validate logfiles are not truncated when using bash symbolic &1 and &2
ETEST_elogfile_truncation_symbolic()
{
    ## &1
    einfo "Testing &1"
    (
        elogfile ${FUNCNAME}.log
        einfo "Test#1"
        echo "" >&1
    )
    grep --quiet "Test#1" ${FUNCNAME}.log || die "Logfile was truncated"
    eend

    ## &2
    einfo "Testing &2"
    (
        elogfile ${FUNCNAME}.log
        einfo "Test#2"
        echo "" >&2
    )
    grep --quiet "Test#1" ${FUNCNAME}.log || die "Logfile was truncated"
    grep --quiet "Test#2" ${FUNCNAME}.log || die "Logfile was truncated"
    eend

    # Need to sleep for a second to give tail a chance to notice subprocess exit and shutdown properly
    sleep 1
}
