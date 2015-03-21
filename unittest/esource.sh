ETEST_esource_multiple_files()
{
    echo "A=1" > s1.sh
    echo "B=2" > s2.sh
    echo "C=3" > s3.sh

    $(esource s1.sh s2.sh s3.sh)
    expect_eq 1 $A
    expect_eq 2 $B
    expect_eq 3 $C
}

ETEST_esource_multiple_files_and_values()
{
    echo "A=1; AA=10" > s1.sh
    echo "B=2; BB=20" > s2.sh
    echo "C=3; CC=30" > s3.sh

    $(esource s1.sh s2.sh s3.sh)
    expect_eq 1  $A
    expect_eq 10 $AA
    expect_eq 2  $B
    expect_eq 20 $BB
    expect_eq 3  $C
    expect_eq 30 $CC
}

ETEST_esource_missing_file()
{
    erm missing.sh
    ( EFUNCS_FATAL=0 $(esource missing.sh &> /dev/null) && return 1 )
    return 0
}

ETEST_esource_override_value()
{
    echo "A=1" > s1.sh
    echo "A=2" > s2.sh

    $(esource s1.sh s2.sh)
    expect_eq 2 $A
}

ETEST_esource_associative_array()
{
    echo "declare -A PMAP; PMAP['boot']=1;" > common.sh
    $(esource common.sh)
    expect_eq 1 ${PMAP[boot]}
}
