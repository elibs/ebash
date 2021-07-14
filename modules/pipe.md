# Module pipe


## func pipe_read


Helper method to read from a pipe until we see EOF.

```Groff
ARGUMENTS

   pipe
        pipe

```

## func pipe_read_quote


Helper method to read from a pipe until we see EOF and then also intelligently quote the output in a way that can be
reused as shell input via "printf %q". This will allow us to safely eval the input without fear of anything being
exectued.

> **_NOTE:_** This method will echo `""` instead of using printf if the output is an empty string to avoid causing
various test failures where we'd expect an empty string `""` instead of a string with literal quotes in it `"''"`.

```Groff
ARGUMENTS

   pipe
        pipe

```
