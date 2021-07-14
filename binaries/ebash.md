# Binary ebash


ebash is an open source project developed at NetApp/SolidFire as an open source project from 2011-2018 under the name
bashutils and the Apache 2.0 License. I forked bashutils into ebash upon my departure from NetApp/SolidFire to continue
active development and ensure it remained free and open source.

The primary goal of ebash is to significantly enhance bash code and make it more robust, feature rich and simple which
greatly accelerates developer productivity.

Because bash is a lower level language, it lacks some of the features and more advanced data structures typically found
in higher level languages. ebash aims to be the answer to this problem. The most important and compelling feature of
ebash is implicit error detection. This typically results in bash scripts being 75% shorter due to removal of explicit
error handling and the ability to leverage extensive ebash modules.

The ebash script itself is the primary entry point into ebash. It supports various modes of operation as outlined in
[usage](doc/usage.md):

- Sourcing. You can use ebash code in your bash script by adding the following to the top of your script. This assumes
  you have `ebash` in `${PATH}`. For example: `$(ebash --source)`

- Interpreter. Another very simple approach is to have ebash in your `${PATH}` and then simply change the interpreter
  at the top of your shell script to find `ebash` using `env`. For example: `#!/usr/bin/env ebash`

- Interactive ebash. One of the cool things ebash provides is an interactive REPL interface. This makes it super easy to
  interactively test out code to see how it behaves or debug failures. Simply invoke `ebash` and you'll be presented a
  prompt that you can use to run commands in.

- ebash binaries. Ebash provides multiple [binaries](https://elibs.github.io/ebash/binaries) which are essentially just
  scripts which magically invoke functions of the same name within ebash. Each of these binaries is really just a symlink
  to ebash itself. These work similarly to `busybox` in that if you invoke one of these symlinks, then `ebash` will look
  for a function matching the name of the binary. If it finds one, it will call it with the options and arguments passed
  in. This makes it easy to write modular, functional code and still expose it as a callable binary.

See also: [Ebash Documentation](https://elibs.github.io/ebash/index.html).

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --color, -c
         Force explicit color mode.

   --interactive, -i
         Force interactive mode even if we are not attached to a terminal.

   --load, -l <value>
         ebash should source the specified file before attempting to run the specified command.

   --msg-prefix, -m <value>
         Prefix to use for all emsg messages.

   --name, -n <value>
         Name to use as a starting point for finding functions. This basically pretends that
         ebash is running with the specified name.

   --print-environment, --printenv, -p
         Dump environment variables that ebash would like to use in a format bash can interpret

   --source, -s
         Print commands that would load ebash from its existing location on disk into the current
         shell and then exit. You'd use this in a script like this: $(ebash --source)

```
