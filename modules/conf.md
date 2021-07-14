# Module conf

The conf module operates on INI configuration files. These are supported by many different tools and languages.
Sometimes the rules vary a little. This implementation is based on [wikipedia's](https://en.wikipedia.org/wiki/INI_file)
description of the INI format.

These typically look something like the following:

```INI
[section]
property=value

[another_section]
property=different value
another_property=value
```

Where a sequence of "properties" are stored in sections. There may be properties of the same name in different sections
with different values. In this implementation, values that are not in a named section will be placed in a section named
"default"

You may specify multiple configuration files, in which case files that are *later* in the list will override the settings
from configuration files specified earlier in the list. In other words, if you call `conf_read` like this, settings from
`~/.config/A` will override those in `/etc/A` and all results will be stored in `CONF`

```bash
declare -A CONF
conf_read CONF /etc/A ~/.config/A
```

Here the the details of the INI specification from wikipedia's description that ebash implements:

### Comments

- Both ; and # at the beginning of a line start a comment.
- You can't create comments at the end of a line. Instead, whatever is on the line past the equal sign will become part
  of the property created on that line

### Sections

- Section names may not contain whitespace, nor may they contain equal signs or periods.
- Section names are case sensitive.
- No section is required, properties without a section declaration are placed in "default"

### Properties

- Property names may not contain whitespace, nor may they contain equal signs
- Property names are case sensitive.
- Whitespace around the name is ignored.
- Values cannot contain newlines. Whitespace is stripped from the ends, but retained within the value
- Values can be surrounded by single or double quotes, in which case there must only be two of that particular quote
  character on the line. No escaping is allowed.
- When quoted, all whitespace in the value within the quotes is retained. This doesn't change that values cannot contain
  newlines.

## func conf_contains


Determine whether a configuration store that conf_read extracted from file contains a particular configuration property.

```Groff
ARGUMENTS

   __conf_store
         Associative array variable that conf_read filled with configuration data.

   property
         Property of the form 'section.key'. If no section is specified 'default' is assumed.

```

## func conf_dump


Display an entire configuration in a form that could be written to a file and re-read as a new configuration. Note that
when we read and store a configuration, the comments are dropped so if you used this to re-create a configuration file
you trash all of the comments.

Use conf_set to modify a configuration file without blowing away comments.

```Groff
ARGUMENTS

   __conf_store
         Variable containing the configuration data.

```

## func conf_get


Read a particular configuration value out of a configuration store that has already been read from disk with conf_read.

```Groff
ARGUMENTS

   __conf_store
         Associative array variable that conf_read filled with configuration data.

   property
         Property of the form 'section.key'. If no section is specified 'default' is assumed.

```

## func conf_read


Reads one or more "INI"-style configuration file into an associative array that you have prepared in advance. Keys in
the associative array will be named for the sections of your INI file, and the entry will be a pack containing all
configuration values from inside that section.

```Groff
ARGUMENTS

   __conf_store
         Name of the associative array to store configuration in. This must be previously declared
         and existing contents will be overwritten.

   files
         Configuration files that should be read in. Settings from files later in the list will
         override those earlier in the list.
```

## func conf_set


Set a value in an INI-style configuration file.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --compact, -c
         Use a more compact format for properties. Without this option enabled, it emits 'key =
         value' but with this option it emits a more compact 'key=value'.

   --file, -f <value>
         Config file that should be modified. Required.

   --pretend, -p
         Don't actually modify the file. Just print what it would end up containing.

   --unset, -u
         Remove the property and value from the configuration file.


ARGUMENTS

   property
         The config property to set in the form 'section.key'. If no section is specified, default
         is assumed. Note that it is fine for the property name to contain additional periods. The
         first separates section from key, but the rest are assumed to be part of the key name.

   value
         New value to give the property.

```
