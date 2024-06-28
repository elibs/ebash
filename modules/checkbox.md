# Module checkbox


## func checkbox

checkbox is a simple function to display a checkbox at the start of the line followed by an optional message.

## func checkbox_close

This is used to close a previosly opened checkbox with optional return code. The default if no return code is passed in
is `0` for success. This will move the curser up a line and fill in the open `[ ]` checkbox with a checkmark on success
and an `X` on failure.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --all, -a
         If set, kill ALL known checkbox_timer processes, not just the current one

   --return-code, --rc, -r <value>
         Should this checkbox show a mark for success or failure?

```

## func checkbox_eend

`checkbox_eend` is used to print the final closing checkbox message via checkbox_close which in turn passes this function
into eprogress_kill. It will essentially ack the same as `eend` only it prints the checkbox with either a successful
check mark or a failing X.

## func checkbox_failed

checkbox_failed is a simple wrapper around checkbox that displays a failure checkbox and FAILED followed by an optional
message.

## func checkbox_open

Dispay an open checkbox with an optional message to display. You can then later call checkbox_close to have the checkbox
filled in with a successful check mark or with a failing X. This is useful to display a list of dependencies or tasks.

## func checkbox_open_timer

Display an open checkbox with an optional message as well as a timer. This is similar in purpose as checkbox_open only
this also displays a timer. This is useful when you want to have a long-running task with a timer and then fill in the
checkbox with a successful check mark or a failing X.

## func checkbox_passed

checkbox_passed is a simple wrapper around checkbox that displays a successful checkbox and PASSED followed by an
optional message.
