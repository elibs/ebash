# Module dialog


## func dialog

This is a generic wrapper around [dialog](https://invisible-island.net/dialog/#screenshot) which adds `--hide` and
`--trace` options across the board so that we don't have to implement wrappers for every widget. Moreover, it also deals
with dialog behavior of returning non-zero for lots of not-fatal reasons. We don't want callers to throw fatal errors
when that happens. Intead they should inspect the error codes and output and take action accordingly. Secondly, we need
to capture the stdout from dialog and then parse it accordingly. Using the tryrc idiom addresses these issues by
capturing the return code into `dialog_rc` and the output into `dialog_output` for subsequent inspection and parsing.

## func dialog_cancel

`dialog_cancel` is a helper function to cancel the dialog process that we spawned in a consistent reusable way.

## func dialog_checklist

`dialog_checklist` provides a very simple interface around the dialog checklist widget by simplying operating on an
array variable. Instead of taking in raw strings and worrying about quoting and escaping this simply takes in the
**name** of an array and then directly operates on it. Each entry in the widget is composed of the first three elements
in the array.

So, typically you would format the array as follows:

```shell
array=()
array+=( tag "item text with spaces" status )
```

Where `status` is either `on` or `off`

Each 3-tuple in the array will be parsed and presented in a checklist widget. At the end, the output is parsed to
determine which ones were selected and the input array is updated for the caller. With the `--delete` flag (on by
default) it will delete anything in the array which was not selected. If this flag is not used, then the caller can
manually look at the `status` field in each array element to see if it is `on` or `off`.

`dialog_checklist` tries to intelligently auto detect the geometry of the window but the caller is always allowed to
override this with `--geometry` option.

## func dialog_error

Helper function to make it easier to display simple error boxes inside dialog. This is similar in purpose and
usage to `eerror` and will display a dialog msgbox with the provided text.

## func dialog_info

Helper function to make it easier to display simple information boxes inside dialog. This is similar in purpose and
usage to `einfo` and will display a dialog msgbox with the provided text.

## func dialog_kill

`dialog_kill` is a helper function to provide a consistent and safe way to kill dialog subprocess that we spawn.

## func dialog_list_extract


`dialog_list_extract` is a function to provide a simple interface to extract the elements of an array formatted for
dialog_checklist and dialog_radiolist usage and copy out only the desired elements. The input array contains 3-tuples of
the format ( tag text status ). You can then use this function to create a new array with just the text field of each
tuple extracted. You can filter on fields with the desired status value of `on` or `off`.

By default it filters on elements with a status value of `on` if no explicit value is provided.

```shell
local options=( "1" "Option #1" "on"
                "2" "Option #2" "on"
                "3" "Option #3" "off"
               )
local results=()
dialog_list_extract options results
# Results: ( "Option #1" "Option #2" )
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --status <value>
         Matching status values to extract.


ARGUMENTS

   __source
         Source array to extract text values from.

   __target
         Target array to extract text values into.

```

## func dialog_prgbox


Helper function to make it easier to use `dialog --prgbox` without buffering. This is done using stdbuf which can then
disable buffering on stdout and stderr before invoking the command requested by the caller. This way we have a nice
uniform way to call external programs and ensure their output is displayed in real-time instead of waiting until the
program completes.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --geometry, -g <value>
         Optional geometry in 'HxW format.

   --ok-label <value>
         Optional override of the OK button text.


ARGUMENTS

   text
         Text to display in the program box.

   command
         Command to execute and display the output from inside the program box.

```

## func dialog_prompt


`dialog_prompt` provides a very simple interface for the caller to prompt for one or more values from the user using the
[dialog](https://invisible-island.net/dialog/#screenshot) ncurses tool. Each named option passed into `dialog_prompt`
will be displayed as a field within dialog. By default each value is initially empty, but the caller can override this
by using `option=value` syntax wherein `value` would be the initial value for `option` and displayed in the dialog
interface. By default all options are **required** and the user will be unable to exit the dialog interface until all
required fields are provided. The caller can prefix an option with a `?` to annotate that it is optional. In the dialog
interface, required options are marked as required with a preceeding `*`. After the user fills in all required fields,
the provided option names will be set to the user provided values. This is done using the "eval command invocation
string" idiom so that the code to set variables is executed in the caller's environment.

For example:

```shell
$(dialog_prompt field)
```

`dialog_prompt` tries to intelligently auto detect the geometry of the window based on the number of fields being prompted
for. It overcomes some annoyances with dialog not scaling very well with how it pads the fields in the window. But the
caller is always allowed to override this with the `--geometry` option.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --backtitle <value>
         Text to display on backdrop at top left of the screen.

   --declare
         Declare variables before assigning to them. This is almost always required unless the
         caller has already declared the variables before calling into dialog_prompt and disires
         to simply reuse the existing variables.

   --geometry <value>
         Geometry of the box (HEIGHTxWIDTHxMENU-HEIGHT).

   --help-callback <value>
         Callback to invoke when 'Help' button is pressed.

   --help-label <value>
         Override label used for 'Help' button.

   --hide
         Hide ncurses output from screen (useful for testing).

   --instructions
         Include instructions on how to navigate dialog window.

   --title <value>
         String to display as the top of the dialog box.

   --trace
         If enabled, enable extensive dialog debugging to stderr.

   --transform (&)
         Accumulator of sed-like replace expressions to perform on dialog labels. Expressions
         are 's/regexp/replace/[flags]' where regexp is a regular expression and replace is a
         replacement for each label matching regexp. For more details see the sed manpage.


ARGUMENTS

   fields
         List of option fields to prompt for. Field names may not contain spaces, newlines or
         special punctuation characters.
```

## func dialog_prompt_username_password


dialog_prompt_username_password is a special case of dialog_prompt that is specialized to deal with username and password
authentication in a secure manner by not displaying the passwords in plain text in the dialog window. It also deals
with pecularities around a password wherein we want to present a second inbox box to confirm the password being
entered is valid. If they don't match the caller is prompted to re-enter the password(s). Otherwise it functions the
same as dialog_prompt does with the "eval command invocation string" idiom so that the code to set variables is
executed in the caller's environment. For example: $(dialog_prompt_username_password). The names of the variables it sets
are 'username' and 'password'.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --declare
         Declare variables before assigning to them. This is almost always required unless the
         caller has already declared the variables before calling into dialog_prompt and disires
         to simly reuse the existing variables.

   --optional, -o
         If true, the username and password are optional. In this case the user will be allowed
         to exit the dialog menu without providing username and passwords. Otherwise it will
         sit in a loop until the user provides both values.

   --title <value>
         Title to put at the top of the dialog box.

```

## func dialog_prompt_username_password_UI


This function separates the UI from the business logic of the username/password function. This allows us to unit test
the business logic without user interaction.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --password <value>
         Password to display (obscured), if any

   --title <value>
         Text for title bar of dialog

   --username <value>
         Username to display, if any

```

## func dialog_radiolist

`dialog_radiolist` provides a very simple interface around the dialog radiolist widget by simplying operating on an
array variable. Instead of taking in raw strings and worrying about quoting and escaping this simply takes in the
**name** of an array and then directly operates on it. Each entry in the widget is composed of the first three elements
in the array.

So, typically you would format the array as follows:

```shell
array=()
array+=( tag "item text with spaces" status )
```

Where `status` is either `on` or `off`

Each 3-tuple in the array will be parsed and presented in a radiolist widget. At the end, the output is parsed to
determine which ones were selected and the input array is updated for the caller. With the `--delete` flag (on by
default) it will delete anything in the array which was not selected. If this flag is not used, then the caller can
manually look at the `status` field in each array element to see if it is `on` or `off`.

`dialog_radiolist` tries to intelligently auto detect the geometry of the window but the caller is always allowed to
override this with `--geometry` option.

> **_NOTE:_** A radiolist is almost identical to a checklist only the radiolist only allows a single element to be selected
whereas a checklist allows multiple rows to be selected.

## func dialog_read


Helper function to safely read characters in a while loop from the standard input stream for dialog. This function
deals with many complications around reading characters for dialog properly and safely.

Race Conditions on Exit
=======================
We definitely cannot try to read characters from the input stream if the dialog process has exited. So, the first thing
this function does is check if dialog is runnig or not. If it is no longer running then we are done reading and this
function will return an error (1) to indicate that dialog_read did not complete successfully and we should exit the
read loop.

While this check is necessary, it is not sufficient to know if we are done reading or not.

There are several non-obvious reasons for this:

- We may be streaming in tons of input characters (e.g. from a unit test) and have a series of dialog windows we're
  going to open up sequentially to receive the input. If we keep reading after the first dialog window exits then
  we'll consume characters that were intended for the second window, and so on.

- When dialog receives input that triggers it to exit there is some delay before the process actually cleans up and
  exits. During that window we could wrongly think we need to read more characters.

- This is also a small delay between when keys are sent into ebash which in turn forwards them over to dialog process.
  And of course it takes some time for dialog to process the key and decide if it should exit or not.

So, we detect this situation by checking if the last character that was pressed was the ENTER key. This is the required
key that the user must press to complete a form or close a window. If the last key pressed was indeed ENTER then we can
check if dialog actually exited or not. We do this by checking if dialog has written its return code into `rc_file` or
not. If it has, then we know it has exited and we should stop reading characters.

Multi-Byte Characters
=====================
Unfortunately some arrow keys and other control characters are represented as multi-byte characters:
- EBASH_KEY_UP
- EBASH_KEY_RIGHT
- EBASH_KEY_DOWN
- EBASH_KEY_RIGHT
- EBASH_KEY_DELETE
- EBASH_KEY_BACKSPACE
- EBASH_KEY_SPACE

So this function helps by reading a character and checking if it looks like the start of a multi-byte control character.
If so, it will read the next character and so on until it has read the required 4 characters to know if it is indeed a
multi-byte control character or not.

```Groff
ARGUMENTS

   __dialog_pid
         Variable name which contains the PID of the dialog process.

   __rc_file
         Variable name which contains the name of the return code file that dialog will write
         its exit code to when it exits.

   __char
         Variable name which we should use for both INPUT and OUTPUT. Specifically, this will
         contain the character that was read in on the last input loop (if any). And this is
         the variable that we will write the updated value to after we read from the input stream.

```

## func dialog_warn

Helper function to make it easier to display simple warning boxes inside dialog. This is similar in purpose and
usage to `ewarn` and will display a dialog msgbox with the provided text.
