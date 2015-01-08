ETEST_setvars_basic()
{
    local file="setvars_basic.txt"
    local name="Immanual Kant"
    echo "name=[__name__]" > "${file}"
    trap_add "erm ${file}" EXIT

    setvars "${file}"
    expect_eq "name=[${name}]" "$(cat ${file})"
}

ETEST_setvars_multi()
{
    local file="setvars_multi.txt"
    local arg1="Foo"
    local arg2="Bar"
    echo "__arg1__ __arg2__" > "${file}"
    trap_add "erm ${file}" EXIT

    setvars "${file}"
    expect_eq "${arg1} ${arg2}" "$(cat ${file})"
}

# Test when variables are not fully expanded that setvars fails.
ETEST_setvars_error()
{
    local file="setvars_multi.txt"
    local arg1="Foo"
    echo "__arg1__ __arg2__" > "${file}"
    trap_add "erm ${file}" EXIT

    expect_false SETVARS_FATAL=0 SETVARS_WARN=0 setvars "${file}"
}

adjust_version()
{
    local key=$1
    local val=$2
    edebug "$(lval key val)"

    # If we've patched the firmware package itself it's version will change but the underlying version of the reported firmware
    # itself is unchanged. So we need to strip off any -pXXX on the version string.
    [[ ${key} =~ .*_DRIVER_VERSION$ || ${key} =~ .*_FIRMWARE_VERSION$ ]] && val=${val%%-p*}

    echo -n "${val}"
}

ETEST_setvars_callback()
{
    local file="setvars_callback.txt"
    local MARVELL_VERSION="1.7.2-p1"
    local MARVELL_DRIVER_VERSION=${MARVELL_VERSION}
    local MARVELL_FIRMWARE_VERSION=${MARVELL_VERSION}
    echo "__MARVELL_VERSION__ __MARVELL_DRIVER_VERSION__ __MARVELL_FIRMWARE_VERSION__" > "${file}"
    trap_add "erm ${file}" EXIT

    setvars "${file}" adjust_version
    expect_eq "1.7.2-p1 1.7.2 1.7.2" "$(cat ${file})"
}
