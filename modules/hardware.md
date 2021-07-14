# Module hardware


## func get_memory_size


Get the size of memory on the system in various units. This works properly on both Linux and Mac.

The `--units` option allows you to specify the desired 1 or 2 character code of the units to express the size in. Both
SI and IEC units are supported.

Here is the list of supported unit codes (case-sensitive) along with their meanings:

    B  = bytes

    SI Units
    --------
    K  = kilobytes
    M  = megabytes
    G  = gigabytes
    T  = terabytes
    P  = petabytes

    IEC Units
    ---------
    Ki = kibibyte
    Mi = Mebibyte
    Gi = gibibyte
    Ti = tebibyte
    Pi = pebibyte

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --units <value>
         Units to report memory in (B,K,M,G,T,P,Ki,Mi,Gi,Ti,Pi).

```
