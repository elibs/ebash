# Binary ebench


This utility isn't yet all that advanced, but it's good for timing various operations in bash and helping you to
understand the time spent on each.

This should at least help us determine what sort of performance effects we have as we change things in ebash. Or at
least, it would do that once we actually test useful things in here. For now, it's mostly useful when you're willing to
edit the script and add the timing of things you're curious about.

Notes to developers:

   * If you add a function BENCH_<something>, you will have created a new item to benchmark. Next time you run ebench,
     it will be run <count> times.

   * If you add an additional function named PREBENCH_<something>, where
     <something> is the same as above, that function will be run once prior to the repeated runs of BENCH_<something>.

   * You can also create POSTBENCH_<something> for cleanup if need be.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --count, -c <value>
         Basline number of times to run each test.

   --exclude, -x <value>
         Benchmarks whose name match this filter will not be run. By default, all are run.

   --filter, -f <value>
         Only benchmarks matching this filter will be run. By default all are run.

```
