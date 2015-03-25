## Check if we're root and re-execute if we're not through sudo ##
if [[ $(id -u) != "0" ]]; then
    sudo -E "$0" "$@"
    exit $?
fi

ETEST_emount_bind()
{
    emkdir src
    etouch src/file
    echo "Love" > src/file

    # Bind moutn and verify mounted and verify content
    emkdir dst
    emount --bind src dst &> $(edebug_out)
    emounted dst || die
    diff src/file dst/file || die

    # Success
    return 0
}

ETEST_emount_unmount()
{
    # Bind mount src to dst
    emkdir src dst
    emount --bind src dst &> $(edebug_out)

    # Verify mounted, unmount, then verify unmounted
    emounted dst || die
    eunmount dst &> $(edebug_out) 
    emounted dst && die

    # Success
    return 0
}

ETEST_emount_unmount_recursive()
{
    # Bind mount a couple of nested directories
    emkdir src1 src2 dst/dst1 dst/dst2
    emount --bind src1 dst/dst1 &> $(edebug_out)
    emount --bind src2 dst/dst2 &> $(edebug_out)

    # Verify state
    emounted dst      && die
    emounted dst/dst1 || die
    emounted dst/dst2 || die

    # Recursive unmount using top-level directory structure even though it isn't mounted
    eunmount_recursive dst &> $(edebug_out)
    emounted dst/dst1 && die
    emounted dst/dst2 && die

    # Success
    return 0
}

ETEST_emount_partial_match()
{
    # Bind mount a couple of nested directories
    emkdir src1 src2 dst/dst1 dst/dst2
    emount --bind src1 dst/dst1 &> $(edebug_out)
    emount --bind src2 dst/dst2 &> $(edebug_out)

    # Verify state
    emounted dst      && die
    emounted dst/dst1 || die
    emounted dst/dst2 || die

    # Use a partial match -- should NOT find any mounts
    emounted dst/d    && die

    # Success
    return 0
}
