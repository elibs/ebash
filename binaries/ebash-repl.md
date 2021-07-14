# Binary ebash-repl



One of the cool things ebash provides is an interactive [REPL](https://en.wikipedia.org/wiki/read%e2%80%93eval%e2%80%93print_loop)
interface. this makes it super easy to interactively test out code to see how it behaves or debug failures.

here's an example:

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
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --load, -l <value>
         Load the specified file prior to running the interactive interpreter.

```
