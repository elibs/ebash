# Binary bashlint


Analyze all the requested bash scripts in the specified directories and perform various Linting operations on them. There
are various internal checks performed by bashlint including bash syntax errors, using removed ebash code, ambiguous
return statements, and combined variable declaration and assignment errors.

Additionally, bashlint can utilize the fantastic external tool shellcheck to look for far more difficult to detect
linting errors. By default shellcheck linting is disabled. Yout can opt-in by passing in --shellcheck-severity with a
value of error, warning, info, style.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --break, -b
         Break on first failure.

   --exclude, -x <value>
         Files that match this (bash-style) regular expression will not be run.

   --filter, -f <value>
         Files that match this (bash-style) regular expression will be run.

   --git-files
         Run bashlint on all git files.

   --git-files-no-modules
         Run bashlint on all git files but skip any files contained inside git modules.

   --internal, -i
         Run all ebash internal checks. This includes checking for bash syntax errors,
         non-versioned ebash, deprecated ebash code, ambiguous return statements, combined local
         variable declaration and assignment with a subshell result, etc.

   --quiet, -q
         Make bashlint produce no output.

   --shellcheck-severity, --severity <value>
         Minimum shellcheck severity of errors to consider (error, warning, info, style).

```
