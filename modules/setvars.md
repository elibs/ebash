# Module setvars


## func setvars


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
    replace the __key__ in the file. if you require that functionality, simply use SETVARS_ALLOW_EMPTY=1 and it will
    happily allow you to replace __key__ with an empty string.

    After all variables have been expanded in the provided file, a final check is performed to see if all variables were
    set properly. It will return 0 if all variables have been successfully set and 1 otherwise.

SETVARS_WARN=(0|1)
    To aid in debugging this will display a warning on any unset variables.

OPTIONAL CALLBACK:
    You may provided an optional callback as the second parameter to this function. The callback will be called with
    the key and the value it obtained from the environment (if any). The callback is then free to make whatever
    modifications or filtering it desires and then echo the new value to stdout. This value will then be used by setvars
    as the replacement value.

```Groff
ARGUMENTS

   filename
         File to modify.

   callback
         You may provided an optional callback as the second parameter to this function. The
         callback will be called with the key and the value it obtained from the environment
         (if any). The callback is free to make whatever modifications or filtering it desires
         and then echo the new value to stdout.  This value will be used by setvars as the
         replacement value.

```
