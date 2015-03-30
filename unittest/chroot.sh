
# Global settings
$(esource chroot.sh)
CHROOT=build
CHROOT_MOUNTS=( /dev /proc /sys )

assert_chroot_not_mounted()
{
    assert_false emounted ${CHROOT}

    # Verify chroot paths not mounted
    for path in ${CHROOT_MOUNTS[@]}; do
        assert_false emounted ${CHROOT}${path}
        assert_eq 0 $(emount_count ${CHROOT}${path})
    done
}

DISABLED_ETEST_chroot_create_mount()
{
    mkchroot ${CHROOT} precise oxygen bdr-jenkins amd64
    trap_add "chroot_exit" HUP INT QUIT BUS PIPE TERM EXIT

    # Verify chroot paths not mounted
    assert_chroot_not_mounted

    # Mount a few times and verify counts go up
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        chroot_mount
    done

    # Unmount and verify counts go down
    for (( i=${nmounts}; i>0; --i )); do
        chroot_unmount
    done

    assert_chroot_not_mounted
}
