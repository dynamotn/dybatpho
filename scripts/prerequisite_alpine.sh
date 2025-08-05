#!/bin/sh
# @file prerequisite_alpine.sh
# @brief Install prerequisites for Alpine Linux container
# @note This script is intended to be run in an fresh Alpine Linux environment,
# this mean you should run this script with Bourne shell, not Bash shell
set -e

apk upgrade --available --no-cache \
  && apk add --no-cache coreutils `# GNU core tools` \
    bash `# Shell` \
    curl `# HTTP(S) tool` \
    ca-certificates `# SSL certs`
