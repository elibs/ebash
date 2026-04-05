# ebash

Production-grade bash utility framework with error handling, testing, logging, and data structures.
Originally developed at NetApp/SolidFire (2011-2018).

## Quick Reference

**Always use `make test` to run tests, never `./bin/etest` directly.**

```bash
# Run tests
make test                     # All tests
make test FILTER=emsg         # Filter by name
make test EXCLUDE=docker      # Exclude by name
make test JOBS=8              # Parallel jobs
make test FAILFAST=1          # Stop on first failure

# Lint
make lint

# Docker multi-distro testing
make dtest-debian-12
make dtest-ubuntu-20.04

# Check if executable exists in PATH (ignores functions/aliases)
type -P podman &>/dev/null && echo "podman available"
```

## Project Structure

- `bin/` - Executables (ebash, etest, bashlint, ebench, edoc)
- `share/` - Core modules (58 .sh files)
- `share/etest/` - Test framework modules
- `tests/` - Test suites (70+ .etest files)
- `doc/` - Documentation (14 markdown files)
- `docker/` - Docker build configuration
- `install/` - Dependency installation scripts

## Writing Tests

Tests are bash functions prefixed with `ETEST_` in `.etest` files.
Use `DISABLED_ETEST_` prefix to exclude tests from normal runs (run with `etest --disabled`):

```bash
#!/usr/bin/env bash

ETEST_example()
{
    local result
    result=$(my_function "input")
    assert_eq "expected" "${result}"
}

setup()
{
    # Runs before each test
}

teardown()
{
    # Runs after each test
}
```

### Skipping Tests

Use `$(skip_if condition)` inside a test to skip it when the condition is true:

```bash
ETEST_requires_linux()
{
    $(skip_if "! os linux")
    $(skip_if "os_distro centos && os_release 8")
    # test code here
}
```

Use `$(skip_file_if condition)` at the top of a test file to skip all tests in that file:

```bash
#!/usr/bin/env bash
$(skip_file_if "! os linux")
$(skip_file_if "[[ ${EUID} -ne 0 ]]")
```

## Coding Style

### Formatting
- 4-space indentation (spaces, not tabs except in heredocs)
- Lines under 120 characters
- `then` and `do` on same line as condition
- Use `[[` and `]]` instead of `[` and `]`
- Align newline escape characters (`\`) when breaking long lines

### Naming
- Variables and functions: `lower_snake_case`
- Environment variables: `UPPER_SNAKE_CASE`
- Group related functions with prefixes (e.g., `array_size`, `cgroup_create`)

### Variables
- Always use `${VAR}` notation (except short builtins like `$1`, `$?`, `$!`)
- Every variable must be declared `local` in functions
- Always use curly braces around array indices: `${ARR[$i]}`

### Control Flow
- Prefer explicit `if/else` over one-liner conditionals for variable assignments
- One-liners are fine for simple actions (e.g., `[[ -d dir ]] && cd dir`)

### Arithmetic
- Use `(( ++i ))` (prefix) not `(( i++ ))` (postfix) for incrementing
- Postfix returns original value, so `(( i++ ))` returns 0 when i=0, causing exit code 1
- Prefix returns new value, so `(( ++i ))` returns 1 when i=0, which succeeds

### Error Handling
- ebash enables implicit error detection with stack traces
- Avoid `||` and `&&` around function calls (disables error detection)
- Never use `|| true` as it suppresses fatal errors handling.
  If absolutely required, add a comment explaining why.
- Use `tryrc` or `try/catch` or explicit error checking for expected failures
- Use `die` for fatal errors

### Markdown
- Use `-` for bullets, not `*`
- Use triple backticks with language specifier for code blocks
- Do not prefix shell commands with `$` unless showing command vs output
- Use `> **_NOTE:_**` and `> **_WARNING:_**` for emphasis
- Keep table columns aligned for readability

## Key Modules

| Module         | Purpose                                |
|----------------|----------------------------------------|
| `ebash.sh`     | Bootstrap and configuration            |
| `emsg.sh`      | Logging (einfo, ewarn, eerror, edebug) |
| `opt.sh`       | Option parsing (opt_parse)             |
| `die.sh`       | Error handling (die, die_on_error)     |
| `assert.sh`    | Test assertions (30+ functions)        |
| `try_catch.sh` | Try/catch error handling               |
| `array.sh`     | Array operations                       |
| `json.sh`      | JSON parsing/generation                |
| `emock.sh`     | Mocking framework                      |
| `docker.sh`    | Docker integration                     |

## Git Workflow

- `main` - Production release branch
- `develop` - Active development branch (default for PRs)

## Environment Variables

| Variable       | Purpose                     |
|----------------|-----------------------------|
| `EBASH_HOME`   | Path to ebash installation  |
| `EMSG_PREFIX`  | Log message format          |
| `EDEBUG`       | Debug trace functions       |
| `CI`           | CI/CD environment indicator |

## Common Patterns

### Using ebash in scripts
```bash
#!/usr/bin/env bash
$(ebash --source)
```

### Option parsing
```bash
$(opt_parse \
    "+verbose v | Enable verbose output." \
    ":file f    | Input file path."       \
    "name       | Required positional arg.")
```

### Assertions
```bash
assert_true [[ -f "${file}" ]]
assert_eq "expected" "${actual}"
assert_match "pattern" "${string}"
assert_exists "${path}"
assert_empty "${var}"
```
