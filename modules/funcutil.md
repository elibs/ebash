# Module funcutil


## func override_function

override_function is a more powerful version of save_function in that it will still save off the contents of a
previously declared function into ${1}_real but it will also define a new function with the provided body ${2} and mark
this new function as readonly so that it cannot be overridden later. If you call override_function multiple times we
have to ensure it's idempotent. The danger here is in calling save_function multiple tiems as it may cause infinite
recursion. So this guards against saving off the same function multiple times.

```Groff
ARGUMENTS

   func
        func

   body
        body

```

## func save_function

save_function is used to safe off the contents of a previously declared function into ${1}_real to aid in overridding
a function or altering it's behavior.
