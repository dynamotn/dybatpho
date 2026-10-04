# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file file.sh
# @brief Utilities for file handling
# @namespace dybatpho
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

# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, helpers that rewrite a file write through a
#   symlink instead of replacing it
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
    local path_join
    path_join=$(dybatpho::path_join "${dirname}" "${stem}${new_ext}")
    printf '%s\n' "${path_join}"
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
# @note With no explicit parent directory, the path is created under
#   `TMPDIR`, or under the Bats temporary directory when running as a test.
#   Bats re-arms its own `EXIT` trap after each test body, which discards the
#   cleanup trap registered here, so a file left in `TMPDIR` would survive the
#   run; Bats removes its own directory instead.
#######################################
function dybatpho::create_temp {
  local __dybatpho_tmp_var __dybatpho_tmp_ext
  dybatpho::expect_args __dybatpho_tmp_var __dybatpho_tmp_ext -- "$@"
  shift 2

  if dybatpho::is empty "${__dybatpho_tmp_var}"; then
    return 1
  fi
  dybatpho::expect_ref "${__dybatpho_tmp_var}"

  # Ensure existed parent folder
  local __dybatpho_tmp_parent="${2-}"
  if [[ -z "${__dybatpho_tmp_parent}" ]]; then
    __dybatpho_tmp_parent="${TMPDIR:-/tmp}"
    # Bats re-arms its own EXIT trap after each test body, which discards the
    # cleanup trap registered here, so a temporary file left in /tmp would
    # outlive the run. Bats removes its own temporary directory instead, and
    # that is exactly the lifetime a file created by a test should have.
    local __dybatpho_tmp_bats="${BATS_TEST_TMPDIR:-${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR:-}}}"
    if [[ -n "${__dybatpho_tmp_bats}" ]] && dybatpho::is dir "${__dybatpho_tmp_bats}"; then
      __dybatpho_tmp_parent="${__dybatpho_tmp_bats}"
    fi
  fi
  if ! dybatpho::is dir "${__dybatpho_tmp_parent}"; then
    dybatpho::die "Folder ${__dybatpho_tmp_parent} is not existed" # kcov(skip)
  fi

  __dybatpho_tmp_ext=${__dybatpho_tmp_ext%%/*} # Remove '/' and after in extension, for security
  local __dybatpho_tmp_pid="${BASHPID}"
  local -n __dybatpho_tmp_path="${__dybatpho_tmp_var}"
  local __dybatpho_tmp_prefix="${1:-temp}"
  local __dybatpho_tmp_format="dybatpho_${__dybatpho_tmp_prefix}_${__dybatpho_tmp_pid}"
  if hash "mktemp" > /dev/null 2>&1; then
    local __dybatpho_tmp_template="${__dybatpho_tmp_parent%/}/${__dybatpho_tmp_format}_XXXXXXXX"
    # dyshellint disable=BSG046 # this is `dybatpho::create_temp` itself
    if dybatpho::is empty "${__dybatpho_tmp_ext}"; then
      __dybatpho_tmp_path=$(mktemp -d "${__dybatpho_tmp_template}")
    else
      __dybatpho_tmp_path=$(mktemp "${__dybatpho_tmp_template}")
      local __dybatpho_tmp_extended="${__dybatpho_tmp_path}${__dybatpho_tmp_ext}"
      mv "${__dybatpho_tmp_path}" "${__dybatpho_tmp_extended}"
      __dybatpho_tmp_path="${__dybatpho_tmp_extended}"
    fi
  else
    # kcov(disabled)
    # No `mktemp`. The name must still be unpredictable and the creation must
    # still fail rather than follow something that is already there: a name
    # made only of a prefix and a pid is guessable, and `touch` on a symbolic
    # link planted at it writes through to whatever it points at.
    #
    # `mkdir` already fails on an existing name. For a file, `set -C` makes
    # `>` refuse to open one that exists, symbolic link included, which is the
    # `O_EXCL` this path would otherwise be missing.
    local -i __dybatpho_tmp_attempt
    local __dybatpho_tmp_suffix __dybatpho_tmp_umask
    __dybatpho_tmp_umask="$(umask)"
    umask 077
    for ((__dybatpho_tmp_attempt = 0; __dybatpho_tmp_attempt < 10; __dybatpho_tmp_attempt++)); do
      printf -v __dybatpho_tmp_suffix '%04x%04x' "${RANDOM}" "${RANDOM}"
      if dybatpho::is empty "${__dybatpho_tmp_ext}"; then
        __dybatpho_tmp_path="${__dybatpho_tmp_parent%/}/${__dybatpho_tmp_format}_${__dybatpho_tmp_suffix}"
        mkdir "${__dybatpho_tmp_path}" 2> /dev/null && break
      else
        __dybatpho_tmp_path="${__dybatpho_tmp_parent%/}/${__dybatpho_tmp_format}_${__dybatpho_tmp_suffix}"
        __dybatpho_tmp_path+="${__dybatpho_tmp_ext}"
        (
          set -C
          : > "${__dybatpho_tmp_path}"
        ) 2> /dev/null && break
      fi
      __dybatpho_tmp_path=""
    done
    umask "${__dybatpho_tmp_umask}"
    [[ -n "${__dybatpho_tmp_path}" ]] \
      || dybatpho::die "${FUNCNAME[0]}: Unable to create a temporary path under ${__dybatpho_tmp_parent}"
    # kcov(enabled)
  fi
  dybatpho::cleanup_file_on_exit "${__dybatpho_tmp_path}"
}

#######################################
# @description Read one metadata field of a path across `stat` implementations.
#   GNU and BusyBox `stat` take `-c`, BSD and macOS take `-f` with different
#   format letters, so the GNU form is tried first and the BSD form second.
# @arg $1 string Field to read, one of `mode`, `size`, `mtime`, or `owner`
# @arg $2 string Path to inspect
# @stdout Requested field
# @exitcode 1 No `stat` implementation understood the request
# @internal
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
# @description Walk a directory tree into two parallel arrays: each entry's
#   path relative to the root, and its kind, one of `file`, `directory`,
#   `symlink` or `other`.
#   The walk runs from inside the root, so a root that is itself a symbolic
#   link to a directory is walked as that directory, and `find` prints the same
#   `./`-relative paths on GNU, BSD and BusyBox. Entries are read
#   NUL-separated, which keeps a name holding a newline in one piece, and come
#   back in byte order, which puts every directory ahead of what it holds. The
#   root itself is not an entry, and a symbolic link is never followed.
#
#   A part of the tree that cannot be read makes the walk fail, though the
#   arrays still hold everything that was listed: `find` lists what it can and
#   reports the rest, and passing that on as a complete tree let a comparison
#   or a checksum stand in for contents nobody had read.
# @arg $1 string Name of the array receiving the relative paths
# @arg $2 string Name of the array receiving the kinds, or `-`
# @arg $3 string Directory to walk
# @set The two named arrays
# @exitcode 1 The root, or something under it, could not be read
# @internal
#######################################
function __dybatpho_file_walk_into {
  local -a __dybatpho_file_walk_unwanted=()
  local -n __dybatpho_file_walk_paths="$1"
  local -n __dybatpho_file_walk_kinds="${2/#-/__dybatpho_file_walk_unwanted}"
  local __dybatpho_file_walk_root="$3" __dybatpho_file_walk_entry __dybatpho_file_walk_full
  __dybatpho_file_walk_paths=()
  __dybatpho_file_walk_kinds=()

  # Listed into a file first, so `find`'s status survives: a process
  # substitution would drop it, and a NUL-separated list cannot be held in a
  # variable. Not a `__dybatpho`-prefixed name: `dybatpho::create_temp` refuses one.
  local dybatpho_file_walk_list __dybatpho_file_walk_status=0
  dybatpho::create_temp dybatpho_file_walk_list ".walk" "walk"
  (cd -- "${__dybatpho_file_walk_root}" && find . -mindepth 1 -print0) \
    > "${dybatpho_file_walk_list}" || __dybatpho_file_walk_status=1
  LC_ALL=C sort -z -o "${dybatpho_file_walk_list}" -- "${dybatpho_file_walk_list}" \
    || __dybatpho_file_walk_status=1

  while IFS= read -r -d '' __dybatpho_file_walk_entry; do
    __dybatpho_file_walk_entry="${__dybatpho_file_walk_entry#./}"
    __dybatpho_file_walk_full="${__dybatpho_file_walk_root}/${__dybatpho_file_walk_entry}"
    __dybatpho_file_walk_paths+=("${__dybatpho_file_walk_entry}")
    if [[ -L "${__dybatpho_file_walk_full}" ]]; then
      __dybatpho_file_walk_kinds+=(symlink)
    elif [[ -d "${__dybatpho_file_walk_full}" ]]; then
      __dybatpho_file_walk_kinds+=(directory)
    elif [[ -f "${__dybatpho_file_walk_full}" ]]; then
      __dybatpho_file_walk_kinds+=(file)
    else
      __dybatpho_file_walk_kinds+=(other)
    fi
    # kcov never records the redirection line of a loop; the body above it runs.
  done < "${dybatpho_file_walk_list}" # kcov(skip)
  rm -f -- "${dybatpho_file_walk_list}"
  return "${__dybatpho_file_walk_status}"
}

#######################################
# @description Follow a symlink chain to the file it ends at, and set a
#   variable to it.
#   Committing a rewrite means renaming a staging file onto the destination,
#   which would replace a symlink with a regular file and quietly detach it from
#   whatever it pointed at. Resolving first writes through the link instead, so
#   a dotfile symlinked into a repository keeps pointing there and the file in
#   the repository is the one that changes.
#
#   It runs in the caller's shell, so a chain too deep to be valid stops the
#   script there. Called inside `$(...)`, the refusal ended only the
#   substitution, and wherever errexit was suspended the writer carried on with
#   an empty path and staged a file in the working directory.
# @arg $1 string Name of the variable receiving the resolved path
# @arg $2 string Path to resolve
# @arg $3 string Name the refusal is reported under
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When false-like, return the path unchanged so the symlink itself is replaced
# @set The named variable: the resolved path, or the path itself when it is not a symlink
# @internal
#######################################
function __dybatpho_file_resolve_into {
  local -n __dybatpho_file_resolve_ref="$1"
  local __dybatpho_file_resolve_path="$2" __dybatpho_file_resolve_caller="$3"
  local __dybatpho_file_resolve_target __dybatpho_file_resolve_depth=0
  if ! dybatpho::is true "${DYBATPHO_FILE_FOLLOW_SYMLINKS}"; then
    __dybatpho_file_resolve_ref="${__dybatpho_file_resolve_path}"
    return 0
  fi
  # Plain `readlink` reads one level on every platform, unlike `readlink -f`,
  # which BSD and older macOS do not provide.
  while [[ -L "${__dybatpho_file_resolve_path}" ]]; do
    if ((__dybatpho_file_resolve_depth++ >= 40)); then
      local __dybatpho_file_resolve_why="Too many levels of symbolic links"
      dybatpho::die "${__dybatpho_file_resolve_caller}: ${__dybatpho_file_resolve_why}: ${__dybatpho_file_resolve_path}"
    fi
    __dybatpho_file_resolve_target="$(readlink -- "${__dybatpho_file_resolve_path}")"
    if [[ "${__dybatpho_file_resolve_target}" != /* ]]; then
      local __dybatpho_file_resolve_dir
      __dybatpho_file_resolve_dir="$(dybatpho::path_dirname "${__dybatpho_file_resolve_path}")"
      __dybatpho_file_resolve_target="${__dybatpho_file_resolve_dir}/${__dybatpho_file_resolve_target}"
    fi
    __dybatpho_file_resolve_path="$(dybatpho::path_normalize "${__dybatpho_file_resolve_target}")"
  done
  __dybatpho_file_resolve_ref="${__dybatpho_file_resolve_path}"
}

#######################################
# @description Create a staging file next to a destination, and set a
#   variable to its path.
#   The staging file has to share a directory with the destination, because
#   `mv` is only atomic within one filesystem. Its name carries a random suffix
#   and it is created exclusively: a name built from the process id alone could
#   be guessed, and anyone able to write to the directory could plant a link
#   there and have the rewrite land in the file the link points at. With
#   `noclobber`, a name that is already taken, link or not, is refused and a
#   fresh one is tried. The file is created through a redirection, so its mode
#   follows the umask as a plain write would.
# @arg $1 string Name of the variable receiving the staging file path
# @arg $2 string Destination path
# @set The named variable
# @exitcode 1 No staging file can be created in the destination's directory
# @internal
#######################################
function __dybatpho_file_staging_into {
  local -n __dybatpho_file_staging_ref="$1"
  local __dybatpho_file_staging_path="$2"
  local __dybatpho_file_staging_dir __dybatpho_file_staging_base
  local __dybatpho_file_staging_name __dybatpho_file_staging_try=0
  __dybatpho_file_staging_dir="${__dybatpho_file_staging_path%/*}"
  [[ "${__dybatpho_file_staging_path}" == */* ]] || __dybatpho_file_staging_dir="."
  [[ -n "${__dybatpho_file_staging_dir}" ]] || __dybatpho_file_staging_dir="/"
  __dybatpho_file_staging_base="${__dybatpho_file_staging_path##*/}"

  while ((__dybatpho_file_staging_try++ < 20)); do
    __dybatpho_file_staging_name="${__dybatpho_file_staging_dir%/}/.dybatpho_staging_${__dybatpho_file_staging_base}"
    __dybatpho_file_staging_name+=".${BASHPID}.${RANDOM}${RANDOM}"
    if (set -C && : > "${__dybatpho_file_staging_name}") 2> /dev/null; then
      # `noclobber` still opens an existing non-regular file, such as a link
      # to a device, so what was opened has to be the plain file just made.
      if [[ -f "${__dybatpho_file_staging_name}" && ! -L "${__dybatpho_file_staging_name}" ]]; then
        __dybatpho_file_staging_ref="${__dybatpho_file_staging_name}"
        return 0
      fi
      continue
    fi
    # A name that is free and still could not be created means the directory
    # refuses the write; trying other names will not change that.
    [[ -e "${__dybatpho_file_staging_name}" || -L "${__dybatpho_file_staging_name}" ]] || return 1
  done
  return 1
}

#######################################
# @description Remove a staging file that will not be committed.
# @arg $1 string Staging file path
# @internal
#######################################
function __dybatpho_file_discard {
  rm -f -- "$1" 2> /dev/null || true
}

#######################################
# @description Render a path that is safe to pass to a command that does not
#   understand `--`. The BSD versions of `chmod`, `chown`, and `sed` on macOS
#   treat `--` as a file name rather than as the end of the options, so a path
#   that could be read as an option is prefixed with `./` instead.
# @arg $1 string Path
# @stdout The path, prefixed with `./` when it starts with a dash
# @internal
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
# @arg $3 string Public function the failure is reported for
# @exitcode 1 The staging file cannot be moved into place
# @internal
#######################################
function __dybatpho_file_commit {
  local staging path caller mode owner operand
  dybatpho::expect_args staging path caller -- "$@"
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
    dybatpho::die "${caller}: Cannot write ${path}"
  fi
}

#######################################
# @description Rewrite a file through a staging file: create the staging file
#   next to it, let a producer write the new contents there, and move it into
#   place, so readers see either the previous contents or the complete new
#   ones. A producer that fails leaves the destination untouched and the
#   staging file removed.
#   Every in-place writer of this module goes through here, so the exclusive
#   staging file, the failure handling and the commit live in one place.
# @arg $1 string Public function the failures are reported for
# @arg $2 string Destination path, already resolved
# @arg $3 string What to report when the producer fails
# @arg $4 string Producer, called with the staging path and the rest of the arguments
# @arg $@ string Extra arguments for the producer
# @exitcode 1 Stop the script when the staging file cannot be created, the producer fails, or the move fails
# @internal
#######################################
function __dybatpho_file_rewrite {
  local caller="$1" path="$2" failure="$3" producer="$4" staging
  shift 4
  # The rename that commits the rewrite would move the staging file inside a
  # directory rather than replace it, and report success.
  [[ ! -d "${path}" ]] || dybatpho::die "${caller}: Not a file: ${path}"
  __dybatpho_file_staging_into staging "${path}" \
    || dybatpho::die "${caller}: Cannot write staging file for ${path}"
  if ! "${producer}" "${staging}" "$@"; then
    __dybatpho_file_discard "${staging}"
    dybatpho::die "${caller}: ${failure}"
  fi
  __dybatpho_file_commit "${staging}" "${path}" "${caller}"
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
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing
#   it
# @exitcode 1 The destination directory is missing or the write fails
# @tip The destination keeps its mode, and its owner when the process may set it
#######################################
function dybatpho::file_write_atomic {
  local path directory
  dybatpho::expect_args path -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  __dybatpho_file_resolve_into path "${path}" "${FUNCNAME[0]}"
  directory="$(dybatpho::path_dirname "${path}")"
  dybatpho::is dir "${directory}" \
    || dybatpho::die "${FUNCNAME[0]}: Directory doesn't exist: ${directory}"

  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  if dybatpho::is true "${DRY_RUN}"; then
    # Drain standard input so that the process feeding this helper is not
    # interrupted by a closed pipe.
    cat > /dev/null
    dybatpho::dry_run write "${path}"
    return 0
  fi

  __dybatpho_file_rewrite "${FUNCNAME[0]}" "${path}" \
    "Cannot write staging file for ${path}" __dybatpho_file_produce_stdin
  dybatpho::debug "Wrote ${path}"
}

#######################################
# @description Producer for `dybatpho::file_write_atomic`: standard input.
# @arg $1 string Staging file path
# @internal
#######################################
function __dybatpho_file_produce_stdin {
  cat > "$1"
}

#######################################
# @description Pick a `sed` substitution delimiter that appears in neither the
#   pattern nor the replacement, so that neither has to be escaped.
# @arg $1 string Substitution pattern
# @arg $2 string Replacement text
# @stdout Delimiter character
# @exitcode 1 Every candidate delimiter occurs in the pattern or replacement
# @internal
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
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing
#   it
# @exitcode 1 The file is missing, `sed` fails, or no delimiter can be chosen
# @tip This avoids `sed -i`, whose argument differs between GNU and BSD, by
#   rewriting through a staging file instead
#######################################
function dybatpho::file_replace {
  local path pattern replacement delimiter
  dybatpho::expect_args path pattern replacement -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  __dybatpho_file_resolve_into path "${path}" "${FUNCNAME[0]}"
  delimiter="$(__dybatpho_file_sed_delimiter "${pattern}" "${replacement}")" \
    || dybatpho::die "${FUNCNAME[0]}: Cannot find a usable sed delimiter for '${pattern}'"

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run replace "${pattern}" "${replacement}" "${path}"
    return 0
  fi

  local file_operand
  file_operand=$(__dybatpho_file_operand "${path}")
  __dybatpho_file_rewrite "${FUNCNAME[0]}" "${path}" \
    "Cannot apply '${pattern}' to ${path}" __dybatpho_file_produce_sed \
    "s${delimiter}${pattern}${delimiter}${replacement}${delimiter}g" "${file_operand}"
}

#######################################
# @description Producer for `dybatpho::file_replace`: the file run through one
#   `sed` substitution.
# @arg $1 string Staging file path
# @arg $2 string `sed` script
# @arg $3 string Source file, as `__dybatpho_file_operand` renders it
# @internal
#######################################
function __dybatpho_file_produce_sed {
  sed "$2" "$3" > "$1"
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
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing
#   it
# @exitcode 1 The parent directory is missing or the write fails
# @tip The comparison is an exact whole-line match, not a substring or pattern
#######################################
function dybatpho::file_ensure_line {
  local path line directory
  dybatpho::expect_args path line -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  __dybatpho_file_resolve_into path "${path}" "${FUNCNAME[0]}"
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

  __dybatpho_file_rewrite "${FUNCNAME[0]}" "${path}" \
    "Cannot write staging file for ${path}" __dybatpho_file_produce_appended "${path}" "${line}"
}

#######################################
# @description Producer for `dybatpho::file_ensure_line`: the file, if any,
#   with the line appended.
# @arg $1 string Staging file path
# @arg $2 string Source file path
# @arg $3 string Line to append
# @internal
#######################################
function __dybatpho_file_produce_appended {
  if dybatpho::is file "$2"; then
    cat -- "$2" > "$1" || return
    # A file whose last line has no newline would otherwise absorb the new line.
    if [[ -s "$1" ]] && [[ "$(tail -c 1 -- "$1")" != "" ]]; then
      printf '\n' >> "$1"
    fi
  fi
  printf '%s\n' "$3" >> "$1"
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
# @env DYBATPHO_FILE_FOLLOW_SYMLINKS string When true-like, the default, write through a symlink rather than replacing
#   it
# @exitcode 1 The write fails
# @tip The comparison is an exact whole-line match, not a substring or pattern
#######################################
function dybatpho::file_remove_line {
  local path line
  dybatpho::expect_args path line -- "$@"
  [[ -n "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Path must not be empty"
  __dybatpho_file_resolve_into path "${path}" "${FUNCNAME[0]}"
  if ! dybatpho::is file "${path}" || ! grep -qxF -- "${line}" "${path}"; then
    dybatpho::debug "Line already absent from ${path}"
    return 0
  fi

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run remove "${line}" "${path}"
    return 0
  fi

  __dybatpho_file_rewrite "${FUNCNAME[0]}" "${path}" \
    "Cannot filter ${path}" __dybatpho_file_produce_without "${path}" "${line}"
}

#######################################
# @description Producer for `dybatpho::file_remove_line`: the file without
#   every occurrence of the line.
# @arg $1 string Staging file path
# @arg $2 string Source file path
# @arg $3 string Line to drop
# @exitcode 0 The file was filtered, including down to nothing
# @exitcode other `grep` failed
# @internal
#######################################
function __dybatpho_file_produce_without {
  # `grep -v` reports "no match" when every line is removed, which is a valid
  # result here rather than a failure.
  local status=0
  grep -vxF -- "$3" "$2" > "$1" || status=$?
  ((status <= 1))
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

  # The file goes in on standard input rather than as an argument. Given a
  # name, the `*sum` tools quote one that holds a newline or a backslash: they
  # print a `\` before the digest and escape the name, so `${checksum%% *}`
  # came back as `\<digest>` and every comparison against it failed. Reading
  # standard input has no name to quote, and it is the one spelling all four
  # tools agree on.
  if dybatpho::is command "${algorithm}sum"; then
    checksum="$("${algorithm}sum" < "${path}")"
  elif [[ "${algorithm}" == md5 ]] && dybatpho::is command md5; then
    checksum="$(md5 -q < "${path}")" # kcov(skip)
  elif [[ "${algorithm}" != md5 ]] && dybatpho::is command shasum; then
    checksum="$(shasum -a "${algorithm#sha}" < "${path}")"
  elif dybatpho::is command openssl; then
    checksum="$(openssl dgst "-${algorithm}" < "${path}")"
    checksum="${checksum##* }"
  else
    dybatpho::die "${FUNCNAME[0]}: No tool available to compute ${algorithm}" # kcov(skip)
  fi
  # Reading standard input, the `*sum` and `shasum` tools print
  # `<checksum>  -`. An unreadable file leaves nothing at all, and an empty
  # answer must not be mistaken for a digest.
  checksum="${checksum%% *}"
  [[ -n "${checksum}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Unable to read ${path}"
  printf '%s\n' "${checksum}"
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

#######################################
# @description Print a directory from the XDG Base Directory specification,
#   optionally scoped to one application.
#   The specification's own default is used whenever the variable is unset or
#   holds a relative path, which it requires to be ignored.
# @arg $1 string Variable name, such as `XDG_CONFIG_HOME`
# @arg $2 string Default path relative to the home directory
# @arg $3 string Optional application name appended to the directory
# @stdout The resolved directory
# @exitcode 1 Neither the variable nor `HOME` is usable
# @internal
#######################################
function __dybatpho_xdg_dir {
  local variable fallback application base
  dybatpho::expect_args variable fallback -- "$@"
  application="${3-}"
  base="${!variable-}"
  # The specification says a relative value must be treated as unset.
  if [[ -z "${base}" || "${base}" != /* ]]; then
    [[ -n "${HOME-}" ]] \
      || dybatpho::die "${FUNCNAME[1]}: Neither ${variable} nor HOME is set"
    base="${HOME%/}/${fallback}"
  fi
  if [[ -n "${application}" ]]; then
    dybatpho::path_join "${base}" "${application}"
  else
    printf '%s\n' "${base%/}"
  fi
}

#######################################
# @description Resolve an XDG base directory into a named variable, in the
#   caller's shell.
#   The public `dybatpho::xdg_*_dir` functions print, so a module that called
#   them inside `$(...)` lost their refusal with the subshell: with neither the
#   variable nor HOME set, it carried on and placed its files under `/`. The
#   check runs here instead, where it stops the script under the name of the
#   function the caller was running.
# @arg $1 string Name of the variable receiving the directory
# @arg $2 string Name to report a refusal under
# @arg $3 string XDG variable, such as `XDG_STATE_HOME`
# @arg $4 string Fallback below HOME, such as `.local/state`
# @arg $5 string Optional application subdirectory
# @set The named variable
# @internal
#######################################
function __dybatpho_xdg_dir_into {
  local -n __dybatpho_xdg_into_ref="$1"
  local __dybatpho_xdg_into_variable="$3"
  if [[ "${!__dybatpho_xdg_into_variable-}" != /* && -z "${HOME-}" ]]; then
    dybatpho::die "$2: Neither ${__dybatpho_xdg_into_variable} nor HOME is set"
  fi
  # Nothing left in it can refuse, so the substitution is only a capture.
  __dybatpho_xdg_into_ref="$(__dybatpho_xdg_dir "$3" "$4" "${5-}")"
}

#######################################
# @description Print the directory a program's configuration belongs in.
# @example
#   config="$(dybatpho::ensure_dir "$(dybatpho::xdg_config_dir myapp)")"
#   printf 'theme = dark\n' | dybatpho::file_write_atomic "${config}/settings.ini"
#
# @arg $1 string Optional application name appended to the directory
# @env XDG_CONFIG_HOME string Base configuration directory, default is `~/.config`
# @stdout The configuration directory
# @exitcode 1 Neither `XDG_CONFIG_HOME` nor `HOME` is set
# @tip These helpers only build a path; pair them with `dybatpho::ensure_dir`
#   when the directory has to exist
#######################################
function dybatpho::xdg_config_dir {
  __dybatpho_xdg_dir XDG_CONFIG_HOME ".config" "${1-}"
}

#######################################
# @description Print the directory a program's cache belongs in.
# @example
#   cache="$(dybatpho::xdg_cache_dir myapp)"
#
# @arg $1 string Optional application name appended to the directory
# @env XDG_CACHE_HOME string Base cache directory, default is `~/.cache`
# @stdout The cache directory
# @exitcode 1 Neither `XDG_CACHE_HOME` nor `HOME` is set
#######################################
function dybatpho::xdg_cache_dir {
  __dybatpho_xdg_dir XDG_CACHE_HOME ".cache" "${1-}"
}

#######################################
# @description Print the directory a program's data belongs in.
# @example
#   data="$(dybatpho::xdg_data_dir myapp)"
#
# @arg $1 string Optional application name appended to the directory
# @env XDG_DATA_HOME string Base data directory, default is `~/.local/share`
# @stdout The data directory
# @exitcode 1 Neither `XDG_DATA_HOME` nor `HOME` is set
#######################################
function dybatpho::xdg_data_dir {
  __dybatpho_xdg_dir XDG_DATA_HOME ".local/share" "${1-}"
}

#######################################
# @description Print the directory a program's state belongs in.
#   State is what a program wants back on the next run but should not be backed
#   up, such as logs and history, which is what separates it from data.
# @example
#   state="$(dybatpho::ensure_dir "$(dybatpho::xdg_state_dir myapp)")"
#   printf '%s\n' "${run_id}" | dybatpho::file_write_atomic "${state}/last-run"
#
# @arg $1 string Optional application name appended to the directory
# @env XDG_STATE_HOME string Base state directory, default is `~/.local/state`
# @stdout The state directory
# @exitcode 1 Neither `XDG_STATE_HOME` nor `HOME` is set
#######################################
function dybatpho::xdg_state_dir {
  __dybatpho_xdg_dir XDG_STATE_HOME ".local/state" "${1-}"
}

#######################################
# @description Print when a file was last modified, as a Unix timestamp.
# @example
#   modified="$(dybatpho::file_mtime "${cache}")"
#
# @arg $1 string File path
# @stdout Modification time in seconds since the epoch
# @exitcode 1 The file is missing or its modification time cannot be read
# @tip `dybatpho::file_age_seconds` answers the same question relative to now
#######################################
function dybatpho::file_mtime {
  local path modified
  dybatpho::expect_args path -- "$@"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  modified="$(__dybatpho_file_stat mtime "${path}" || true)"
  [[ -n "${modified}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Cannot read modification time of ${path}" # kcov(skip)
  printf '%s\n' "${modified}"
}

#######################################
# @description Print the total size of the regular files in a directory tree.
#   The result is the sum of the files' sizes rather than the disk space they
#   occupy, so it matches `dybatpho::file_size` instead of `du`, whose block
#   accounting and flags differ between platforms.
# @example
#   bytes="$(dybatpho::dir_size ./build)"
#
# @arg $1 string Directory path
# @stdout Total size in bytes, `0` for a directory holding no files
# @stderr An error when part of the tree could not be read
# @exitcode 1 The directory is missing, or part of it could not be read; the
#   size printed then counts only what could be read
# @tip Symbolic links are not counted at all, the way `du` treats them, so a
#   link to a file inside the same tree cannot count its target twice
#######################################
function dybatpho::dir_size {
  local directory total
  dybatpho::expect_args directory -- "$@"
  dybatpho::is dir "${directory}" \
    || dybatpho::die "${FUNCNAME[0]}: Directory doesn't exist: ${directory}"
  # One `stat` call for the whole tree rather than one per file. The flavour is
  # asked once, up front: falling back after a failed `find` walked the tree a
  # second time whenever any part of it could not be read.
  local -a stat_size=(stat -L -c '%s')
  stat -c '%s' -- "${directory}" > /dev/null 2>&1 || stat_size=(stat -L -f '%z')
  local sizes status=0
  sizes="$(find "${directory}" -type f -exec "${stat_size[@]}" {} + 2> /dev/null)" || status=$?
  total="$(printf '%s\n' "${sizes}" | awk '{ total += $1 } END { printf "%d\n", total }')"
  printf '%s\n' "${total:-0}"
  if ((status != 0)); then
    dybatpho::error "${FUNCNAME[0]}: Part of ${directory} could not be read; the size counts only the rest"
    return 1
  fi
}

#######################################
# @description Return success when a file looks like binary rather than text.
#   A NUL byte in the first block is the signal `grep` and `git` use, and it is
#   what makes a file unsafe to pass through line-oriented tools.
# @example
#   if dybatpho::file_is_binary "${path}"; then
#     dybatpho::warn "Refusing to rewrite ${path}"
#   else
#     dybatpho::file_replace "${path}" 'old' 'new'
#   fi
#
# @arg $1 string File path
# @exitcode 0 The file contains a NUL byte in its first block
# @exitcode 1 The file looks like text, or is empty; stop the script when it cannot be read
# @tip Check this before a text rewrite, which would otherwise mangle a binary
#######################################
function dybatpho::file_is_binary {
  local path sampled stripped
  dybatpho::expect_args path -- "$@"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  # Reading nothing would count as a block with no NUL byte, and report an
  # unreadable binary as text.
  [[ -r "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Cannot read file: ${path}"
  # A NUL byte cannot survive in a shell variable, so the byte counts before and
  # after removing NULs are compared instead of the contents.
  # shellcheck disable=SC2312 # a variable cannot hold the NUL bytes being counted
  sampled=$(head -c 8192 -- "${path}" | wc -c)
  # shellcheck disable=SC2312 # a variable cannot hold the NUL bytes being counted
  stripped=$(head -c 8192 -- "${path}" | LC_ALL=C tr -d '\000' | wc -c)
  ((${sampled//[^0-9]/} != ${stripped//[^0-9]/}))
}

#######################################
# @description Create a temporary directory and register it for cleanup on shell exit.
#   This is `dybatpho::create_temp` with the argument that asks for a directory
#   already supplied, because passing `/` as an extension reads like a mistake.
# @example
#   local workdir
#   dybatpho::create_temp_dir workdir "build"
#   printf 'artifact\n' > "${workdir}/out"
#
# @arg $1 string Variable name that receives the created path
# @arg $2 string Name prefix, default is `temp`
# @arg $3 string Parent directory, default is `${TMPDIR:-/tmp}`
# @set The named variable, to the created directory
# @tip The directory is removed with its contents when the shell exits
#######################################
function dybatpho::create_temp_dir {
  local __dybatpho_file_tmpdir_var
  dybatpho::expect_args __dybatpho_file_tmpdir_var -- "$@"
  shift
  dybatpho::create_temp "${__dybatpho_file_tmpdir_var}" "" ${1+"$1"} ${2+"$2"}
}
