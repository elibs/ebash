# Usage

## Sourcing (deprecated)

The original, deprecated way to use ebash was to simply source it at the top of your shell script. Suppose you had ebash
installed in `/opt/ebash`, then you would do the following:

```shell
source "/opt/ebash/share/ebash.sh"
```

## Sourcing

The newer way to use ebash is to simply invoke it with the `--source` option and invoke that output using what is called
the _eval command invocation string_ idiom: Assuming that `ebash` is in your `${PATH}`, you can simply do the following
at the top of your shell scripts:

```shell
#!/bin/bash
$(ebash --source)
```
## Sourcing Without `${PATH}`

If `ebash` is NOT in your `${PATH}` then you can simply fully qualify the path to `ebash` in your script. Suppose you
have it installed at `/opt/ebash`, then you would do the following:

```shell
#!/bin/bash
$(/opt/ebash/bin/ebash --source)
```

## Interpreter

Another very simple approach is to have `ebash` in your `${PATH}` and then simply change the interpreter at the top of
your shell script to find `ebash` using `/usr/bin/env`:

```shell
#!/usr/bin/env ebash
```

Or you can always just give the full path:

```shell
#!/opt/ebash/bin/ebash
```

## Interactive ebash

One of the cool things ebash provides is an interactive [REPL](https://en.wikipedia.org/wiki/read%e2%80%93eval%e2%80%93print_loop) interface. This
makes it super easy to interactively test out code to see how it behaves or debug failures.

Here's an example:

```shell
$ .ebash/bin/ebash
>> ebash ebash="/home/marshall/code/liqid/os/.ebash/share"
ebash> einfo "testing"
>> testing
ebash> assert_true true
ebash> assert_false true

>> assert failed (rc=0) :: true
   :: assert.sh:72         | assert_false
   :: ebash-repl:64        | repl
   :: ebash-repl:91        | main
ebash> exit
 marshall@caprica  ~/.../liqid/os   liqswos-537  v2.4.1.11-1-ge5c6b83156 
```
