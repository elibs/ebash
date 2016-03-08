#!/bin/bash
#
# Copyright 2016, SolidFire, Inc. All rights reserved.
#
: ${BASHUTILS:=$(dirname $0)}
source ${BASHUTILS}/bashutils.sh || { echo "Unable to source bashutils." ; exit 1 ; }

function class()
{
    argcheck 1
    local className="${1}"
    declare -gA ${className}_base
    obj_init ${className}_base
    for f in "${@:2:${#@}}"; do
        if [[ ${f} == "{" ]]; then
            continue
        elif [[ ${f} == "}" ]]; then
            break
        fi

        if [[ "${f}" == *=* ]]; then
            obj_set ${className}_base.${f}
        else
            obj_func ${className}_base ${f}
        fi
    done
    eval "function ${className}()
    {
        obj_clone ${className}_base \"\${1}\"
        for key in \$(pack_keys ${className}_base); do
            edebug \"Creating function \${1}.\${key}\"
            eval \"function \${1}.\${key}(){
                edebug \"Calling function \${1}.\${key} with args: \\\${@}\"
                obj_run \${1}.\${key} \"\\\${@}\"
            }\"
        done
        if [[ -n \"\$(obj_get \${1}._ctor)\" ]]; then
            obj_run \${1}._ctor \${@:2:\${#@}}
        fi
    }"
}
function extend()
{
    argcheck 1 2
    obj_init ${2}_base
    obj_clone ${1}_base ${2}_base
}
function var()
{
    argcheck 1
    local object="${1%%.*}"
    local variable="${1#*.}"
    variable="${variable%%=*}"
    local value="${1#*=}${@:2:${#@}}"
    edebug "Object='${object}' Variable='${variable}', Value='${value}'"
    eval "function ${object}.${variable}(){
        if [[ \${#@} -eq 2 && \"\${1}\" == \"=\" ]]; then
            obj_set ${object}.${variable}=\"\${@:2:\${#@}}\"
        else
            echo -n \$(obj_get ${object}.${variable})
        fi
    }"
    ${object}.${variable} = "${value}"
}

function obj_init()
{
    argcheck 1
    pack_set "${1}"
}

function obj_clone()
{
    argcheck 1 2
    pack_copy ${1} ${2}
}

function obj_func()
{
    argcheck 1 2
    obj_set "${1}.${2}=${2}"
}

function obj_set()
{
    argcheck 1
    pack_set "${1%%.*}" "${1#*.}"
}

function obj_get()
{
    argcheck 1
    echo "$(pack_get ${1%%.*} ${1#*.})"
}

function obj_run()
{
    argcheck 1
    $(pack_get ${1%%.*} ${1#*.}) ${1%%.*} "${@:2:${#@}}"
}

#====================================================================
# TESTS BEYOND THIS POINT
#====================================================================

printFood()
{
    local this=${1}
    echo "I am a $(${this}.type)."
}
eat()
{
    local this=${1}
    ${this}.printFood
    echo "Nom nom nom... "
}

AppleCtor()
{
    local this=${1}
    var ${this}.type="${2} apple"
    #obj_set ${1}.type=${2}
}

class Food {       \
    printFood      \
    eat            \
}

extend Food Apple
class Apple {       \
    _ctor=AppleCtor \
}

Apple anApple red
anApple.eat


sayHi()
{
    local this=${1}
    if [[ ${#@} -eq 2 && -n "${2}" ]]; then
        echo "Hello $(${2}.name)."
    else
        echo "Hi"
    fi
}

PersonCtor()
{
    local this=${1}
    var ${this}.name="${this}"
}

class Person {       \
    _ctor=PersonCtor \
    sayHi            \
}

Person John
Person Frank
echo "$(John.name) and $(Frank.name) walk in to a bar"
John.sayHi Frank
Frank.sayHi
