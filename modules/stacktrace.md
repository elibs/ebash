# Module stacktrace


## func stacktrace

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: stacktrace [option]... 

DESCRIPTION

Print stacktrace to stdout. Each frame of the stacktrace is separated by a newline. Allows you to optionally pass in a
starting frame to start the stacktrace at. 0 is the top of the stack and counts up. See also stacktrace and
error_stacktrace.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --frame, -f <value>
         Frame number to start at if not the current one

```

## func stacktrace_array

edoc v3.0.19 (2026-04-16)

SYNOPSIS

Usage: stacktrace_array [option]... array 

DESCRIPTION

Populate an array with the frames of the current stacktrace. Allows you to optionally pass in a starting frame to start
the stacktrace at. 0 is the top of the stack and counts up. See also stacktrace and eerror_stacktrace

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --frame, -f <value>
         Frame number to start at


ARGUMENTS

   array
        array

```
