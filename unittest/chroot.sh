
# Global settings
$(esource chroot.sh)
CHROOT=build
CHROOT_MOUNTS=( /dev /proc /sys )

check_mounts()
{
    $(declare_args count)

    # Verify chroot paths not mounted
    for path in ${CHROOT_MOUNTS[@]}; do
        [[ ${count} -eq 0 ]] && assert_false emounted ${CHROOT}${path} || assert_true emounted ${CHROOT}${path}
        assert_eq ${count} $(emount_count ${CHROOT}${path})
    done
}

ETEST_chroot_create_mount()
{
    mkchroot ${CHROOT} precise oxygen bdr-jenkins amd64
    check_mounts 0

    # Mount a few times and verify counts go up
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        chroot_mount
        check_mounts $((i+1))
    done

    # Unmount and verify counts go down
    for (( i=${nmounts}; i>0; --i )); do
        chroot_unmount
        check_mounts $((i-1))
    done

    check_mounts 0
}
