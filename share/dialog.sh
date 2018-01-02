#!/usr/bin/env bash
#
# Copyright 2011-2017, SolidFire, Inc. All rights reserved.
#

# DT-373: Dialog doesn't work properly on OSX and Ubuntu 12.04. The version of dialog on Darwin does not properly
# handle BU_KEY_DELETE and also misses the final character on the last field being modified. Ubuntu 12.04 has a very old
# version of dialog and it is missing required flags --default-button and --default-item. This check will exclude these
# two OSes completely so the code doesn't get included at all. This means we don't have to check for support in all the
# dialog functions as they won't be emitted or callable at all.
if os Darwin || (os_distro ubuntu && os_release 12.04); then
    return 0
fi

# Constants used by dialog to communicate results via exit codes.
DIALOG_OK=0
DIALOG_CANCEL=1
DIALOG_HELP=2
DIALOG_EXTRA=3
DIALOG_ITEM_HELP=4
DIALOG_ESC=255

dialog_load()
{
    # Constants used for various arrow keys. Some of these are standard across all TERMs (TAB, ESC, ENTER, BACKSPACE and DELETE)
    # but the arrow keys are not. So we have to look those up dynamically.
    BU_KEY_UP=$(tput kcuu1) 
    BU_KEY_DOWN=$(tput kcud1)
    BU_KEY_RIGHT=$(tput kcuf1)
    BU_KEY_LEFT=$(tput kcub1)
    BU_KEY_TAB=$'\t'
    BU_KEY_ESC=$'\e'
    BU_KEY_ENTER=$'\n'
    BU_KEY_BACKSPACE=$'\b'
    BU_KEY_DELETE=$'\e[3~'

    # Key sequence when we're done with dialog_prompt and want to hit "OK"
    BU_KEY_DONE="${BU_KEY_TAB}${BU_KEY_ENTER}"
}

# Create an alias to wrap calls to dialog through our tryrc idiom. This is necessary for a couple of reasons. First
# dialog returns non-zero for lots of not-fatal reasons. We don't want callers to throw fatal errors when that happens.
# Intead they should inspect the error codes and output and take action accordingly. Secondly, we need to capture the
# stdout from dialog and then parse it accordingly. Using the tryrc idiom addresses these issues by capturing the 
# return code into 'dialog_rc' and the output into 'dialog_output' for subsequent inspection and parsing.
alias dialog='tryrc --stdout=dialog_output --rc=dialog_rc command dialog --stdout --no-mouse'
dialog_load

opt_usage dialog_info <<'END'
Helper function to make it easier to display simple information boxes inside dialog. This is similar in purpose and
usage to einfo and will display a dialog msgbox with the provided text.
END
dialog_info()
{
    $(dialog --no-cancel --msgbox "$@" 10 50)
    return 0
}

opt_usage dialog_warn <<'END'
Helper function to make it easier to display simple warning boxes inside dialog. This is similar in purpose and
usage to ewarn and will display a dialog msgbox with the provided text.
END
dialog_warn()
{
    $(dialog --no-cancel --colors --title "Warning" --msgbox "$@" 10 50)
    return 0
}

opt_usage dialog_error <<'END'
Helper function to make it easier to display simple error boxes inside dialog. This is similar in purpose and
usage to eerror and will display a dialog msgbox with the provided text.
END
dialog_error()
{
    $(dialog --no-cancel --colors --title "Error" --msgbox "\Zb\Z1$@" 10 50)
    return 0
}

opt_usage dialog_prgbox <<'END'
Helper function to make it easier to use dialog --prgbox without buffering. This is done using stdbuf which can then
disable buffering on stdout and stderr before invoking the command requested by the caller. This way we have a nice
uniform way to call external programs and ensure their output is displayed in real-time instead of waiting until the
program completes.
END
dialog_prgbox()
{
    $(opt_parse \
        ":geometry g=25x100   | Optional geometry in 'HxW format." \
        ":ok_label="OK"       | Optional override of the OK button text." \
        "text                 | Text to display in the program box." \
        "command              | Command to execute and display the output from inside the program box.")

    # Replace the "x" in geometry with a space before passing it through to dialog.
    geometry=${geometry//x/ }
    $(dialog --ok-label "${ok_label}" --prgbox "${text}" "stdbuf -o0 -e0 ${command}" ${geometry})
}

opt_usage dialog_read <<'END'
Helper function for dialog_prompt to try to read a character from stdin. Unfortunately some arrow keys and other
control characters are represented as multi-byte characters (see BU_KEY_UP, BU_KEY_RIGHT, BU_KEY_DOWN, BU_KEY_RIGHT,
BU_KEY_DELETE, BU_KEY_BACKSPACE). So this function helps by reading a character and checking if it looks like the start
of a multi-byte control character. If so, it will read the next character and so on until it has read the required 4
characters to know if it is indeed a multi-byte control character or not.
END
dialog_read()
{
    $(opt_parse output)

    # Try to read the first character if this fails for any reason (usually due to EOF) then propagate the error.
    local c1="" c2="" c3="" c4=""
    IFS= read -rsN1 c1 || return 1

    # If that character was BU_KEY_ESC, then that is a signal that there are more characters to be read as this is the
    # start of a multi-byte control character. So try to read another character with infinitesimally small timeout.
    # Don't fail if nothing is retrieved since user may not actually have pressed a mult-byte character. There is no
    # danger of a race condition here since the multibyte characters are presented to the input stream atomically.
    if [[ "${c1}" == ${BU_KEY_ESC} ]]; then
        local timeout=1
        IFS= read -rsN1 -t ${timeout} c2 || true

        # If we just read a '[' then that is another signal that there is more to read. There may or may not be anything
        # to read so don't fail the read if it times out.
        if [[ "${c2}" == "[" || "${c2}" == "O" ]]; then
            IFS= read -rsN1 -t ${timeout} c3 || true
        fi

        # An arrow key will be done after seeing an 'A', 'B', 'C' or 'D'. If we read anything else, then we may be 
        # reading in BU_KEY_DELETE or BU_KEY_BACKSPACE, so try to read one more character.
        if [[ "${c3}" != @(|A|B|C|D) ]]; then
            IFS= read -rsN1 -t ${timeout} c4 || true
        fi
    fi

    # Assemble all the individual characters into one string and then copy that out to the caller's context.
    local char="${c1}${c2}${c3}${c4}"
    echo "eval declare ${output}=$(printf "%q" "${char}");"
    return 0
}

opt_usage dialog_prompt <<'END'
dialog_prompt provides a very simple interface for the caller to prompt for one or more values from the user using
the dialog(1) ncurses tool. Each named option passed into dialog_prompt will be displayed as a field within dialog.
By default each value is initially empty, but the caller can override this by using 'option=value' syntax wherein 
'value' would be the initial value for 'option' and displayed in the dialog interface. By default all options are 
*required* and the user will be unable to exit the dialog interface until all required fields are provided. The caller
can prefix an option with a '?' to annotate that it is optional. In the dialog interface, required options are marked
as required with a preceeding '*'. After the user fills in all required fields, the provided option names will be 
set to the user provided values. This is done using the "eval command invocation string" idiom so that the code to
set variables is executed in the caller's environment. For example: $(dialog_prompt field).

dialog_prompt tries to intelligently auto detect the geometry of the window based on the number of fields being 
prompted for. It overcomes some annoyances with dialog not scaling very well with how it pads the fields in the 
window. But the caller is always allowed to override this with the --geometry option.
END
dialog_prompt()
{
    $(opt_parse \
        "+instructions=1                                   | Include instructions on how to navigate dialog window."   \
        ":backtitle                                        | Text to display on backdrop at top left of the screen."   \
        ":geometry g                                       | Geometry of the box (HEIGHTxWIDTHxMENU-HEIGHT). "         \
        ":help_label                                       | Override label used for 'Help' button."                   \
        ":help_callback                                    | Callback to invoke when 'Help' button is pressed."        \
        "+hide                                             | Hide ncurses output from screen (useful for testing)."    \
        ":title t=Please provide the following information | String to display as the top of the dialog box."          \
        "+trace                                            | If enabled, enable extensive dialog debugging to stderr." \
        "@fields                                           | List of option fields to prompt for. Field names may not
                                                             contain spaces, newlines or special punctuation characters.")

    # Ensure at least one field was prompted for
    if array_empty fields; then
        die "Must prompt for at least one field."
    fi

    # We're creating an "eval command string" inside the command substitution the caller wraps around dialog_prompt.
    #
    # Command substitution really can only run one big command.  In other words, everything after the first command
    # inside it is passed as an argument to the first command.  But you can separate multiple commands by semicolons
    # inside an eval, so we put an eval around the entire output of dialog_prompt.
    #
    # Later we also put eval around the inside commands.  We basically quote everything twice and then make up for it by
    # eval-ing twice in order to convince everything to keep whitespace as it is.
    echo eval  

    # Compute reasonable geometry if one wasn't explicitly requested by the caller.
    geometry=${geometry//x/ }
    local width=60
    if [[ -z ${geometry} ]]; then
        
        # Inputmenu doesn't scale well. With only a few fields it needs more padding around the menus or they don't
        # fit on the canvas. But with larger number of fields they require less padding or else the canvas is too 
        # large. So set some explicit values for the scale to use to give it good appearance in all these cases.
        local scale=5
        [[ ${#fields[@]} -le 2 ]] && scale=8
        [[ ${#fields[@]} -eq 3 ]] && scale=6
        local height=$(( ${#fields[@]} * ${scale} ))
        local menu_height=$(( ${#fields[@]} * ${scale} ))

        # Minimum height is 11
        [[ ${height} -lt 11 ]] && height=11

        # If instructions were requested we have to increase the height proportionally.
        if [[ ${instructions} -eq 1 ]]; then
            (( height+=5 ))
        fi

        # Final geometry setting
        geometry="${height} ${width} ${menu_height}"
    
    fi

    # Iterate over all the requested fields and create a pack for each of them to allow us to store and access various 
    # metadata about each option. This includes things like the display name, whether it's required or optional, the
    # current value, etc.
    declare -A fpack=()
    local entry="" field="" value="" required=0 display= keys=()
    for entry in "${fields[@]}"; do

        # Parse any provided initial default value for the option.
        if [[ ${entry} =~ = ]]; then
            field=${entry%%=*}
            value=${entry#*=}
        else
            field="${entry}"
            value=""
        fi

        # See if this field is optional or not
        if [[ ! ${field:0:1} == "?" ]]; then
            required=1
            display="*${field^}"
        else
            required=0
            field="${field:1}"
            display="${field^}"
        fi
 
        # Ensure field name doesn't have any unsupported characters. It may not contain spaces, newlines or any special
        # punctuation characters.
        assert_match "${field}" "^[-_A-Za-z1-9]+$" "Invalid characters in $(lval field)"
  
        # Setup the pack and add the field name to the list of keys we'll iterate over later.
        pack_set fpack[$field] value="${value}" display="${display}" required=${required}
        keys+=( "${field}" )
    done

    # Create a temporary directory to contain some temporary files for communication with dialog. The creates an input
    # file to feed input to dialog, and output file to read its output from and a temporary configuration file to alter
    # dialog keybindings. The mechanism we use in this function to drive dialog essentially spawns dialog as a separate
    # background process reading and writing to these temporary files. We then retain foreground control so that we can
    # drive dialog and control its behavior a little better. Normally, the user has to press ENTER in order to enter an
    # input field and then press ENTER again to get out of the input field. This a very unintuitive process that is very
    # clunky for users. So we improve the usabilty by essentially pressing the ENTER key for the user whenever they are
    # on an input field and start typing. Similarly, we automatically exit the input field when the user tries to arrow
    # up or down or tab out of the field.
    local input_fd=0 output_fd=0
    local tmp=$(mktemp --tmpdir --directory eprompt-dialog-XXXXXX)
    trap_add "rm --recursive --force \"${tmp}\""
    local input_file="${tmp}/input"
    local output_file="${tmp}/output"
    local dlgrc="${tmp}/dlgrc"
    mkfifo "${input_file}"
    exec {input_fd}<>${input_file}
    exec {output_fd}<>${output_file}
    local dialog_pid=0 dialog_rc=0

    # Setup array of static arguments to pass through to dialog.
    local dialog_args=(
        --no-mouse
        --input-fd ${input_fd}
        --output-fd ${output_fd}
        --backtitle "${backtitle}"
        --extra-label "Edit"
    )

    # Optionally append trace and help arguments
    [[ ${trace} -eq 1   ]] && dialog_args+=( --trace "$(fd_path)/2" )
    [[ -n ${help_label} ]] && dialog_args+=( --help-button --help-label "${help_label}" )

    # Optionally append navigation instructions into title
    if [[ ${instructions} -eq 1 ]]; then
        eval "local banner=\$(printf -- '-%.0s' {1..$((${width}-4))})"
        title+="\n${banner}\n"
        title+="Use ↑/↓ to navigate between fields. Start typing or hit ←/→ to enter the field to make changes. Press 'enter' to submit changes for that field. To save all pending changes hit 'tab' then 'enter'.\n\Zb\Z1* denotes required fields." 
        title+=""
    fi
    
    # Append final static flags
    dialog_args+=( --inputmenu "${title}" ${geometry} )

    # Where should the ncurses output go to?
    local ncurses_out="$(fd_path)/2"
    if [[ ${hide} -eq 1 ]]; then 
        ncurses_out="/dev/null"
    fi

    # Enter loop to prompt for all required values.
    local offset=0
    local default_button="extra"
    local default_item="$(pack_get fpack[${keys[0]}] display):"
    while true; do

        edebug "[STARTING INPUT LOOP] $(lval default_button default_item dialog_pid offset)"

        # In order to support a more seamless experience for the user we want to only have one of the windows in 
        # focus. This refers to the top window where all the fields are and the bottom window where the control buttons
        # such as 'OK', 'CANCEL', etc., are. Dialog doesn't natively support that but we can easily coerce it to do so
        # by changing the colors so that only the one we want to be 'in focus' has color highlights enabled whereas
        # the other one we set to the same colors as the background so that it blends in and does not look like it
        # has focus. In this first block of code we setup the default color schemes for every iteration. Then we 
        # essentially set the colors for the items and buttons in the unfocused window so that they blend into the
        # background and then do not look like they have focus.
        {
            echo "bindkey menu TAB ENTER"
            echo "tag_key_color = (BLUE,WHITE,ON)"
            echo "tag_key_selected_color = (YELLOW,BLUE,ON)"
            echo "tag_selected_color = (YELLOW,BLUE,ON)" 
            echo "tag_key_selected_color = (YELLOW,BLUE,ON)"
        } > "${dlgrc}"

        if [[ ${default_button} == "ok" ]]; then
            echo "item_selected_color = (BLACK,WHITE,OFF)"
            echo "tag_selected_color = (BLUE,WHITE,ON)"
            echo "tag_key_selected_color = (BLUE,WHITE,ON)"
        else
            echo "item_selected_color = (WHITE,BLUE,ON)"
            echo "tag_selected_color = (YELLOW,BLUE,ON)"
            echo "button_active_color = (BLACK,WHITE,OFF)"
            echo "button_label_active_color = (BLACK,WHITE,OFF)"
        fi >> "${dlgrc}"

        local key="" fields_opt=()
        for key in "${keys[@]}"; do
            fields_opt+=( "$(pack_get fpack[$key] display):" "$(pack_get fpack[$key] value)" )
        done

        echo "" > "${output_file}"

        # Spawn a background dialog process to react to the key presses and other metadata keys we'll feed it through
        # the input file descriptor.
        (
            __BU_INSIDE_TRY=1
            disable_die_parent
            DIALOGRC=${dlgrc} command dialog --colors   \
                --default-button    "${default_button}" \
                --default-item      "${default_item}"   \
                "${dialog_args[@]}" "${fields_opt[@]}"
        ) >${ncurses_out} &

        # While the above process is still running, read characters from stdin and essentially echo them into dialog
        # input file descriptor. But magically insert necessary ENTER keys so that focus will automatically enter the
        # input fiels and automatically exit the input fields when arrow keys or tab are pressed.
        dialog_pid=$!
        edebug "Spawned $(lval dialog_pid)"
        
        # Helper function to provide a consistent and safe way to kill dialog subprocess that we spawn.
        dialog_kill()
        {
            if [[ -n "${dialog_pid:-}" ]]; then
                edebug "Killing $(lval dialog_pid)"
                ekilltree -k=0.25s ${dialog_pid}
                wait ${dialog_pid} &>/dev/null || true
            fi
        }
        trap_add dialog_kill

        # Helper function to cancel the dialog process that we spawned in a consistent reusable way.
        dialog_cancel()
        {
            dialog_kill
            dialog_error "Operation canceled."
            echo "eval return ${DIALOG_CANCEL};"
        }

        local char="" focus=0
        while process_running ${dialog_pid} && $(dialog_read char); do

            # TAB. This key is used to transfer focus between the input fields and the control characters at the bottom
            # of the window. So here we essentially update the default_button.
            if [[ "${char}" == "${BU_KEY_TAB}" && ${focus} -ne 1 ]]; then

                # Ignore TAB if we're in the middle of an input field as it's not clear if the expectation is to
                # insert a literal tab character into the input field or to navigate down to the bottom menu. Doing
                # any kind of automatic navigation is sloppy and confusing for the user.
                if [[ ${focus} -eq 1 ]]; then
                    continue
                fi

                if [[ ${default_button} == "extra" ]]; then
                    default_button="ok"
                elif [[ ${default_button} == "ok" ]]; then
                    default_button="extra"
                fi

                dialog_kill
                continue 2
            
            # ESCAPE KEY. No matter where we are in in dialog, if ESC is pressed we want to cancel out and return to
            # the prior menu.
            elif [[ "${char}" == "${BU_KEY_ESC}" ]]; then
                dialog_cancel
                return 0
            fi

            # FOCUS. This is where all the magic happens to automatically transfer focus into the input fields when
            # any character is typed and automatically transfer focus out of the input field when UP, DOWN or TAB is pressed.
            if [[ ${default_button} == "extra" ]]; then

                # If we already have focus, and we just received an UP or DOWN or ENTER key, then lose focus. Also have
                # to update our offset so that the right field will be highlighted on the next loop.
                if [[ ${focus} -eq 1 && ( "${char}" == "${BU_KEY_UP}" || "${char}" == "${BU_KEY_DOWN}" || "${char}" == "${BU_KEY_ENTER}" || "${char}" == "${BU_KEY_TAB}" ) ]]; then
                    edebug "Lost focus"
                    focus=0
                    echo "" > "${input_file}"

                    if [[ "${char}" == ${BU_KEY_DOWN} || "${char}" == ${BU_KEY_ENTER} || "${char}" == "${BU_KEY_TAB}" ]]; then
                        offset=1
                    elif [[ "${char}" == "${BU_KEY_UP}" ]]; then
                        offset=-1
                    fi

                    break

                # If we do NOT have focus, and pressed anything other than an UP or DOWN keys then transfer focus into
                # the input field by echoing an ENTER key into the input field.
                elif [[ ${focus} -eq 0 && "${char}" != ${BU_KEY_UP} && "${char}" != ${BU_KEY_DOWN} ]]; then
                    edebug "Taking focus"
                    focus=1
                    echo "" > "${input_file}"
                fi
            fi

            # Send this character to dialog
            echo -n "${char}" > "${input_file}"

            # If the button we just pressed was an 'enter' key that may cause the program to exit. But if we loop
            # around too quickly we won't know that and we'll wait for additional input. So this adds in some delay to give the
            # process time to exit before we check if it's running.
            if [[ "${char}" == "${BU_KEY_ENTER}" ]]; then
                edebug "Sleeping to give process a chance to exit."
                sleep 0.25
            fi
        done

        # Wait for process to exit so we know it's return code. Ensure it exited due to one of the valid exit codes.
        # If it exited for any non-dialog reason then we need to abort as something unexpected happened.
        wait ${dialog_pid} &>/dev/null && dialog_rc=0 || dialog_rc=$?
        if [[ ${dialog_rc} != @(${DIALOG_OK}|${DIALOG_CANCEL}|${DIALOG_HELP}|${DIALOG_EXTRA}|${DIALOG_ITEM_HELP}|${DIALOG_ESC}) ]]; then
            dialog_error "Dialog failed with an unknown exit code (${dialog_rc})"
            return ${dialog_rc}
        fi

        local dialog_output="$(string_trim "$(cat "${output_file}")")"
        edebug "Dialog exited $(lval dialog_pid dialog_rc dialog_output)"

        if [[ ${dialog_rc} == ${DIALOG_CANCEL} ]]; then
            dialog_cancel
            return 0
        fi

        # HELP
        local dialog_help="HELP "
        local dialog_renamed="RENAMED "
        if [[ "${dialog_output}" =~ ^${dialog_help} && -n "${help_callback}" ]]; then
            default_button="extra"
            ${help_callback}

        # EDIT
        elif [[ "${dialog_output}" =~ ^${dialog_renamed} ]]; then
            local field=$(echo "${dialog_output}" | grep -Po "RENAMED \K[^:]*")
            local value=$(echo "${dialog_output}" | grep -Po ": \K.*" || true) # May not have any value at all

            # The output from dialog is the *display* which may not match the actual variable passed in. So we have to
            # lookup the correct pack entry from the display key.
            local idx
            for idx in $(array_indexes keys); do
                local key=${keys[$idx]}
                if [[ "${field}" == "$(pack_get fpack[$key] display)" ]]; then

                    edebug "Assigning: $(print_value key) => $(print_value value)"
                    pack_set fpack[$key] value="${value}"

                    local next=$((idx+${offset}))
                    if [[ ${next} -ge ${#keys[@]} ]]; then
                        next=$(( ${#keys[@]} -1 ))
                    elif [[ ${next} -lt 0 ]]; then
                        next=0
                    fi
                    local next_field="${keys[$next]}"
                    default_item="$(pack_get fpack[$next_field] display):"

                    break
                fi
            done
        fi

        # Now check if we are done or not. We should only check this if the user hit the "OK" button. 
        # If there are any required fields that have not been provided display an error
        # and re-prompt them for the required fields.
        if [[ ${default_button} == "ok" || ${dialog_rc} -eq 0 ]]; then

            local missing=()
            for key in "${keys[@]}"; do
                if [[ $(pack_get fpack[$key] required) -eq 1 && -z $(pack_get fpack[$key] value) ]]; then
                    missing+=( $(pack_get fpack[$key] display | sed 's|^*||') )
                fi
            done

            if array_not_empty missing; then
                dialog_error "One or more required fields are $(lval missing)."
                default_button="extra"
                continue
            fi

            edebug "Finished prompting for required fields"
            break
        fi
    done

    # Export final values for caller
    echo "eval declare dialog_rc=${dialog_rc};"
    for key in "${keys[@]}"; do
        edebug "${key}=>$(pack_get fpack[$key] value)"
        echo "eval declare ${key}=$(printf %q "$(printf "%q" "$(pack_get fpack[$key] value)")");"
    done

    # Clean-up
    rm --recursive --force "${tmp}"
    dialog_kill
}

opt_usage dialog_prompt_username_password <<'END'
dialog_prompt_username_password is a special case of dialog_prompt that is specialized to deal with username and password
authentication in a secure manner by not displaying the passwords in plain text in the dialog window. It also deals 
with pecularities around a password wherein we want to present a second inbox box to confirm the password being 
entered is valid. If they don't match the caller is prompted to re-enter the password(s). Otherwise it functions the
same as dialog_prompt does with the "eval command invocation string" idiom so that the code to set variables is
executed in the caller's environment. For example: $(dialog_prompt_username_password). The names of the variables it sets
are 'username' and 'password'.
END
dialog_prompt_username_password()
{
    local default_title="\nPlease provide login information.\n"
    $(opt_parse \
        "+optional               | If true, the username and password are optional. In this case the user will be
                                   allowed to exit the dialog menu without providing username and passwords. Otherwise
                                   it will sit in a loop until the user provides both values." \
        ":title=${default_title} | Title to put at the top of the dialog box.")

    # We're creating an "eval command string" inside the command substitution the caller wraps around dialog_prompt.
    #
    # Command substitution really can only run one big command.  In other words, everything after the first command
    # inside it is passed as an argument to the first command.  But you can separate multiple commands by semicolons
    # inside an eval, so we put an eval around the entire output of dialog_prompt.
    #
    # Later we also put eval around the inside commands.  We basically quote everything twice and then make up for it by
    # eval-ing twice in order to convince everything to keep whitespace as it is.
    echo eval  
    local username=""
    local password=""

    while true; do
        
        # Reset the password on each attempt.
        password=""

        $(dialog \
            --title "Authentication"            \
            --insecure                          \
            --mixedform "${title}"              \
            12 50 3                             \
                "Username"         1 1 "${username}" 1 20 20 0 0 \
                "Password"         2 1 "${password}" 2 20 20 0 1 \
                "Confirm Password" 3 1 "${password}" 3 20 20 0 1)

        username=$(string_getline "${dialog_output}" 1)
        password=$(string_getline "${dialog_output}" 2)
        password_confirm=$(string_getline "${dialog_output}" 3)

        # If any are empty and values are required, show an error and loop again.
        if [[ ${optional} -ne 1 && ( -z "${username}" || -z "${password}" ) ]]; then
            dialog_error "Please provide both a username and a password"
            continue
        fi

        # If passwords don't match it's an error
        if [[ "${password}" != "${password_confirm}" ]]; then
            dialog_error "Passwords do not match"
            continue
        fi

        echo "eval declare username=$(printf %q "${username}"); "
        echo "eval declare password=$(printf %q "${password}"); "
        return 0
    done
}
