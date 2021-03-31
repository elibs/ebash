#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# Type Helpers
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage is_int <<'END'
Returns success (0) if the input string is an integer and failure (1) otherwise. May have a leading '-' or '+' to
indicate the number is negative or positive. This does NOT handle floating point numbers. For that you should instead
use is_num.
END
is_int()
{
    [[ "${1}" =~ ^[-+]?[0-9]+$ ]]
}

opt_usage is_num <<'END'
Returns success (0) if the input string is a number and failure (1) otherwise. May have a leading '-' or '+' to indicate
the number is negative or positive. Unlike is_integer, this function properly handles floating point numbers.

is_num at present does not handle fractions or exponents or numbers is other bases (e.g. hex). But in the future we may
add support for these as needed. As such we decided not to limit ourselves with calling this just is_float.
END
is_num()
{
    [[ "${1}" =~ ^[-+]?[0-9]+\.?[0-9]*$ ]]
}

opt_usage is_array <<'END'
Returns success (0) if the variable name provided refers to an array and failure (1) otherwise.

For example:

```shell
arr=(1 2 3)
is_array arr
# returns: 0 (success)
```

In the above example notice that we use `is_array arr` and not `is_array ${arr}`.
END
is_array()
{
    [[ "$(declare -p $1 2>/dev/null)" =~ ^declare\ -a ]]
}

opt_usage is_associative_array <<'END'
Returns success (0) if the variable name provided refers to an associative array and failure (1) otherwise.

For example:

```shell
declare -A data
data[key]="value"
is_associative_array data
# returns: 0 (success)
```

In the above example notice that we use `is_associative_array data` and not `is_associative_array ${data}`.
END
is_associative_array()
{
    [[ "$(declare -p $1 2>/dev/null)" =~ ^declare\ -A ]]
}

opt_usage is_pack <<'END'
Returns success (0) if the variable name provided refers to a pack and failure (1) otherwise.

For example:

```shell
declare mypack=""
pack_set mypack a=foo b=bar
is_pack mypack
# returns: 0 (success)
```
In the above example notice that we use `is_pack mypack` and not `is_pack ${mypack}`.
END
is_pack()
{
    # Detecting packs relies on the ebash convention of "if the first character of the name is a %, consider it a pack"
    [[ "${1:0:1}" == '%' ]]
}

opt_usage is_function <<'END'
Returns success (0) if the variable name provided refers to a function and failure (1) otherwise.

For example:

```shell
foo() { echo "foo"; }
is_function foo
# returns: 0 (success)
```
END
is_function()
{
    if [[ $# != 1 ]] ; then
        die "is_function takes only a single argument but was passed $@"
    fi

    declare -F "$1" &>/dev/null
}

opt_usage discard_qualifiers <<'END'
This is an internal function used by ebash to strip off various type qualifiers from variables.
END
__discard_qualifiers()
{
    echo "${1##%}"
}
