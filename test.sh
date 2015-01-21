#!/bin/bash

source efuncs.sh

display()
{
    ## EINFO ##
    einfo "Building RTFI"
    einfos "Copying file1"
    einfos "Copying file2"

    ## WARN ##
    ewarn "OOPS -- there was a potential problem"
    ewarns "On file1"
    ewarns "Or file2"

    ## ERROR ##
    eerror "Aieee! Something terrible happened"
}

# Defaults
ebanner "Defaults"
display

# Timestamps added
ebanner "Timestamps"
EFUNCS_TIME=1 display

# Timestamps and more log level indicators
ebanner "Timestamps + INFO,WARN,ERROR"
EFUNCS_TIME=1 EFUNCS_LEVEL="INFO WARN ERROR" display

# Timestamps + ALL log level indicators
ebanner "Timestamps + ALL levels"
EFUNCS_TIME=1 EFUNCS_LEVEL="INFO INFOS WARN WARNS ERROR" display

# No time + more log levels
ebanner "NO Time, INFO, INFOS, WARN, WARNS"
EFUNCS_TIME=0 EFUNCS_LEVEL="INFO INFOS WARN WARNS ERROR" display

# NO color
EFUNCS_COLOR=0 ebanner "Everything without color"
EFUNCS_COLOR=0 EFUNCS_TIME=1 EFUNCS_LEVEL="INFO INFOS WARN WARNS ERROR" display
