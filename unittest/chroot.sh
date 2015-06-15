
# Global settings
$(esource chroot.sh)
CHROOT=build
CHROOT_MOUNTS=( /dev /dev/pts /proc /sys )

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

# Ensure if we have multiple chroot_mounts going on that we can successfully
# unmount them properly using a single call to eunmount_recursive. 
ETEST_chroot_create_mount_unmount_recursive()
{
    mkchroot ${CHROOT} precise oxygen bdr-jenkins amd64
    check_mounts 0

    # Mount a few times and verify counts go up
    local nmounts=10
    for (( i=0; i<${nmounts}; ++i )); do
        chroot_mount
        check_mounts $((i+1))
    done

    # One eunmount_recursive should clean everything up.
    eunmount_recursive ${CHROOT}
    check_mounts 0
}

# A problem that we've had repeatedly is after using chroot_mount, our root
# system gets honked up.  This seems to be related to shared/private mounts.
# Here we create a file on the root system in /dev/shm, which will go away if
# that problem occurs.  This seems to occur only on systems that mount /dev as
# shared initially (e.g. those running systemd)
ETEST_chroot_slash_dev_shared_mounts()
{
    TESTFILE=/dev/shm/${FUNCNAME}_$$

    touch ${TESTFILE}
    [[ -f ${TESTFILE} ]] || die "Unable to create ${TESTFILE}"
    trap_add "rm ${TESTFILE}" HUP INT QUIT BUS PIPE TERM EXIT

    # Force /dev to be mounted "shared" so that the following code can test
    # whether it actually works that way.  This is the default on systemd
    # boxes, but not others
    mount --make-shared /dev

    mkdir dev

    ebindmount /dev dev
    trap_add "ewarn trap ; eunmount dev" HUP INT QUIT BUS PIPE TERM EXIT

    ebindmount /dev dev
    trap_add "ewarn trap ; eunmount dev" HUP INT QUIT BUS PIPE TERM EXIT

    # So now, while we've done a pair of bind mounts, the file should be missing
    [[ -f ${TESTFILE} ]] || die "File is missing"
}
