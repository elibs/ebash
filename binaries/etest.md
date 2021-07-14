# Binary etest


etest is an extensible test framework primarily focused at providing a rich test framework for bash complete with test
suites and a rich set of test assertions and other various test related frameworks. It also supports running any
standalone executable binaries or scripts written in any language. In this mode it is essentially a simple test driver.

Tests can be grouped into test suites by placing them into a *.etest file. Each test is then a function inside that file
with the naming scheme `ETEST_${suite}_${testcase}` (e.g. `ETEST_array_init` for the `array` suite and the testcase
`init`). Each test suite *.etest file can contain optional `sutie_setup` and `suite_teardown` functions which are
performed only once at the start and end of a suite, respectively. It can also optionally contain `setup` and
`teardown` functions which are run before and after every single individual test.

etest provides several additional security and auditing features of interest:

    1) Every test is run in its own subshell to ensure process isolation.
    2) Every test is run inside a unique cgroup (on Linux) to further isolate the process, mounts and networking from
       the rest of the system.
    3) Each test is monitored for process leaks and mount leaks.

Tests can be repeated, filtered, excluded, debugged, traced and a host of other extensive developer friendly features.

etest produces a JUnit/XUnit compatible etest.xml file at the end of the test run listing all the tests that were
executed along with runtimes and specific lists of passing, failing and flaky tests. This file can be directly hooked
into Jenkins, GitHub Actions, and BitBucket Pipelines for clear test visibility and reporting.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --break, -b
         Stop immediately on first failure.

   --clean, -c
         Clean only and then exit.

   --debug, -D <value>
         EDEBUG output.

   --delete, -d
         Delete all output files when tests complete.

   --exclude, -x <value>
         Tests whose name or file match this (bash-style) regular expression will not be run.

   --failures <value>
         Number of failures per-test to permit. Normally etest will return non-zero if any
         test fails at all. However, in certain circumstances where flaky tests exist it may be
         desireable to allow each test to retried a specified number of times and only classify
         it as a failure if that test fails more than the requested threshold.

   --filter, -f <value>
         Tests whose name or file match this (bash-style) regular expression will be run.

   --html, -h
         Produce an HTML logfile and strip color codes out of etest.log.

   --log-dir <value>
         Directory to place logs in. Defaults to the current directory.

   --mount-ns
         Run tests inside a mount namespace.

   --name <value>
         Name of this test run to use for artifacts and display purposes. Defaults to etest.

   --print-only, --print, -p
         Print list of tests that would be executed based on provided filter and exclude to
         stdout and then exit without actually running any tests.

   --repeat, -r <value>
         Number of times to repeat each test.

   --subreaper
         On Linux, set the CHILD_SUBREAPER flag so that any processes created by etest get
         reparented to etest itself instead of to init or whatever process ancestor may have
         set this flag. This allows us to properly detect process leak detections and ensure
         they are cleaned up properly. At present, this only works on Linux with gdb installed.

   --summary, -s
         Display final summary to terminal in addition to logging it to etest.json.

   --test-list, -l (&)
         File that contains a list of tests to run. This file may contain comments on lines that
         begin with the # character. All other nonblank lines will be interpreted as things that
         could be passed as @tests -- directories, executable scripts, or .etest files. Relative
         paths will be interpreted against the current directory. This option may be specified
         multiple times.

   --timeout <value>
         Per-Test timeout. After this duration the test will be killed if it has not completed.
         You can also define this programmatically in setup() using the ETEST_TIMEOUT variable.
         This uses sleep(1) time syntax.

   --total-timeout <value>
         Total test timeout for entire etest run. This is different than timeout which is for
         a single unit test. This is the total timeout for ALL test suites and tests being
         executed. After this duration etest will be killed if it has not completed. This uses
         sleep(1) time syntax.

   --verbose, -v
         Verbose output.

   --work-dir <value>
         Temporary location where etest can place temporary files. This location will be both
         created and deleted by etest.


ARGUMENTS

   tests
         Any number of individual tests, which may be executables to be executed and checked
         for exit code or may be files whose names end in .etest, in which case they will be
         sourced and any test functions found will be executed. You may also specify directories
         in which case etest will recursively find executables and .etest files and treat them
         in similar fashion.
```
