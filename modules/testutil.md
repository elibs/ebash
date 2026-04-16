# Module testutil


## func skip_file_if

Skip an entire etest file if the provided condition is true. When this is called at the top of a test file and the
condition evaluates to true, ALL tests in that file will be marked as skipped. The tests will still be discovered
but will not be executed.

This should be called at the top level of the test file (not inside a function) using command substitution syntax.

Examples:

```bash
$(skip_file_if "os_distro centos")
$(skip_file_if "! command_exists docker")
```

## func skip_if

Skip an etest if the provided condition is true. Uses exit code 77 (standard skip code) which etest detects and
tracks as a skipped test rather than a pass or fail.

Examples:

```bash
$(skip_if "os_distro centos")
$(skip_if "os_distro centos && os_release 8")
```
