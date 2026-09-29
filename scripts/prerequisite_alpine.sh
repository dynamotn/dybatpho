#!/bin/sh
# This script installs bash, so it cannot be written in it: on a fresh Alpine
# the only shell is BusyBox `ash`, which has neither `set -o pipefail` nor the
# `#!/usr/bin/env bash` this repository asks every other script for.
# dyshellint disable=BSG030,BSG031
# @file prerequisite_alpine.sh
# @brief Install prerequisites for Alpine Linux container
# @description
#   Brings a bare Alpine image up to what the test suite needs: GNU coreutils,
#   bash itself, curl and the CA bundle curl verifies against. The repository's
#   `Dockerfile` runs it as its first layer, before anything else in `scripts/`
#   can run at all.
# @note This script is intended to be run in an fresh Alpine Linux environment,
# this mean you should run this script with Bourne shell, not Bash shell
set -e

apk upgrade --available --no-cache \
  && apk add --no-cache coreutils `# GNU core tools` \
    bash `# Shell` \
    curl `# HTTP(S) tool` \
    ca-certificates `# SSL certs`
