# Binary bashlint

bashlint v3.0.19 (2026-04-16)

SYNOPSIS

Usage: bashlint [option]... 

DESCRIPTION


```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Files that match this (bash-style) regular expression will not be run.

   --failfast, --break, -b
         Break on first failure.

   --filter, -f <value>
         Files that match this (bash-style) regular expression will be run.

   --git-files
         Run bashlint on all git files.

   --git-files-no-modules
         Run bashlint on all git files but skip any files contained inside git modules.

   --internal, -i
         Run all ebash internal checks. This includes checking for bash syntax errors, non-versioned ebash,
         deprecated ebash code, ambiguous return statements, combined local variable declaration and assignment
         with a subshell result, etc.

   --quiet, -q
         Make bashlint produce no output.

   --shellcheck-severity, --severity <value>
         Minimum shellcheck severity of errors to consider (error, warning, info, style).

```
