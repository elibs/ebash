# Module ansible


## func ansible_status

`ansible_status` is used to relay status back to Ansible in expected JSON format for completed tasks.
This prints status for Ansible in the following format -
{"failed": <true|false> "changed": <true|false> "msg": <user provided message>}

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --changed, -c
         Did this module change anything.

   --failed, -f
         Did this module fail.

   --message, --msg, -m <non-empty value> (*)
         Message associated with this status.

```
