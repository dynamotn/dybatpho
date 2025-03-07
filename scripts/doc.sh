#!/usr/bin/env bash
# @file doc.sh
# @brief Generate documentation of dybatpho
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../init.sh"
dybatpho::require "shdoc"
dybatpho::require "gawk"

# shellcheck disable=SC2162
while read module; do
  shdoc < "$DYBATPHO_DIR/src/$module.sh" > doc/"$module".md || true
done < "$DYBATPHO_DIR"/modules
