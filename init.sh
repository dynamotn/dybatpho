#!/usr/bin/env bash
# @file init.sh
# @brief Initial script
# @description This script should be sourced before any of
# the other scripts in this repo. Other scripts
# make use of ${DYBATPHO_DIR} to find each other.

# Require bash >= v4
if ((BASH_VERSINFO[0] < 4)); then
  echo "dybatpho requires bash v4 or greater"
  echo "Current Bash Version: ${BASH_VERSION}"
  exit 1
fi

# Default shell options
set -Eeuo pipefail         # Strict mode
shopt -s nullglob globstar # Safer and better globbing

# Get path to root of repository and export to subshell
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
export DYBATPHO_DIR

# Load modules
for module in string logging helpers; do
  # shellcheck disable=SC1090
  source "${DYBATPHO_DIR}/src/${module}.sh"
done
