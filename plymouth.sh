#!/bin/bash
# 
# Copyright 2013, SolidFire, Inc. All rights reserved.
#

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

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
