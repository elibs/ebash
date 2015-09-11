#!/usr/bin/env bash

assert_exists()
{
    for name in $@; do
        einfo "Exists: ${name}"
        [[ -e ${name} ]] || die "${name} is missing"
        eend
    done
}

assert_not_exists()
{
    for name in $@; do
        einfo "NotExists: ${name}"
        [[ ! -e ${name} ]] || die "${name} exists but should not"
        eend
    done
}

ETEST_logrorate()
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

ETEST_logrotate_custom()
{
    touch foo
    elogrotate -m=2 foo
    assert_exists foo foo.1
    assert_not_exists foo.2

    elogrotate -m=2 foo
    assert_exists foo foo.1
    assert_not_exists foo.{2..3}
}

ETEST_logrotate_prune()
{
    touch foo
    touch foo.{1..20}
    ls foo* | sort --version-sort

    elogrotate -m=3 foo
    assert_exists foo foo.{1..2}
    assert_not_exists foo.{3..20}
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
