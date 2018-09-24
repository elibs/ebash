#!/bin/bash
#
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#

opt_usage efetch <<'END'
Fetch one or more URLs to an optional destination path with progress monitor and metadata validation. Older versions
of this function took either one ${url} argument or two arguments: ${url} and ${destination}. Now, this is much more 
powerful as it can take any abitrary number of arguments and show a detailed progress bar with percent complete for
each file instead of just an eprogress ticker. 

If only one argument is provided it is the name of the remote URL which will be downloaded to ${TMPDIR} which defaults
to '/tmp'. If two arguments are provided the first is ${url} and the second is ${destination}. In this case, the 
${destination} can be an existing directory or the name of the local file to save the remote URL to inside the existing
${destination} directory. If more than two arguments are given, the final argument is required to be an existing local
directory to download the files to. In the newer multi-argument mode

You can silence all the output from efetch using `--quiet`. Or, more usefully, you can redirect all the output to
an alternative output file via `--output <filename>`. In this case the ebanner and the per-file detailed progress
status will be sent to that output file instead. You can then background the efetch process and then tail the output
file and wait for the fetching to complete. To mke this simpler, you can use `efetch_wait --tail <pid>`. For example:

efetch --output efetch.output <url1> <url2> ... <destination> & 
efetch_pid=$!
<do other stuff>
efetch_wait --tail ${efetch_pid}
END
efetch()
{
    $(opt_parse \
        "+md5 m         | Fetch companion .md5 file and validate fetched file's MD5 matches." \
        "+meta M        | Fetch companion .meta file and validate metadata fields using emetadata_check." \
        ":output o      | Redirect all STDOUT and STDERR to the requested file." \
        "+quiet q       | Quiet mode. (Disable ebanner, progress and other info messages from going to STDOUT and STDERR)." \
        ":public_key p  | Path to a PGP public key that can be used to validate PGPSignature in .meta file." \
        "@urls          | URLs to fetch. The last one in this array will be considered as the destionation directory.")

    # Optionally send all STDOUT and STDERR to an output file for caller's use
    if [[ -n "${output}" ]]; then
        mkdir -p "$(dirname "${output}")"
        > "${output}"
        if einteractive; then
            EINTERACTIVE=1
        fi
        exec &> "${output}"
    elif [[ ${quiet} -eq 1 ]]; then
        exec &>/dev/null
    fi

    ebanner --uppercase "Downloading requested URLs" md5 meta output quiet public_key urls

    local pad=0 pad_max=60
    local errors=0
    declare -A data=()
    __efetch_load_info
    __efetch_download
    __efetch_download_wait
    __efetch_check_incomplete_or_failed
    __efetch_digest_validation

    if [[ "${errors}" -eq 0 ]]; then
        einfo "Successfully fetched all files."
    else
        eerror "Failure fetching all files."
    fi

    return "${errors}"
}

# Internal helper method to load all the metadata for all the requested URLs in efetch() into an associative array of
# packs. This allows us to store a bunch of metadata on each URL we are fetching such as the filename and its destination
# path and progress file, etc., in a single place and all the functions that operate on this metadata can just use these
# variables without having them each reimplement the parsing logic.
#
# NOTE: This is an internal only method which uses the variables created by the caller to allow sharing state and to
#       avoid the overhead of needlessly calling opt_parse again.
__efetch_load_info()
{
    # Determine what our destination directory will be.
    local url destination destination_is_file=0
    if [[ "${#urls[@]}" -eq 0 ]]; then
        die "Please specify at least one URL to fetch."
    elif [[ "${#urls[@]}" -eq 1 ]]; then
        destination="${TMPDIR:-/tmp}"
    else
        destination=${urls[-1]}
        unset urls[-1]

        # Figure out if the destination path is a directory or a filename.
        if [[ -d "${destination}" ]]; then 
            destination_is_file=0
        elif [[ -d $(dirname ${destination}) ]]; then
            destination_is_file=1
            assert_eq 1 "${#urls[@]}" "$(lval destination) must be an existing directory when fetching more than 1 URL"
        else
            die "$(lval destination) must be a directory or a filename in an existing directory."
        fi
    fi

    # Process each URL and store information about it into the provided associative array of packs.
    for url in "${urls[@]}"; do
        local fname="$(basename ${url})" dest=""
        if [[ ${destination_is_file} -eq 1 ]]; then
            dest="${destination}"
        else
            dest="${destination}/${fname}"
        fi

        local timecond=""
        if [[ -f "${dest}" ]]; then
            timecond="--time-cond ${dest}"
        fi

        # Keep track of the longest file name that doesn't exist our maximum desired pad to allow us to format the
        # output nicely. The '+5' here is to account for the '.meta' suffix that we'll fetch in addition to the actual
        # file.
        if [[ $(( "${#fname}" + 5 )) -gt "${pad}" && "${#fname}" -lt "${pad_max}" ]]; then
            pad="$(( ${#fname} + 5 ))"
        fi

        # Set the pack info for this URL.
        pack_set data["${url}"]         \
            url="${url}"                \
            fname="${fname}"            \
            dest="${dest}"              \
            progress="${dest}.progress" \
            timecond="${timecond}" 

        # Also load info for the associated *.md5 and *.meta file for this URL if requested.
        for opt in md5 meta; do
            if [[ "${!opt}" -eq 1 ]]; then
                 pack_set data["${url}.${opt}"]    \
                    url="${url}.${opt}"            \
                    fname="${fname}.${opt}"        \
                    dest="${dest}.${opt}"          \
                    progress="${dest}.${opt}.progress" \
                    timecond=""
            fi
        done
    done

    if edebug_enabled; then
        for url in "${urls[@]}"; do
            edebug "$(lval %data[$url])"
        done
    fi
}

# Internal helper method to call out to curl to download all of the URLs requested in efetch. It will background a 
# call to curl for each URL requested in efetch along with `--progress` flag so that we get a nice ticker showing
# percent complete of each file. This is all redirected to the progress file for each URL. We store the PID off of the
# backgrounded process so we can wait on them in __efetch_download_wait.
#
# NOTE: This is an internal only method which uses the variables created by the caller to allow sharing state and to
#       avoid the overhead of needlessly calling opt_parse again.
__efetch_download()
{
    local url=""
    for url in ${!data[@]}; do
        $(pack_import data[$url])

        # Call curl with explicit COLUMNS so that the progress bar will fit into the amount of room left on the
        # console after we print the filename.
        COLUMNS=$(( ${COLUMNS}-${pad}-1)) curl --location --fail --show-error --insecure --progress ${timecond} \
            --output "${dest}.pending" "${url}" &> "${progress}" &

        pack_set data[$url] pid=$!
    done
}

# Internal heper method to wait for all the backgrounded curl calls to complete for all the URLs requested in efetch.
# On each iteration of the loop in this function it will print the file name and the progress file output from curl.
# Then it will move back up to the first file and print it again so that we see a nice output table of all the files
# being downloaded.
#
# NOTE: This is an internal only method which uses the variables created by the caller to allow sharing state and to
#       avoid the overhead of needlessly calling opt_parse again.
__efetch_download_wait()
{
    ecolor hide_cursor
    trap_add "ecolor clear_to_eol" 
    trap_add "ecolor show_cursor"

    local finished=()
    while [[ ${#finished[@]} -lt ${#data[@]} ]]; do
        
        local url
        for url in ${!data[@]}; do
            $(pack_import data[$url])

            # This is where all the pretty output formatting happens. We basically move the cursor to the start of the
            # line, then print the filename followed by the progress bar curl is writing out to the progress file. That
            # file has a bunch of control characters in it to move the cursor around. We don't want to display all of 
            # that as it messes up our output since we are already in a loop. So we just grab the very last line from
            # the progress file and display that as that is the current status line for that file.
            ecolor start_of_line
            local status=$(cat ${progress} | sed 's|[[:cntrl:]]|\n|g' | tail -1)
            printf "%-${pad}s %s\n" "$(string_truncate -e ${pad} ${fname})" "${status}"
        
            # update the result of this fetch to either "failed" or "passed"
            if ! array_contains finished ${pid} && process_not_running ${pid}; then
                if ! wait "${pid}"; then
                    pack_set data[$url] result="failed"
                else
                    pack_set data[$url] result="passed"
                fi

                finished+=( ${pid} )
            fi
        done

        # If we aren't done, move the cursor back up to prepare for the next iteration.
        if [[ ${#finished[@]} -lt ${#data[@]} ]]; then
            tput cuu ${#data[@]}
        fi

    done

    ecolor show_cursor
}

# Internel helper method to check if any of the fetch jobs were incomplete or failed. If they were successful then it
# moves the *.pending file to its final destination. If it failed, then we remove the incomplete file as well as its
# *.md5 and *.meta file.
#
# NOTE: This is an internal only method which uses the variables created by the caller to allow sharing state and to
#       avoid the overhead of needlessly calling opt_parse again.
__efetch_check_incomplete_or_failed()
{
    # Move files to their final destinations or remove pending files for failed downloads
    einfo "Checking for incomplete or failed downloads"
    local url
    for url in ${!data[@]}; do
        $(pack_import data[$url])

        einfos "${fname}"

        if [[ "${result}" == "failed" ]]; then
            eend 1
            rm --verbose --force ${dest}{,.md5,meta}.pending
            (( errors += 1 ))
        else
            eend 0
            
            if [[ -e "${dest}.pending" ]]; then
                mv "${dest}.pending" "${dest}"
            else
                # If curl succeeded, but the file wasn't created, then the remote file was an empty file. This was a
                # bug in older versions of curl that was fixed in newer versions. To make the old curl match the new
                # curl behavior, simply touch an empty file if one doesn't exist.
                # See: https://github.com/curl/curl/issues/183
                edebug "Working around old curl bug #183 wherein empty files are not properly created."
                touch "${dest}"
            fi

            assert_exists "${dest}"
        fi
    done
}

# Internel helper method to validate the files we downloaded against companion md5 or our newer more powerful *.meta 
# files which includes optional PGP signature validation. If any files we downloaded are corrupt then they are deleted. 
#
# NOTE: This is an internal only method which uses the variables created by the caller to allow sharing state and to
#       avoid the overhead of needlessly calling opt_parse again.
__efetch_digest_validation()
{
    if [[ ${md5} -eq 0 && ${meta} -eq 0 ]]; then
        return 0
    fi

    local url
    for url in ${!data[@]}; do
        $(pack_import data[$url])

        if [[ "${dest##*.}" == @(md5|meta) ]]; then
            continue
        fi

        try
        {
            if [[ "${md5}" -eq 1 ]]; then
                opt_forward emd5sum_check quiet -- "${dest}"
            fi
            
            if [[ "${meta}" -eq 1 ]]; then
                opt_forward emetadata_check quiet public_key -- "${dest}"
            fi
        }
        catch
        {
            (( errors +=1 ))
            eerror "Removing corrupt files"
            rm --verbose --force ${dest}{,.md5,.meta}
        }
    done
}

opt_usage efetch_wait <<'END'
Wait for previously backgrounded efetch process to complete and optionally tail its output on the console.
See also `efetch`. The basic usage of these two would be:

efetch --output efetch.output <url1> <url2> ... <destination> & 
efetch_pid=$!
<do other stuff>
efetch_wait --tail efetch.output ${efetch_pid}
END
efetch_wait()
{
    $(opt_parse \
        ":output_file tail | Tail the output in the specified file." \
        "+progress         | Display an eprogress ticker while waiting for efetch to complete (not available with --tail)." \
        "pid               | The efetch pid to wait for.")

    trap_add "ekill ${pid}"
    local tail_pid=""
    if [[ -n "${output_file}" ]]; then
        tail --lines +1 --follow --pid "${pid}" "${output_file}" &
        tail_pid=$!
    fi

    # Wait for tail to complete. That process will stop gracefully when the process we are tailing exits.
    if [[ -n "${tail_pid}" ]]; then
        wait ${tail_pid}
    else

        if [[ "${progress}" -eq 1 ]]; then
            eprogress "Waiting for efetch $(lval pid) to complete"
        fi

        # Wait for the process to complete. We can't just call wait because we are usually not the direct ancestor of
        # the efetch process. So instead we have to probe waiting for it to complete.
        while process_running "${pid}"; do
            sleep 1
        done

        echo ">> DONE" >> foo.txt

        #{
        #ekill ${pid} #&>/dev/null
        #wait ${pid} #&> /dev/null || true
        #} >> foo.txt 

        if [[ "${progress}" -eq 1 ]]; then
            eprogress_kill
        fi
    fi
}

