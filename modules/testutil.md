# Module testutil


## func skip_if

Skip an etest if the provided condition is true.

Examples:

```bash
$(skip_if "os_distro centos")
$(skip_if "os_distro centos && os_release 8")
```
