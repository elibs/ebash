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
    echo "${frames[@]}"
    echo ""

    # Make sure this ends up being valid json
    array_to_json frames | jq --monochrome-output .
    assert_zero $?
}
