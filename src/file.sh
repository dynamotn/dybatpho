#!/usr/bin/env bash
# @file file.sh
# @brief Utilities for file handling
# @description
#   This module contains helpers for previewing files, splitting, joining,
#   normalizing, comparing, and rewriting paths, creating temporary files
#   or directories that are cleaned up automatically on shell exit, and
#   reading or rewriting the contents of a file.
#
#   Every helper that changes a file writes through a staging file in the
#   destination directory and renames it into place, so a reader never observes
#   a half-written file and an interrupted run leaves the original intact. The
#   destination's mode is carried over, and its owner too when the process has
#   the privilege to set it. These helpers honor `DRY_RUN`.
# @see
#   - `example/file_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, helpers that rewrite a file write through a symlink instead of replacing it
DYBATPHO_FILE_FOLLOW_SYMLINKS="${DYBATPHO_FILE_FOLLOW_SYMLINKS:-true}"

#######################################
# @description Show the contents of a file with line numbers.
# @arg $1 string File path
# @stderr File contents
# @tip Uses `bat` when available for richer output, otherwise falls back to `cat -n`
#######################################
function dybatpho::show_file {
  local file_path
  dybatpho::expect_args file_path -- "$@"

  if dybatpho::is command "bat"; then
    bat "${file_path}" >&2
  else
    cat -n "${file_path}" >&2 # kcov(skip)
  fi
}

#######################################
# @description Return the directory component of a path.
# @arg $1 string Path to inspect
# @stdout Directory component of the path
#######################################
function dybatpho::path_dirname {
  local path
  dybatpho::expect_args path -- "$@"
  while [[ "${path}" == */ && "${path}" != "/" ]]; do
    path="${path%/}"
  done
  if [[ "${path}" == "/" ]]; then
    printf '/\n'
  elif [[ "${path}" != */* ]]; then
    printf '.\n'
  else
    path="${path%/*}"
    printf '%s\n' "${path:-/}"
  fi
}

#######################################
# @description Return the basename component of a path.
# @arg $1 string Path to inspect
# @arg $2 string Optional suffix to strip from the basename
# @stdout Basename component of the path
#######################################
function dybatpho::path_basename {
  local path suffix
  dybatpho::expect_args path -- "$@"
  suffix="${2-}"
  while [[ "${path}" == */ && "${path}" != "/" ]]; do
    path="${path%/}"
  done
  if [[ "${path}" == "/" ]]; then
    printf '/\n'
    return 0
  fi
  path="${path##*/}"
  if [[ -n "${suffix}" ]] && dybatpho::string_ends_with "${path}" "${suffix}"; then
    path="${path%"${suffix}"}"
  fi
  printf '%s\n' "${path}"
}

#######################################
# @description Return the final extension of a path, including the leading dot.
# @arg $1 string Path to inspect
# @stdout Final extension of the basename, or empty when none exists
#######################################
function dybatpho::path_extname {
  local basename
  basename=$(dybatpho::path_basename "$1")
  if [[ "${basename}" == '' || "${basename}" == '/' || "${basename}" == *'.' ]]; then
    printf '\n'
  elif [[ "${basename}" == .* && "${basename#*.}" != *.* ]]; then
    printf '\n'
  elif [[ "${basename}" == *.* ]]; then
    printf '%s\n' ".${basename##*.}"
  else
    printf '\n'
  fi
}

#######################################
# @description Return the basename of a path without its final extension.
# @arg $1 string Path to inspect
# @stdout Basename without the final extension
#######################################
function dybatpho::path_stem {
  local basename extname
  basename=$(dybatpho::path_basename "$1")
  extname=$(dybatpho::path_extname "$1")
  if [[ -n "${extname}" ]] && [[ "${basename}" != "/" ]]; then
    basename="${basename%"${extname}"}"
  fi
  printf '%s\n' "${basename}"
}

#######################################
# @description Join path segments with single `/` separators.
# @arg $@ string Path segments to join
# @stdout Joined path
#######################################
function dybatpho::path_join {
  if [[ $# -eq 0 ]]; then
    dybatpho::die "${FUNCNAME[0]}: Expected at least one path segment" # kcov(skip)
  fi

  local result=""
  local segment
  local first_segment=true

  for segment in "$@"; do
    [[ -z "${segment}" ]] && continue

    while [[ "${segment}" == */ && "${segment}" != "/" ]]; do
      segment="${segment%/}"
    done

    if [[ "${first_segment}" == true ]]; then
      if [[ "${segment}" == "/" ]]; then
        result="/"
      elif [[ "${segment}" == /* ]]; then
        while [[ "${segment}" == /* ]]; do
          segment="${segment#/}"
        done
        result="/${segment}"
      else
        result="${segment}"
      fi
      first_segment=false
      continue
    fi

    while [[ "${segment}" == /* ]]; do
      segment="${segment#/}"
    done
    [[ -z "${segment}" ]] && continue

    if [[ -z "${result}" || "${result}" == "/" ]]; then
      result="${result%/}/${segment}"
    else
      result="${result%/}/${segment}"
    fi
  done

  printf '%s\n' "${result}"
}

#######################################
# @description Normalize a path by collapsing repeated separators and resolving `.` and `..` textually.
# @arg $1 string Path to normalize
# @stdout Normalized path
#######################################
function dybatpho::path_normalize {
  local path
  dybatpho::expect_args path -- "$@"

  if [[ -z "${path}" ]]; then
    printf '.\n'
    return 0
  fi

  local is_absolute=false
  [[ "${path}" == /* ]] && is_absolute=true

  while [[ "${path}" == *'//'* ]]; do
    path="${path//\/\//\/}"
  done

  local -a parts=() normalized_parts=()
  local part last_index
  IFS='/' read -r -a parts <<< "${path}"

  for part in "${parts[@]}"; do
    case "${part}" in
      '' | '.')
        continue
        ;;
      '..')
        if ((${#normalized_parts[@]} > 0)); then
          last_index=$((${#normalized_parts[@]} - 1))
          if [[ "${normalized_parts[${last_index}]}" != '..' ]]; then
            unset 'normalized_parts[last_index]'
            continue
          fi
        fi
        [[ "${is_absolute}" == true ]] || normalized_parts+=('..')
        ;;
      *)
        normalized_parts+=("${part}")
        ;;
    esac
  done

  local normalized_path
  normalized_path=$(IFS=/ && printf '%s' "${normalized_parts[*]}")
  if [[ "${is_absolute}" == true ]]; then
    printf '%s\n' "/${normalized_path}"
  elif [[ -n "${normalized_path}" ]]; then
    printf '%s\n' "${normalized_path}"
  else
    printf '.\n'
  fi
}

#######################################
# @description Return success when a path is absolute.
# @arg $1 string Path to inspect
# @exitcode 0 The path is absolute
# @exitcode 1 The path is relative
#######################################
function dybatpho::path_is_abs {
  local path
  dybatpho::expect_args path -- "$@"
  [[ "${path}" == /* ]]
}

#######################################
# @description Return success when a path has any extension or a matching exact extension.
# @arg $1 string Path to inspect
# @arg $2 string Optional extension to compare against
# @exitcode 0 The path has an extension or matches the requested one
# @exitcode 1 The path does not have an extension or does not match the requested one
#######################################
function dybatpho::path_has_ext {
  local path expected_ext actual_ext
  dybatpho::expect_args path -- "$@"
  expected_ext="${2-}"
  if [[ -n "${expected_ext}" && "${expected_ext}" != .* ]]; then
    expected_ext=".${expected_ext}"
  fi
  actual_ext=$(dybatpho::path_extname "${path}")
  if [[ -n "${expected_ext}" ]]; then
    [[ "${actual_ext}" == "${expected_ext}" ]]
  else
    [[ -n "${actual_ext}" ]]
  fi
}

#######################################
# @description Return a path with its final extension replaced.
# @arg $1 string Path to rewrite
# @arg $2 string New extension, with or without leading dot, or empty to remove the extension
# @stdout Path with updated extension
#######################################
function dybatpho::path_change_ext {
  local path new_ext dirname stem
  dybatpho::expect_args path new_ext -- "$@"
  dirname=$(dybatpho::path_dirname "${path}")
  stem=$(dybatpho::path_stem "${path}")
  if [[ -n "${new_ext}" && "${new_ext}" != .* ]]; then
    new_ext=".${new_ext}"
  fi
  if [[ "${dirname}" == "." ]]; then
    printf '%s\n' "${stem}${new_ext}"
  else
    printf '%s\n' "$(dybatpho::path_join "${dirname}" "${stem}${new_ext}")"
  fi
}

#######################################
# @description Return the relative path from a base path to a target path.
# @arg $1 string Target path
# @arg $2 string Base path
# @stdout Relative path from base to target
#######################################
function dybatpho::path_relative {
  local target base
  dybatpho::expect_args target base -- "$@"
  local target_is_absolute=false base_is_absolute=false
  [[ "${target}" == /* ]] && target_is_absolute=true
  [[ "${base}" == /* ]] && base_is_absolute=true
  target=$(dybatpho::path_normalize "${target}")
  base=$(dybatpho::path_normalize "${base}")
  if [[ "${target_is_absolute}" != "${base_is_absolute}" ]]; then
    printf '%s\n' "${target}"
    return 0
  fi

  local -a target_parts=() base_parts=() relative_parts=()
  local i common=0
  if [[ "${target}" != "." ]]; then
    IFS='/' read -r -a target_parts <<< "${target#/}"
  fi
  if [[ "${base}" != "." ]]; then
    IFS='/' read -r -a base_parts <<< "${base#/}"
  fi

  while ((common < ${#target_parts[@]} && common < ${#base_parts[@]})); do
    [[ "${target_parts[${common}]}" == "${base_parts[${common}]}" ]] || break
    common=$((common + 1))
  done

  for ((i = common; i < ${#base_parts[@]}; i++)); do
    [[ -n "${base_parts[${i}]}" ]] && relative_parts+=("..")
  done
  for ((i = common; i < ${#target_parts[@]}; i++)); do
    [[ -n "${target_parts[${i}]}" ]] && relative_parts+=("${target_parts[${i}]}")
  done

  if ((${#relative_parts[@]} == 0)); then
    printf '.\n'
  else
    printf '%s\n' "$(IFS=/ && printf '%s' "${relative_parts[*]}")"
  fi
}

#######################################
# @description Create a temporary file or directory and register it for cleanup on shell exit.
# @example
#   local TMPFILE
#   dybatpho::create_temp TMPFILE ".txt"
#   echo "hello" > "${TMPFILE}"
#
# @example
#   local TMPDIR_VAR
#   dybatpho::create_temp TMPDIR_VAR "/"
#   mkdir -p "${TMPDIR_VAR}/subdir"
#
# @arg $1 string Variable name that receives the created path
# @arg $2 string File extension to append, or `/`/empty to create a directory
# @arg $3 string Name prefix, default is `temp`
# @arg $4 string Parent directory, default is `${TMPDIR:-/tmp}`
# @tip Pass `/` or an empty extension to create a directory instead of a file
# @tip The created path is automatically registered for cleanup on script exit
#######################################
function dybatpho::create_temp {
  local path_var extension
  dybatpho::expect_args path_var extension -- "$@"
  shift 2

  if dybatpho::is empty "${path_var}"; then
    return 1
  fi

  # Ensure existed parent folder
  local parent_folder=${2:-${TMPDIR:-/tmp}}
  if ! dybatpho::is dir "${parent_folder}"; then
    dybatpho::die "Folder ${parent_folder} is not existed" # kcov(skip)
  fi

  extension=${extension%%/*} # Remove '/' and after in extension, for security
  local pid="${BASHPID}"
  local -n temp_path="${path_var}"
  local prefix="${1:-temp}"
  local filename_format="dybatpho_${prefix}_${pid}"
  if hash "mktemp" > /dev/null 2>&1; then
    local temp_template="${parent_folder%/}/${filename_format}_XXXXXXXX"
    if dybatpho::is empty "${extension}"; then
      temp_path=$(mktemp -d "${temp_template}")
    else
      temp_path=$(mktemp "${temp_template}")
      local extended_temp_path="${temp_path}${extension}"
      mv "${temp_path}" "${extended_temp_path}"
      temp_path="${extended_temp_path}"
    fi
  else
    # kcov(disabled)
    if dybatpho::is empty "${extension}"; then
      temp_path="/tmp/${filename_format}"
      mkdir "${temp_path}"
    else
      temp_path="/tmp/${filename_format}${extension}"
      touch "${temp_path}"
    fi
    # kcov(enabled)
  fi
  dybatpho::cleanup_file_on_exit "${temp_path}"
}

#######################################
# @description Read one metadata field of a path across `stat` implementations.
#   GNU and BusyBox `stat` take `-c`, BSD and macOS take `-f` with different
#   format letters, so the GNU form is tried first and the BSD form second.
# @arg $1 string Field to read, one of `mode`, `size`, `mtime`, or `owner`
# @arg $2 string Path to inspect
# @stdout Requested field
# @exitcode 1 No `stat` implementation understood the request
#######################################
function __dybatpho_file_stat {
  local field path gnu_format bsd_format
  dybatpho::expect_args field path -- "$@"
  case "${field}" in
    mode)
      gnu_format='%a'
      bsd_format='%Lp'
      ;;
    size)
      gnu_format='%s'
      bsd_format='%z'
      ;;
    mtime)
      gnu_format='%Y'
      bsd_format='%m'
      ;;
    owner)
      gnu_format='%u:%g'
      bsd_format='%u:%g'
      ;;
    *) dybatpho::die "${FUNCNAME[0]}: Unknown field '${field}'" ;; # kcov(skip)
  esac
  # `-L` makes both flavours report the file a symlink points at, rather than
  # the link itself, which is what every caller of this helper means.
  stat -L -c "${gnu_format}" -- "${path}" 2> /dev/null \
    || stat -L -f "${bsd_format}" -- "${path}" 2> /dev/null
}

#######################################
# @description Follow a symlink chain to the file it ends at.
#   Committing a rewrite means renaming a staging file onto the destination,
#   which would replace a symlink with a regular file and quietly detach it from
#   whatever it pointed at. Resolving first writes through the link instead, so
#   a dotfile symlinked into a repository keeps pointing there and the file in
#   the repository is the one that changes.
# @arg $1 string Path to resolve
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When false-like, return the path unchanged so the symlink itself is replaced
# @stdout Resolved path, or the original path when it is not a symlink
# @exitcode 1 The symlink chain is too deep to be a valid one
#######################################
function __dybatpho_file_resolve {
  local path target depth=0
  dybatpho::expect_args path -- "$@"
  if ! dybatpho::is true "${DYBATPHO_FILE_FOLLOW_SYMLINKS}"; then
    printf '%s\n' "${path}"
    return 0
  fi
  # Plain `readlink` reads one level on every platform, unlike `readlink -f`,
  # which BSD and older macOS do not provide.
  while [[ -L "${path}" ]]; do
    if ((depth++ >= 40)); then
      dybatpho::die "${FUNCNAME[1]}: Too many levels of symbolic links: ${path}"
    fi
    target="$(readlink -- "${path}")"
    [[ "${target}" == /* ]] || target="$(dybatpho::path_dirname "${path}")/${target}"
    path="$(dybatpho::path_normalize "${target}")"
  done
  printf '%s\n' "${path}"
}

#######################################
# @description Print the path of a staging file next to a destination.
#   The staging file has to share a directory with the destination, because
#   `mv` is only atomic within one filesystem.
# @arg $1 string Destination path
# @stdout Staging file path
#######################################
function __dybatpho_file_staging {
  local path directory basename
  dybatpho::expect_args path -- "$@"
  directory="$(dybatpho::path_dirname "${path}")"
  basename="$(dybatpho::path_basename "${path}")"
  printf '%s/.dybatpho_staging_%s.%s\n' "${directory%/}" "${basename}" "${BASHPID}"
}

#######################################
# @description Remove a staging file that will not be committed.
# @arg $1 string Staging file path
#######################################
function __dybatpho_file_discard {
  rm -f -- "${1}" 2> /dev/null || true
}

#######################################
# @description Render a path that is safe to pass to a command that does not
#   understand `--`. The BSD versions of `chmod`, `chown`, and `sed` on macOS
#   treat `--` as a file name rather than as the end of the options, so a path
#   that could be read as an option is prefixed with `./` instead.
# @arg $1 string Path
# @stdout The path, prefixed with `./` when it starts with a dash
#######################################
function __dybatpho_file_operand {
  local path
  dybatpho::expect_args path -- "$@"
  case "${path}" in
    -*) printf '%s\n' "./${path}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

#######################################
# @description Move a staging file onto its destination, carrying the
#   destination's mode and owner over first so that the rename does not change
#   how the file is accessed.
# @arg $1 string Staging file path
# @arg $2 string Destination path
# @exitcode 1 The staging file cannot be moved into place
#######################################
function __dybatpho_file_commit {
  local staging path mode owner operand
  dybatpho::expect_args staging path -- "$@"
  if dybatpho::is file "${path}"; then
    operand="$(__dybatpho_file_operand "${staging}")"
    mode="$(__dybatpho_file_stat mode "${path}" || true)"
    [[ -n "${mode}" ]] && chmod "${mode}" "${operand}"
    # Changing the owner needs privilege the caller usually does not have, so a
    # refusal here is expected rather than a failure.
    owner="$(__dybatpho_file_stat owner "${path}" || true)"
    [[ -n "${owner}" ]] && chown "${owner}" "${operand}" 2> /dev/null || true
  fi
  if ! mv -f -- "${staging}" "${path}"; then
    __dybatpho_file_discard "${staging}"
    dybatpho::die "${FUNCNAME[1]}: Cannot write ${path}"
  fi
}

#######################################
# @description Write standard input to a file through a staging file, so that
#   readers see either the previous contents or the complete new contents.
# @example
#   printf 'port = 8080\n' | dybatpho::file_write_atomic "${HOME}/.config/app.ini"
#
# @example
#   dybatpho::file_write_atomic "./config.json" << 'EOF'
#   { "debug": false }
#   EOF
#
# @arg $1 string Destination file path
# @env DRY_RUN string When true-like, report the write instead of performing it
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing it
# @exitcode 1 The destination directory is missing or the write fails
# @tip The destination keeps its mode, and its owner when the process may set it
#######################################
function dybatpho::file_write_atomic {
  local path directory staging
  dybatpho::expect_args path -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  path="$(__dybatpho_file_resolve "${path}")"
  directory="$(dybatpho::path_dirname "${path}")"
  dybatpho::is dir "${directory}" \
    || dybatpho::die "${FUNCNAME[0]}: Directory doesn't exist: ${directory}"

  if dybatpho::is true "${DRY_RUN}"; then
    # Drain standard input so that the process feeding this helper is not
    # interrupted by a closed pipe.
    cat > /dev/null
    dybatpho::dry_run write "${path}"
    return 0
  fi

  staging="$(__dybatpho_file_staging "${path}")"
  if ! cat > "${staging}"; then
    __dybatpho_file_discard "${staging}" # kcov(skip)
    dybatpho::die "${FUNCNAME[0]}: Cannot write staging file for ${path}" # kcov(skip)
  fi
  __dybatpho_file_commit "${staging}" "${path}"
  dybatpho::debug "Wrote ${path}"
}

#######################################
# @description Pick a `sed` substitution delimiter that appears in neither the
#   pattern nor the replacement, so that neither has to be escaped.
# @arg $1 string Substitution pattern
# @arg $2 string Replacement text
# @stdout Delimiter character
# @exitcode 1 Every candidate delimiter occurs in the pattern or replacement
#######################################
function __dybatpho_file_sed_delimiter {
  local pattern replacement candidate
  dybatpho::expect_args pattern replacement -- "$@"
  for candidate in '/' '|' ',' '#' '%' '^' '!' '@' '+' '=' ':' ';' '~'; do
    [[ "${pattern}" == *"${candidate}"* ]] && continue
    [[ "${replacement}" == *"${candidate}"* ]] && continue
    printf '%s\n' "${candidate}"
    return 0
  done
  return 1
}

#######################################
# @description Substitute every match of a pattern in a file, in place.
# @example
#   dybatpho::file_replace "./app.conf" "^debug = true$" "debug = false"
#
# @example
#   dybatpho::file_replace "./Makefile" "v[0-9]\+\.[0-9]\+" "v2.0"
#
# @arg $1 string File path to rewrite
# @arg $2 string POSIX basic regular expression to match
# @arg $3 string Replacement text, where `&` and `\1` refer to the match
# @env DRY_RUN string When true-like, report the rewrite instead of performing it
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing it
# @exitcode 1 The file is missing, `sed` fails, or no delimiter can be chosen
# @tip This avoids `sed -i`, whose argument differs between GNU and BSD, by
#   rewriting through a staging file instead
#######################################
function dybatpho::file_replace {
  local path pattern replacement delimiter staging
  dybatpho::expect_args path pattern replacement -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  path="$(__dybatpho_file_resolve "${path}")"
  delimiter="$(__dybatpho_file_sed_delimiter "${pattern}" "${replacement}")" \
    || dybatpho::die "${FUNCNAME[0]}: Cannot find a usable sed delimiter for '${pattern}'"

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run replace "${pattern}" "${replacement}" "${path}"
    return 0
  fi

  staging="$(__dybatpho_file_staging "${path}")"
  if ! sed "s${delimiter}${pattern}${delimiter}${replacement}${delimiter}g" \
    "$(__dybatpho_file_operand "${path}")" > "${staging}"; then
    __dybatpho_file_discard "${staging}"
    dybatpho::die "${FUNCNAME[0]}: Cannot apply '${pattern}' to ${path}"
  fi
  __dybatpho_file_commit "${staging}" "${path}"
}

#######################################
# @description Append a line to a file unless the exact line is already there.
#   Running it again changes nothing, which makes it safe for scripts that
#   maintain a dotfile across repeated runs.
# @example
#   dybatpho::file_ensure_line "${HOME}/.bashrc" 'export EDITOR=nvim'
#
# @arg $1 string File path, created when it does not exist
# @arg $2 string Exact line to guarantee
# @env DRY_RUN string When true-like, report the change instead of performing it
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing it
# @exitcode 1 The parent directory is missing or the write fails
# @tip The comparison is an exact whole-line match, not a substring or pattern
#######################################
function dybatpho::file_ensure_line {
  local path line directory staging
  dybatpho::expect_args path line -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  path="$(__dybatpho_file_resolve "${path}")"
  directory="$(dybatpho::path_dirname "${path}")"
  dybatpho::is dir "${directory}" \
    || dybatpho::die "${FUNCNAME[0]}: Directory doesn't exist: ${directory}"

  if dybatpho::is file "${path}" && grep -qxF -- "${line}" "${path}"; then
    dybatpho::debug "Line already present in ${path}"
    return 0
  fi

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run append "${line}" "${path}"
    return 0
  fi

  staging="$(__dybatpho_file_staging "${path}")"
  if dybatpho::is file "${path}"; then
    cat -- "${path}" > "${staging}"
    # A file whose last line has no newline would otherwise absorb the new line.
    if [[ -s "${staging}" ]] && [[ "$(tail -c 1 -- "${staging}")" != "" ]]; then
      printf '\n' >> "${staging}"
    fi
  else
    : > "${staging}"
  fi
  printf '%s\n' "${line}" >> "${staging}"
  __dybatpho_file_commit "${staging}" "${path}"
}

#######################################
# @description Remove every occurrence of an exact line from a file.
#   A file that never contained the line, or that does not exist, is left as is
#   and reported as success: the line is absent either way.
# @example
#   dybatpho::file_remove_line "${HOME}/.bashrc" 'export EDITOR=nvim'
#
# @arg $1 string File path
# @arg $2 string Exact line to remove
# @env DRY_RUN string When true-like, report the change instead of performing it
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing it
# @exitcode 1 The write fails
# @tip The comparison is an exact whole-line match, not a substring or pattern
#######################################
function dybatpho::file_remove_line {
  local path line staging
  dybatpho::expect_args path line -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  path="$(__dybatpho_file_resolve "${path}")"
  if ! dybatpho::is file "${path}" || ! grep -qxF -- "${line}" "${path}"; then
    dybatpho::debug "Line already absent from ${path}"
    return 0
  fi

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run remove "${line}" "${path}"
    return 0
  fi

  staging="$(__dybatpho_file_staging "${path}")"
  # `grep -v` reports "no match" when every line is removed, which is a valid
  # result here rather than a failure.
  grep -vxF -- "${line}" "${path}" > "${staging}" || [[ $? -eq 1 ]] \
    || {
      __dybatpho_file_discard "${staging}" # kcov(skip)
      dybatpho::die "${FUNCNAME[0]}: Cannot filter ${path}" # kcov(skip)
    }
  __dybatpho_file_commit "${staging}" "${path}"
}

#######################################
# @description Print the checksum of a file.
# @example
#   checksum="$(dybatpho::file_hash "./release.tar.gz")"
#   dybatpho::file_hash "./release.tar.gz" sha512
#
# @arg $1 string File path
# @arg $2 string Algorithm, one of `md5`, `sha1`, `sha256` (default), or `sha512`
# @stdout Checksum in lowercase hexadecimal, without the file name
# @exitcode 1 The file is missing, the algorithm is unknown, or no checksum tool is installed
# @tip Falls back from the GNU `*sum` tools to `shasum`/`md5` and then `openssl`
#######################################
function dybatpho::file_hash {
  local path algorithm checksum
  dybatpho::expect_args path -- "$@"
  algorithm="$(dybatpho::lower "${2:-sha256}")"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  case "${algorithm}" in
    md5 | sha1 | sha256 | sha512) ;;
    *) dybatpho::die "${FUNCNAME[0]}: Unknown algorithm '${algorithm}', expected md5, sha1, sha256 or sha512" ;;
  esac

  if dybatpho::is command "${algorithm}sum"; then
    checksum="$("${algorithm}sum" -- "${path}")"
  elif [[ "${algorithm}" == md5 ]] && dybatpho::is command md5; then
    checksum="$(md5 -q -- "${path}")" # kcov(skip)
  elif [[ "${algorithm}" != md5 ]] && dybatpho::is command shasum; then
    checksum="$(shasum -a "${algorithm#sha}" -- "${path}")"
  elif dybatpho::is command openssl; then
    checksum="$(openssl dgst "-${algorithm}" -- "${path}")"
    checksum="${checksum##* }"
  else
    dybatpho::die "${FUNCNAME[0]}: No tool available to compute ${algorithm}" # kcov(skip)
  fi
  # The `*sum` and `shasum` tools print `<checksum>  <path>`.
  printf '%s\n' "${checksum%% *}"
}

#######################################
# @description Print the size of a file in bytes.
# @example
#   bytes="$(dybatpho::file_size "./release.tar.gz")"
#
# @arg $1 string File path
# @stdout Size in bytes
# @exitcode 1 The file is missing
#######################################
function dybatpho::file_size {
  local path size
  dybatpho::expect_args path -- "$@"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  size="$(__dybatpho_file_stat size "${path}" || true)"
  # Counting bytes works anywhere, for the rare `stat` that understands neither
  # format, at the cost of reading the whole file.
  [[ -n "${size}" ]] || size="$(wc -c < "${path}")" # kcov(skip)
  printf '%s\n' "${size// /}"
}

#######################################
# @description Print how many seconds have passed since a file was last modified.
# @example
#   if (($(dybatpho::file_age_seconds "${cache}") > 3600)); then
#     dybatpho::info "Cache is stale"
#   fi
#
# @arg $1 string File path
# @stdout Age in seconds, or `0` when the modification time is in the future
# @exitcode 1 The file is missing or its modification time cannot be read
#######################################
function dybatpho::file_age_seconds {
  local path modified now age
  dybatpho::expect_args path -- "$@"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  modified="$(__dybatpho_file_stat mtime "${path}" || true)"
  [[ -n "${modified}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Cannot read modification time of ${path}" # kcov(skip)
  now="$(date +%s)"
  age=$((now - modified))
  ((age < 0)) && age=0
  printf '%s\n' "${age}"
}

#######################################
# @description Copy a file next to itself under a timestamped name and print
#   the copy's path, so that a caller can undo a change it is about to make.
# @example
#   backup="$(dybatpho::file_backup "${HOME}/.bashrc")"
#   dybatpho::info "Previous version kept at ${backup}"
#
# @arg $1 string File path to back up
# @stdout Path of the backup copy
# @env DRY_RUN string When true-like, print the path without copying anything
# @exitcode 1 The file is missing or the copy fails
# @tip A second backup in the same second gets a numeric suffix, so an existing
#   backup is never overwritten
#######################################
function dybatpho::file_backup {
  local path backup counter
  dybatpho::expect_args path -- "$@"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"

  backup="${path}.$(date +%Y%m%d%H%M%S).bak"
  counter=1
  while [[ -e "${backup}" ]]; do
    backup="${path}.$(date +%Y%m%d%H%M%S).${counter}.bak"
    counter=$((counter + 1))
  done

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run cp -p -- "${path}" "${backup}"
  else
    cp -p -- "${path}" "${backup}" \
      || dybatpho::die "${FUNCNAME[0]}: Cannot back up ${path}" # kcov(skip)
  fi
  printf '%s\n' "${backup}"
}

#######################################
# @description Search a directory and each of its parents for an entry, and
#   print the first one found. This is how a tool locates the root of the
#   project it was invoked inside, from wherever the caller happened to be.
# @example
#   if git_dir="$(dybatpho::find_up ".git")"; then
#     root="$(dybatpho::path_dirname "${git_dir}")"
#   fi
#
# @example
#   manifest="$(dybatpho::find_up "package.json" "${source_dir}")"
#
# @arg $1 string Entry name to look for in each directory
# @arg $2 string Directory to start from, default is the current directory
# @stdout Absolute path of the first matching entry
# @exitcode 0 A matching entry was found
# @exitcode 1 The filesystem root was reached without a match
# @tip Matches files and directories alike, so `.git` is found in a worktree,
#   where it is a file, as well as in a normal clone
#######################################
function dybatpho::find_up {
  local name start current candidate
  dybatpho::expect_args name -- "$@"
  start="${2:-${PWD}}"
  dybatpho::is dir "${start}" \
    || dybatpho::die "${FUNCNAME[0]}: Directory doesn't exist: ${start}"
  current="$(cd -- "${start}" && pwd)"

  while :; do
    candidate="${current%/}/${name}"
    if [[ -e "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    [[ "${current}" == "/" ]] && break
    current="$(dybatpho::path_dirname "${current}")"
  done
  return 1
}

#######################################
# @description Create a directory and every missing parent, then print its
#   path. Running it again on an existing directory changes nothing, which lets
#   a script call it before every write instead of guarding each one.
# @example
#   cache="$(dybatpho::ensure_dir "${HOME}/.cache/myapp")"
#   printf 'cached\n' | dybatpho::file_write_atomic "${cache}/last-run"
#
# @example
#   dybatpho::ensure_dir "${HOME}/.config/myapp" 700 > /dev/null
#
# @arg $1 string Directory path
# @arg $2 string Optional mode applied to the directory, such as `755`
# @stdout The directory path
# @env DRY_RUN string When true-like, print the path without creating anything
# @exitcode 1 The path exists as something other than a directory, or cannot be created
# @tip A mode is applied whether the directory was just created or already
#   existed, so the result does not depend on whether the script ran before
#######################################
function dybatpho::ensure_dir {
  local path mode
  dybatpho::expect_args path -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  mode="${2-}"
  if [[ -e "${path}" ]] && ! dybatpho::is dir "${path}"; then
    dybatpho::die "${FUNCNAME[0]}: Path exists and is not a directory: ${path}"
  fi

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::is dir "${path}" || dybatpho::dry_run mkdir -p -- "${path}"
    [[ -n "${mode}" ]] && dybatpho::dry_run chmod "${mode}" "$(__dybatpho_file_operand "${path}")"
    printf '%s\n' "${path}"
    return 0
  fi

  if ! dybatpho::is dir "${path}"; then
    mkdir -p -- "${path}" \
      || dybatpho::die "${FUNCNAME[0]}: Cannot create directory: ${path}"
    dybatpho::debug "Created directory ${path}"
  fi
  if [[ -n "${mode}" ]]; then
    chmod "${mode}" "$(__dybatpho_file_operand "${path}")" \
      || dybatpho::die "${FUNCNAME[0]}: Cannot set mode ${mode} on ${path}" # kcov(skip)
  fi
  printf '%s\n' "${path}"
}
