#!/usr/bin/env bash

ETEST_json_escape()
{
    string=$'escape " these \n chars'
    escaped=$(json_escape "${string}")

    [[ ${escaped} =~ escape ]]   || die
    [[ ${escaped} =~ these ]]    || die
    [[ ${escaped} =~ chars ]]    || die

    [[ ${escaped} =~ \\n ]]    || die

    quote='\"'
    [[ ${escaped} =~ ${quote} ]] || die

    # Make sure there isn't still a newline in the string
    assert_eq 1 $(echo "${escaped}" | wc -l)
}

ETEST_array_to_json()
{
    ARR=(a "b c" d)

    json=$(array_to_json ARR)
    echo "json: ${json}"

    for (( i = 0 ; i < ${#ARR[@]} ; i++ )) ; do
        assert_eq "${ARR[$i]}" "$(echo "${json}" | jq --raw-output ".[$i]")"
    done
}

ETEST_pack_to_json()
{
    pack_set P A="alpha 1" B="beta 2"

    json=$(pack_to_json P)
    echo "json ${json}"
}

ETEST_stacktrace_to_json()
{
    array_init_nl frames "$(stacktrace)"
    json=$(array_to_json frames)

    # Make sure this ends up being valid json
    echo ${json} | jq --monochrome-output .
    assert_zero $?

    ebanner msg json
}

ETEST_all_to_json()
{
    pack_set P A=1 B="2 3 4" C="alpha beta"
    A=1
    ARRAY=(a "b c" d)

    declare -A AA
    AA[alpha]="10 20 30"
    AA[beta]="100 200 300"

    json=$(to_json AA A ARRAY +P)

    # Dump the json and make sure it validates
    echo ${json} | jq .
    assert_zero $?

    # And spot check a few values to make sure they match
    assert_eq "$(pack_get P A)" "$(echo ${json} | jq .P.A --raw-output)"
    assert_eq "$(pack_get P B)" "$(echo ${json} | jq .P.B --raw-output)"
    assert_eq "$(pack_get P C)" "$(echo ${json} | jq .P.C --raw-output)"

    assert_eq "${A}" "$(echo ${json} | jq .A --raw-output)"

    assert_eq "${AA[alpha]}" "$(echo ${json} | jq .AA.alpha --raw-output)"
    assert_eq "${AA[beta]}"  "$(echo ${json} | jq .AA.beta --raw-output)"
}

ETEST_AA_to_json()
{
    declare -A AA
    AA[alpha]="b c"
    AA[beta]="1 2 3"

    json=$(associative_array_to_json AA)

    assert_eq "${AA[alpha]}" "$(echo ${json} | jq --raw-output .alpha)"
    assert_eq "${AA[beta]}"  "$(echo ${json} | jq --raw-output .beta)"
}

ETEST_to_json_single()
{
    A="1 2 3"
    json=$(to_json A)

    echo ${json} | jq .
    assert_eq "${A}" "$(echo ${json} | jq --raw-output .A)"
}
