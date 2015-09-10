#!/usr/bin/env bash

ETEST_checksum_basic()
{
    cp ${BASH_SOURCE} .
    local src="$(basename ${BASH_SOURCE})"
    local meta="${src}.meta"

    echecksum ${src} > ${meta}
    cat ${meta}
    pack_set MPACK $(cat ${meta})
    $(pack_import MPACK)

    assert_eq "${Filename}" "$(basename "${src}")"
    assert_eq "${Size}"     "$(stat --printf='%s' ${src})"
    assert_eq "${MD5}"      "$(md5sum    ${src} | awk '{print $1}')"
    assert_eq "${SHA1}"     "$(sha1sum   ${src} | awk '{print $1}')"
    assert_eq "${SHA256}"   "$(sha256sum ${src} | awk '{print $1}')"
}

ETEST_checksum_pgp()
{
    # Grab public and private keys as well as passphrase
    efetch http://bdr-jenkins:/keys/solidfire_packaging_public.asc  public.asc
    efetch http://bdr-jenkins:/keys/solidfire_packaging_private.asc private.asc
    efetch http://bdr-jenkins:/keys/solidfire_packaging.phrase      phrase.txt

    cp ${BASH_SOURCE} .
    local src="$(basename ${BASH_SOURCE})"
    local meta="${src}.meta"
    echecksum -p="private.asc" -k="$(cat phrase.txt)" ${src} > ${meta}
    cat ${meta}
    pack_set MPACK $(cat ${meta})
    $(pack_import MPACK)

    # Now validate what we just signed using public key
    echecksum_check -p="public.asc" ${src}
}
