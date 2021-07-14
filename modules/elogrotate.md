# Module elogrotate


## func elogrotate


elogrotate rotates all the log files with a given basename similar to what happens with logrotate. It will always touch
an empty non-versioned file just log logrotate.

For example, if you pass in the pathname '/var/log/foo' and ask to keep a max of 5, it will do the following:

```shell
mv /var/log/foo.4 /var/log/foo.5
mv /var/log/foo.3 /var/log/foo.4
mv /var/log/foo.2 /var/log/foo.3
mv /var/log/foo.1 /var/log/foo.2
mv /var/log/foo   /var/log/foo.1
touch /var/log/foo
```

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --count, -c <value>
         Maximum number of logs to keep

   --size, -s <value>
         If specified, rotate logs at this specified size rather than each call to elogrotate. You
         can use these units: c -- bytes, w -- two-byte words, k -- kilobytes, m -- Megabytes,
         G -- gigabytes


ARGUMENTS

   name
         Base name to use for the logfile.

```
