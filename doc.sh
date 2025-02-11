#!/usr/bin/env bash
# @file doc.sh
# @brief Generate documentation of dybatpho
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DYBATPHO_DIR/init"
dybatpho::require "shdoc"
dybatpho::require "gawk"

for module in string logging helpers process; do
  shdoc < "$DYBATPHO_DIR/src/$module.sh" > doc/"$module".md || true
done
