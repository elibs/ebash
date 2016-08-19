#!/usr/bin/env bash

# General doc on bashutils' interpretation of what it means to be an INI file.
declare _bu_conf_ini_doc="These typically look something like the following:

    [section]
    property=value

    [another_section]
    property=different value
    another_property=value

Where a sequence of "properties" are stored in sections.  There may be properties of the same name
in different sections with different values.  In this implementation, values that are not in a named
section will be placed in a section named "default"

You may specify multiple configuration files, in which case files that are _later_in the list will
override the settings from configuration files specified earlier in the list.  In other words, if
you call conf_read like this, settings from ~/.config/A will override those in /etc/A and all
results will be stored in CONF

    declare -A CONF
    conf_read CONF /etc/A ~/.config/A


Many different tools use INI configuration files.  Sometimes the rules vary a little.  This
implementation is based on wikipedia's description of the ini format
(https://en.wikipedia.org/wiki/INI_file) and has the following quirks:

Comments

  - Both ; and # at the beginning of a line start a comment.
  - You can't create comments at the end of a line.  Instead, whatever is on the line past the
    equal sign will become part of the property created on that line


Sections

  - Section names may contain whitespace but be careful with your quoting.
  - Section names are case sensitive.
  - No section is required, properties without a section declaration are placed in "default"


Properties

  - Property names may not contain whitespace.
  - Property names are case sensitive.
  - Whitespace around the name is ignored.
  - Values cannot contain newlines.  Whitespace is stripped from the ends, but retained within the
    value
  - Values can be surrounded by single or double quotes, in which case there must only be two of
    that particular quote character on the line.  No escaping is allowed.
  - When quoted, all whitespace in the value within the quotes is retained.  This doesn't change
    that values cannot contain newlines.

"

opt_usage conf_read<<END
Reads one or more "INI"-style configuration file into an associative array that you have prepared in
advance. Keys in the associative array will be named for the sections of your INI file, and the
entry will be a pack containing all configuration values from inside that section.

${_bu_conf_ini_doc}
END
conf_read()
{
    $(opt_parse \
        "var    | Name of the associative array to store configuration in.  This must be previously
                  declared and existing contents will be overwritten." \
        "@files | Configuration files that should be read in.  Settings from files later in the list
                  will override those earlier in the list.")


    if array_empty files ; then
        die "Must specify at least one config file to read."
    fi

    for filename in "${files[@]}" ; do

        local line_count=0
        local section="default"

        # NOTE: read strips whitespace off left and right of string
        while read line ; do
            (( line_count += 1 ))

            # NOTE: Present implementation supports full line comments, but not comments at the end of
            # lines.  I don't know whether it should or not.

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
                pack_set CONF["$section"] ${key}="${value}"

            else
                die "Invalid configuration at ${filename}:${line_count}: ${line}"
            fi

        done < ${filename}
    done
}

opt_usage conf_set<<END
Set a value in an INI-style configuration file.

${_bu_conf_ini_doc}
END
conf_set()
{
    $(opt_parse \
        ":file f            | Config file that should be modified.  Required." \
        ":section s=default | Section that contains (or should contain) the property." \
        "+pretend p         | Don't actually modify the file.  Just print what it would end up containing" \
        "key                | Name of the property to set in that file." \
        "value              | New value to give the property.")

    argcheck file

    local output=""
    local done=0
    local current_section="default"
    local line_count=0

    while read line ; do

        (( line_count += 1 ))

        if (( done == 1 )) ; then
            output+="${line}"$'\n'
            continue
        fi

        # NOTE: Present implementation supports full line comments, but not comments at the end of
        # lines.  I don't know whether it should or not.

        # Ignore blanks and comments (which start with either # or ; )
        if [[ ${line} == "" || ${line} == [\;\#]* ]] ; then
            output+="${line}"$'\n'
            continue

        # Found a new section
        elif [[ ${line} =~ ^\[(.*)\]$ ]] ; then

            # Before leaving a section, see if we need to write the new value to this section
            if [[ ${section} == ${current_section} ]] ; then
                output+="${key}=${value}"$'\n'
                done=1
            fi

            output+="${line}"$'\n'
            current_section=${BASH_REMATCH[1]}

        # Is that exact property in the file?
        elif [[ ${line} =~ ^([^=[:space:]]+)[[:space:]]*=.*$ ]] ; then

            local this_key=${BASH_REMATCH[1]}

            if [[ ${section} == ${current_section} && ${this_key} == ${key} ]] ; then
                output+="${key} = ${value}"$'\n'
                done=1

            else
                output+="${line}"$'\n'
            fi

        else
            die "Invalid configuration at ${file}:${line_count}: ${line}"
        fi

    done < ${file}

    # If the section wasn't encountered or it was the last section and we never wrote to it
    if (( done == 0 )) ; then

        if [[ ${section} != ${current_section} ]] ; then
            output+=$'\n'"[${section}]"$'\n'
        fi
        output+="${key} = ${value}"$'\n'
    fi

    if (( pretend == 0 )) ; then
        printf "%s" "${output}" > ${file}
    else
        printf "%s" "${output}"
    fi
}

unset _bu_conf_ini_doc
