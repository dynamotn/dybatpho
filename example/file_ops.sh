#!/usr/bin/env bash
# @file file_ops.sh
# @brief Example showing file utilities
# @description Demonstrates dybatpho::create_temp, show_file, path_basename, path_dirname, path_extname, path_stem, path_join, path_normalize, path_is_abs, path_has_ext, path_change_ext, path_relative, and temp cleanup behavior
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _demo_temp_file {
  dybatpho::header "TEMPORARY FILE"

  local TMPFILE
  dybatpho::create_temp TMPFILE ".sh"
  dybatpho::info "Created temp file: ${TMPFILE}"

  cat > "${TMPFILE}" << 'EOF'
# This is a temporary bash snippet
function hello {
  echo "Hello from temp file!"
}
hello
EOF

  dybatpho::info "Contents of temp file:"
  dybatpho::show_file "${TMPFILE}"
  dybatpho::info "Temp file will be deleted automatically when script exits"
}

function _demo_temp_dir {
  dybatpho::header "TEMPORARY DIRECTORY"

  local TMPDIR_VAR
  dybatpho::create_temp TMPDIR_VAR "/"
  dybatpho::info "Created temp directory: ${TMPDIR_VAR}"

  # Create some files inside
  echo "file one" > "${TMPDIR_VAR}/one.txt"
  echo "file two" > "${TMPDIR_VAR}/two.txt"
  mkdir -p "${TMPDIR_VAR}/subdir"
  echo "nested" > "${TMPDIR_VAR}/subdir/three.txt"

  dybatpho::info "Temp dir contents (tree):"
  if command -v tree &> /dev/null; then
    tree "${TMPDIR_VAR}" >&2
  else
    find "${TMPDIR_VAR}" -type f | sort | while IFS= read -r f; do
      dybatpho::print "  ${f}"
    done
  fi

  dybatpho::info "Temp directory will be removed recursively on exit"
}

function _demo_show_file {
  dybatpho::header "SHOW FILE (source of this script)"
  # Show the first 20 lines of this very script
  local TMPFILE
  dybatpho::create_temp TMPFILE ".sh"
  head -20 "${BASH_SOURCE[0]}" > "${TMPFILE}"
  dybatpho::show_file "${TMPFILE}"
}

function _demo_path_parts {
  dybatpho::header "PATH PARTS"
  local path="/tmp/dybatpho/demo/archive.tar.gz"
  dybatpho::info "Path     : ${path}"
  dybatpho::info "Dirname  : $(dybatpho::path_dirname "${path}")"
  dybatpho::info "Basename : $(dybatpho::path_basename "${path}")"
  dybatpho::info "Extname  : $(dybatpho::path_extname "${path}")"
  dybatpho::info "Stem     : $(dybatpho::path_basename "${path}" ".gz")"
  dybatpho::info "Stem 2   : $(dybatpho::path_stem "${path}")"
}

function _demo_path_join {
  dybatpho::header "PATH JOIN"
  dybatpho::info "Joined absolute path: $(dybatpho::path_join "/tmp/" "/dybatpho/" "cache" "data.json")"
  dybatpho::info "Joined relative path: $(dybatpho::path_join "var" "log" "dybatpho")"
}

function _demo_path_normalize {
  dybatpho::header "PATH NORMALIZE"
  dybatpho::info "Normalized absolute path: $(dybatpho::path_normalize "/tmp//dybatpho/./cache/../data.json")"
  dybatpho::info "Normalized relative path: $(dybatpho::path_normalize "var//log/../tmp/./app/")"
}

function _demo_path_checks {
  dybatpho::header "PATH CHECKS / REWRITE"
  local path="/tmp/dybatpho/demo/archive.tar.gz"
  dybatpho::info "Absolute?      : $(dybatpho::path_is_abs "${path}" && echo yes || echo no)"
  dybatpho::info "Has .gz ext?   : $(dybatpho::path_has_ext "${path}" ".gz" && echo yes || echo no)"
  dybatpho::info "Change ext     : $(dybatpho::path_change_ext "${path}" "zip")"
  dybatpho::info "Relative to /tmp: $(dybatpho::path_relative "${path}" "/tmp")"
}

function _main {
  _demo_temp_file
  _demo_temp_dir
  _demo_show_file
  _demo_path_parts
  _demo_path_join
  _demo_path_normalize
  _demo_path_checks
  dybatpho::success "File operations demo complete"
}

_main "$@"
