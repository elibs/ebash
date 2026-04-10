#!/bin/bash
#
# Copyright 2021, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Test Util
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage skip_if <<'END'
Skip an etest if the provided condition is true. Uses exit code 77 (standard skip code) which etest detects and
tracks as a skipped test rather than a pass or fail.

Examples:

```bash
$(skip_if "os_distro centos")
$(skip_if "os_distro centos && os_release 8")
```
END
skip_if()
{
    # shellcheck disable=SC2145
    # We do not want to use $* as that doesn't preserve word splitting that we want to honor
    # Exit code 77 is the standard convention for skipped tests (used by Automake/autotools)
    # Wrap in subshell so arbitrary commands with pipes work
    echo "eval if ( ${@} ); then ewarn \"Skipping \${FUNCNAME[0]}: ${@}\" && exit 77; fi"
}

opt_usage skip_file_if <<'END'
Skip an entire etest file if the provided condition is true. When this is called at the top of a test file and the
condition evaluates to true, ALL tests in that file will be marked as skipped. The tests will still be discovered
but will not be executed.

This should be called at the top level of the test file (not inside a function) using command substitution syntax.

Examples:

```bash
$(skip_file_if "os_distro centos")
$(skip_file_if "! command_exists docker")
```
END
skip_file_if()
{
    # shellcheck disable=SC2145
    # We do not want to use $* as that doesn't preserve word splitting that we want to honor
    echo "eval if ${@}; then ewarn \"Skipping file: ${@}\"; ETEST_SKIP_FILE=1; return 0; fi"
}
