# Module trap


## func trap

ebash asks bash to let the ERR and DEBUG traps be inherited from shell to subshell by setting appropriate shell options.
Unfortunately, its method of enforcing that inheritance is somewhat limited. It only lasts until someone sets any other
trap. At that point, the inhertied trap is erased.

To workaround this behavior, ebash overrides "trap" such that it will do the normal work that you expect trap to do, but
it will also make sure that the ERR and DEBUG traps are truly inherited from shell to shell and persist regardless of
whether other traps are created.

## func trap_add

Appends a command to a trap. By default this will use the default list of signals: ${DIE_SIGNALS[@]}, ERR and EXIT so
that this trap gets called by default for any signal that would cause termination. If that's not the desired behavior
then simply pass in an explicit list of signals to trap.

```Groff
ARGUMENTS

   cmd
         Command to be added to the trap, quoted to be one argument.

   signals
         Signals (or pseudo-signals) that should invoke the trap. Default is EXIT.
```

## func trap_get

Print the trap command associated with a given signal (if any). This essentially parses trap -p in order to extract the
command from that trap for use in other functions such as call_die_traps and trap_add.

```Groff
ARGUMENTS

   sig
         Signal name to print traps for.

```
