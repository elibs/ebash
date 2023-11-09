# Module type


## func is_array

Returns success (0) if the variable name provided refers to an array and failure (1) otherwise.

For example:

```shell
arr=(1 2 3)
is_array arr
# returns: 0 (success)
```

In the above example notice that we use `is_array arr` and not `is_array ${arr}`.

## func is_associative_array

Returns success (0) if the variable name provided refers to an associative array and failure (1) otherwise.

For example:

```shell
declare -A data
data[key]="value"
is_associative_array data
# returns: 0 (success)
```

In the above example notice that we use `is_associative_array data` and not `is_associative_array ${data}`.

## func is_function

Returns success (0) if the variable name provided refers to a function and failure (1) otherwise.

For example:

```shell
foo() { echo "foo"; }
is_function foo
# returns: 0 (success)
```

## func is_int

Returns success (0) if the input string is an integer and failure (1) otherwise. May have a leading '-' or '+' to
indicate the number is negative or positive. This does NOT handle floating point numbers. For that you should instead
use is_num.

## func is_num

Returns success (0) if the input string is a number and failure (1) otherwise. May have a leading '-' or '+' to indicate
the number is negative or positive. Unlike is_integer, this function properly handles floating point numbers.

is_num at present does not handle fractions or exponents or numbers is other bases (e.g. hex). But in the future we may
add support for these as needed. As such we decided not to limit ourselves with calling this just is_float.

## func is_pack

Returns success (0) if the variable name provided refers to a pack and failure (1) otherwise.

For example:

```shell
declare mypack=""
pack_set mypack a=foo b=bar
is_pack mypack
# returns: 0 (success)
```
In the above example notice that we use `is_pack mypack` and not `is_pack ${mypack}`.
