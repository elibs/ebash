ETEST_checksum_basic()
{
    echecksum ${BASH_SOURCE} > ${BASH_SOURCE}.meta
    cat ${BASH_SOURCE}.meta
    pack_set MPACK $(cat ${BASH_SOURCE}.meta)
    $(pack_import MPACK)

    assert_eq "${Filename}" "$(basename "${BASH_SOURCE}")"
    assert_eq "${Size}"     "$(stat --printf='%s' ${BASH_SOURCE})"
    assert_eq "${MD5}"      "$(md5sum    ${BASH_SOURCE} | awk '{print $1}')"
    assert_eq "${SHA1}"     "$(sha1sum   ${BASH_SOURCE} | awk '{print $1}')"
    assert_eq "${SHA256}"   "$(sha256sum ${BASH_SOURCE} | awk '{print $1}')"
}

ETEST_checksum_pgp()
{
    # Grab public and private keys as well as passphrase
    efetch http://bdr-jenkins:/keys/solidfire_packaging_public.asc  public.asc
    efetch http://bdr-jenkins:/keys/solidfire_packaging_private.asc private.asc
    efetch http://bdr-jenkins:/keys/solidfire_packaging.phrase      phrase.txt

    echecksum -P="private.asc" -p="$(cat phrase.txt)" ${BASH_SOURCE} > ${BASH_SOURCE}.meta
    cat ${BASH_SOURCE}.meta
    pack_set MPACK $(cat ${BASH_SOURCE}.meta)
    $(pack_import MPACK)

    # Now validate what we just signed using public key
    echecksum_check -P="public.asc" ${BASH_SOURCE}
}
