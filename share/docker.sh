#!/bin/bash
#
# Copyright 2020, Marshall McMullen <marshall.mcmullen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

opt_usage running_in_docker <<'END'
Check if we are running inside docker or not.
END
running_in_docker()
{
    [[ -f "/.dockerenv" ]] || grep -qw docker /proc/$$/cgroup 2>/dev/null
}
