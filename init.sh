#!/usr/bin/env bash
# @file init.sh
# @brief Initial script
# @description This script should be sourced before any of
# the other scripts in this repo. Other scripts
# make use of ${DYBATPHO_DIR} to find each other.

# Require bash >= v4
if ((BASH_VERSINFO[0] < 4)); then
  # kcov(disabled)
  echo "dybatpho requires bash v4 or greater"
  echo "Current Bash Version: ${BASH_VERSION}"
  exit 1
  # kcov(enabled)
fi

# Default shell options
set -euo pipefail          # Strict mode
shopt -s nullglob globstar # Safer and better globbing
shopt -s extglob           # Extended globbing

# Get path to root of repository and export to subshell
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
export DYBATPHO_DIR

# Load modules
# shellcheck disable=SC2162
while read module; do
  # shellcheck disable=SC1090
  . "${DYBATPHO_DIR}/src/${module}.sh"
done <"$DYBATPHO_DIR"/modules # kcov(skip)

# Filter functions and re-export only dybatpho functions to subshells
eval "$(declare -F | sed -e 's/-f /-fx /' | grep 'x dybatpho::')"
