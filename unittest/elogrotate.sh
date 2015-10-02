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

ETEST_elogrotate_count()
{
    touch foo
    elogrotate -c=2 foo
    find . | sort --version-sort
    assert_exists foo foo.1
    assert_not_exists foo.2

    elogrotate -c=2 foo
    find . | sort --version-sort
    assert_exists foo foo.1
    assert_not_exists foo.{2..3}
}

ETEST_elogrotate_size()
{
    eprogress "Creating 1K file"
    dd if=/dev/random of=foo bs=1K count=1
    eprogress_kill

    elogrotate -s=1k foo
    find . | sort --version-sort
    assert_exists foo foo.1
    assert_not_exists foo.2
    assert_false [[ -s foo   ]]
    assert_true  [[ -s foo.1 ]]
}

ETEST_elogrotate_prune()
{
    touch foo foo.{1..20}
    find . | sort --version-sort

    elogrotate -c=3 foo
    assert_exists foo foo.{1..2}
    assert_not_exists foo.{3..20}
}

# Ensure we only delete files matching our prefix exactly with optional numerical suffixes.
ETEST_elogrotate_exact()
{
    touch fooXXX foo. foo foo.{1..20}
    einfo "Before log rotation"
    find . | sort --version-sort

    elogrotate -c=3 foo
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

    elogrotate -c=3 foo
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

    elogrotate -c=3 foo
    einfo "After log rotation"
    find . | sort --version-sort
    assert_exists foo foo.{1..2} bar/foo.{1..10}
    assert_not_exists foo.{3..10}
}

