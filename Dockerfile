#
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

FROM ubuntu:16.04
RUN apt-get update \
    && apt-get install -y util-linux-locales lsb-release
COPY . /bashutils
WORKDIR /bashutils

