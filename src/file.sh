#!/usr/bin/env bash
# @file file.sh
# @brief Utilities for file handling
# @description
#   This module contains helpers for previewing files, splitting, joining,
#   normalizing, comparing, and rewriting paths, and creating temporary files
#   or directories that are cleaned up automatically on shell exit.
# @see
#   - `example/file_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

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
    dybatpho::die "${FUNCNAME[0]}: Expected at least one path segment"
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

  while [[ "${path}" == *'//'*
  ]]; do
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
  normalized_path=$(IFS=/; printf '%s' "${normalized_parts[*]}")
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
    ((common++))
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
    printf '%s\n' "$(IFS=/; printf '%s' "${relative_parts[*]}")"
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
    dybatpho::die "Folder ${parent_folder} is not existed"
  fi

  extension=${extension%%/*} # Remove '/' and after in extension, for security
  local pid="${BASHPID}"
  local -n temp_path="${path_var}"
  local prefix="${1:-temp}"
  local filename_format="dybatpho_${prefix}_${pid}"
  if hash "mktemp" > /dev/null 2>&1; then
    if dybatpho::is empty "${extension}"; then
      temp_path=$(mktemp --tmpdir="${parent_folder}" -d "${filename_format}_XXXXXXXX")
    else
      temp_path=$(mktemp --tmpdir="${parent_folder}" "${filename_format}_XXXXXXXX${extension}")
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
