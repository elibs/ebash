#!/bin/bash
#
# Copyright 2011-2017, SolidFire, Inc. All rights reserved.
#

opt_usage eprompt <<'END'
eprompt allows the caller to present a prompt to the user and have the result the user types in echoed back to the
caller's standard output. The current design of eprompt is limited it that you can only prompt for a single value at
a time and it doesn't do anything fancy in terms of validation or knowing about optional or required values. Additionally
the output cannot currently contain newlines though it can contain whitespace.
END
eprompt()
{
    echo -en "$(ecolor bold) * $@: $(ecolor none)" >&2
    local result=""

    read result < /dev/stdin

    echo -en "${result}"
}

opt_usage eprompt_with_options <<'END'
eprompt_with_options allows the caller to specify what options are valid responses to the provided question using a 
comma separated list. The caller can also optionally provide a list of "secret" options which will not be displayed in
the prompt to the user but will be accepted as a valid response. This list is also comma separated.
END
eprompt_with_options()
{
    $(opt_parse "msg" "opt" "?secret")
    local valid="$(echo ${opt},${secret} | tr ',' '\n' | sort --ignore-case --unique)"
    msg+=" (${opt})"

    ## Keep reading input until a valid response is given
    while true; do
        response=$(eprompt "${msg}")
        matches=( $(echo "${valid}" | grep -io "^${response}\S*" || true) )
        edebug "$(lval response opt secret matches valid)"
        [[ ${#matches[@]} -eq 1 ]] && { echo -en "${matches[0]}"; return 0; }

        eerror "Invalid response=[${response}] -- use a unique prefix from options=[${opt}]"
    done
}

opt_usage epromptyn <<'END'
epromptyn is a special case of eprompt_with_options wherein the only valid options are "Yes" and "No". If the caller
provides anything other than those values they will receive an error message and be presented with another prompt to
re-input the value correctly.
END
epromptyn()
{
    $(opt_parse "msg")
    eprompt_with_options "${msg}" "Yes,No"
}

opt_usage eprompt_dialog_read <<'END'
Helper function for eprompt_dialog to try to read a character from stdin. Unfortunately some arrow keys and other
control characters are represented as multi-byte characters (see KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_RIGHT, KEY_DELETE,
KEY_BASKSPACE). So this function helps by reading a character and checking if it looks like the start of a multi-byte
control character. If so, it will read the next character and so on until it has read the required 4 characters to know
if it is indeed a multi-byte control character or not.
END
eprompt_dialog_read()
{
    $(opt_parse output)

    # Try to read the first character if this fails for any reason (usually due to EOF) then propagate the error.
    local timeout=0.0001 c1="" c2="" c3="" c4=""
    IFS= read -rsN1 c1 || return 1

    # If that character was KEY_ESC, then that is a signal that there are more characters to be read as this is the
    # start of a multi-byte control character. So try to read another character with infinitesimally small timeout.
    # Don't fail if nothing is retrieved since user may not actually have pressed a mult-byte character. There is no
    # danger of a race condition here since the multibyte characters are presented to the input stream atomically.
    if [[ "${c1}" == ${KEY_ESC} ]]; then
        IFS= read -rsN1 -t ${timeout} c2 || true

        # If we just read a '[' then that is another signal that there is more to read. There may or may not be anything
        # to read so don't fail the read if it times out.
        if [[ "${c2}" == "[" ]]; then
            IFS= read -rsN1 -t ${timeout} c3 || true
        fi

        # An arrow key will be done after seeing an 'A', 'B', 'C' or 'D'. If we read anything else, then we may be 
        # reading in KEY_DELETE or KEY_BACKSPACE, so try to read one more character.
        if [[ "${c3}" != @(|A|B|C|D) ]]; then
            IFS= read -rsN1 -t ${timeout} c4 || true
        fi
    fi

    # Assemble all the individual characters into one string and then copy that out to the caller's context.
    local char="${c1}${c2}${c3}${c4}"
    edebug "Read $(lval c1 c2 c3 char)"
    echo "eval declare ${output}=$(printf "%q" "${char}");"
    return 0
}

opt_usage eprompt_dialog <<'END'
eprompt_dialog provides a very simple interface for the caller to prompt for one or more values from the user using
the dialog(1) ncurses tool. Each named option passed into eprompt_dialog will be displayed as a field within dialog.
By default each value is initially empty, but the caller can override this by using 'option=value' syntax wherein 
'value' would be the initial value for 'option' and displayed in the dialog interface. By default all options are 
*required* and the user will be unable to exit the dialog interface until all required fields are provided. The caller
can prefix an option with a '?' to annotate that it is optional. In the dialog interface, required options are marked
as required with a preceeding '*'. After the user fills in all required fields, the provided option names will be 
set to the user provided values. This is done using the "eval command invocation string" idiom so that the code to
set variables is executed in the caller's environment. For example: $(eprompt_dialog field).

eprompt_dialog tries to intelligently auto detect the geometry of the window based on the number of fields being 
prompted for. It overcomes some annoyances with dialog not scaling very well with how it pads the fields in the 
window. But the caller is always allowed to override this with the --geometry option.
END
eprompt_dialog()
{
    $(opt_parse \
        ":backtitle                                        | Text to display on backdrop at top left of the screen."   \
        "+hide                                             | Hide ncurses output from screen (useful for testing)."    \
        "+retry=1                                          | If all required fields are not provided retry. Otherwise 
                                                             abort and return an error."                               \
        ":title t=Please provide the following information | String to display as the top of the dialog box."          \
        ":geometry geom g                                  | Geometry of the box (height width menu-height). "         \
        ":help_label                                       | Override label used for 'Help' button."                   \
        ":help_callback                                    | Callback to invoke when 'Help' button is pressed."        \
        "@fields                                           | List of option fields to prompt for. May not contain
                                                             spaces, newlines or any special punctuation characters.")

	# We're creating an "eval command string" inside the command substitution the caller wraps around eprompt_dialog.
	#
	# Command substitution really can only run one big command.  In other words, everything after the first command
	# inside it is passed as an argument to the first command.  But you can separate multiple commands by semicolons
	# inside an eval, so we put an eval around the entire output of eprompt_dialog.
	#
	# Later we also put eval around the inside commands.  We basically quote everything twice and then make up for it by
	# eval-ing twice in order to convince everything to keep whitespace as it is.
	echo eval  

    # Compute reasonable geometry if one wasn't explicitly requested by the caller.
    if [[ -z ${geometry} ]]; then
        local width=50
        
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
   
        # Setup the pack and add the field name to the list of keys we'll iterate over later.
        pack_set fpack[$field] value="${value}" display="${display}" required=${required}
        keys+=( "${field}" )
    done

    # Determine whether help button should be shown
    local help_args=()
    if [[ -n ${help_label} && -n ${help_callback} ]]; then
        help_args+=( --help-button --help-label "${help_label}" )
    fi

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
    local dialog_pid=

    # Where should the ncurses output go to?
    local ncurses_out="$(fd_path)/2"
    if [[ ${hide} -eq 1 ]]; then 
        ncurses_out="/dev/null"
    fi

    # Bind TAB key to ENTER so we can use it to toggle between input and navigation keys
    echo "bindkey menu TAB ENTER" >> "${dlgrc}"

    # Enter loop to prompt for all required values.
    local default_button="extra"
    local default_item="$(pack_get fpack[${keys[0]}] display):"
    while true; do

        edebug "[STARTING INPUT LOOP] $(lval default_button default_item dialog_pid)"

        local key="" fields_opt=()
        for key in "${keys[@]}"; do
            fields_opt+=( "$(pack_get fpack[$key] display):" "$(pack_get fpack[$key] value)" )
        done

        echo "" > "${output_file}"
        local offset=0

        # Spawn a background dialog process to react to the key presses and other metadata keys we'll feed it through
        # the input file descriptor.
        (
            __BU_INSIDE_TRY=1
            disable_die_parent
            DIALOGRC=${dlgrc} command dialog        \
                --no-mouse                          \
                --input-fd ${input_fd}              \
                --output-fd ${output_fd}            \
                --backtitle "${backtitle}"          \
                --default-button "${default_button}"\
                --default-item "${default_item}"    \
                --extra-label "Edit"                \
                ${help_args[@]:-}                   \
                --inputmenu "${title}"              \
                ${geometry}                         \
                "${fields_opt[@]}"
        ) >${ncurses_out} &

        # While the above process is still running, read characters from stdin and essentially echo them into dialog
        # input file descriptor. But magically insert necessary ENTER keys so that focus will automatically enter the
        # input fiels and automatically exit the input fields when arrow keys or tab are pressed.
        dialog_pid=$!
        edebug "Spawned $(lval dialog_pid)"
        trap_add "ekilltree -s=SIGKILL ${dialog_pid}"
        local char="" focus=0
        while process_running ${dialog_pid} && $(eprompt_dialog_read char); do

            # TAB. This key is used to transfer focus between the input fields and the control characters at the bottom
            # of the window. So here we essentially update the default_button.
            if [[ "${char}" == "${KEY_TAB}" ]]; then
                if [[ ${default_button} == "extra" ]]; then
                    default_button="ok"
                elif [[ ${default_button} == "ok" ]]; then
                    default_button="extra"

                    # Echo two newlines to simulate ENTER key being pressed as follows:
                    # (1) Select "Edit" button
                    # (2) Enter next field for input
                    echo "" > "${input_file}"
                    echo "" > "${input_file}"
                fi

                continue
            
            # ESCAPE KEY. No matter where we are in in dialog, if ESC is pressed we want to cancel out and return to
            # the prior menu.
            elif [[ "${char}" == "${KEY_ESC}" ]]; then
                ekilltree -s=SIGKILL "${dialog_pid}"
                wait ${dialog_pid} &>/dev/null || true
                eerror "Operation cancelled"
                echo "eval return ${DIALOG_CANCEL};"
                return ${DIALOG_CANCEL}
            fi

            # FOCUS. This is where all the magic happens to automatically transfer focus into the input fields when
            # any character is typed and automatically transfer focus out of the input field when UP, DOWN or TAB is pressed.
            if [[ ${default_button} == "extra" ]]; then

                # If we already have focus, and we just received an UP or DOWN or ENTER key, then lose focus. Also have
                # to update our offset so that the right field will be highlighted on the next loop.
                if [[ ${focus} -eq 1 && ( ${char} == ${KEY_UP} || ${char} == ${KEY_DOWN} || ${char} == ${KEY_ENTER} ) ]]; then
                    edebug "Lost focus"
                    focus=0
                    echo "" > "${input_file}"

                    if [[ ${char} == ${KEY_DOWN} || ${char} == ${KEY_ENTER} ]]; then
                        offset=1
                    elif [[ ${char} == ${KEY_UP} ]]; then
                        offset=-1
                    fi

                    break

                # If we do NOT have focus, and pressed anything other than an UP or DOWN keys then transfer focus into
                # the input field by echoing an ENTER key into the input field.
                elif [[ ${focus} -eq 0 && ${char} != ${KEY_UP} && ${char} != ${KEY_DOWN} ]]; then
                    edebug "Taking focus"
                    focus=1
                    echo "" > "${input_file}"
                fi
            fi

            # Send this character to dialog
            echo -n "${char}" > "${input_file}"

            # If the default button is not "extra" then the button we just pressed may cause the program to exit. But if we loop
            # around too quickly we won't know that and we'll wait for additional input. So this adds in some delay to give the
            # process time to exit before we check if it's running.
            if [[ ${default_button} != "extra" && "${char}" == ${KEY_ENTER} ]]; then
                edebug "Sleeping to give process a chance to exit."
                sleep 0.5
            fi
        done

        # Wait for process to exit so we know it's return code.
        wait ${dialog_pid} &>/dev/null && dialog_rc=0 || dialog_rc=$?
        local dialog_output="$(string_trim "$(cat "${output_file}")")"
        edebug "Dialog exited $(lval dialog_pid dialog_rc dialog_output)"
        echo "eval declare dialog_rc=${dialog_rc}; "

        # HELP
        local dialog_help="HELP "
        local dialog_renamed="RENAMED "
        if [[ "${dialog_output}" =~ ^${dialog_help} && -n "${help_callback}" ]]; then
            default_button="ok"
            ${help_callback}

        # EDIT
        elif [[ "${dialog_output}" =~ ^${dialog_renamed} ]]; then
            local field=$(echo "${dialog_output}" | grep -Po "RENAMED \K[^:]*")
            local value=$(echo "${dialog_output}" | grep -Po ": \K.*" || true) # May not have any value at all
            field=${field#\*}
            field=${field,,}
            edebug "Assigning: $(print_value field) => $(print_value value)"
            pack_set fpack[$field] value="${value}"
        fi

        # Find index of the field that was just modified so we can set the default item to the next item in the list.
        local idx
        for idx in $(array_indexes keys); do
            local key=${keys[$idx]}
            if [[ "${default_item}" == "$(pack_get fpack[$key] display):" ]]; then
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

        # Now check if we are done or not. If there are any required fields that have not been provided display an error
        # and re-prompt them for the required fields.
        for key in "${!fpack[@]}"; do
            if [[ $(pack_get fpack[$key] required) -eq 1 && -z $(pack_get fpack[$key] value) ]]; then
                local error_msg="Required field (${key}) was not provided."
                if [[ ${retry} -eq 0 ]]; then
                    die "${error_msg}"
                else
                    eerror "${error_msg}"
                fi

                default_button="extra"
                continue 2
            fi
        done

        # Everything looks great. Go ahead and break out of our input loop.
        if [[ ${dialog_rc} -eq 0 ]]; then
            edebug "Finished prompting for required fields"
            break
        fi
    done

    # Export final values for caller
    for key in "${keys[@]}"; do
        edebug "${key}=>$(pack_get fpack[$key] value)"
        echo "eval declare ${key}=$(printf %q "$(printf "%q" "$(pack_get fpack[$key] value)")");"
    done

    # Clean-up
    rm --recursive --force "${tmp}"
    edebug "Killing $(lval dialog_pid)"
    ekilltree -s=SIGKILL ${dialog_pid}
    wait ${dialog_pid} &>/dev/null || true
}

opt_usage eprompt_dialog_username_password <<'END'
eprompt_dialog_username_password is a special case of eprompt_dialog that is specialized to deal with username and password
authentication in a secure manner by not displaying the passwords in plain text in the dialog window. It also deals 
with pecularities around a password wherein we want to present a second inbox box to confirm the password being 
entered is valid. If they don't match the caller is prompted to re-enter the password(s). Otherwise it functions the
same as eprompt_dialog does with the "eval command invocation string" idiom so that the code to set variables is
executed in the caller's environment. For example: $(eprompt_dialog_username_password). The names of the variables it sets
are 'username' and 'password'.
END
eprompt_dialog_username_password()
{
    local default_title="\nPlese provide login information.\n"
    $(opt_parse \
        "+optional               | If true, the username and password are optional. In this case the user will be
                                   allowed to exit the dialog menu without providing username and passwords. Otherwise
                                   it will sit in a loop until the user provides both values." \
        ":title=${default_title} | Title to put at the top of the dialog box.")

	# We're creating an "eval command string" inside the command substitution the caller wraps around eprompt_dialog.
	#
	# Command substitution really can only run one big command.  In other words, everything after the first command
	# inside it is passed as an argument to the first command.  But you can separate multiple commands by semicolons
	# inside an eval, so we put an eval around the entire output of eprompt_dialog.
	#
	# Later we also put eval around the inside commands.  We basically quote everything twice and then make up for it by
	# eval-ing twice in order to convince everything to keep whitespace as it is.
	echo eval  
    local username=""
    local password=""

    while true; do
        
        $(dialog \
            --title "Authentication"            \
            --insecure                          \
            --mixedform "${title}"              \
            12 50 3                             \
                "Username"         1 1 "${username}" 1 20 20 0 0 \
                "Password"         2 1 "${password}" 2 20 20 0 1 \
                "Confirm Password" 3 1 "${password}" 3 20 20 0 1)

        username=$(dialog_output_line 1)
        password=$(dialog_output_line 2)
        password_confirm=$(dialog_output_line 3)

        # If any are empty and values are required, show an error and loop again.
        if [[ ${optional} -ne 1 && ( -z "${username}" || -z "${password}" ) ]]; then
            eerror "Please provide both a username and a password"
            continue
        fi

        # If passords don't match it's an error
        if [[ "${password}" != "${password_confirm}" ]]; then
            eerror "Passwords do not match"
            continue
        fi

        echo "eval declare username=$(printf %q "${username}"); "
        echo "eval declare password=$(printf %q "${password}"); "
        return 0
    done
}
