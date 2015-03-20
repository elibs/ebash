ETEST_setvars_basic()
{
    local file="setvars_basic.txt"
    local name="Immanual Kant"
    echo "name=[__name__]" > "${file}"

    setvars "${file}"
    expect_eq "name=[${name}]" "$(cat ${file})"
}

ETEST_setvars_multi()
{
    local file="setvars_multi.txt"
    local arg1="Foo"
    local arg2="Bar"
    echo "__arg1__ __arg2__" > "${file}"

    setvars "${file}"
    expect_eq "${arg1} ${arg2}" "$(cat ${file})"
}

# Test when variables are not fully expanded that setvars fails.
ETEST_setvars_error()
{
    local file="setvars_multi.txt"
    local arg1="Foo"
    echo "__arg1__ __arg2__" > "${file}"

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

    setvars "${file}" adjust_version
    expect_eq "1.7.2-p1 1.7.2 1.7.2" "$(cat ${file})"
}

ETEST_setvars_with_newlines()
{
    local file="setvars_with_newlines.txt"

    echo "A __B__ C" > ${file}

    B="a
b
c"

    expected="A a
b
c C"

    setvars "${file}"

    expect_eq "${expected}" "$(cat $file)"
}

ETEST_setvars_punctuation()
{
    PUNCT="!@#$%^&*()-=[]{};'\",.<>/?|"

    local file="setvars_punctuation.txt"

    # Iterate over the above string of punctuation marks
    for (( i=0 ; i < ${#PUNCT} ; ++i )) ; do
        local mark=${PUNCT:$i:1}
        local endmark=${mark}

        [[ $mark == "(" ]] && endmark=")"
        [[ $mark == "[" ]] && endmark="]"
        [[ $mark == "{" ]] && endmark="}"
        [[ $mark == "<" ]] && endmark=">"

        edebug "$(lval mark endmark)"

        # Create a simple file to setvars in, and replace part of it with a
        # string containing that punctuation mark
        echo "A __B__ C" > ${file}
        B=jan${mark}feb${endmark}march
        setvars "${file}"

        expect_eq "A jan${mark}feb${endmark}march C" "$(cat ${file})"

        edebug_enabled && cat "${file}" || true
    done
}
