#!/bin/bash
# 
# Copyright 2011-2013, SolidFire, Inc. All rights reserved.
#

OMCONFIG=/opt/dell/srvadmin/bin/omconfig

# Use omconfig to turn on the little blue LED on the front panel
led_on()
{
    $OMCONFIG chassis leds led=identify flash=on
}

# Use omconfig to turn off the little blue LED on the front panel
led_off()
{
    $OMCONFIG chassis leds led=identify flash=off
}
 
#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
