#!/usr/bin/env bash
# @file doc.sh
# @brief Generate documentation of dybatpho
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DYBATPHO_DIR/init.sh"
_require "shdoc"
_require "gawk"

for module in string logging helpers; do
  shdoc < "$DYBATPHO_DIR/src/$module.sh" > doc/"$module".md || true
done
