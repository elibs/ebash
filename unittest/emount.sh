ETEST_emount_bind()
{
    emkdir src
    etouch src/file
    echo "Love" > src/file

    # Bind mount and verify mounted and verify content
    emkdir dst
    emount --bind src dst
    assert_true emounted dst
    assert_true diff src/file dst/file
}

ETEST_emount_unmount()
{
    # Bind mount src to dst
    emkdir src dst
    emount --bind src dst

    # Verify mounted, unmount, then verify unmounted
    emounted dst || die
    eunmount dst
    emounted dst && die
}

ETEST_emount_unmount_recursive()
{
    # Bind mount a couple of nested directories
    emkdir src1 src2 dst/dst1 dst/dst2
    emount --bind src1 dst/dst1
    emount --bind src2 dst/dst2

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
    emount --bind src1 dst/dst1
    emount --bind src2 dst/dst2

    # Verify state
    emounted dst      && die
    emounted dst/dst1 || die
    emounted dst/dst2 || die

    # Use a partial match -- should NOT find any mounts
    emounted dst/d    && die
}

emount_check_mounts()
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
        trap_add "eunmount dst${i}" HUP INT QUIT BUS PIPE TERM EXIT
        emount_check_mounts dst${i} 1
    done

    # Umount and verify counts go down properly
    for (( i=${nmounts}; i>0; --i )); do
        eunmount dst${i}
        emount_check_mounts dst${i} 0
    done
}

DISABLED_ETEST_emount_bind_count_shared()
{
    emkdir src
    emkdir dst

    # Mount a few times and ensure counter goes up correctly
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        emount --bind --make-unbindable src dst
        trap_add "eunmount dst &>/dev/null" HUP INT QUIT BUS PIPE TERM EXIT
        emount_check_mounts dst $((i+1))
    done

    # Umount and verify counts go down properly
    for (( i=${nmounts}; i>0; --i )); do
        eunmount dst
        emount_check_mounts dst $((i-1))
    done
}
