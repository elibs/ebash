# Module etable


## func etable

etable is designed to be able to easily produce a nicely formatted ASCII, HTML or "box-drawing" or "boxart" tables with
columns and rows. The input passed into this function is essentially a variadic number of strings, where each string
represents a row in the table. Each entry provided has the columns encoded with a vertical pipe character separating
each column.

For example, suppose you wanted to produce this ASCII table:

```
+------+-------------+-------------+
| Repo | Source      | Target      |
+------+-------------+-------------+
| api  | develop-2.5 | release-2.5 |
| os   | release-2.4 | develop-2.5 |
| ui   | develop-2.5 | release-2.5 |
+------+-------------+-------------+
```

The raw input you would need to pass is as follows:

```shell
bin/etable "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"
```

This can be cumbersome to create, so there are helper methods to make this easier. For example:

```shell
array_init_nl table "Repo|Source|Target"
array_add_nl  table "api|develop-2.5|release-2.5"
array_add_nl  table "os|develop-2.4|release-2.5"
array_add_nl  table "ui|develop-2.5|release-2.5"
etable "${table[@]}"
```

You can also optionally get a line separating each row, via:

```shell
$ etable --rowlines "${table[@]}"
+------+-------------+-------------+
| Repo | Source      | Target      |
+------+-------------+-------------+
| api  | develop-2.5 | release-2.5 |
|------|-------------|-------------|
| os   | release-2.4 | develop-2.5 |
|------|-------------|-------------|
| ui   | develop-2.5 | release-2.5 |
+------+-------------+-------------+
```

If instead you wanted to produce an HTML formatted table, you would use the exact same input as above only you would
pass in `--style=html` usage flag. This would produce:

```
$ etable --style=html "${table[@]}"
<table>
    <tbody>
        <tr>
            <th><p><strong>Repo</strong></p></th>
            <th><p><strong>Source</strong></p></th>
            <th><p><strong>Target</strong></p></th>
        </tr>
        <tr>
            <td><p>api</p></td>
            <td><p>develop-2.5</p></td>
            <td><p>release-2.5</p></td>
        </tr>
        <tr>
            <td><p>os</p></td>
            <td><p>release-2.4</p></td>
            <td><p>develop-2.5</p></td>
        </tr>
        <tr>
            <td><p>ui</p></td>
            <td><p>develop-2.5</p></td>
            <td><p>release-2.5</p></td>
        </tr>
    </tbody>
</table>
```

Finally, etable also supports box-drawing boxart characters instead of ASCII

```shell
$ bin/etable --style=boxart --rowlines "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"

┌──────┬─────────────┬─────────────┐
│ Repo │ Source      │ Target      │
├──────┼─────────────┼─────────────┤
│ api  │ develop-2.5 │ release-2.5 │
├──────┼─────────────┼─────────────┤
│ os   │ release-2.4 │ develop-2.5 │
├──────┼─────────────┼─────────────┤
│ ui   │ develop-2.5 │ release-2.5 │
└──────┴─────────────┴─────────────┘
```

Or without rowlines:

```shell
$ bin/etable --style=boxart "Repo|Source|Target" "api|develop-2.5|release-2.5" "os|release-2.4|develop-2.5" "ui|develop-2.5|release-2.5"

┌──────┬─────────────┬─────────────┐
│ Repo │ Source      │ Target      │
├──────┼─────────────┼─────────────┤
│ api  │ develop-2.5 │ release-2.5 │
│ os   │ release-2.4 │ develop-2.5 │
│ ui   │ develop-2.5 │ release-2.5 │
└──────┴─────────────┴─────────────┘
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --column-delim
         Display column delimiters.

   --headers
         Display column headers.

   --headers-delim
         Display column headers delimiter.

   --rowlines
         Display a separator line in between each row.

   --style <value>
         Table style (ascii, html, boxart). Default=ascii.

   --title <value>
         Table title to display.


ARGUMENTS

   columns
         Column headers for the table. Each column should be separated by a vertical pipe
         character.

   entries
         Array of encoded rows and columns. Each entry in the array is a single row in the
         table. Within a single entry, the columns are separated by a vertical pipe character.
```

## func etable_values

etable_values is a special-purpose wrapper around etable which makes it easier to create an etable with a provided list
of values and formats it into two columns, one showing the KEY and one showing the VALUE. For each variable, if it is a
string or an array it will be expanded into the value as you'd expect. If the variable is an associative array or a
pack, the keys and values will be unpacked and displayed in the KEY/VALUE columns in an exploded manner. This function
relies on print_value() for pretty printing arrays.

For example:

```shell
$ etable_values HOME USER
+------+----------------+
| Key  | Value          |
+------+----------------+
| HOME | /home/marshall |
| USER | marshall       |
+------+----------------+
```

If you have an associative array:

```shell
$ declare -A data([key1]="value1" [key2]="value2")
$ etable_values data
+------+--------+
| Key  | Value  |
+------+--------+
| key1 | value1 |
| key2 | value2 |
+------+--------+
```

With a pack:

```shell
$ pack_set data key1="value1" key2="value2"
$ etable_values %data

+------+--------+
| Key  | Value  |
+------+--------+
| key1 | value1 |
| key2 | value2 |
+------+--------+
```

Similar to ebanner there is an --uppercase and a --lowercase if you want to have all the keys in all uppercase or
lowercase for consistency.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --column-delim
         Display column delimiters.

   --columns <value>
        Value.

   --lowercase
         Lowercase all keys for display consistency.

   --rowlines
         Display a separator line in between each row.

   --sort
         Sort keys in the tabular output.

   --style <value>
         Table style (ascii, html, boxart). Default=ascii.

   --uppercase
         Uppercase all keys for display consistency.


ARGUMENTS

   entries
         Array of variables to display the values of.
```
