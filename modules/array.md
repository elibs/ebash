# Module array


## func array_add


array_add will split a given input string on requested delimiters and add them to the given array (which may or may not
already exist).

```Groff
ARGUMENTS

   __array
         Name of array to add elements to.

   __string
         String to be split up and added to that array.

   __delim
         Delimiter to use when splitting. Defaults to IFS.

```

## func array_add_nl

Identical to array_add only hard codes the delimter to be a newline.

## func array_contains


array_contains will check if an array contains a given value or not. This will return success (0) if it contains the
requested element and failure (1) if it does not.

```Groff
ARGUMENTS

   __array
         Name of the array to search.

   __value
         Value to seek in that array.

```

## func array_copy


array_copy is a convenience function for copying one array to another. This is easier to use than raw bash code as it
handles empty arrays sensibly to avoid tripping up `set -e` and `set -u` settings. It also deals with properly quoting
the array contents properly so you don't have to worry about it.

Examples:

```shell
local source=("a 1" "b 2" "c 3" "d 4")
local target
array_copy source target
```

```Groff
ARGUMENTS

   __source
         Source array to copy from.

   __target
         Target array to copy into.

```

## func array_empty


Return true (0) if an array is empty and false (1) otherwise

```Groff
ARGUMENTS

   __array
         Name of array to test.

```

## func array_equal


array_equal is used to check if two arrays are equal or not. This is easier to use than raw bash code as arrays are passed
by reference instead of by value. This avoids the need for careful quoting of variables in an attempt to compare them.
It also deals more sensibly with empty variables and doesn't get tripped up by `set -e` and `set -u` settings.
Returns success (0) if the arrays are equal and failure (1) if they are not.

Examples:

```shell
$ local a1=("a 1" "b 2" "c 3" "d 4")
$ local a2=("a 1" "b 2" "c 3" "d 4")
$ array_equal a1 a2
$ echo $?
0
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --verbose, -v
         Enable verbose mode to show which elements differ.


ARGUMENTS

   __array1
         First array for comparison.

   __array2
         Second array for comparison.

```

## func array_indexes


Bash arrays may have non-contiguous indexes. For instance, you can unset an ARRAY[index] to remove an item from the
array and bash does not shuffle the indexes.

If you need to iterate over the indexes of an array (rather than simply iterating over the items), you can call
array_indexes on the array and it will echo all of the indexes that exist in the array.

```Groff
ARGUMENTS

   __array_indexes_array
         Name of array to produce indexes from.

```

## func array_indexes_sort


Same as array_indexes only iterate in sorted order.

```Groff
ARGUMENTS

   __array_indexes_array
         Name of array to produce indexes from.

```

## func array_init


array_init will split a string on any characters you specify, placing the results in an array for you.

```Groff
ARGUMENTS

   __array
         Name of array to assign to.

   __string
         String to be split

   __delim
         Optional delimiting characters to split on. Defaults to IFS.

```

## func array_init_json


Initialize an array from a Json array. This will essentially just strip off the brackets from around the Json array.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --keepquotes, -k
         Keep quotes around array elements of string to be split


ARGUMENTS

   __array
         Name of array to assign to.

   __string
         String to be split

```

## func array_init_nl

array_init_nl works identically to array_init, but always specifies that the delimiter be a newline.

## func array_join


array_join will join an array into one flat string with the provided multi character delimeter between each element in
the resulting string. Can also optionally pass in options to also put the delimiter before or after (or both) all
elements.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --after, -a
         Insert delimiter after all joined elements.

   --before, -b
         Insert delimiter before all joined elements.


ARGUMENTS

   __array
         Name of array to operate on.

   delim
         Delimiter to place between array items. Default is a space.

```

## func array_join_nl

Identical to array_join only it hardcodes the dilimter to a newline.

## func array_not_empty


Returns true (0) if an array is not empty and false (1) otherwise

```Groff
ARGUMENTS

   __array
         Name of array to test.

```

## func array_regex


Create a regular expression that will match any one of the items in this array. Suppose you had an array containing the
first four letters of the alphabet. Calling array_regex on that array will produce:

```shell
(a|b|c|d)
```

Perhaps this is an esoteric thing to do, but it's pretty handy when you want it.

> **_NOTE:_** Quote the output of your array_regex call, because bash finds parantheses and pipe characters to be
very important.

> **_WARNING:_** This probably only works if your array contains items that do not have whitespace or regex-y characters
in them. Pids are good. Other stuff, probably not so much.

```Groff
ARGUMENTS

   __array
         Name of array to read and create a regex from.

```

## func array_remove


Remove one (or optionally, all copies of ) the given value(s) from an array, if present.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --all, -a
         Remove all instances of the item instead of just the first.


ARGUMENTS

   __array
         Name of array to operate on.

```

## func array_rindexes


Same as array_indexes only this enumerates them in reverse order. Unlike prior versions of this function this now
correctly handles multi-digit index values.

```Groff
ARGUMENTS

   __array_indexes_array
         Name of array whose indexes should be produced.

```

## func array_size


Print the size of any array. Yes, you can also do this with ${#array[@]}. But this functions makes for symmertry with
pack (i.e. pack_size).

```Groff
ARGUMENTS

   __array
         Name of array to check the size of.

```

## func array_sort


Sort an array in-place.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --unique, -u
         Remove all but one copy of each item in the array.

   --version, -V
         Perform a natural (version number) sort.

```
