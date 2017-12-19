FROM ubuntu:16.04
RUN apt-get update \
    && apt-get install -y util-linux-locales lsb-release
COPY . /bashutils
WORKDIR /bashutils

