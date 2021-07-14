# Module json


## func array_to_json


Convert an array specified by name (i.e ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json array containing the same data.

```Groff
ARGUMENTS

   __array
        __array

```

## func associative_array_to_json

Convert an associative array by name (e.g. ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json object containing the same
data.

## func associative_array_to_json_split


Convert an associative array by name (e.g. ARRAY not ${ARRAY} or ${ARRAY[@]}) into a json object containing the same
data. This is similar to associative_array_to_json with some extra functionality layered ontop wherein it will split
each entry in the associative array on the provided delimiter into an array.

For example:

```shell
$ declare -A data
$ data[key1]="value1 value2 value3"
$ data[key2]="entry1 entry2 entry3"
$ associative_array_to_json_split data " " | jq .
{
    "key1": [
        "value1",
        "value2",
        "value3"
    ],
    "key2": [
        "entry1",
        "entry2",
        "entry3"
    ]
}
```

```Groff
ARGUMENTS

   input
         Name of the associative array to convert to json.

   delim
         Delimiter to place between array items. Default is a space.

```

## func file_to_json


Parse the contents of a given file and echo the output in JSON format. This function requires you to specify the format
of the file being parsed. At present the only supported format is --exports which is essentially a KEY=VALUE exports
file.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exports
         File format is an 'exports file' (e.g. KEY=VALUE).

   --lowercase
         Convert all keys to lowercase during conversion.


ARGUMENTS

   file
         Parse contents of provided file.

```

## func json_compare


Compare two json strings. This function returns diff's return code and if the json strings don't compare the diff
will be printed to stdout.

```Groff
ARGUMENTS

   first
        first

   second
        second

```

## func json_compare_files


Compare two json files. The files can only contain a single json object.

```Groff
ARGUMENTS

   left
        left

   right
        right

```

## func json_escape

Escape an arbitrary string (specified as $1) so that it is quoted and safe to put inside json. This is done via a call
to jq with --raw-input which will cause it to emit a properly quoted and escaped string that is safe to use inside
json.

## func json_import


Import all of the key:value pairs from a non-nested Json object directly into the caller's environment as proper bash
variables. By default this will import all the keys available into the caller's environment. Alternatively you can
provide an optional list of keys to restrict what is imported. If any of the explicitly requested keys are not present
this will be interpreted as an error and json_import will return non-zero. Keys can be marked optional via the '?'
prefix before the key name in which case they will be set to an empty string if the key is missing.

Similar to a lot of other  methods inside ebash, this uses the "eval command invocation string" idom. So, the proper
calling convention for this is:

```shell
$(json_import)
```

By default this function operates on stdin. Alternatively you can change it to operate on a file via -f. To use via
STDIN use one of these idioms:

```shell
$(json_import <<< ${json}) $(curl ... | $(json_import)
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --exclude, -x <value>
         Whitespace separated list of keys to exclude while importing.

   --export, -e
         Emit exported variables instead of local ones.

   --file, -f <value>
         Parse contents of provided file instead of stdin.

   --global, -g
         Emit global variables instead of local ones.

   --prefix, -p <value>
         Prefix all keys with the provided required prefix.

   --query, --jq, -q <value>
         Use JQ style query expression on given JSON before parsing.

   --upper-snake-case, -u
         Convert all keys into UPPER_SNAKE_CASE.


ARGUMENTS

   _json_import_keys
         Optional list of json keys to import. If none, all are imported.
```

## func pack_to_json


Convert a single pack into a json blob where the keys are the same as the keys from the pack (and so are the values)

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --lowercase
         Convert keys in the pack to all lowercase


ARGUMENTS

   _pack
         Named pack to operate on.

```

## func to_json

Convert each argument, in turn, to json in an appropriate way and drop them all in a single json blob.
