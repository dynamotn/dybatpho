# shellcheck shell=bash
# @file archive.sh
# @brief Utilities for creating, extracting, and listing archives
# @namespace dybatpho
# @description
#   This module contains helpers for common archive workflows in shell scripts:
#   creating archives from files or directories, extracting them into a target
#   directory, and listing their contents. Supported formats include `.tar`,
#   `.tar.gz` / `.tgz`, `.tar.xz`, `.tar.bz2` / `.tbz2` / `.tbz`, `.tar.zst`,
#   `.zip`, and single-file compressed outputs such as `.gz`, `.xz`, `.bz2`,
#   and `.zst`. Extraction also supports optional strip-components behavior.
# @see
#   - `example/archive_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Detect the supported archive format from a file name.
# @arg $1 string Archive file path
# @stdout Archive format identifier
# @internal
#######################################
function __dybatpho_archive_format {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  case "${archive_path}" in
    *.tar.gz | *.tgz)
      printf 'tar.gz\n'
      ;;
    *.tar.xz)
      printf 'tar.xz\n'
      ;;
    *.tar.bz2 | *.tbz2 | *.tbz)
      printf 'tar.bz2\n'
      ;;
    *.tar.zst)
      printf 'tar.zst\n'
      ;;
    *.tar)
      printf 'tar\n'
      ;;
    *.xz)
      printf 'xz\n'
      ;;
    *.gz)
      printf 'gz\n'
      ;;
    *.bz2)
      printf 'bz2\n'
      ;;
    *.zst)
      printf 'zst\n'
      ;;
    *.zip)
      printf 'zip\n'
      ;;
    *)
      dybatpho::die "Unsupported archive format: ${archive_path}" # kcov(skip)
      ;;
  esac
}

#######################################
# @description Fill in how tar is told a tar archive's compression, for the
#   formats tar reads and writes itself: a letter bundled into the mode, such
#   as the `z` of `-czf`, or, for zstd, which has no portable letter, an option
#   ahead of everything else.
# @arg $1 string Name of the array receiving the options that go first
# @arg $2 string Name of the variable receiving the letter bundled into the mode
# @arg $3 string Archive format, as `__dybatpho_archive_format` prints it
# @set The two named variables
# @exitcode 0 The format is a tar archive
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_archive_tar_mode_into {
  local prefix_var letter_var format
  dybatpho::expect_args prefix_var letter_var format -- "$@"
  local -n __dybatpho_archive_prefix_ref="${prefix_var}"
  local -n __dybatpho_archive_letter_ref="${letter_var}"
  __dybatpho_archive_prefix_ref=()
  __dybatpho_archive_letter_ref=""
  case "${format}" in
    tar.gz) __dybatpho_archive_letter_ref=z ;;
    tar.xz) __dybatpho_archive_letter_ref=J ;;
    tar.bz2) __dybatpho_archive_letter_ref=j ;;
    tar.zst) __dybatpho_archive_prefix_ref=(--zstd) ;;
    tar) ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Fill in the command that compresses and decompresses a
#   single-file format, which holds one file and no names.
# @arg $1 string Name of the variable receiving the command
# @arg $2 string Name of the array receiving its compress arguments
# @arg $3 string Name of the array receiving its decompress arguments
# @arg $4 string Archive format, as `__dybatpho_archive_format` prints it
# @set The three named variables
# @exitcode 0 The format is a single-file format
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_archive_codec_into {
  local tool_var pack_var unpack_var format
  dybatpho::expect_args tool_var pack_var unpack_var format -- "$@"
  local -n __dybatpho_archive_tool_ref="${tool_var}"
  local -n __dybatpho_archive_pack_ref="${pack_var}" __dybatpho_archive_unpack_ref="${unpack_var}"
  __dybatpho_archive_pack_ref=(-c)
  __dybatpho_archive_unpack_ref=(-dc)
  case "${format}" in
    xz) __dybatpho_archive_tool_ref=xz ;;
    gz) __dybatpho_archive_tool_ref=gzip ;;
    bz2) __dybatpho_archive_tool_ref=bzip2 ;;
    zst)
      __dybatpho_archive_tool_ref=zstd
      __dybatpho_archive_pack_ref=(-q -c)
      __dybatpho_archive_unpack_ref=(-d -q -c)
      ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Return the output name produced when a single-file compressed archive is extracted.
# @arg $1 string Archive file path
# @stdout Default extracted file name
# @internal
#######################################
function __dybatpho_archive_output_name {
  local archive_path format
  dybatpho::expect_args archive_path -- "$@"
  format=$(__dybatpho_archive_format "${archive_path}") || return $?
  local tool
  local -a pack=() unpack=()
  if __dybatpho_archive_codec_into tool pack unpack "${format}"; then
    dybatpho::path_basename "${archive_path}" ".${format}"
  else
    dybatpho::path_basename "${archive_path}"
  fi
}

#######################################
# @description Move extracted zip contents while stripping leading path components.
# @arg $1 string Temporary extraction directory
# @arg $2 string Final destination directory
# @arg $3 number Number of leading path components to remove
# @internal
#######################################
function __dybatpho_archive_move_stripped {
  local source_root destination strip_components
  dybatpho::expect_args source_root destination strip_components -- "$@"
  local kind path rel stripped dir_path find_entries find_output
  local -a parts=()

  # Directories first, so every file has somewhere to land. `find -printf '%P'`
  # would drop the prefix in one flag, but it is GNU-only: neither BusyBox nor
  # BSD has it, and this is the zip path of an extractor the library documents
  # as portable. The prefix comes off here instead.
  for kind in directories files; do
    if [[ "${kind}" == directories ]]; then
      find_entries=$(find "${source_root}" -mindepth 1 -type d) # kcov(skip)
    else
      find_entries=$(find "${source_root}" -mindepth 1 ! -type d) # kcov(skip)
    fi
    find_output=$(printf '%s\n' "${find_entries}" | sort) # kcov(skip)
    while IFS= read -r path || [[ -n "${path}" ]]; do
      rel="${path#"${source_root}/"}"
      [[ -z "${rel}" || "${rel}" == "${path}" ]] && continue
      IFS=/ read -r -a parts <<< "${rel}"
      ((${#parts[@]} > strip_components)) || continue
      printf -v stripped '%s/' "${parts[@]:strip_components}"
      stripped="${stripped%/}"
      if [[ "${kind}" == directories ]]; then
        mkdir -p "${destination}/${stripped}"
      else
        dir_path=$(dybatpho::path_dirname "${destination}/${stripped}")
        mkdir -p "${dir_path}"
        mv "${source_root}/${rel}" "${destination}/${stripped}"
      fi
    done < <(printf '%s' "${find_output}")
  done
}

#######################################
# @description Create an archive from a file or directory.
# @arg $1 string Source file or directory
# @arg $2 string Output archive path
# @stdout Command output from the selected archiver, if any
#######################################
function dybatpho::archive_create {
  local source_path output_path
  dybatpho::expect_args source_path output_path -- "$@"
  dybatpho::is exist "${source_path}" || dybatpho::die "Source path does not exist: ${source_path}"

  local format source_dir source_name output_abs
  format=$(__dybatpho_archive_format "${output_path}") || return $?
  source_dir=$(dybatpho::path_dirname "${source_path}")
  source_name=$(dybatpho::path_basename "${source_path}")

  local tool letter
  local -a prefix=() pack=() unpack=()
  if __dybatpho_archive_tar_mode_into prefix letter "${format}"; then
    dybatpho::require tar
    tar ${prefix[@]+"${prefix[@]}"} -C "${source_dir}" "-c${letter}f" "${output_path}" "${source_name}"
  elif __dybatpho_archive_codec_into tool pack unpack "${format}"; then
    dybatpho::require "${tool}"
    dybatpho::is file "${source_path}" || dybatpho::die \
      "Single-file archive formats require a file source: ${source_path}"
    "${tool}" "${pack[@]}" "${source_path}" > "${output_path}"
  else
    dybatpho::require zip
    if dybatpho::path_is_abs "${output_path}"; then
      output_abs="${output_path}"
    else
      local pwd
      pwd=$(pwd)
      output_abs="$(dybatpho::path_join "${pwd}" "${output_path}")"
    fi
    ( # kcov(skip) - subshell keeps the caller's working directory
      cd "${source_dir}" || exit
      zip -rq "${output_abs}" "${source_name}"
    )
  fi
}

#######################################
# @description Extract an archive into a target directory.
# @arg $1 string Archive file path
# @arg $2 string Optional extraction directory, default is `.`
# @arg $3 number Optional strip-components count, default is `0`
# @stdout Command output from the selected extractor, if any
#######################################
function dybatpho::archive_extract {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local destination="${2:-.}"
  local strip_components="${3:-0}"
  local format
  local -a strip_args=()
  format=$(__dybatpho_archive_format "${archive_path}") || return $?
  [[ "${strip_components}" =~ ^[0-9]+$ ]] || dybatpho::die \
    "strip-components must be a non-negative integer: ${strip_components}"
  if ((strip_components > 0)); then
    strip_args=(--strip-components "${strip_components}")
  fi
  mkdir -p "${destination}"

  local tool name letter
  local -a prefix=() pack=() unpack=()
  if __dybatpho_archive_tar_mode_into prefix letter "${format}"; then
    dybatpho::require tar
    tar ${prefix[@]+"${prefix[@]}"} "-x${letter}f" "${archive_path}" -C "${destination}" \
      ${strip_args[@]+"${strip_args[@]}"}
  elif __dybatpho_archive_codec_into tool pack unpack "${format}"; then
    dybatpho::require "${tool}"
    ((strip_components == 0)) || dybatpho::die "strip-components is only supported for multi-entry archives"
    name=$(__dybatpho_archive_output_name "${archive_path}")
    "${tool}" "${unpack[@]}" "${archive_path}" \
      > "$(dybatpho::path_join "${destination}" "${name}")"
  else
    dybatpho::require unzip
    if ((strip_components == 0)); then
      unzip -q "${archive_path}" -d "${destination}"
    else
      local temp_dir
      dybatpho::create_temp temp_dir ""
      unzip -q "${archive_path}" -d "${temp_dir}"
      __dybatpho_archive_move_stripped "${temp_dir}" "${destination}" "${strip_components}"
    fi
  fi
}

#######################################
# @description List the contents of an archive without extracting it.
# @arg $1 string Archive file path
# @stdout One listed entry per line
#######################################
function dybatpho::archive_list {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local format
  format=$(__dybatpho_archive_format "${archive_path}") || return $?

  local tool letter
  local -a prefix=() pack=() unpack=()
  if __dybatpho_archive_tar_mode_into prefix letter "${format}"; then
    dybatpho::require tar
    tar ${prefix[@]+"${prefix[@]}"} "-t${letter}f" "${archive_path}"
  elif __dybatpho_archive_codec_into tool pack unpack "${format}"; then
    __dybatpho_archive_output_name "${archive_path}"
  else
    dybatpho::require unzip
    unzip -Z1 "${archive_path}"
  fi
}

#######################################
# @description Capture an archive's listing, failing when it cannot be read.
#   The listing runs in a command substitution to be captured, so its failure
#   is carried out by status and reported here, where it can still reach the
#   caller; ignoring it reads an unreadable archive as one with no entries.
# @arg $1 string Name of the variable receiving the listing
# @arg $2 string Archive file path
# @set The named variable
# @stderr An error when the archive cannot be listed
# @exitcode 0 The archive was listed
# @exitcode other The listing failed, with its status
# @internal
#######################################
function __dybatpho_archive_list_into {
  local __dybatpho_archive_listing_var __dybatpho_archive_listed
  dybatpho::expect_args __dybatpho_archive_listing_var __dybatpho_archive_listed -- "$@"
  local -n __dybatpho_archive_listing_ref="${__dybatpho_archive_listing_var}"
  local __dybatpho_archive_status=0
  __dybatpho_archive_listing_ref="$(dybatpho::archive_list "${__dybatpho_archive_listed}")" \
    || __dybatpho_archive_status=$?
  if ((__dybatpho_archive_status != 0)); then
    dybatpho::error "Can't list archive ${__dybatpho_archive_listed}, so its entries can't be checked"
    return "${__dybatpho_archive_status}"
  fi
}

#######################################
# @description Return success when an archive entry stays inside the extraction directory.
# @arg $1 string Entry name as reported by `dybatpho::archive_list`
# @exitcode 0 The entry is a safe relative path
# @exitcode 1 The entry is absolute, escapes through `..`, or uses a Windows drive path
# @internal
#######################################
function __dybatpho_archive_entry_is_safe {
  local entry
  dybatpho::expect_args entry -- "$@"
  # Treat backslashes as separators so Windows-style entries can't hide a traversal.
  local normalized="${entry//\\//}"
  # shellcheck disable=SC2088 # the `~/` branch matches a literal entry, it never expands
  case "${normalized}" in
    /* | '~/'* | [a-zA-Z]:/*) return 1 ;;
    .. | ../* | */../* | */..) return 1 ;;
    *) ;;
  esac
  return 0
}

#######################################
# @description List archive entries that would escape the extraction directory.
#   An archive that cannot be listed -- corrupt, truncated, or a zip with no
#   `unzip` installed -- is a failure, not an empty list: no entry was checked,
#   so none can be vouched for.
# @arg $1 string Archive file path
# @stdout One unsafe entry per line, empty when the archive is safe
# @stderr An error when the archive cannot be listed
# @exitcode 0 The archive was listed; the unsafe entries, if any, are on stdout
# @exitcode other The archive could not be listed
# @tip Use `dybatpho::safe_extract` to validate and extract in one step; it
#   lives in the `safety` module, which `archive` does not load
#######################################
function dybatpho::archive_unsafe_entries {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local entry
  local archive_list_output
  __dybatpho_archive_list_into archive_list_output "${archive_path}" || return $?
  while IFS= read -r entry || [[ -n "${entry}" ]]; do
    [[ -n "${entry}" ]] || continue
    if ! __dybatpho_archive_entry_is_safe "${entry}"; then
      printf '%s\n' "${entry}"
    fi
  done < <(printf '%s' "${archive_list_output}")
}

#######################################
# @description Return success when no archive entry escapes the extraction directory.
# @arg $1 string Archive file path
# @stderr An error when the archive cannot be listed
# @exitcode 0 Every entry is a safe relative path
# @exitcode 1 At least one entry is absolute or traverses outside the destination
# @exitcode other The archive could not be listed, so nothing was checked
#######################################
function dybatpho::archive_is_safe {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local unsafe_entries
  unsafe_entries="$(dybatpho::archive_unsafe_entries "${archive_path}")" || return $?
  [[ -z "${unsafe_entries}" ]]
}
