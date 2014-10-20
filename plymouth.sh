#!/bin/bash
# 
# Copyright 2013, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# PULL IN DEPENDENT PACKAGES
#-----------------------------------------------------------------------------
source "${BASHUTILS_PATH}/efuncs.sh"   || { echo "Failed to find efuncs.sh" ; exit 1; }

#-----------------------------------------------------------------------------
# PLYMOUTH
#-----------------------------------------------------------------------------
disable_arrowkeys_vtswitch()
{
    local new_keymap="/tmp/.disable_arrowkeys_vtswitch.kmap"
    echo "keymaps 0-127"   > ${new_keymap}
    echo "keycode 105 = " >> ${new_keymap}
    echo "keycode 106 = " >> ${new_keymap}
    echo "keycode 103 = " >> ${new_keymap}
    echo "keycode 108 = " >> ${new_keymap}

    loadkeys "${new_keymap}" || die "loadkeys ${new_keymap} failed"
}

plymouthd_start()
{
    plymouthd --mode=boot --attach-to-session || { echo "Failed to start plymouthd"; exit 1; }
}

plymouth_start()
{
    plymouth_running || plymouthd_start

    ## Prevent arrow keys from switching Virtual Terminals
    disable_arrowkeys_vtswitch
    
    plymouth --show-splash || die "Failed to show splash"
}

plymouth_stop()
{
    plymouth --wait quit || die "Failed to quit plythmouh"
}

plymouth_restart()
{
    plymouth --wait quit
    plymouth_start
}

plymouth_running()
{
    plymouth --ping
    return $?
}

plymouth_clear()
{
    plymouth --hide-splash
    plymouth --show-splash
}

plymouth_pause()
{
    plymouth_running && plymouth pause-progress
}

plymouth_resume()
{
    plymouth_running && plymouth unpause-progress
}

plymouth_message()
{
    plymouth message --text="$@"
}

plymouth_prompt()
{
    local tmp="/tmp/.plymouth_prompt"
    local result=$(plymouth ask-question --prompt="$@" --command="tee ${tmp}"; rm -f ${tmp})
    echo -en "${result}"
}

plymouth_prompt_timeout()
{
    local timeout=$1 ; shift; [[ -z "${timeout}" ]] && die "Missing timeout value"
    local default=$1 ; shift; [[ -z "${default}" ]] && die "Missing default value"

    local tmp="/tmp/.plymouth_prompt"
    erm ${tmp}
    plymouth ask-question --prompt="$@" --command="tee ${tmp}" &

    local i=0
    while true; do
        if [[ -e ${tmp} ]]; then
            break
        fi

        if [[ ${i} -gt ${timeout} ]]; then
            plymouth_restart
            echo -en "${default}"
            break
        fi

        local left=$((timeout - $i))
        plymouth_message "Will continue in ($left) seconds..."
        sleep 1
        i=$((i+1))
    done

    plymouth_message ""
    erm ${tmp}
}

#-----------------------------------------------------------------------------
# Interposed functions
#-----------------------------------------------------------------------------

override_function einfo '
{
    einfo_real $@
    plymouth_message "$@"
}'

override_function einfon '
{
    einfon_real $@
    plymouth_message "$@"
}'

override_function ewarn '
{
    ewarn_real $@
    plymouth_message "$@"
    sleep 2
}'

override_function eerror '
{
    eerror_real $@
    plymouth_message "$@"
    sleep 5
}'

override_function eprompt '
{
    local output=$(compress_spaces "$@")
    ewarn_real "${output}"
    echo -en $(plymouth_prompt "${output}")
}'

override_function eprompt_timeout '
{
    ewarn_real "$@"
    echo -en $(plymouth_prompt_timeout $@)
}'

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
