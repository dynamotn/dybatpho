#!/usr/bin/env bash
# @file init.sh
# @brief Initial script
# @description This script should be sourced before any of
# the other scripts in this repo. Other scripts
# make use of ${DYBATPHO_DIR} to find each other.

# Capture the current source path before strict mode. Some shells invoked through
# `bash -c/-lc` may expose an empty `BASH_SOURCE` array transiently.
__dybatpho_init_source="${BASH_SOURCE[0]-}"

# Require bash >= v4
if ((BASH_VERSINFO[0] < 4)); then
  # kcov(disabled)
  echo "dybatpho requires bash v4 or greater"
  echo "Current Bash Version: ${BASH_VERSION}"
  exit 1
  # kcov(enabled)
fi

if [[ -n "${__dybatpho_init_source}" && "${__dybatpho_init_source}" == "${0}" ]]; then
  # kcov(disabled)
  echo "dybatpho can't be executed directly. Please source dybatpho."
  exit 1
  # kcov(enabled)
fi

# Default shell options
set -euo pipefail          # Strict mode
shopt -s nullglob globstar # Safer and better globbing
shopt -s extglob           # Extended globbing

# Get path to root of repository and export to subshell
if [[ -z "${__dybatpho_init_source}" ]]; then
  echo "dybatpho couldn't resolve its source path. Please source init.sh from a file-backed shell context."
  exit 1
fi
DYBATPHO_DIR="$(cd -- "$(dirname "${__dybatpho_init_source}")" && pwd)"
unset __dybatpho_init_source
export DYBATPHO_DIR

# Load modules
# HACK: We need to use declarative modules at here
# to work with bash-language-server (LSP for bash)
# shellcheck source=src/string.sh
. "${DYBATPHO_DIR}/src/string.sh"
# shellcheck source=src/array.sh
. "${DYBATPHO_DIR}/src/array.sh"
# shellcheck source=src/text.sh
. "${DYBATPHO_DIR}/src/text.sh"
# shellcheck source=src/logging.sh
. "${DYBATPHO_DIR}/src/logging.sh"
# shellcheck source=src/helpers.sh
. "${DYBATPHO_DIR}/src/helpers.sh"
# shellcheck source=src/process.sh
. "${DYBATPHO_DIR}/src/process.sh"
# shellcheck source=src/network.sh
. "${DYBATPHO_DIR}/src/network.sh"
# shellcheck source=src/date.sh
. "${DYBATPHO_DIR}/src/date.sh"
# shellcheck source=src/json.sh
. "${DYBATPHO_DIR}/src/json.sh"
# shellcheck source=src/file.sh
. "${DYBATPHO_DIR}/src/file.sh"
# shellcheck source=src/archive.sh
. "${DYBATPHO_DIR}/src/archive.sh"
# shellcheck source=src/git.sh
. "${DYBATPHO_DIR}/src/git.sh"
# shellcheck source=src/table.sh
. "${DYBATPHO_DIR}/src/table.sh"
# shellcheck source=src/cli.sh
. "${DYBATPHO_DIR}/src/cli.sh"
# shellcheck source=src/os.sh
. "${DYBATPHO_DIR}/src/os.sh"
# shellcheck source=src/notification.sh
. "${DYBATPHO_DIR}/src/notification.sh"
# shellcheck source=src/semver.sh
. "${DYBATPHO_DIR}/src/semver.sh"

# Filter functions and re-export only dybatpho functions to subshells
eval "$(declare -F | sed -e 's/-f /-fx /' | grep 'x dybatpho::')"
