#!/usr/bin/env bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#-----------------------------------------------------------------------------------------------------------------------
opt_usage module_conf <<'END'
The conf module operates on INI configuration files. These are supported by many different tools and languages.
Sometimes the rules vary a little. This implementation is based on [wikipedia's](https://en.wikipedia.org/wiki/INI_file)
description of the INI format.

These typically look something like the following:

```INI
[section]
property=value

[another_section]
property=different value
another_property=value
```

Where a sequence of "properties" are stored in sections. There may be properties of the same name in different sections
with different values. In this implementation, values that are not in a named section will be placed in a section named
"default"

You may specify multiple configuration files, in which case files that are *later* in the list will override the
settings from configuration files specified earlier in the list. In other words, if you call `conf_read` like this,
settings from `~/.config/A` will override those in `/etc/A` and all results will be stored in `CONF`

```bash
declare -A CONF
conf_read CONF /etc/A ~/.config/A
```

Here the the details of the INI specification from wikipedia's description that ebash implements:

### Comments

- Both ; and # at the beginning of a line start a comment.
- You can't create comments at the end of a line. Instead, whatever is on the line past the equal sign will become part
  of the property created on that line

### Sections

- Section names may not contain whitespace, nor may they contain equal signs or periods.
- Section names are case sensitive.
- No section is required, properties without a section declaration are placed in "default"

### Properties

- Property names may not contain whitespace, nor may they contain equal signs
- Property names are case sensitive.
- Whitespace around the name is ignored.
- Values cannot contain newlines. Whitespace is stripped from the ends, but retained within the value
- Values can be surrounded by single or double quotes, in which case there must only be two of that particular quote
  character on the line. No escaping is allowed.
- When quoted, all whitespace in the value within the quotes is retained. This doesn't change that values cannot contain
  newlines.
END
#-----------------------------------------------------------------------------------------------------------------------

opt_usage conf_read <<END
Reads one or more "INI"-style configuration file into an associative array that you have prepared in advance. Keys in
the associative array will be named for the sections of your INI file, and the entry will be a pack containing all
configuration values from inside that section.
END
conf_read()
{
    $(opt_parse \
        "__conf_store | Name of the associative array to store configuration in. This must be previously declared and
                        existing contents will be overwritten." \
        "@files       | Configuration files that should be read in. Settings from files later in the list will override
                        those earlier in the list.")


    if array_empty files ; then
        die "Must specify at least one config file to read."
    fi

    local filename
    for filename in "${files[@]}" ; do

        # Skip any non-existent files or directories.
        if [[ ! -f "${filename}" ]]; then
            continue
        fi

        local line_count=0
        local section="default"

        # NOTE: read strips whitespace off left and right of string
        while read line ; do
            (( line_count += 1 ))

            # NOTE: Present implementation supports full line comments, but not comments at the end of lines. I don't
            # know whether it should or not.

            # Ignore blanks and comments (which start with either # or ; )
            if [[ ${line} == "" || ${line} == [\;\#]* ]] ; then
                continue

            # Start a new section
            elif [[ ${line} =~ ^\[(.*)\]$ ]] ; then
                section=${BASH_REMATCH[1]}

            # Read a property
            elif [[ ${line} =~ ^([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$ ]] ; then
                local key=${BASH_REMATCH[1]}
                local value=${BASH_REMATCH[2]}

                # If surrounded by double quotes, strip them off
                if [[ ${value} =~ ^\"(.*)\"$ ]] ; then
                    value=${BASH_REMATCH[1]}
                    [[ ${value} != *\"* ]] || die "Property ${key} contains unmatched double quotes."

                # If surrounded by single quotes, strip them off
                elif [[ ${value} =~ ^\'(.*)\'$ ]] ; then
                    value=${BASH_REMATCH[1]}
                    [[ ${value} != *\'* ]] || die "Property ${key} contains unmatched single quotes."
                fi

                edebug "$(lval filename section key value)"
                pack_set ${__conf_store}["$section"] ${key}="${value}"

            else
                die "Invalid configuration at ${filename}:${line_count}: ${line}"
            fi

        done < ${filename}
    done
}

opt_usage conf_get <<'END'
Read a particular configuration value out of a configuration store that has already been read from disk with conf_read.
END
conf_get()
{
    $(opt_parse \
        "__conf_store | Associative array variable that conf_read filled with configuration data." \
        "property     | Property of the form 'section.key'. If no section is specified 'default' is assumed.")

    local section=default
    local key=${property}
    if [[ ${property} == *.* ]] ; then
        section=${key%%.*}
        key=${key#*.}
    fi

    pack_get "${__conf_store}[$section]" "${key}"
}

opt_usage conf_contains <<'END'
Determine whether a configuration store that conf_read extracted from file contains a particular configuration property.
END
conf_contains()
{
    $(opt_parse \
        "__conf_store | Associative array variable that conf_read filled with configuration data." \
        "property     | Property of the form 'section.key'. If no section is specified 'default' is assumed.")

    local section=default
    local key=${property}
    if [[ ${property} == *.* ]] ; then
        section=${key%%.*}
        key=${key#*.}
    fi

    pack_contains "${__conf_store}[$section]" "${key}"
}

opt_usage conf_set <<'END'
Set a value in an INI-style configuration file.
END
conf_set()
{
    $(opt_parse \
        ":file f    | Config file that should be modified. Required." \
        "+pretend p | Don't actually modify the file. Just print what it would end up containing." \
        "+unset u   | Remove the property and value from the configuration file." \
        "+compact c | Use a more compact format for properties. Without this option enabled, it emits 'key = value'
                      but with this option it emits a more compact 'key=value'." \
        "property   | The config property to set in the form 'section.key'. If no section is specified, default is
                      assumed. Note that it is fine for the property name to contain additional periods. The first
                      separates section from key, but the rest are assumed to be part of the key name." \
        "?value     | New value to give the property.")

    argcheck file

    local output=""
    local done=0
    local current_section="default"
    local line_count=0

    local section=default
    local key=${property}
    if [[ ${property} == *.* ]] ; then
        section=${key%%.*}
        key=${key#*.}
    fi

    local pad=" "
    if [[ ${compact} -eq 1 ]]; then
        pad=""
    fi

    while read line ; do

        (( line_count += 1 ))

        if [[ ${done} -eq 1 ]] ; then
            output+="${line}"$'\n'
            continue
        fi

        # NOTE: Present implementation supports full line comments, but not comments at the end of lines. I don't know
        # whether it should or not.

        # Ignore blanks and comments (which start with either # or ; )
        if [[ ${line} == "" || ${line} == [\;\#]* ]] ; then
            output+="${line}"$'\n'
            continue

        # Found a new section
        elif [[ ${line} =~ ^\[(.*)\]$ ]] ; then

            # Before leaving a section, see if we need to write the new value to this section
            if [[ ${section} == ${current_section} ]] ; then
                output+="${key}${pad}=${pad}${value}"$'\n'
                done=1
            fi

            output+="${line}"$'\n'
            current_section=${BASH_REMATCH[1]}

        # Is that exact property in the file?
        elif [[ ${line} =~ ^([^=[:space:]]+)[[:space:]]*=.*$ ]] ; then

            local this_key=${BASH_REMATCH[1]}

            if [[ ${section} == ${current_section} && ${this_key} == ${key} ]] ; then

                if [[ ${unset} -eq 0 ]] ; then
                    output+="${key}${pad}=${pad}${value}"$'\n'
                fi
                done=1

            else
                output+="${line}"$'\n'
            fi

        else
            die "Invalid configuration at ${file}:${line_count}: ${line}"
        fi

    done < ${file}

    # If the section wasn't encountered or it was the last section and we never wrote to it
    if [[ ${done} -eq 0 && ${unset} != 1 ]] ; then

        if [[ ${section} != ${current_section} ]] ; then
            local prefix=""
            if [[ ${line_count} -gt 0 ]]; then
                prefix=$'\n'
            fi

            output+="${prefix}[${section}]"$'\n'
        fi
        output+="${key}${pad}=${pad}${value}"$'\n'
    fi

    if (( pretend == 0 )) ; then
        printf "%s" "${output}" > ${file}
    else
        printf "%s" "${output}"
    fi
}

opt_usage conf_dump <<'END'
Display an entire configuration in a form that could be written to a file and re-read as a new configuration. Note that
when we read and store a configuration, the comments are dropped so if you used this to re-create a configuration file
you trash all of the comments.

Use conf_set to modify a configuration file without blowing away comments.
END
conf_dump()
{
    $(opt_parse "__conf_store | Variable containing the configuration data.")

    for key in $(array_indexes_sort ${__conf_store}) ; do
        echo "[$key]"
        pack_iterate _conf_dump_helper "${__conf_store}[$key]"
        echo ""
    done
}

_conf_dump_helper()
{
    printf "%s = %s\n" "$1" "$2"
}

opt_usage conf_secitons <<'END'
List the sections defined within a configuration.
END
conf_sections()
{
    $(opt_parse "__conf_store | Variable containing the configuration data.")

    echo $(array_indexes_sort ${__conf_store})
}

opt_usage conf_props <<'END'
List the properties defined within a named section within a configuration.
END
conf_props()
{
    $(opt_parse \
        "__conf_store | Associative array variable that conf_read filled with configuration data."              \
        "?section     | Section name to enumerate props from. If no section is specified 'default' is assumed." \
    )

    if [[ -z "${section}" ]]; then
        section="default"
    fi

    pack_keys "${__conf_store}[$section]"
}

opt_usage conf_to_json  <<'END'
conf_to_json converts the named configuration to an anonymous JSON object. Each named section in the configratuion will
be a top-level named JSON object. Each property inside that section will then be a series of '"key": "value"' pairs in
the JSON. By defualt, all the properties are displayed as quoted strings. But this can be controlled via --props-int to
not quote the values as they are known to be integers. Alternatively the properties can be automatically split on
whitespace and printed as a JSON array.

For some detailed examples see `tests/conf.etest`:

ETEST_conf_to_json
ETEST_conf_to_json_int
ETEST_conf_to_json_array
...
END
conf_to_json()
{
    $(opt_parse \
        "+props_int   | Display all props as ints instead of strings." \
        "+props_array | Split all props into arrays."                  \
        "__conf_store | Variable containing the configuration data."   \
    )

    {
        echo "{"

        local idx=0
        local idx_last=$(( $(array_size ${__conf_store}) - 1 ))

        for key in $(array_indexes_sort ${__conf_store}) ; do
            echo '"'${key}'": {'
            pack_iterate _conf_json_helper "${__conf_store}[$key]" | sed 's|,$||'

            if [[ "${idx}" -lt "${idx_last}" ]]; then
                echo "},"
            else
                echo "}"
            fi

            (( idx += 1 ))

        done

        echo "}"

    } | jq .
}

_conf_json_helper()
{
    if [[ "${props_array}" -eq 1 ]]; then
        local parts=()
        array_init parts "$2"
        printf '"%s": %s,' "$1" "$(array_to_json parts)"
    elif [[ "${props_int}" -eq 1 ]]; then
        printf '"%s": %s,' "$1" "$2"
    else
        printf '"%s": "%s",' "$1" "$2"
    fi
}
