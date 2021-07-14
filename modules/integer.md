# Module integer


## func decrement


decrement is a convenience wrapper around the bash "-=" and "--" operators to avoid triggering "set -e" failures and
make it easier to do such a simple task in ebash. This fundamental problem this solves is when decrementing a bash
integer, bash returns a non-zero return code from the "--" which ebash detects and triggers die(). The reason that bash
does this is because it returns the decremented value which generally is non-zero and thus an error.

The other idiom we frequently use is "(( i -= 1 ))". This idiom also has problems though when the value gets decremented
to zero. This gets confusingly reported as an error by bash which ebash will then detect and abort on. The safest idiom
to use , which works in every scenario, is as follows:

```shell
i=$(( i -= 1 ))
```

However, that's pretty ugly syntax and easy to mess up. So the ebash solution is to simply call the "decrement"
function:

```shell
decrement i
```

The other useful feature of decrement is that you can pass in an optional amount to decrement by, which defaults to 1:

    decrement i 100

```Groff
ARGUMENTS

   __variable
         Variable to decrement

   __amount
         The amount to decrement the variable by.

```

## func increment


increment is a convenience wrapper around the bash "+=" and "++" operators to avoid triggering "set -e" failures and
make it easier to do such a simple task in ebash. This fundamental problem this solves is when incrementing a bash
integer, bash returns a non-zero return code from the "++" which ebash detects and triggers die(). The reason that bash
does this is because it returns the incremented value which generally is non-zero and thus an error.

The other idiom we frequently use is "(( i += 1 ))". This idiom also has problems though when the value gets incremented
to zero or decremented to zero. This gets confusingly reported as an error by bash which ebash will then detect and abort
on. The safest idiom to use , which works in every scenario, is as follows:

```shell
i=$(( i -= 1 ))
```

However, that's pretty ugly syntax and easy to mess up. So the ebash solution is to simply call the "increment"
function:

```shell
increment i
```

The other useful feature of increment is that you can pass in an optional amount to increment by, which defaults to 1:

```shell
increment i 100
```

```Groff
ARGUMENTS

   __variable
         Variable to increment

   __amount
         The amount to increment the variable by.

```
