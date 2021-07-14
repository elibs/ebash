# Module efetch


## func efetch


`efetch` is used to fetch one or more URLs to an optional destination path with progress monitor and metadata
validation. Older versions of this function took either one `${url}` argument or two arguments: `${url}` and
`${destination}`. Now, this is much more powerful as it can take any abitrary number of arguments and show a detailed
progress bar with percent complete for each file instead of just an eprogress ticker.

If only one argument is provided it is the name of the remote URL which will be downloaded to `${TMPDIR}` which defaults
to `/tmp`. If two arguments are provided the first is `${url}` and the second is `${destination}`. In this case, the
`${destination}` can be an existing directory or the name of the local file to save the remote URL to inside the existing
`${destination}` directory. If more than two arguments are given, the final argument is required to be an existing local
directory to download the files to.

Just like `eprogress` the caller can set `EPROGRESS=0` to disable the progress bar emitted by `efetch`. Alternatively,
the caller can silence all the output from efetch using `--quiet`. Or, more usefully, you can redirect all the output
to an alternative output file via `--output <filename>`. In this case the `ebanner` and the per-file detailed progress
status will be sent to that output file instead. You can then background the `efetch` process and then tail the output
file and wait for the fetching to complete. To make this simpler, you can use `efetch_wait --tail <pid>`.

For example:

```shell
efetch --output efetch.output <url1> <url2> ... <destination> &
efetch_pid=$!
# ... do other stuff ...
efetch_wait --tail ${efetch_pid}
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --md5, -m
         Fetch companion .md5 file and validate fetched file's MD5 matches.

   --meta, -M
         Fetch companion .meta file and validate metadata fields using emetadata_check.

   --output, -o <value>
         Redirect all STDOUT and STDERR to the requested file.

   --public-key, -p <value>
         Path to a PGP public key that can be used to validate PGPSignature in .meta file.

   --quiet, -q
         Quiet mode. (Disable ebanner, progress and other info messages from going to STDOUT
         and STDERR).

   --style <value>
         Style used when displaying the message. You might want to use einfo, ewarn or eerror
         instead.


ARGUMENTS

   urls
         URLs to fetch. The last one in this array will be considered as the destionation
         directory.
```

## func efetch_wait


`efetch_wait` is used to wait for previously backgrounded efetch process to complete and optionally tail its output on
the console. See also `efetch`. The basic usage of these two would be:

```shell
efetch --output efetch.output <url1> <url2> ... <destination> &
efetch_pid=$!
<do other stuff>
efetch_wait --tail efetch.output ${efetch_pid}
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --delete-output
         If enabled, delete the output file being tailed to avoid caller having to do it.

   --output-file, --tail <value>
         Tail the output in the specified file.

   --progress
         Display an eprogress ticker while waiting for efetch to complete (not available with
         --tail).


ARGUMENTS

   pid
         The efetch pid to wait for.

```
