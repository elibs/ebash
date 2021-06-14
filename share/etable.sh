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
etable is designed to be able to easily produce a nicely formatted ASCII, HTML or "box-drawing" or "boxart" tables with
columns and rows. The input passed into this function is essentially a variadic number of strings, where each string
represents a row in the table. Each entry provided has the columns encoded with a vertical pipe character separating
each column.

For example, suppose you wanted to produce this ASCII table:

```
+------+-------------+-------------+
| Repo | Source      | Target      |
+------+-------------+-------------+
| api  | develop-2.5 | release-2.5 |
| os   | release-2.4 | develop-2.5 |
| ui   | develop-2.5 | release-2.5 |
+------+-------------+-------------+
```

The raw input you would need to pass is as follows:

```shell
bin/etable "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"
```

This can be cumbersome to create, so there are helper methods to make this easier. For example:

```shell
array_init_nl table "Repo|Source|Target"
array_add_nl  table "api|develop-2.5|release-2.5"
array_add_nl  table "os|develop-2.4|release-2.5"
array_add_nl  table "ui|develop-2.5|release-2.5"
etable "${table[@]}"
```

You can also optionally get a line separating each row, via:

```shell
$ etable --rowlines "${table[@]}"
+------+-------------+-------------+
| Repo | Source      | Target      |
+------+-------------+-------------+
| api  | develop-2.5 | release-2.5 |
|------|-------------|-------------|
| os   | release-2.4 | develop-2.5 |
|------|-------------|-------------|
| ui   | develop-2.5 | release-2.5 |
+------+-------------+-------------+
```

If instead you wanted to produce an HTML formatted table, you would use the exact same input as above only you would
pass in `--style=html` usage flag. This would produce:

```
$ etable --style=html "${table[@]}"
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
```

Finally, etable also supports box-drawing boxart characters instead of ASCII

```shell
$ bin/etable --style=boxart --rowlines "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"

┌──────┬─────────────┬─────────────┐
│ Repo │ Source      │ Target      │
├──────┼─────────────┼─────────────┤
│ api  │ develop-2.5 │ release-2.5 │
├──────┼─────────────┼─────────────┤
│ os   │ release-2.4 │ develop-2.5 │
├──────┼─────────────┼─────────────┤
│ ui   │ develop-2.5 │ release-2.5 │
└──────┴─────────────┴─────────────┘
```

Or without rowlines:

```shell
$ bin/etable --style=boxart "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"

┌──────┬─────────────┬─────────────┐
│ Repo │ Source      │ Target      │
├──────┼─────────────┼─────────────┤
│ api  │ develop-2.5 │ release-2.5 │
│ os   │ release-2.4 │ develop-2.5 │
│ ui   │ develop-2.5 │ release-2.5 │
└──────┴─────────────┴─────────────┘
```
END
etable()
{
    $(opt_parse \
        ":style            | Table style (ascii, html, boxart). Default=ascii." \
        "+rowlines         | Display a separator line in between each row." \
        "+headers=1        | Display column headers." \
        "+headers_delim=1  | Display column headers delimiter." \
        ":title            | Table title to display." \
        "+column_delim=1   | Display column delimiters." \
        "columns           | Column headers for the table. Each column should be separated by a vertical pipe character." \
        "@entries          | Array of encoded rows and columns. Each entry in the array is a single row in the table. Within
                             a single entry, the columns are separated by a vertical pipe character.")

    # Default style is ascii
    : ${style:=ascii}

    if [[ ${headers} -eq 0 ]]; then
        headers_delim=0
    fi

    #  Generate table using internal function
    if [[ ${style} == "html" ]]; then
        __etable_internal_html
    elif [[ "${style}" == @(ascii|boxart) ]]; then
        __etable_internal_ascii
    else
        die "Unsupported $(lval style)"
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
    local column_indexes=()

    # First iterate over all the column headers and all the rows and figure out the longest value in each column.
    for line in "${columns}" "${entries[@]}"; do
        array_init parts "${line}" "|"
        local idx=0
        for part in "${parts[@]}"; do
            part_len=$(echo -n "${part}" | noansi | wc -c)
            [[ ${part_len} -gt ${lengths[$idx]:-} ]] && lengths[$idx]=${part_len}
            idx=$((idx+1))
        done
    done

    # Figure out what symbols to use
    declare -A symbols=()
    if [[ ${style} == "boxart" ]]; then
        symbols[bottom_left]="└"
        symbols[bottom_right]="┘"
        symbols[bottom_tee]="┴"
        symbols[horizonal_line]="─"
        symbols[left_tee]="├"
        symbols[middle_tee]="┼"
        symbols[right_tee]="┤"
        symbols[top_left]="┌"
        symbols[top_right]="┐"
        symbols[top_tee]="┬"
        symbols[vertical_line]="│"
    else
        symbols[bottom_left]="+"
        symbols[bottom_right]="+"
        symbols[bottom_tee]="+"
        symbols[horizonal_line]="-"
        symbols[left_tee]="|"
        symbols[middle_tee]="+"
        symbols[right_tee]="+"
        symbols[top_left]="+"
        symbols[top_right]="+"
        symbols[top_tee]="+"
        symbols[vertical_line]="|"
    fi

    local divider="${symbols[top_left]}"
    local divider_len=0
    array_init parts "${columns}" "|"
    column_indexes=$(array_indexes parts)
    local idx=0

    local len=0
    for idx in ${column_indexes[@]}; do
        len=$((lengths[$idx]+2))
        (( divider_len += len ))

        if [[ $(( idx+1 )) -eq $(array_size parts) ]]; then
            divider+=$(printf "%${len}s${symbols[top_right]}" | sed -e "s| |${symbols[horizonal_line]}|g")
        else
            divider+=$(printf "%${len}s${symbols[top_tee]}"   | sed -e "s| |${symbols[horizonal_line]}|g")
        fi
    done

    if [[ -n "${title}" ]]; then

        if [[ ${style} == "ascii" ]]; then
            printf "== ${title} ==\n\n%s\n" "${divider}"
        else
            local title_nocolor
            title_nocolor=$(echo "${title}" | noansi)

            # Offset needs to be adjusted depending on if the title is even or odd number of characters.
            local offset
            if [[ ${#title_nocolor}%2 -eq 0 ]]; then
                offset=4
            else
                offset=3
            fi

            len=$(( ${divider_len} - ${#title_nocolor} - ${offset} ))

            printf "╒══__TITLE__%${len}s ══╕\n" | sed -e "s| |═|g" -e "s|__TITLE__| ${title} |"

            if [[ ${headers_delim} -eq 1 ]]; then
                printf "${divider}\n" | sed \
                    -e "s|${symbols[top_left]}|${symbols[left_tee]}|" \
                    -e "s|${symbols[top_right]}|${symbols[right_tee]}|"
            else
                printf "${symbols[vertical_line]}%$(( divider_len + 4 ))s${symbols[vertical_line]}\n"
            fi
        fi

    else
        printf "%s\n" ${divider}
    fi

    # Now iterate over each row and print each row and it's row delimiter.
    local lnum=0
    for line in "${columns}" "${entries[@]}"; do

        if [[ ${lnum} -eq 0 && ${headers} -eq 0 ]]; then
            ((lnum+=1))
            continue
        fi

        # Split this row on the column delimiter and then iterate over each part and print it padded out to the right
        # width.
        array_init parts "${line}" "|"
        printf "${symbols[vertical_line]}"

        local idx=0
        for idx in ${column_indexes[@]}; do
            part=${parts[$idx]:-}
            part_len=$(echo -n "${part}" | noansi | wc -c)
            pad=$(( lengths[$idx] - part_len + 1 ))

            if [[ ${column_delim} -eq 1 || ${idx} -eq $(( ${#parts[@]} - 1 )) ]]; then
                printf " %s%${pad}s${symbols[vertical_line]}" "${part}" " "
            else
                printf " %s%${pad}s " "${part}" " "
            fi
        done
        printf $'\n'

        # Print either header/footer delimiter if we're on the first or last row, or optionally print the row line
        # separator if requested.
        lnum=$((lnum+1))
        if [[ ${lnum} -eq 1 ]]; then

            if [[ ${style} == "ascii" ]]; then
                echo "${divider}"
            else

                if [[ ${column_delim} -eq 0 ]]; then
                    echo "${divider}" | sed -e "s/${symbols[top_tee]}/${symbols[horizonal_line]}/g" \
                                            -e "s/${symbols[top_left]}/${symbols[left_tee]}/g"  \
                                            -e "s/${symbols[top_right]}/${symbols[right_tee]}/g"
                else
                    echo "${divider}" | sed -e "s/${symbols[top_tee]}/${symbols[middle_tee]}/g" \
                                            -e "s/${symbols[top_left]}/${symbols[left_tee]}/g"  \
                                            -e "s/${symbols[top_right]}/${symbols[right_tee]}/g"
                fi
            fi

        elif [[ ${lnum} -eq $(( ${#entries[@]} + 1 )) ]]; then

            if [[ ${column_delim} -eq 0 ]]; then
                echo "${divider}" | sed -e "s/${symbols[top_tee]}/${symbols[horizonal_line]}/g" \
                                        -e "s/${symbols[top_left]}/${symbols[bottom_left]}/g"   \
                                        -e "s/${symbols[top_right]}/${symbols[bottom_right]}/g"
            else
                echo "${divider}" | sed -e "s/${symbols[top_tee]}/${symbols[bottom_tee]}/g"     \
                                        -e "s/${symbols[top_left]}/${symbols[bottom_left]}/g"   \
                                        -e "s/${symbols[top_right]}/${symbols[bottom_right]}/g"
            fi

        elif [[ ${rowlines} -eq 1 ]]; then
            echo "${divider}" | sed -e "s/${symbols[top_left]}/${symbols[left_tee]}/g"  \
                                    -e "s/${symbols[top_tee]}/${symbols[middle_tee]}/g" \
                                    -e "s/${symbols[top_right]}/${symbols[right_tee]}/g"
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

opt_usage etable_values <<'END'
etable_values is a special-purpose wrapper around etable which makes it easier to create an etable with a provided list
of values and formats it into two columns, one showing the KEY and one showing the VALUE. For each variable, if it is a
string or an array it will be expanded into the value as you'd expect. If the variable is an associative array or a
pack, the keys and values will be unpacked and displayed in the KEY/VALUE columns in an exploded manner. This function
relies on print_value() for pretty printing arrays.

For example:

```shell
$ etable_values HOME USER
+------+----------------+
| Key  | Value          |
+------+----------------+
| HOME | /home/marshall |
| USER | marshall       |
+------+----------------+
```

If you have an associative array:

```shell
$ declare -A data([key1]="value1" [key2]="value2")
$ etable_values data
+------+--------+
| Key  | Value  |
+------+--------+
| key1 | value1 |
| key2 | value2 |
+------+--------+
```

With a pack:

```shell
$ pack_set data key1="value1" key2="value2"
$ etable_values %data

+------+--------+
| Key  | Value  |
+------+--------+
| key1 | value1 |
| key2 | value2 |
+------+--------+
```

Similar to ebanner there is an --uppercase and a --lowercase if you want to have all the keys in all uppercase or
lowercase for consistency.
END
etable_values()
{
    local default_columns="Key|Value"
    $(opt_parse \
        ":style          | Table style (ascii, html, boxart). Default=ascii."         \
        "+rowlines       | Display a separator line in between each row."             \
        "+column_delim=1 | Display column delimiters."                                \
        ":columns        | Column headers for the table (default=${default_columns}." \
        "+uppercase      | Uppercase all keys for display consistency."               \
        "+lowercase      | Lowercase all keys for display consistency."               \
        "+sort=1         | Sort keys in the tabular output."                          \
        "@entries        | Array of variables to display the values of.")

    : ${columns:="${default_columns}"}
    local rows=()

    # Helper function to determine display key to use
    display_key()
    {
        local original_key="${1}"
        if [[ ${uppercase} -eq 1 ]]; then
            echo "${original_key^^}"
        elif [[ ${lowercase} -eq 1 ]]; then
            echo "${original_key,,}"
        else
            echo "${original_key}"
        fi
    }

    local __entry __key
    for __entry in "${entries[@]}"; do

        if is_associative_array "${__entry}"; then
            for __key in $(array_indexes_sort ${__entry}); do
                eval 'array_add_nl rows "'$(display_key ${__key})'|${'${__entry}'['${__key}']}"'
            done

        elif is_pack "${__entry}"; then
            for __key in $(pack_keys_sort ${__entry#%}); do
                array_add_nl rows "$(display_key ${__key})|$(pack_get ${__entry#%} ${__key})"
            done
        elif is_array "${__entry}"; then
            array_add_nl rows "$(display_key ${__entry})|$(print_value ${__entry})"
        else
            eval 'array_add_nl rows "'$(display_key ${__entry})'|${'${__entry}'}"'
        fi
    done

    if [[ ${sort} -eq 1 ]]; then
        array_sort rows
    fi

    # We add in the column headers after we've added all the rows so it doesn't get sorted amongst the actual rows.
    rows=( "${columns}" "${rows[@]}" )

    # Forward everything to actual etable function.
    opt_forward etable style rowlines column_delim -- "${rows[@]}"
}

