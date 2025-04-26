# Module compare


## func compare

Generic comparison function using awk which doesn't suffer from bash stupidity with regards to having to do use separate
comparison operators for integers and strings and even worse being completely incapable of comparing floats.

```Groff
ARGUMENTS

   lh
        ?lh

   op
        op

   rh
        ?rh

```

## func compare_version

Specialized comparision helper to properly compare versions
