ETEST_emount_bind()
{
    emkdir src
    etouch src/file
    echo "Love" > src/file

    # Bind mount and verify mounted and verify content
    emkdir dst
    ebindmount src dst
    assert_true emounted dst
    assert_true diff src/file dst/file
}

ETEST_emount_unmount()
{
    # Bind mount src to dst
    emkdir src dst
    ebindmount src dst

    # Verify mounted, unmount, then verify unmounted
    emounted dst || die
    eunmount dst
    emounted dst && die
}

ETEST_emount_unmount_recursive()
{
    # Bind mount a couple of nested directories
    emkdir src1 src2 dst/dst1 dst/dst2
    ebindmount  src1 dst/dst1
    ebindmount  src2 dst/dst2

    # Verify state
    emounted dst      && die
    emounted dst/dst1 || die
    emounted dst/dst2 || die

    # Recursive unmount using top-level directory structure even though it isn't mounted
    eunmount_recursive dst
    emounted dst/dst1 && die
    emounted dst/dst2 && die
}

ETEST_emount_partial_match()
{
    # Bind mount a couple of nested directories
    emkdir src1 src2 dst/dst1 dst/dst2
    ebindmount src1 dst/dst1
    ebindmount src2 dst/dst2

    # Verify state
    emounted dst      && die
    emounted dst/dst1 || die
    emounted dst/dst2 || die

    # Use a partial match -- should NOT find any mounts
    emounted dst/d    && die
}

check_mounts()
{
    $(declare_args path count)

    [[ ${count} -eq 0 ]] && assert_false emounted ${path} || assert_true emounted ${path}
    assert_eq ${count} $(emount_count ${path})
}

ETEST_emount_bind_count_separate()
{
    emkdir src

    # Mount a few times and ensure counter goes up correctly
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        emkdir dst${i}
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
    emkdir src
    emkdir dst

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
    emkdir src
    emkdir dst
    einfo "Bind mounting src to dst"
    emount --bind src dst
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Remove the source of the bind mount and verify we still
    # recongize it's mounted (as we had a bug in emounted as well).
    einfo "Remove src and verify still mounted"
    erm src
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
    emkdir src
    emkdir dst
    einfo "Bind mounting src to dst"
    emount --bind src dst
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Remove the source of the bind mount and verify we still
    # recongize it's mounted (as we had a bug in emounted as well).
    einfo "Remove src and verify still mounted"
    erm src
    emounted dst || die
    assert_eq 1 $(emount_count dst)

    # Ensure eunmount_recursive can unmount it and doesn't hang.
    einfo "Unmount dst and verify not mounted"
    eunmount_recursive dst
    emounted dst && die
    assert_eq 0 $(emount_count dst)
}
