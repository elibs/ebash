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
# String
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage to_upper_snake_case <<'END'
Convert a given input string into "upper snake case". This is generally most useful when converting a "CamelCase" string
although it will work just as well on non-camel case input. Essentially it looks for all upper case letters and puts an
underscore before it, then uppercase the entire input string.

For example:

    sliceDriveSize => SLICE_DRIVE_SIZE
    slicedrivesize => SLICEDRIVESIZE

It has some special handling for some common corner cases where the normal camel case idiom isn't well followed. The
best example for this is around units (e.g. MB, GB). Consider "sliceDriveSizeGB" where SLICE_DRIVE_SIZE_GB is preferable
to SLICE_DRIVE_SIZE_G_B.

The current list of translation corner cases this handles: KB, MB, GB, TB
END
to_upper_snake_case()
{
    $(opt_parse input)

    echo "${input}"         \
        | sed -e 's|KB|Kb|' \
              -e 's|MB|Mb|' \
              -e 's|GB|Gb|' \
              -e 's|TB|Tb|' \
        | perl -ne 'print uc(join("_", split(/(?=[A-Z])/)))'
}

opt_usage to_lower_snake_case <<'END'
Convert a given input string into "lower snake case". This is generally most useful when converting a "CamelCase" string
although it will work just as well on non-camel case input. Essentially it looks for all upper case letters and puts an
underscore before it, then lowercase the entire input string.

For example:

    sliceDriveSize => slice_drive_size
    slicedrivesize => slicedrivesize

It has some special handling for some common corner cases where the normal camel case idiom isn't well followed. The
best example for this is around units (e.g. MB, GB). Consider "sliceDriveSizeGB" where slice_drive_size_gb is preferable
to slice_drive_size_g_b.

The current list of translation corner cases this handles: KB, MB, GB, TB
END
to_lower_snake_case()
{
    $(opt_parse input)

    echo "${input}"         \
        | sed -e 's|KB|Kb|' \
              -e 's|MB|Mb|' \
              -e 's|GB|Gb|' \
              -e 's|TB|Tb|' \
        | perl -ne 'print lc(join("_", split(/(?=[A-Z])/)))'
}

string_trim()
{
    local text=$*
    text=${text%%+([[:space:]])}
    text=${text##+([[:space:]])}
    printf -- "%s" "${text}"
}

opt_usage string_truncate <<'END'
Truncate a specified string to fit within the specified number of characters. If the ellipsis option is specified,
truncation will result in an ellipses where the removed characters were (and the total string will still fit within
length characters)

Any arguments after the length will be considered part of the text to string_truncate
END
string_truncate()
{
    $(opt_parse \
        "+ellipsis e | If set, an elilipsis (...) will replace any removed text." \
        "length      | Desired maximum length for text." )

    local text=$*

    # NOTE: WE never want string_truncate to return non-zero error code as it is used inside die and other places
    # where we don't want cascading errors. Hence we append `|| true` to the commands. Also always explicitly return 0
    # from this function.
    if [[ ${#text} -gt ${length} && ${ellipsis} -eq 1 ]] ; then
        printf -- "%s" "${text:0:$((length-3))}..." || true
    else
        printf -- "%s" "${text:0:${length}}" || true
    fi

    return 0
}

opt_usage string_collapse <<'END'
Collapse grouped whitespace in the specified string to single spaces.
END
string_collapse()
{
    echo -en "$@" | tr -s "[:space:]" " "
}

opt_usage string_getline <<'END'
Helper function to make it easy to grab a specific line from a provided string. This is done using sed with '${num}q;d'.
What this does is advance to the requested line number, deleting everything it has seen in the buffer prior to the
current line, then then quits. This is significantly faster than the typical head | tail approach. The requested line
number must be > 0 or an error will be returned. Since we don't expect the caller to check the number of lines in the
input string before calling this function, this function will return an empty string if a line number is requested
beyond the length of the privided string.
END
string_getline()
{
    $(opt_parse \
        "?input | Input string to parse for the requested line number." \
        "num    | Line number to fetch from the provided input string.")

    assert_num_gt "${num}" "0" "Line number must be > 0"
    echo "${input}" | sed "${num}q;d"
}
