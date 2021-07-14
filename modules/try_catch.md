# Module try_catch


## alias catch

Catch block attached to a preceeding try block. This is a rather complex alias and it's probably not readily obvious
why it jumps through the hoops it is jumping through but trust me they are all important. A few important notes about
this alias:

1) Note that the ");" ends the preceeding subshell created by the "try" block. Which means that a try block on it's
   own will be invalid syntax to try to force try/catch to always be used properly.

2) All of the "|| true" stuff in this alias is extremely important. Without it the implicit error handling will kick
   in and the process will be terminated immediately instead of allowing the catch() block to handle the error.

3) It's often really convenient for the catch block to know what the error code was inside the try block. But that's
   actually kinda of hard to get right. So here we capture the error code, and then we employ a curious "( exit $rc; )
   ||" to create a NEW subshell which exits with the original try block's status. If it was 0 this will do nothing.
   Otherwise it will call the catch block handling code. If we didn't care about the nesting
    levels this wouldn't be necessary and we could just simplify the catch alias to "); ||". But knowing the nesting
    level is really important.

4) The dangling "||" here requries the caller to put something after the catch block which sufficiently handles the
   error or the code won't be valid.

## alias disable_die_parent

Prevent an error or other die call in the _current_ shell from killing its parent. By default with ebash, errors
propagate to the parent by sending the parent a sigterm.

You might want to use this in shells that you put in the background if you don't want an error in them to cause you to
be notified via sigterm.

## alias try

The below aliases allow us to support rich error handling through the use of the try/catch idom typically found in
higher level languages. Essentially the 'try' alias creates a subshell and then turns on implicit error handling
through "die_on_error" (which essentially just enables 'set -e'). Since this runs in a subshell with fatal error
handling enabled, the subshell will immediately exit on failure. The catch block which immediately follows the try
block captures the exit status of the subshell and if it's not '0' it will invoke the catch block to handle the error.

One clever trick employed here is to keep track of what level of the try/catch stack we are in so that the parent's
ERR trap won't get triggered and cause the process to exit. Because we WANT the try subshell to exit and allow the
failure to be handled inside the catch block.

## func inside_try

Returns true (0) if the current code is executing inside a try/catch block and false otherwise.

## func throw

Throw is just a simple wrapper around exit but it looks a little nicer inside a 'try' block to see 'throw' instead of
'exit'.

## func tryrc


Tryrc is a convenience wrapper around try/catch that makes it really easy to execute a given command and capture the
command's return code, stdout and stderr into local variables. We created this idiom because if you handle the failure
of a command in any way then bash effectively disables `set -e` that command invocation REGARDLESS OF DEPTH. **Handling
the failure** includes putting it in a while or until loop, part of an if/else statement or part of a command executed
in a `&&` or `||`.

Consider a function call chain such as:

    foo->bar->zap

and you want to get the return value from foo, you might (wrongly) think you could safely use this and safely bypass set
`set -e` explosion:

```shell
foo || rc=$?
```

The problem is bash effectively disables `set -e` for this command when used in this context. That means even if `zap`
encounteres an unhandled error `die` will NOT get implicitly called (explicit calls to `die` would still get called of
course).

Here is the insidious documentation from `man bash` regarding this obscene behavior:

    The ERR trap is not executed if the failed command is part of the command list immediately following a while or
    until keyword, part of the test in an if statement, part of a command executed in a && or ||  list  except the
    command following the final && or ||, any command in a pipeline but the last, or if the command's return value is
    being inverted using !.

What's not obvious from that statement is that this applies to the entire expression including any functions it may call
not just the top-level expression that had an error. Ick.

Thus we created `tryrc` to allow safely capturing the return code, stdout and stderr of a function call WITHOUT bypassing
`set -e` safety!

This is invoked using the "eval command invocation string" idiom so that it is invoked in the caller's envionment. For
example:

```shell
$(tryrc some-command)
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --global, -g
         Make variables created global rather than local

   --rc, -r <value>
         Variable to assign the return code to.

   --stderr, -e <value>
         Write stderr to the specified variable rather than letting it go to stderr. The special
         value '_' means to discard it entirely by sending to to /dev/null.

   --stdout, -o <value>
         Write stdout to the specified variable rather than letting it go to stdout. The special
         value '_' means to discard it entirely by sending it to /dev/null.


ARGUMENTS

   cmd
         Command to run, along with any arguments.
```
