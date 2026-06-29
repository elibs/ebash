# ebash Style

These are the styles we use when writing code in ebash, and frequently in related code using ebash.

## General Formatting

The top level of code belongs at the far left, and each compound statement deserves an indent of 4 spaces.

```shell
if true; then
    if something_else; then
        something
    fi
fi
```

> **_NOTE:_** We use spaces instead of tabs in all ebash code. The only exception to this is that **here docs** and **here strings**
(using `<<-` operator) must use tabs because that is what bash requires.

We also try to keep lines under 120 characters and indent for lines that are continuations of the previous the same amount.

```shell
some_really_long_command --with --long --args \
    | grep pattern                            \
    | tail
```

When we escape very long lines, we try to align the escape characters. This helps us visually scan code and know that the
escape characters are present on each line. One place you'll see a lot of this is with `opt_parse`:

```shell
$(opt_parse \
  "+best             | Use the best compression (level=9)."                              \
  "+bootable boot b  | Make the ISO bootable (ISO only)."                                \
  "+delete           | Delete the source files after successful archive creation."       \
  "+dereference      | Dereference (follow) symbolic links (tar only)."                  \
  ":directory dir  d | Directory to cd into before archive creation."                    \
  ":exclude x        | List of paths to be excluded from archive."                       \
  "+fast             | Use the fastest compression (level=1)."                           \
  "+ignore_missing i | Ignore missing files instead of failing and returning non-zero."  \
  ":level l=9        | Compression level (1=fast, 9=best)."                              \
  "+nice n           | Be nice and use non-parallel compressors and only a single core." \
  ":type t           | Override automatic type detection and use explicit archive type." \
  ":volume v         | Optional volume name to use (ISO only)."                          \
  "dest              | Destination path for resulting archive."                          \
  "@srcs             | Source paths to archive.")
```

## Naming

Spell out your words. Lvng out vwls is cnfsng. (Leaving out vowels is confusing). Avoid abbreviations unless they're
really common (e.g. num for number) or they're used all over the place (e.g. cmd for command). Try to name based on the
purpose of something rather than its type (e.g. `string` and `array` aren't particularly descriptive names).

* Local variables names should use `lower_snake_case`.
* Global variable names historically used `UPPER_SNAKE_CASE` but we now prefer `lower_snake_case` as well.
* Function names should use `lower_snake_case`.
* Environment variables MUST use `UPPER_SNAKE_CASE`.

Bash provides no namespaces, so when we have a group of related functions, we’ll frequently use a common term as the
first word of the name to group them and avoid collisions. For that first word, we do occasionally use abbreviations as
we don't want them to cause the names to increase to ridiculous lengths.

For instance, you’ll find functions with these names in ebash:

- `cgroup_create`
- `cgroup_destroy`
- `array_size`
- `netns_exec`

## Curly Braces

When reading the value of a variable, use curly braces. For example, use `${VAR}` and not `$VAR.`

Exceptions:

* When the variable is an index into an array, we leave the braces off to reduce the noise. For instance `${VAR[$i]}`
  is good.
* Bash builtin variables with short names. For instance, we often say `${@},` but that's not required. We almost
  always use a simple `$!` or `$?`, and we frequently use `$1` and `$2.` But bash builtins like `${BASHPID}` or
  `${BASH_REMATCH}` look like global variables and so they should have braces.

## `if`/`then` and `do` Alignment

Put `then` and `do` on the same line as the statement they belong to.  For instance:

```shell
if true; then
    something
fi

for i in "${array[@]}"; do
    something
done
```

## Always use `[[` and `]]` instead of `[` and `]`

Bash provides `[[` because it's easier to deal with, has more functionality such as regular expression matching, and
reduces the amount of quoting you must do to use it correctly.

`[` is a posix-standard external binary. `[[` is a bash builtin, so it's cheaper to run. The builtin is also able to
give you syntactic niceties. For instance, you need to quote your variables much less. This is safe. Whereas the same
thing with the `[` command would not be.

Safe:

```shell
[[ -z ${A} ]]
```

**NOT** Safe:

```shell
[ -z ${A} ]
```

Aside from posix shell compatibility (which is not a concern when using ebash), there is no downside.

## Local Variables

Every variable that can be declared local must be declared local.

If you don't tell bash to use local variables, it assumes that all of the variables you create are global. If someone
else happens to use the same name for something, one of you is likely to stomp on the value that the other set.

Note that both local and declare create local variables. ebash helpers such as `opt_parse` and `tryrc` create local
variables for you, too.

One place that it's really easy to accidentally not use a local variable is with a bash for loop.

```shell
# Note: index here is NOT LOCAL
for index in "${array[@]}" ; do
    something
done
```

You must specifically declare for loop index variables as local.

```shell
local index
for index in "${array[@]}"; do
  something
done
```

## NEVER change `IFS`

Like most other bash code, ebash is written under the assumption that `IFS` is at its default value. If you change the
value of `IFS` and call any ebash code, expect things to break most likely in subtle ways.

## Markdown Style

Adhere to the guidance in the fantastic [Markdown Style Guide](https://cirosantilli.com/markdown-style-guide). Particular choices
we have made to use ebash:

- **Bullets**: Use `-` instead of `*` for bullets. This avoids confusion with bold and italics and is rendered the same.
- **Code Blocks**: Use triple backticks instead of merely indentation. Combined with explicit language of the code block
  this is rendered with syntax highlighting and looks much better.
- **Dollar signs in code blocks**: Follow the guidance in [Dollar signs in shell code](https://cirosantilli.com/markdown-style-guide/#dollar-signs-in-shell-code).
  Specifically:
  - _Do Not_ universally prefix all shell code inside a code block with a dollar sign `$` as this creates a lot of noise.
  - Code cannot be copy-pasted properly if they have leading dollar signs.
  - The leading dollar sign can be confused with subshell invocations, e.g. `$(find ...)`.
  - The only time you _should_ use the `$` prefix is when you are trying to show a clear example that differentiates
    the command being run from its output.
  - Sometimes we may prefer to use `>` prefix instead of `$` to avoid ambiguity with subshell invocations.
- For **NOTES** and **WARNINGS** inside markdown, use `> **_NOTE:_**` and `> **_WARNING:_**`
- Generally, prefer to use `-` in lists instead of numbered lists using `1.`
