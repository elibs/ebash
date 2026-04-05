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
    local output=""

    # Fast visible length calculation - avoids subshells when no ANSI codes present
    __visible_len()
    {
        local text="$1"
        if [[ "$text" != *$'\e'* ]]; then
            # No ANSI codes - just return length (handles UTF-8 correctly with ${#})
            echo ${#text}
        else
            # Has ANSI codes - strip them first
            local stripped
            stripped="${text//$'\e'\[*([0-9;])m/}"
            echo ${#stripped}
        fi
    }

    # First iterate over all the column headers and all the rows and figure out the longest value in each column.
    for line in "${columns}" "${entries[@]}"; do
        array_init parts "${line}" "|"
        local idx=0
        for part in "${parts[@]}"; do
            part_len=$(__visible_len "${part}")
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

    local len=0 hline=""
    for idx in ${column_indexes[*]}; do
        len=$((lengths[$idx]+2))
        (( divider_len += len ))

        # Build horizontal line segment without subshell
        printf -v hline '%*s' "$len" ""
        hline="${hline// /${symbols[horizonal_line]}}"

        if [[ $(( idx+1 )) -eq $(array_size parts) ]]; then
            divider+="${hline}${symbols[top_right]}"
        else
            divider+="${hline}${symbols[top_tee]}"
        fi
    done

    # Pre-compute all divider variations using bash string replacement (avoid sed subshells)
    local divider_title divider_title_no_delim divider_header divider_header_no_delim divider_footer divider_footer_no_delim divider_row
    # Title divider (after title, before column headers) - keeps ┬
    divider_title="${divider//${symbols[top_left]}/${symbols[left_tee]}}"
    divider_title="${divider_title//${symbols[top_right]}/${symbols[right_tee]}}"
    # Title divider without column delimiters
    divider_title_no_delim="${divider//${symbols[top_tee]}/${symbols[horizonal_line]}}"
    divider_title_no_delim="${divider_title_no_delim//${symbols[top_left]}/${symbols[left_tee]}}"
    divider_title_no_delim="${divider_title_no_delim//${symbols[top_right]}/${symbols[right_tee]}}"
    # Header divider (after column headers) - changes ┬ to ┼
    divider_header="${divider//${symbols[top_tee]}/${symbols[middle_tee]}}"
    divider_header="${divider_header//${symbols[top_left]}/${symbols[left_tee]}}"
    divider_header="${divider_header//${symbols[top_right]}/${symbols[right_tee]}}"
    # Header divider without column delimiters
    divider_header_no_delim="${divider//${symbols[top_tee]}/${symbols[horizonal_line]}}"
    divider_header_no_delim="${divider_header_no_delim//${symbols[top_left]}/${symbols[left_tee]}}"
    divider_header_no_delim="${divider_header_no_delim//${symbols[top_right]}/${symbols[right_tee]}}"
    # Footer divider (bottom of table)
    divider_footer="${divider//${symbols[top_tee]}/${symbols[bottom_tee]}}"
    divider_footer="${divider_footer//${symbols[top_left]}/${symbols[bottom_left]}}"
    divider_footer="${divider_footer//${symbols[top_right]}/${symbols[bottom_right]}}"
    # Footer without column delimiters
    divider_footer_no_delim="${divider//${symbols[top_tee]}/${symbols[horizonal_line]}}"
    divider_footer_no_delim="${divider_footer_no_delim//${symbols[top_left]}/${symbols[bottom_left]}}"
    divider_footer_no_delim="${divider_footer_no_delim//${symbols[top_right]}/${symbols[bottom_right]}}"
    # Row divider (between rows)
    divider_row="${divider_header}"

    if [[ -n "${title}" ]]; then

        if [[ ${style} == "ascii" ]]; then
            output+="== ${title} =="$'\n\n'"${divider}"$'\n'
        else
            local title_nocolor title_line title_padding
            # Strip ANSI without subshell if possible
            if [[ "$title" != *$'\e'* ]]; then
                title_nocolor="$title"
            else
                title_nocolor="${title//$'\e'\[*([0-9;])m/}"
            fi

            # Use actual divider width (includes column separators) minus title and fixed frame chars
            # Fixed chars: ╒══(3) + space(1) + space(1) + ══╕(3) = 8
            len=$(( ${#divider} - ${#title_nocolor} - 8 ))

            # Build title line without subshell
            printf -v title_padding '%*s' "$len" ""
            title_padding="${title_padding// /═}"
            output+="╒══ ${title} ${title_padding}══╕"$'\n'

            if [[ ${headers_delim} -eq 1 ]]; then
                output+="${divider_title}"$'\n'
            else
                local blank_line
                printf -v blank_line '%*s' "$(( divider_len + 4 ))" ""
                output+="${symbols[vertical_line]}${blank_line}${symbols[vertical_line]}"$'\n'
            fi
        fi

    else
        output+="${divider}"$'\n'
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
        output+="${symbols[vertical_line]}"

        local idx=0
        for idx in ${column_indexes[*]}; do
            part=${parts[$idx]:-}
            part_len=$(__visible_len "${part}")
            pad=$(( lengths[$idx] - part_len + 1 ))

            # Build padding string without subshell
            local padding=""
            printf -v padding '%*s' "$pad" ""

            if [[ ${column_delim} -eq 1 || ${idx} -eq $(( ${#parts[@]} - 1 )) ]]; then
                output+=" ${part}${padding}${symbols[vertical_line]}"
            else
                output+=" ${part}${padding} "
            fi
        done
        output+=$'\n'

        # Print either header/footer delimiter if we're on the first or last row, or optionally print the row line
        # separator if requested.
        lnum=$((lnum+1))
        if [[ ${lnum} -eq 1 ]]; then

            if [[ ${style} == "ascii" ]]; then
                output+="${divider}"$'\n'
            else
                if [[ ${column_delim} -eq 0 ]]; then
                    output+="${divider_header_no_delim}"$'\n'
                else
                    output+="${divider_header}"$'\n'
                fi
            fi

        elif [[ ${lnum} -eq $(( ${#entries[@]} + 1 )) ]]; then

            if [[ ${column_delim} -eq 0 ]]; then
                output+="${divider_footer_no_delim}"$'\n'
            else
                output+="${divider_footer}"$'\n'
            fi

        elif [[ ${rowlines} -eq 1 ]]; then
            output+="${divider_row}"$'\n'
        fi
    done

    # Print entire table at once
    printf '%s' "${output}"
}

# Internal helper version of etable to generate an HTML table
__etable_internal_html()
{
    local output=""
    output+='<table>'$'\n'
    output+='    <tbody>'$'\n'

    # Fast ANSI strip - avoids subshell when no ANSI codes
    __strip_ansi()
    {
        local text="$1"
        if [[ "$text" != *$'\e'* ]]; then
            echo "$text"
        else
            echo "${text//$'\e'\[*([0-9;])m/}"
        fi
    }

    # Column headers
    output+="        <tr>"$'\n'
    local part parts stripped
    array_init parts "${columns}" "|"
    for part in "${parts[@]}"; do
        stripped=$(__strip_ansi "$part")
        output+="            <th><p><strong>${stripped}</strong></p></th>"$'\n'
    done
    output+="        </tr>"$'\n'

    # Each row
    local line
    for line in "${entries[@]}"; do
        output+="        <tr>"$'\n'

        local part parts
        array_init parts "${line}" "|"
        for part in "${parts[@]}"; do
            stripped=$(__strip_ansi "$part")
            output+="            <td><p>${stripped}</p></td>"$'\n'
        done

        output+="        </tr>"$'\n'
    done

    # Footer
    output+="    </tbody>"$'\n'
    output+="</table>"$'\n'

    # Print entire table at once
    printf '%s' "${output}"
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

