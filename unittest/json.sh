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
    assert_eq 0 $(echo -n "${escaped}" | wc -l)
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

    # NOTE: We can't check $json here, because the $( ) that we used when we
    # assigned to it will strip off any newlines at the end.
    assert_eq 0 $(to_json AA A ARRAY +P | wc -l)
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

ETEST_json_import()
{
    $(json_import <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3" }')
    argcheck driveSize lsiFirmware
    assert_eq "100"     "${driveSize}"
    assert_eq "1.0.2.3" "${lsiFirmware}"
}

ETEST_json_import_explicit_keys()
{
    $(json_import driveSize lsiFirmware <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3", "sliceDriveSize": 100 }')
    argcheck driveSize lsiFirmware
    assert_eq "100"     "${driveSize}"
    assert_eq "1.0.2.3" "${lsiFirmware}"
    assert_empty        "${sliceDriveSize}"
}

ETEST_json_import_upper_snake_case()
{
    $(json_import -u <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3" }')

    argcheck DRIVE_SIZE LSI_FIRMWARE
    assert_eq "100"     "${DRIVE_SIZE}"
    assert_eq "1.0.2.3" "${LSI_FIRMWARE}"
}

ETEST_json_import_default_local()
{
    $(json_import -u <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3" }')
	argcheck DRIVE_SIZE LSI_FIRMWARE
    
    assert_eq 'declare -- DRIVE_SIZE="100"'       "$(declare -p DRIVE_SIZE)"
    assert_eq 'declare -- LSI_FIRMWARE="1.0.2.3"' "$(declare -p LSI_FIRMWARE)"
}

ETEST_json_import_local()
{
    $(json_import -ul <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3" }')
	argcheck DRIVE_SIZE LSI_FIRMWARE
    
    assert_eq 'declare -- DRIVE_SIZE="100"'       "$(declare -p DRIVE_SIZE)"
    assert_eq 'declare -- LSI_FIRMWARE="1.0.2.3"' "$(declare -p LSI_FIRMWARE)"
}

ETEST_json_import_export()
{
    $(json_import -ue <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3" }')
	argcheck DRIVE_SIZE LSI_FIRMWARE
    
    assert_eq 'declare -x DRIVE_SIZE="100"'       "$(declare -p DRIVE_SIZE)"
    assert_eq 'declare -x LSI_FIRMWARE="1.0.2.3"' "$(declare -p LSI_FIRMWARE)"
}

ETEST_json_import_prefix()
{
    $(json_import -u -p=FOO_ <<< '{ "driveSize": 100, "lsiFirmware": "1.0.2.3" }')
    argcheck FOO_DRIVE_SIZE FOO_LSI_FIRMWARE

    assert_eq "100"     "${FOO_DRIVE_SIZE}"
    assert_eq "1.0.2.3" "${FOO_LSI_FIRMWARE}"
}

ETEST_json_import_query()
{
    $(json_import -q=".R620.SF6010" <<< '{ "R620": { "SF3010": { "driveSize": 100, "foo": 1 }, "SF6010": { "driveSize": 200, "foo": 2 } } }')
    argcheck driveSize foo

    assert_eq "200" "${driveSize}"
    assert_eq "2"   "${foo}"
}

ETEST_json_import_query_keys()
{
    $(json_import -q=".R620.SF6010" driveSize <<< '{ "R620": { "SF3010": { "driveSize": 100, "foo": 1 }, "SF6010": { "driveSize": 200, "foo": 2 } } }')
    argcheck driveSize

    assert_eq "200" "${driveSize}"
    assert_empty    "${foo}"
}

ETEST_json_import_exclude_keys()
{
    $(json_import -q=".R620.SF3010" -x=driveSize <<< '{ "R620": { "SF3010": { "driveSize": 100, "foo": 1, "bar": 3 }, "SF6010": { "driveSize": 200, "foo": 2 } } }')
    argcheck foo bar

    assert_eq "1" "${foo}"
    assert_eq "3" "${bar}"
    assert_empty  "${driveSize}"
}

ETEST_json_import_query_keys_file()
{
    echo '{ "R620": { "SF3010": { "driveSize": 100, "foo": 1 }, "SF6010": { "driveSize": 200, "foo": 2 } } }' > file.json
    cat file.json
    $(json_import -q=".R620.SF6010" -f=file.json driveSize)

    argcheck driveSize

    assert_eq "200" "${driveSize}"
    assert_empty    "${foo}"
}

ETEST_json_import_query_platform()
{
    local json='
    { "hardwareConfig": [
        {   
            "chassisType": "R620",
            "nodeType": "SF3010",
            "biosRevision": "1.0",
            "biosVendor": "SolidFire",
            "biosVersion": "1.1.2",
            "blockDriveSize": "300069052416",
            "bmcFirmwareRevision": "1.6",
            "bmcIpmiVersion": "2.0",
            "cpu": "Intel(R) Xeon(R) CPU E5-2640 0 @ 2.50GHz",
            "cpuCores": "6",
            "cpuCoresEnabled": "6",
            "cpuThreads": "12",
            "driveSizeInternal": "400088457216",
            "idracVersion": "1.06.06",
            "lifecycleVersion": "1.0.0.5747",
            "memoryGbPretty": "72",
            "memoryKb": "70000000",
            "memoryMhz": "1333",
            "networkDriver": "^bnx2x$",
            "numCpu": "2",
            "numDrives": "10",
            "numDrivesInternal": "1",
            "rootDrive": "/dev/sdimm0",
            "rpcPostCallbackThreads": "8",
            "scsiBusExternalDriver": "mpt2sas",
            "scsiBusInternalDriver": "ahci",
            "sliceBufferCacheGb": "16",
            "sliceDriveSize": "299992412160"
        },  
        {   
            "chassisType": "R620",
            "nodeType": "SF6010",
            "biosRevision": "1.0",
            "biosVendor": "SolidFire",
            "biosVersion": "1.1.2",
            "blockDriveSize": "600127266816",
            "bmcFirmwareRevision": "1.6",
            "bmcIpmiVersion": "2.0",
            "cpu": "Intel(R) Xeon(R) CPU E5-2640 0 @ 2.50GHz",
            "cpuCores": "6",
            "cpuCoresEnabled": "6",
            "cpuThreads": "12",
            "driveSizeInternal": "100030242816",
            "idracVersion": "1.06.06",
            "lifecycleVersion": "1.0.0.5747",
            "memoryGbPretty": "72",
            "memoryKb": "70000000",
            "memoryMhz": "1333",
            "networkDriver": "^bnx2x$",
            "numCpu": "2",
            "numDrives": "10",
            "numDrivesInternal": "1",
            "rootDrive": "/dev/sdimm0",
            "rpcPostCallbackThreads": "8",
            "scsiBusExternalDriver": "mpt2sas",
            "scsiBusInternalDriver": "ahci",
            "sliceBufferCacheGb": "64",
            "sliceDriveSize": "299992412160"
        }
    ]}'

    local CHASSIS_TYPE="R620"
    local NODE_TYPE="SF3010"
    $(json_import -u -q='.hardwareConfig[]|select(.chassisType == "'${CHASSIS_TYPE}'" and .nodeType == "'${NODE_TYPE}'")' blockDriveSize sliceBufferCacheGb <<< ${json})
    argcheck BLOCK_DRIVE_SIZE SLICE_BUFFER_CACHE_GB

    assert_eq "300069052416" "${BLOCK_DRIVE_SIZE}"
    assert_eq "16"           "${SLICE_BUFFER_CACHE_GB}"
}
