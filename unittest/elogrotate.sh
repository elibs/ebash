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
