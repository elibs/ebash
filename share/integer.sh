#!/bin/bash

increment()
{
    $(opt_parse \
        "__variable  | Variable to increment" \
        "?__amount=1 | The amount to increment the variable by.")

    eval "${__variable}=$(( __variable += __amount ))"
}

decrement()
{
    $(opt_parse \
        "__variable  | Variable to decrement" \
        "?__amount=1 | The amount to decrement the variable by.")

    eval "${__variable}=$(( __variable -= __amount ))"
}
