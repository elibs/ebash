# General Bash Gotchas

## Arrays may be holey!

Although conceptually indexed by numbers, bash arrays are not necessarily contiguous. Really, they’re more like
associative arrays except that bash forces the indexes to be numerical.

For instance:

```shell
$ ARRAY=(A B C D) declare -p ARRAY
declare -a ARRAY='([0]="A" [1]="B" [2]="C" [3]="D")'

$ unset ARRAY[B]
$ unset ARRAY[D]
$ declare -p ARRAY
declare -a ARRAY='([1]="B" [2]="C" [3]="D")'
```

Notice how the items in the array don't get moved or re-indexed. Hence, just doing math to guess which items exist in a
bash array is a bad idea.

> **_WARNING:_** DO NOT DO THIS!  It will blow up on an array with holes in it
```shell
for (( i=0; i < ${#ARRAY[@]}; i++ )); do
    echo "${ARRAY[$i]}"
done
```

Instead, ask bash for the available indexes to the array and iterate over them. You can do this the same way you would
with an associative array, with `"${!array[@}"`.

```shell
for index in "${!ARRAY[@]}"; do
    echo "${ARRAY[$index]}"
done
```

Or, there is an ebash function that does the same thing to help you and also works around buggy behavior on older versions
of bash:

```shell
for index in "$(array_indexes ARRAY)"; do
    echo "${ARRAY[$index]}"
done
```

## Quote EVERYTHING

Bash likes to do crazy things to the contents of your variables when you don't quote them. So unless you're very sure
that it doesn't need to be quoted, just put double quotes around the variable and be done with it. The most
commonly-known case of this relates to filenames and white space.

```shell
$ filename="contains spaces.txt"
touch $filename
```

The above code will produce two separate files: `contains` and `spaces.txt`. But white space isn't the only thing that
matters. For instance, any text that bash could interpret as a glob operator may produce varying output depending on
the contents of your file system:

```shell
$ a=[x]
$ echo ${a}
[x]
$ touch x
$ echo ${a}
x
```

At the end of the day, it's usually easier to just quote everything than to try to guess when it will matter or when it
won't.
