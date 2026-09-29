#!/usr/bin/env bash
# @file file_ops.sh
# @brief Example showing file utilities
# @description
#   Demonstrates dybatpho::create_temp, show_file, path_basename, path_dirname, path_extname, path_stem, path_join,
#   path_normalize, path_is_abs, path_has_ext, path_change_ext, path_relative, xdg_config_dir, xdg_cache_dir,
#   xdg_data_dir, xdg_state_dir, create_temp_dir, file_mtime, dir_size, file_is_binary, file_write_atomic, file_replace,
#   file_ensure_line, file_remove_line, file_hash, file_size, file_age_seconds, file_backup, find_up, ensure_dir, and
#   temp cleanup behavior
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# @description Run the `TEMPORARY FILE` section of this example.
# @noargs
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

# @description Run the `TEMPORARY DIRECTORY` section of this example.
# @noargs
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
    local find_output
    find_output=$(find "${TMPDIR_VAR}" -type f | sort)
    while IFS= read -r f || [[ -n "${f}" ]]; do
      dybatpho::print "  ${f}"
    done < <(printf '%s' "${find_output}")
  fi

  dybatpho::info "Temp directory will be removed recursively on exit"
}

# @description Run the `SHOW FILE (source of this script)` section of this example.
# @noargs
function _demo_show_file {
  dybatpho::header "SHOW FILE (source of this script)"
  # Show the first 20 lines of this very script
  local TMPFILE
  dybatpho::create_temp TMPFILE ".sh"
  head -20 "${BASH_SOURCE[0]}" > "${TMPFILE}"
  dybatpho::show_file "${TMPFILE}"
}

# @description Run the `PATH PARTS` section of this example.
# @noargs
function _demo_path_parts {
  dybatpho::header "PATH PARTS"
  local path="/tmp/dybatpho/demo/archive.tar.gz"
  dybatpho::info "Path     : ${path}"
  local path_dirname
  path_dirname=$(dybatpho::path_dirname "${path}")
  dybatpho::info "Dirname  : ${path_dirname}"
  local path_basename_2
  path_basename_2=$(dybatpho::path_basename "${path}")
  dybatpho::info "Basename : ${path_basename_2}"
  local path_extname
  path_extname=$(dybatpho::path_extname "${path}")
  dybatpho::info "Extname  : ${path_extname}"
  local path_basename
  path_basename=$(dybatpho::path_basename "${path}" ".gz")
  dybatpho::info "Stem     : ${path_basename}"
  local path_stem
  path_stem=$(dybatpho::path_stem "${path}")
  dybatpho::info "Stem 2   : ${path_stem}"
}

# @description Run the `PATH JOIN` section of this example.
# @noargs
function _demo_path_join {
  dybatpho::header "PATH JOIN"
  local path_join_2
  path_join_2=$(dybatpho::path_join "/tmp/" "/dybatpho/" "cache" "data.json")
  dybatpho::info "Joined absolute path: ${path_join_2}"
  local path_join
  path_join=$(dybatpho::path_join "var" "log" "dybatpho")
  dybatpho::info "Joined relative path: ${path_join}"
}

# @description Run the `PATH NORMALIZE` section of this example.
# @noargs
function _demo_path_normalize {
  dybatpho::header "PATH NORMALIZE"
  local path_normalize_2
  path_normalize_2=$(dybatpho::path_normalize "/tmp//dybatpho/./cache/../data.json")
  dybatpho::info "Normalized absolute path: ${path_normalize_2}"
  local path_normalize
  path_normalize=$(dybatpho::path_normalize "var//log/../tmp/./app/")
  dybatpho::info "Normalized relative path: ${path_normalize}"
}

# @description Run the `PATH CHECKS / REWRITE` section of this example.
# @noargs
function _demo_path_checks {
  dybatpho::header "PATH CHECKS / REWRITE"
  local path="/tmp/dybatpho/demo/archive.tar.gz"
  local path_is_abs
  path_is_abs=$(dybatpho::path_is_abs "${path}" && echo yes || echo no)
  dybatpho::info "Absolute?      : ${path_is_abs}"
  local path_has_ext
  path_has_ext=$(dybatpho::path_has_ext "${path}" ".gz" && echo yes || echo no)
  dybatpho::info "Has .gz ext?   : ${path_has_ext}"
  local path_change_ext
  path_change_ext=$(dybatpho::path_change_ext "${path}" "zip")
  dybatpho::info "Change ext     : ${path_change_ext}"
  local path_relative
  path_relative=$(dybatpho::path_relative "${path}" "/tmp")
  dybatpho::info "Relative to /tmp: ${path_relative}"
}

# @description Run the `FILE CONTENTS` section of this example.
# @noargs
function _demo_file_contents {
  dybatpho::header "FILE CONTENTS"
  # A throwaway copy of a dotfile, so the demo never touches a real one.
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  local config="${WORKDIR}/app.conf"

  # `file_write_atomic` takes its content on standard input and swaps the file
  # into place, so a reader never sees a half-written config.
  dybatpho::file_write_atomic "${config}" << 'EOF'
debug = true
port = 8080
EOF
  chmod 640 "${config}"
  dybatpho::info "Wrote ${config}"
  dybatpho::show_file "${config}"

  # Keep a copy before editing, and report where it went.
  local backup
  backup="$(dybatpho::file_backup "${config}")"
  local path_basename
  path_basename=$(dybatpho::path_basename "${backup}")
  dybatpho::info "Backup kept at ${path_basename}"

  # A portable in-place edit: no `sed -i`, whose argument differs on BSD.
  dybatpho::file_replace "${config}" '^debug = true$' 'debug = false'
  dybatpho::info "After replace:"
  dybatpho::show_file "${config}"

  local stat
  stat=$(stat -c %a "${config}" 2> /dev/null || stat -f %Lp "${config}")
  dybatpho::info "Mode survived the rewrite: ${stat}"
}

# @description Run the `IDEMPOTENT LINES` section of this example.
# @noargs
function _demo_file_lines {
  dybatpho::header "IDEMPOTENT LINES"
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  local rc="${WORKDIR}/bashrc"
  # shellcheck disable=SC2016 # writing the literal line into the file, not expanding it here
  printf 'export PATH="${HOME}/bin:${PATH}"\n' > "${rc}"

  # Running the same script twice must not duplicate the line, which is what
  # makes these usable in a dotfiles bootstrap.
  dybatpho::file_ensure_line "${rc}" 'export EDITOR=nvim'
  dybatpho::file_ensure_line "${rc}" 'export EDITOR=nvim'
  local grep
  grep=$(grep -cxF 'export EDITOR=nvim' "${rc}")
  dybatpho::info "EDITOR line count after two calls: ${grep}"

  dybatpho::file_remove_line "${rc}" 'export EDITOR=nvim'
  dybatpho::file_remove_line "${rc}" 'export EDITOR=nvim'
  dybatpho::info "After removing it twice:"
  dybatpho::show_file "${rc}"
}

# @description Run the `FILE METADATA` section of this example.
# @noargs
function _demo_file_metadata {
  dybatpho::header "FILE METADATA"
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  local payload="${WORKDIR}/release.txt"
  printf 'dybatpho release payload\n' > "${payload}"

  local file_size
  file_size=$(dybatpho::file_size "${payload}")
  dybatpho::info "Size    : ${file_size} bytes"
  local file_hash_2
  file_hash_2=$(dybatpho::file_hash "${payload}")
  dybatpho::info "SHA-256 : ${file_hash_2}"
  local file_hash
  file_hash=$(dybatpho::file_hash "${payload}" md5)
  dybatpho::info "MD5     : ${file_hash}"
  local file_age_seconds
  file_age_seconds=$(dybatpho::file_age_seconds "${payload}")
  dybatpho::info "Age     : ${file_age_seconds}s since last modification"

  local age
  age="$(dybatpho::file_age_seconds "${payload}")"
  if ((age > 3600)); then
    dybatpho::warn "Cache is stale"
  else
    dybatpho::info "Cache is fresh enough to reuse"
  fi
}

# @description Run the `DRY RUN` section of this example.
# @noargs
function _demo_dry_run {
  dybatpho::header "DRY RUN"
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  local config="${WORKDIR}/guarded.conf"
  printf 'keep = 1\n' > "${config}"

  # Every writer honors DRY_RUN, so a script can be rehearsed before it runs.
  DRY_RUN=true dybatpho::file_replace "${config}" 'keep' 'gone'
  DRY_RUN=true dybatpho::file_ensure_line "${config}" 'added'
  local cat
  cat=$(cat "${config}")
  dybatpho::info "File is untouched: ${cat}"
}

# @description Run the `FIND UP` section of this example.
# @noargs
function _demo_find_up {
  dybatpho::header "FIND UP"
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  mkdir -p "${WORKDIR}/project/src/deep"
  : > "${WORKDIR}/project/.projectrc"

  # Locating the project root from wherever the caller happens to stand.
  local marker
  if marker="$(dybatpho::find_up ".projectrc" "${WORKDIR}/project/src/deep")"; then
    dybatpho::info "Marker : ${marker}"
    local path_dirname
    path_dirname=$(dybatpho::path_dirname "${marker}")
    dybatpho::info "Root   : ${path_dirname}"
  fi

  if dybatpho::find_up "definitely-not-here" "${WORKDIR}" > /dev/null; then
    dybatpho::warn "Unexpected match"
  else
    dybatpho::info "A missing marker reports failure instead of printing a path"
  fi
}

# @description Run the `ENSURE DIR` section of this example.
# @noargs
function _demo_ensure_dir {
  dybatpho::header "ENSURE DIR"
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"

  # `ensure_dir` prints the path, so it composes with the writers directly.
  local cache
  cache="$(dybatpho::ensure_dir "${WORKDIR}/cache/myapp" 700)"
  printf 'last run: ok\n' | dybatpho::file_write_atomic "${cache}/state"
  local stat
  stat=$(stat -c %a "${cache}" 2> /dev/null || stat -f %Lp "${cache}")
  dybatpho::info "Cache dir : ${cache} (mode ${stat})"
  local cat
  cat=$(cat "${cache}/state")
  dybatpho::info "State file: ${cat}"

  # Calling it again is a no-op, so scripts can call it before every write.
  dybatpho::ensure_dir "${WORKDIR}/cache/myapp" 700 > /dev/null
  dybatpho::info "Second call changed nothing"
}

# @description Run the `SYMLINKED DOTFILE` section of this example.
# @noargs
function _demo_symlinked_dotfile {
  dybatpho::header "SYMLINKED DOTFILE"
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  mkdir -p "${WORKDIR}/dotfiles"
  printf 'export EDITOR=vi\n' > "${WORKDIR}/dotfiles/bashrc"
  ln -s "${WORKDIR}/dotfiles/bashrc" "${WORKDIR}/.bashrc"

  # The writers follow the link, so editing the dotfile edits the file in the
  # repository it points at rather than detaching the link from it.
  dybatpho::file_replace "${WORKDIR}/.bashrc" 'EDITOR=vi' 'EDITOR=nvim'
  local value
  value=$([[ -L "${WORKDIR}/.bashrc" ]] && echo yes || echo no)
  # shellcheck disable=SC2088 # `~/.bashrc` is prose in a log line, not a path to expand
  dybatpho::info "~/.bashrc is still a symlink: ${value}"
  local cat
  cat=$(cat "${WORKDIR}/dotfiles/bashrc")
  dybatpho::info "Repository copy now holds  : ${cat}"
}

# @description Run the `XDG DIRECTORIES` section of this example.
# @noargs
function _demo_xdg {
  dybatpho::header "XDG DIRECTORIES"
  # These only build a path. Pairing them with `ensure_dir`, which prints the
  # directory it made, keeps the whole thing to one line.
  local xdg_config_dir_2
  xdg_config_dir_2=$(dybatpho::xdg_config_dir myapp)
  dybatpho::info "config : ${xdg_config_dir_2}"
  local xdg_cache_dir
  xdg_cache_dir=$(dybatpho::xdg_cache_dir myapp)
  dybatpho::info "cache  : ${xdg_cache_dir}"
  local xdg_data_dir
  xdg_data_dir=$(dybatpho::xdg_data_dir myapp)
  dybatpho::info "data   : ${xdg_data_dir}"
  local xdg_state_dir
  xdg_state_dir=$(dybatpho::xdg_state_dir myapp)
  dybatpho::info "state  : ${xdg_state_dir}"
  local xdg_config_dir
  xdg_config_dir=$(dybatpho::xdg_config_dir)
  dybatpho::info "without an application name: ${xdg_config_dir}"

  # A real script would write into the directory it just made; this one keeps
  # to a temporary root so it never touches the user's home.
  local WORKDIR
  dybatpho::create_temp_dir WORKDIR "xdg"
  local state
  state="$(XDG_STATE_HOME="${WORKDIR}/state" dybatpho::xdg_state_dir myapp)"
  state="$(dybatpho::ensure_dir "${state}" 700)"
  local date
  date=$(date +%s)
  printf 'last-run=%s\n' "${date}" | dybatpho::file_write_atomic "${state}/run"
  local mode
  mode=$(stat -c %a "${state}" 2> /dev/null || stat -f %Lp "${state}")
  dybatpho::info "Wrote ${state#"${WORKDIR}"/}/run with mode ${mode}"
}

# @description Run the `INSPECTING FILES AND TREES` section of this example.
# @noargs
function _demo_inspect {
  dybatpho::header "INSPECTING FILES AND TREES"
  local WORKDIR
  dybatpho::create_temp_dir WORKDIR "inspect"
  mkdir -p "${WORKDIR}/tree/sub"
  head -c 1000 /dev/zero > "${WORKDIR}/tree/a.bin"
  printf 'some text\n' > "${WORKDIR}/tree/sub/notes.txt"
  printf 'binary\000payload' > "${WORKDIR}/tree/sub/blob"

  local dir_size
  dir_size=$(dybatpho::dir_size "${WORKDIR}/tree")
  dybatpho::info "Tree total: ${dir_size} bytes"
  local file_size
  file_size=$(dybatpho::file_size "${WORKDIR}/tree/a.bin")
  dybatpho::info "One file  : ${file_size} bytes"
  local file_mtime
  file_mtime=$(dybatpho::file_mtime "${WORKDIR}/tree/sub/notes.txt")
  dybatpho::info "Modified  : ${file_mtime} (epoch seconds)"

  # Checking before a text rewrite is the point of `file_is_binary`: the
  # substitution below would otherwise mangle the binary file.
  local candidate
  for candidate in "${WORKDIR}/tree/sub/notes.txt" "${WORKDIR}/tree/sub/blob"; do
    if dybatpho::file_is_binary "${candidate}"; then
      local path_basename
      path_basename=$(dybatpho::path_basename "${candidate}")
      dybatpho::warn "  ${path_basename} is binary, leaving it alone"
    else
      dybatpho::file_replace "${candidate}" 'some' 'edited'
      local cat
      cat=$(cat "${candidate}")
      local path_basename_2
      path_basename_2=$(dybatpho::path_basename "${candidate}")
      dybatpho::print "  ${path_basename_2} rewritten: ${cat}"
    fi
  done
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_temp_file
  _demo_temp_dir
  _demo_show_file
  _demo_path_parts
  _demo_path_join
  _demo_path_normalize
  _demo_path_checks
  _demo_file_contents
  _demo_file_lines
  _demo_file_metadata
  _demo_dry_run
  _demo_find_up
  _demo_ensure_dir
  _demo_symlinked_dotfile
  _demo_xdg
  _demo_inspect
  dybatpho::success "File operations demo complete"
}

_main "$@"
