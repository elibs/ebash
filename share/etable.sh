#!/bin/bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
#
# etable
#
#-----------------------------------------------------------------------------------------------------------------------

opt_usage etable <<'END'
etable is designed to be able to easily produce a nicely formatted ASCII or HTML table with columns and rows. The input
passed into this function is essentially a variadic number of strings, where each string represents a row in the table.
Each entry provided has the columns encoded with a vertical pipe character separating each column.

For example, suppose you wanted to produce this ASCII table:

    +------+-------------+-------------+
    | Repo | Source      | Target      |
    +------+-------------+-------------+
    | api  | develop-2.5 | release-2.5 |
    | os   | release-2.4 | develop-2.5 |
    | ui   | develop-2.5 | release-2.5 |
    +------+-------------+-------------+

The raw input you would need to pass is as follows:

    $ bin/etable "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"

This can be cumbersome to create, so there are helper methods to make this easier. For example:

    $ array_init_nl table "Repo|Source|Target"
    $ array_add_nl  table "api|develop-2.5|release-2.5"
    $ array_add_nl  table "os|develop-2.4|release-2.5"
    $ array_add_nl  table "ui|develop-2.5|release-2.5"
    $ etable "${table[@]}"

You can also optionally get a line separating each row, via:

    $ etable --row-lines "${table[@]}"

Which would produce:

    +------+-------------+-------------+
    | Repo | Source      | Target      |
    +------+-------------+-------------+
    | api  | develop-2.5 | release-2.5 |
    |------|-------------|-------------|
    | os   | release-2.4 | develop-2.5 |
    |------|-------------|-------------|
    | ui   | develop-2.5 | release-2.5 |
    +------+-------------+-------------+

If instead you wanted to produce an HTML formatted table, you would use the exact same input as above only you would
pass in `--html` usage flag.

<table>
    <tbody>
        <tr>
            <th><p><strong>Repo</strong></p></th>
            <th><p><strong>Source</strong></p></th>
            <th><p><strong>Target</strong></p></th>
        </tr>
        <tr>
            <td><p>api</p></td>
            <td><p>develop-2.5</p></td>
            <td><p>release-2.5</p></td>
        </tr>
        <tr>
            <td><p>os</p></td>
            <td><p>release-2.4</p></td>
            <td><p>develop-2.5</p></td>
        </tr>
        <tr>
            <td><p>ui</p></td>
            <td><p>develop-2.5</p></td>
            <td><p>release-2.5</p></td>
        </tr>
    </tbody>
</table>
END
etable()
{
    $(opt_parse \
        "+row_lines  | Display a separator line in between each row." \
        "+html       | Output resulting table as an HTML table. This strips out any ANSI color codes using noansi
                       otherwise the generated HTML is invalid." \
        "columns     | Column headers for the table. Each column should be separated by a vertical pipe character." \
        "@entries    | Array of encoded rows and columns. Each entry in the array is a single row in the table. Within
                       a single entry, the columns are separated by a vertical pipe character.")

    if [[ ${html} -eq 1 ]]; then
        __etable_internal_html
    else
        __etable_internal_ascii
    fi
}

# Internal helper version of etable to generate a normal ASCII table
__etable_internal_ascii()
{
    local lengths=()
    local parts=()
    local line
    local part
    local part_len

    # First iterate over all the column heads and all the rows and figure out the longest row in each column.
    for line in "${columns}" "${entries[@]}"; do
        array_init parts "${line}" "|"
        local idx=0
        for part in "${parts[@]}"; do
            part_len=$(echo -n "${part}" | noansi | wc -c)
            [[ ${part_len} -gt ${lengths[$idx]:-} ]] && lengths[$idx]=${part_len}
            idx=$((idx+1))
        done
    done

    # Create divider line
    local divider="+"
    array_init parts "${columns}" "|"
    local idx=0
    local len=0
    for idx in $(array_indexes parts); do
        len=$((lengths[$idx]+2))
        divider+=$(printf "%${len}s+" | sed -e 's| |-|g')
    done

    printf "%s\n" ${divider}

    # Now iterate over each row and print each row and it's row delimiter.
    local lnum=0
    for line in "${columns}" "${entries[@]}"; do

        # Split this row on the column delimiber and then iterate over each part and print it padded out to the right
        # width.
        array_init parts "${line}" "|"
        printf "|"
        local idx=0
        for idx in $(array_indexes parts); do
            part=${parts[$idx]}
            part_len=$(echo -n "${part}" | noansi | wc -c)
            pad=$((lengths[$idx]-${part_len}+1))
            printf " %s%${pad}s|" "${part}" " "
        done
        printf $'\n'

        # Print either header/footer delimiter if we're on the first or last row, or optionally print the row line
        # separator if requested.
        lnum=$((lnum+1))
        if [[ ${lnum} -eq 1 || ${lnum} -eq $(( ${#entries[@]} + 1 )) ]]; then
            printf "%s\n" ${divider}
        else
            if [[ ${row_lines} -eq 1 ]]; then
                printf "%s\n" ${divider//+/|}
            fi
        fi
    done
}

# Internal helper version of etable to generate an HTML table
__etable_internal_html()
{
    echo '<table>'
    echo '    <tbody>'

    # Column headers
    echo "        <tr>"
    local part parts
    array_init parts "${columns}" "|"
    for part in "${parts[@]}"; do
        echo "            <th><p><strong>$(echo "${part}" | noansi)</strong></p></th>"
    done
    echo "        </tr>"

    # Each row
    local line
    for line in "${entries[@]}"; do
        echo "        <tr>"

        local part parts
        array_init parts "${line}" "|"
        for part in "${parts[@]}"; do
            echo "            <td><p>$(echo "${part}" | noansi)</p></td>"
        done

        echo "        </tr>"
    done

    # Footer
    echo "    </tbody>"
    echo "</table>"
}
