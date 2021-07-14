# Module pack


## func pack_copy

Copy a packed value from one variable to another. Either variable may be part of an associative array, if you're so
inclined.

Examples:

```shell
pack_copy A B
pack_copy B A["alpha"]
pack_copy A["alpha"] B[1]
```

## func pack_export

Assigns values into a pack by extracting them from the caller environment. For instance, if you have locals a=1 and b=2
and run the following:

```shell
pack_export pack a b
```

You will be left with the same pack as if you instead said:

```shell
pack_set pack a=${a} b=${b}
```

## func pack_get

Get the last value assigned to a particular key in this pack.

## func pack_import


Spews bash commands that, when executed will declare a series of variables in the caller's environment for each and
every item in the pack. This uses the "eval command invocation string" which the caller then executes in order to
manifest the commands. For instance, if your pack contains keys a and b with respective values 1 and 2, you can create
locals a=1 and b=2 by running:

```shell
$(pack_import pack)
```

If you don't want the pack's entire contents, but only a limited subset, you may specify them. For instance, in the
same example scenario, the following will create a local a=1, but not a local for b.

```shell
$(pack_import pack a)
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --export, -e
         Emit exported variables via export builtin.

   --global, -g
         Emit global variables instead of local (i.e. undeclared variables).

   --local, -l
         Emit local variables via local builtin (default).


ARGUMENTS

   _pack_import_pack
         Pack to operate on.

```

## func pack_iterate

Call provided callback function on each entry in the pack. The callback function should take two arguments, and it
will be called once for each item in the pack and passed the key as the first value and its value as the second value.

## func pack_keys

Echo a whitespace-separated list of the keys in the specified pack to stdout.

## func pack_keys_sort

Echo a whitespace-separated list of the sorted keys in the specified pack to stdout.

## func pack_print

Note: To support working with print_value, pack_print does NOT print a newline at the end of its output

## func pack_set

Consider a "pack" to be a "new" data type for bash. It stores a set of key/value pairs in an arbitrary format inside
a normal bash (string) variable. This is much like an associative array, but has a few differences

- You can store packs INSIDE associative arrays (example in unit tests)
- The "keys" in a pack may not contain an equal sign, nor may they contain whitespace.
- Packed values cannot contain newlines.

For a (new or existing) variable whose contents are formatted as a pack, set one or more keys to values. For example,
the following will create a new variable packvar that will contain three keys (alpha, beta, n) with associated values
(a, b, 7)

```shell
pack_set packvar alpha=a beta=b n=7
```

## func pack_update

 Much like pack_set, and takes arguments of the same form. The difference is that pack_update will create no new keys
 -- it will only update keys that already exist.
