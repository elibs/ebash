#!/bin/bash
#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage setvars <<'END'
setvars takes a template file with optional variables inside the file which are surrounded on both sides by two
underscores. It will replace the variable (and surrounding underscores) with a value you specify in the environment.

For example, if the input file looks like this:
    Hi __NAME__, my name is __OTHERNAME__.

And you call setvars like this
    NAME=Bill OTHERNAME=Ted setvars intputfile

The inputfile will be modified IN PLACE to contain:
    Hi Bill, my name is Ted.

SETVARS_ALLOW_EMPTY=(0|1)
    By default, empty values are NOT allowed. Meaning that if the provided key evaluates to an empty string, it will NOT
    replace the __key__ in the file.  if you require that functionality, simply use SETVARS_ALLOW_EMPTY=1 and it will
    happily allow you to replace __key__ with an empty string.

    After all variables have been expanded in the provided file, a final check is performed to see if all variables were
    set properly. It will return 0 if all variables have been successfully set and 1 otherwise.

SETVARS_WARN=(0|1)
    To aid in debugging this will display a warning on any unset variables.

OPTIONAL CALLBACK:
    You may provided an optional callback as the second parameter to this function.  The callback will be called with
    the key and the value it obtained from the environment (if any). The callback is then free to make whatever
    modifications or filtering it desires and then echo the new value to stdout. This value will then be used by setvars
    as the replacement value.
END
setvars()
{
    $(opt_parse \
        "filename  | File to modify." \
        "?callback | You may provided an optional callback as the second parameter to this function. The callback will
                     be called with the key and the value it obtained from the environment (if any). The callback is
                     free to make whatever modifications or filtering it desires and then echo the new value to stdout.
                     This value will be used by setvars as the replacement value.")

    edebug "Setting variables $(lval filename callback)"
    assert_exists "${filename}"

    # If this file is a binary file skip it
    if file ${filename} | grep -q ELF ; then
        edebug "Skipping binary file $(lval filename): $(file ${filename})"
        return 0
    fi

    for arg in $(grep -o "__\S\+__" ${filename} | sort --unique || true); do
        local key="${arg//__/}"
        local val="${!key:-}"

        # Call provided callback if one was provided which by contract should print the new resulting value to be used
        [[ -n ${callback} ]] && val=$(${callback} "${key}" "${val}")

        # If we got an empty value back and empty values aren't allowed then continue.  We do NOT call die here as we'll
        # deal with that at the end after we have tried to expand all variables.
        [[ -n ${val} || ${SETVARS_ALLOW_EMPTY:-0} -eq 1 ]] || continue

        edebug "   ${key} => ${val}"

        # Put val into perl's environment and let _perl_ pull it out of that environment. This has the benefit of
        # causing it to not try to interpret any of it, but to treat it as a raw string
        VAL="${val}" perl -pi -e "s/__${key}__/\$ENV{VAL}/g" "${filename}" || die "Failed to set $(lval key val filename)"
    done

    # Check if anything is left over and return correct return value accordingly.
    if grep -qs "__\S\+__" "${filename}"; then
        local notset=()
        notset=( $(grep -o '__\S\+__' ${filename} | sort --unique | tr '\n' ' ') )
        [[ ${SETVARS_WARN:-1}  -eq 1 ]] && ewarn "Failed to set all variables in $(lval filename notset)"
        return 1
    fi

    return 0
}

return 0
