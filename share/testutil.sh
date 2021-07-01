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
Skip an etest if the provided condition is true.

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
    echo "eval if ${@}; then ewarn \"Skipping ${FUNCNAME[1]} because '${@}'\"; return 0; fi"
}
