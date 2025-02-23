# Module eprompt


## func eprompt

eprompt allows the caller to present a prompt to the user and have the result the user types in echoed back to the
caller's standard output. The current design of eprompt is limited it that you can only prompt for a single value at
a time and it doesn't do anything fancy in terms of validation or knowing about optional or required values. Additionally
the output cannot currently contain newlines though it can contain whitespace.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --silent, -s
         Be silent and do not echo input coming from the terminal.

```

## func eprompt_with_options

eprompt_with_options allows the caller to specify what options are valid responses to the provided question using a
comma separated list. The caller can also optionally provide a list of "secret" options which will not be displayed in
the prompt to the user but will be accepted as a valid response. This list is also comma separated.

```Groff
ARGUMENTS

   msg
        msg

   opt
        opt

   secret
        ?secret

```

## func epromptyn

epromptyn is a special case of eprompt_with_options wherein the only valid options are "Yes" and "No". If the caller
provides anything other than those values they will receive an error message and be presented with another prompt to
re-input the value correctly.

```Groff
ARGUMENTS

   msg
        msg

```
