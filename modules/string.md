# Module string


## func lower_snake_case_to_title_case


Convert a given input string that is already in "lower snake case" and convert it into "title case". Basically, this
splits on an underscore, and replaces the underscore with a space. Then it capitalizes each word. Note that the first
word is also always capitalized even if there are no underscores in the input string.

For example:

    slice_drive_size => Slice Drive Size
    foo => Foo

```Groff
ARGUMENTS

   input
         Input string to convert from lower_snake_case to Title Case.

```

## func string_collapse

Collapse grouped whitespace in the specified string to single spaces.

## func string_getline


Helper function to make it easy to grab a specific line from a provided string. This is done using sed with '${num}q;d'.
What this does is advance to the requested line number, deleting everything it has seen in the buffer prior to the
current line, then then quits. This is significantly faster than the typical head | tail approach. The requested line
number must be > 0 or an error will be returned. Since we don't expect the caller to check the number of lines in the
input string before calling this function, this function will return an empty string if a line number is requested
beyond the length of the privided string.

```Groff
ARGUMENTS

   input
         Input string to parse for the requested line number.

   num
         Line number to fetch from the provided input string.

```

## func string_trim

string_trim trims all leading and trailing whitespace off of the provided input and returns a new string with all the
leading and trailing whitespace removed.

## func string_truncate


Truncate a specified string to fit within the specified number of characters. If the ellipsis option is specified,
truncation will result in an ellipses where the removed characters were (and the total string will still fit within
length characters)

Any arguments after the length will be considered part of the text to string_truncate

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --ellipsis, -e
         If set, an elilipsis (...) will replace any removed text.


ARGUMENTS

   length
         Desired maximum length for text.

```

## func to_lower_snake_case


Convert a given input string into "lower snake case". This is generally most useful when converting a "CamelCase" string
although it will work just as well on non-camel case input. Essentially it looks for all upper case letters and puts an
underscore before it, then lowercase the entire input string.

For example:

    sliceDriveSize => slice_drive_size
    slicedrivesize => slicedrivesize

It has some special handling for some common corner cases where the normal camel case idiom isn't well followed. The
best example for this is around units (e.g. MB, GB). Consider "sliceDriveSizeGB" where slice_drive_size_gb is preferable
to slice_drive_size_g_b.

The current list of translation corner cases this handles: KB, MB, GB, TB

```Groff
ARGUMENTS

   input
        input

```

## func to_upper_snake_case


Convert a given input string into "upper snake case". This is generally most useful when converting a "CamelCase" string
although it will work just as well on non-camel case input. Essentially it looks for all upper case letters and puts an
underscore before it, then uppercase the entire input string.

For example:

    sliceDriveSize => SLICE_DRIVE_SIZE
    slicedrivesize => SLICEDRIVESIZE

It has some special handling for some common corner cases where the normal camel case idiom isn't well followed. The
best example for this is around units (e.g. MB, GB). Consider "sliceDriveSizeGB" where SLICE_DRIVE_SIZE_GB is preferable
to SLICE_DRIVE_SIZE_G_B.

The current list of translation corner cases this handles: KB, MB, GB, TB

```Groff
ARGUMENTS

   input
        input

```
