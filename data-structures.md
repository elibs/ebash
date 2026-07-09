# Data Structures

## Arrays

In the [array module](modules/array.md) there are several helpers for dealing with standard bash arrays. These are
helpers for dealing with standard bash arrays. Definitely read the full documentation but let's highlight some of the
more interesting functions.

For example, since you should **never** modify `IFS`, you might be interested in a function that can initialize an array
by splitting on a particular separator. For example:

```shell
$ array_init array "one|two|three" "|"
$ declare -p array
declare -a array='([0]="one" [1]="two" [2]="three")'
$ array_init array "aJbJcJd" "J"
$ declare -p array
declare -a array='([0]="a" [1]="b" [2]="c" [3]="d")'
```

The default separator is any whitespace. If you'd like to split up a file by line (retaining whitespace within
individual lines), you can use [array_init_nl](modules/array.md#func-array_init_nl). There's also [array_init_json](modules/array.md#func-array_init_json) to slurp JSON data into an array.

You can use [array_contains](modules/array.md#func-array_contains) to find out if a specific value is in an array, [array_sort](modules/array.md#func-array_sort) to sort an array, and [array_remote](modules/array.md#func-array_remove)
to remove specific items out of an array.

## Packs

[Packs](modules/pack.md) are an entirely new data structure for bash. They're pretty similar to associative arrays, but have compelling
benefits in a few cases. The best one is that you can store packs inside an array or associative array, so you can more
easily keep track of multidimensional data.

There are also downsides. The key for data stored in your pack must not contain an equal sign or whitespace. And the
value for data stored in the pack is not allowed to contain newline or null characters.

So how do you use it?

```shell
$ pack_set my_pack A=1 B=2 C=3
$ pack_get my_pack A
1
$ pack_get my_pack B
2
```

You can continue to change values in the pack over time in the same way.

```shell
$ pack_set my_pack B=40 pack_get my_pack A
1
$ pack_get my_pack B
40
```

But sometimes that gets cumbersome. When you want to work with a lot of the variables, sometimes it's easier to store
them as local variables while you're working, and then put them all back in the pack when you're done. [pack_import](modules/pack.md#func-pack_import) and
[pack_export](modules/pack.md#func-pack_export) were designed for just such a case.

```shell
$ $(pack_import my_pack) echo $A
1
$ echo $B
40
$ A=15
$ B=20
$ pack_export my_pack A B
$ pack_get my_pack A
15
$ pack_get my_pack B
20
```

You can see that after `pack_import,` `A` and `B` were local variables that had values that were extracted from the
pack. After the `pack_export`, the values inside the pack were synced back to the values that had been assigned to the
local variables. You could certainly do this by hand with [pack_set](modules/pack.md#func-pack_set) and [pack_get](modules/pack.md#func-pack_get) but `pack_import` and `pack_export`
are often more convenient.

One more quick tool for using packs. Our `lval` knows how to read them explicitly, but you must tell it that the
variable is a pack by prepending it with a percent sign.

```shell
$ echo "$(lval %my_pack)"
my_pack=([C]="3" [A]="15" [B]="20" )
```
Another super helpful pair of functions are [pack_save](modules/pack.md#func-pack_save) and [pack_load](modules/pack.md#func-pack_load) to easily save a pack to an on-disk file and then
later load it from that file back into memory.

## json

ebash has extensive [json](modules/json.md) functions to make it dramatically easier to use JSON inside bash code. A lot of the heavy-lifting
to accomplish this is accomplished using the fantastic tool [jq](https://stedolan.github.io/jq).

The most important function is [json_import](modules/json.md#func-json_import).

`json_import` imports all of the `key:value` pairs from a non-nested JSON object directly into the caller's environment as
proper bash variables. By default this will import all the keys available into the caller's environment. Alternatively
you can provide an optional list of keys to restrict what is imported. If any of the explicitly requested keys are not
present this will be interpreted as an error and `json_import` will return non-zero. Keys can be marked optional via the
`?` prefix before the key name in which case they will be set to an empty string if the key is missing.

Similar to a lot of other  methods inside ebash, this uses the *eval command invocation string* idom. So, the proper
calling convention for this is:

```shell
$(json_import)
```

By default this function operates on stdin. Alternatively you can change it to operate on a file via `--file` or `-f`.
To use via STDIN use one of these idioms:

```shell
$(json_import <<< ${json}) $(curl ... | $(json_import)
```

Here are some of the other functions you should check out:

* array_to_json
* associative_array_to_json
* associative_array_to_json_split
* file_to_json
* json_compare
* json_escape
* pack_to_json
* to_json

There are lots of tests you can checkout at [json tests](https://github.com/elibs/ebash/blob/master/tests/json.etest).
