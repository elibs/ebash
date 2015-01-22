ETEST_pack_one()
{
    pack_set P a=alpha

    expect_zero $?
    expect_eq "alpha" $(pack_get P a)
    expect_eq 1 $(pack_size P)
}

ETEST_pack_empty_values()
{
    pack_set P a= b=

    local val=$(pack_get P a)
    expect_zero $?
    expect_empty ${val}

    local val=$(pack_get P b)
    expect_zero $?
    expect_empty ${val}

    expect_eq 2 $(pack_size P)
}

ETEST_pack_many()
{
    pack_set P a= b=3 c=7 n=1 x=alpha y=beta z=10

    expect_empty      $(pack_get P a)
    expect_eq "3"     $(pack_get P b)
    expect_eq "7"     $(pack_get P c)
    expect_eq "1"     $(pack_get P n)
    expect_eq "alpha" $(pack_get P x)
    expect_eq "beta"  $(pack_get P y)
    expect_eq "10"    $(pack_get P z)
}

ETEST_pack_sequential()
{
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
    pack_set P a=1

    b=$(pack_get P b)
    expect_eq 1  $?
    expect_empty "${b}"
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
    pack_set P a=1==b c===d

    expect_eq "1==b" $(pack_get P a)
    expect_eq "==d"  $(pack_get P c)
}

ETEST_pack_get_from_empty()
{
    a=$(pack_get P a)

    expect_not_zero $?
    expect_empty "${a}"
}

ETEST_pack_last_of_dupes()
{
    pack_set P a=1 a=7 a=10
    expect_eq 10 $(pack_get P a)

    pack_set P a=3
    expect_eq 3  $(pack_get P a)
}

_pack_iterate_count=0
_pack_iterate_checker()
{
    local key=$1
    local val=$2

    edebug "_pack_iterate_checker: $(lval key val _pack_iterate_count)"
    expect_true '[[ $key == "a" || $key == "b" || $key == "c" || $key == "white" ]]'

    [[ $key != "white" ]] && expect_eq  "val" "$val"
    [[ $key == "white" ]] && expect_eq  "val with spaces" "$val"

    (( _pack_iterate_count += 1 ))
}

ETEST_pack_iterate()
{
    pack_set P a=val b=val c=val white="val with spaces"
    pack_iterate P _pack_iterate_checker

    expect_eq 4 ${_pack_iterate_count}
}

ETEST_pack_keys_are_not_case_insensitive()
{
    pack_set P a="alpha"
    expect_eq "alpha" $(pack_get P a)
    expect_empty      $(pack_get P A)

    pack_set P A="beta"
    expect_eq "alpha" $(pack_get P a)
    expect_eq "beta"  $(pack_get P A)
}

ETEST_pack_values_can_contain_whitespace()
{
    pack_set P "a=alpha beta" "g=gamma kappa"

    expect_eq 2 $(pack_size P)
    expect_eq "alpha beta"  "$(pack_get P a)"
    expect_eq "gamma kappa" "$(pack_get P g)"

    keys=($(pack_keys P))
    expect_eq "a" ${keys[0]}
    expect_eq "g" ${keys[1]}
}

ETEST_pack_update_empty_stays_empty()
{
    pack_update P a=1 b=2 c=3

    expect_empty "${P}"
}

ETEST_pack_update_updates_values()
{
    pack_set P a=1 b=2 c=3

    pack_update P a=10 b=20 d=40

    expect_eq "10" $(pack_get P a)
    expect_eq "20" $(pack_get P b)
    expect_eq "3"  $(pack_get P c)
    expect_empty   $(pack_get P d)
}

ETEST_pack_avoid_common_variable_conflicts()
{
    POTENTIAL_VARS=(arg val key tag)
    for VAR in ${POTENTIAL_VARS[@]} ; do
        edebug "Testing for conflicts in variable name ${VAR}"

        pack_set ${VAR} a=1 b=2 c=3
        pack_update ${VAR} a=10 b=20 c=30 d=40

        expect_eq 10 $(pack_get ${VAR} a)
        expect_eq 20 $(pack_get ${VAR} b)
        expect_eq 30 $(pack_get ${VAR} c)

    done
}

ETEST_pack_no_newlines()
{
    EFUNCS_FATAL=0
    output=$(
        (
            pack_set P "a=$(printf "\na\nb\n")" 2>&1

            # Should never get here, because the above should blow up
            expect_true false
        )
    )
    expect_not_zero $?
    expect_true '[[ "${output}" =~ newlines ]]'
}

ETEST_pack_lots_of_data()
{
    A="http://bdr-distbox.engr.solidfire.net:8080/jobs/dtest_modell/10234"
    pack_set P A=${A} B=${A} C=${A}

    expect_eq "${A}" "$(pack_get P A)"
    expect_eq "${A}" "$(pack_get P B)"
    expect_eq "${A}" "$(pack_get P C)"
}

ETEST_pack_lval()
{
    pack_set P A=1 B=2
    expect_eq 'P=([A]="1" [B]="2" )' "$(lval +P)"
}

ETEST_pack_update_only_complete_matches()
{
    pack_set P ALPHA=1
    expect_eq 1 $(pack_size P)

    pack_update P A=1
    pack_update P AL=1
    pack_update P ALP=1
    pack_update P ALPH=1
    pack_update P ALPHA_=1
    expect_eq 1 $(pack_size P)
}

ETEST_pack_update_key_not_insensitive()
{
    pack_set P A=1 B=2

    pack_update P a=10 b=20

    expect_eq 1  $(pack_get P A)
    expect_eq 2  $(pack_get P B)
    expect_empty $(pack_get P a)
    expect_empty $(pack_get P b)
}

ETEST_pack_copy_empty()
{
    A=""
    B=""
    expect_true pack_copy A B
}

ETEST_pack_copy_over()
{
    pack_set P A=1 B=2
    declare -A B
    pack_set B[alpha] C=10 D=20

    edebug $(lval +P +B[alpha])
    expect_eq 1 $(pack_get P A)
    expect_eq 2 $(pack_get P B)

    pack_copy P B[alpha]
    edebug $(lval +P +B[alpha])
    expect_eq 1 $(pack_get B[alpha] A)
    expect_eq 2 $(pack_get B[alpha] B)
    expect_eq 1 $(pack_get P A)
    expect_eq 2 $(pack_get P B)
}

ETEST_pack_import_all()
{
    expect_empty ${a}
    expect_empty ${b}

    pack_set P a=10 b=20
    eval "$(pack_import P)"

    expect_eq 10 ${a}
    expect_eq 20 ${b}
}

ETEST_pack_import_specific()
{
    expect_empty ${a}
    expect_empty ${b}
    expect_empty ${c}

    pack_set P a=1 b=2 c=3
    eval "$(pack_import P a b)"

    expect_eq 1  ${a}
    expect_eq 2  ${b}
    expect_empty ${c}
}

ETEST_pack_export()
{
    a=1
    b=2
    c=3

    pack_export P a b c

    expect_eq ${a} "$(pack_get P a)"
    expect_eq ${b} "$(pack_get P b)"
    expect_eq ${c} "$(pack_get P c)"

}
