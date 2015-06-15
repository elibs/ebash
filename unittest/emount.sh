ETEST_emount_bind()
{
    mkdir src
    touch src/file
    echo "Love" > src/file

    # Bind mount and verify mounted and verify content
    mkdir dst
    ebindmount src dst
    assert_true emounted dst
    assert_true diff src/file dst/file
}

ETEST_emount_unmount()
{
    # Bind mount src to dst
    mkdir src dst
    ebindmount src dst

    # Verify mounted, unmount, then verify unmounted
    assert_true  emounted dst
    assert_false emounted src
}

ETEST_emount_unmount_recursive()
{
    # Bind mount a couple of nested directories
    mkdir -p src1 src2 dst/dst1 dst/dst2
    ebindmount  src1 dst/dst1
    ebindmount  src2 dst/dst2

    # Verify state
    assert_false emounted dst
    assert_true  emounted dst/dst1
    assert_true  emounted dst/dst2

    # Recursive unmount using top-level directory structure even though it isn't mounted
    eunmount_recursive dst
    assert_false emounted dst/dst1
    assert_false emounted dst/dst2
}

ETEST_emount_partial_match()
{
    # Bind mount a couple of nested directories
    mkdir -p src1 src2 dst/dst1 dst/dst2
    ebindmount src1 dst/dst1
    ebindmount src2 dst/dst2

    # Verify state
    assert_false emounted dst
    assert_true  emounted dst/dst1
    assert_true  emounted dst/dst2

    # Use a partial match -- should NOT find any mounts
    assert_false emounted dst/d
}

check_mounts()
{
    $(declare_args path count)

    [[ ${count} -eq 0 ]] && assert_false emounted ${path} || assert_true emounted ${path}
    assert_eq ${count} $(emount_count ${path})
}

ETEST_emount_bind_count_separate()
{
    mkdir src

    # Mount a few times and ensure counter goes up correctly
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        mkdir dst${i}
        emount --bind src dst${i}
        check_mounts dst${i} 1
    done

    # Umount and verify counts go down properly
    for (( i=${nmounts}-1; i>=0; --i )); do
        eunmount dst${i}
        check_mounts dst${i} 0
    done
}

ETEST_emount_bind_count_shared()
{
    mkdir src dst

    # Mount a few times and ensure counter goes up correctly
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        emount --bind src dst
        emount --make-private dst
        check_mounts dst $((i+1))
    done

    # Umount and verify counts go down properly
    for (( i=${nmounts}; i>0; --i )); do
        eunmount dst
        check_mounts dst $((i-1))
    done
}

# Test bugfix where if you bind mount a directory (or file) and later 
# remove the source of the bind mount then we were unable to unmount
# the destination mount point and it would get caught in an infinite
# loop.
ETEST_emount_deleted()
{
    einfo "Creating src and dst"
    mkdir src dst
    einfo "Bind mounting src to dst"
    emount --bind src dst
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Remove the source of the bind mount and verify we still
    # recongize it's mounted (as we had a bug in emounted as well).
    einfo "Remove src and verify still mounted"
    rm -rf src
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Ensure eunmount_recursive can unmount it and doesn't hang.
    einfo "Unmount dst and verify not mounted"
    eunmount dst
    emounted dst && die
    assert_eq 0 $(emount_count dst)
}

# Same as above but explicitly test eunmount_recursive
ETEST_emount_deleted_recursive()
{
    einfo "Creating src and dst"
    mkdir src dst
    einfo "Bind mounting src to dst"
    emount --bind src dst
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Remove the source of the bind mount and verify we still
    # recongize it's mounted (as we had a bug in emounted as well).
    einfo "Remove src and verify still mounted"
    rm -rf src
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Ensure eunmount_recursive can unmount it and doesn't hang.
    einfo "Unmount dst and verify not mounted"
    eunmount_recursive dst
    emounted dst && die
    assert_eq 0 $(emount_count dst)
}
