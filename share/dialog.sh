#!/usr/bin/env bash
#
# Copyright 2011-2017, SolidFire, Inc. All rights reserved.
#

# Constants used by dialog to communicate results via exit codes.
DIALOG_OK=0
DIALOG_CANCEL=1
DIALOG_HELP=2
DIALOG_EXTRA=3
DIALOG_ITEM_HELP=4
DIALOG_ESC=255

# Constants used for various arrow keys
DIALOG_KEY_UP=$'\e[A'
DIALOG_KEY_DOWN=$'\e[B'
DIALOG_KEY_TAB="	"
DIALOG_KEY_ESC=$'\e'
DIALOG_KEY_NEWLINE=$'\n'

# Create an alias to wrap calls to dialog through our tryrc idiom. This is necessary for a couple of reasons. First
# dialog returns non-zero for lots of not-fatal reasons. We don't want callers to throw fatal errors when that happens.
# Intead they should inspect the error codes and output and take action accordingly. Secondly, we need to capture the
# stdout from dialog and then parse it accordingly. Using the tryrc idiom addresses these issues by capturing the 
# return code into 'dialog_rc' and the output into 'dialog_output' for subsequent inspection and parsing.
alias dialog='tryrc --stdout=dialog_output --rc=dialog_rc command dialog --stdout --no-mouse'

opt_usage dialog_prgbox <<'END'
Helper function to make it easier to use dialog --prgbox without buffering. This is done using stdbuf which can then
disable buffering on stdout and stderr before invoking the command requested by the caller. This way we have a nice
uniform way to call external programs and ensure their output is displayed in real-time instead of waiting until the
program completes.
END
dialog_prgbox()
{
    $(opt_parse \
        "text                 | Text to display in the program box." \
        "command              | Command to execute and display the output from inside the program box." \
        "?geometry=\"25 100\" | Optional geometry in 'height width' format.")

    $(dialog --prgbox "${text}" "stdbuf -o0 -e0 ${command}" ${geometry})
}
