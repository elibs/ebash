# Call etar with various extensions that all map to some variation of 
# bzip. Ensure etar doesn't blow up and that we can extract it afterwards.
ETEST_etar_auto_bzip()
{
    mkdir src
    touch src/a
    touch src/b

    for ext in bz2 tz2 tbz2 tbz gz tgz taz; do
        
        # Create tarfile
        etar --create --file src.${ext} src
        [[ -e src.${ext} ]] || die "src.${ext} didn't get created properly"
        einfo "Source contents"
        find src | sort

        einfo "Tarfile contents"
        etar --list --file src.${ext} | sort

        # Unpack it
        efreshdir dst
        pushd dst
        etar --extract --file ../src.${ext} --strip-components=1
        popd

        # Ensure valid
        diff --recursive src dst
    done
}
