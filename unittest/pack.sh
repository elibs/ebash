ETEST_pack_one()
{
    local P
    pack_set P a=alpha

    expect_eq "alpha" $(pack_get P a)
}

ETEST_pack_empty()
{
    local P
    pack_set P a= b=

    local val=$(pack_get P a)
    expect_eq 0 $?
    expect_eq "" ${val}

    local val=$(pack_get P b)
    expect_eq 0 $?
    expect_eq "" ${val}
}

ETEST_pack_many()
{
    local P
    pack_set P a= b=3 c=7 n=1 x=alpha y=beta z=10

    expect_eq ""      $(pack_get P a)
    expect_eq "3"     $(pack_get P b)
    expect_eq "7"     $(pack_get P c)
    expect_eq "1"     $(pack_get P n)
    expect_eq "alpha" $(pack_get P x)
    expect_eq "beta"  $(pack_get P y)
    expect_eq "10"    $(pack_get P z)
}

ETEST_pack_sequential()
{
    local P
    pack_set P a=alpha
    expect_eq "alpha" $(pack_get P a)
    
    pack_set P b=2
    expect_eq "alpha" $(pack_get P a)
    expect_eq "2"     $(pack_get P b)
    
    pack_set P c=300
    expect_eq "alpha" $(pack_get P a)
    expect_eq "2"     $(pack_get P b)
    expect_eq "300"   $(pack_get P c)
}

ETEST_pack_nonexistent()
{
    local P
    pack_set P a=1

    b=$(pack_get P b)
    expect_eq 1  $?
    expect_eq "" ${b}
}

ETEST_pack_into_associative_array()
{
    local -A AA
    AA[n]=1

    pack_set AA[p] a=7 b=8
    expect_eq 1  ${AA[n]}

    expect_eq 7 $(pack_get AA[p] a)
    expect_eq 8 $(pack_get AA[p] b)
}

ETEST_pack_values_containing_equal_sign()
{
    local P
    pack_set P a=1==b c===d

    expect_eq "1==b" $(pack_get P a)
    expect_eq "==d"  $(pack_get P c)
}
