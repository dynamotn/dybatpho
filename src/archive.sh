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
# @description Return the output name produced when a single-file compressed archive is extracted.
# @arg $1 string Archive file path
# @stdout Default extracted file name
# @internal
#######################################
function __dybatpho_archive_output_name {
  local archive_path format
  dybatpho::expect_args archive_path -- "$@"
  format=$(__dybatpho_archive_format "${archive_path}") || return $?
  case "${format}" in
    xz)
      dybatpho::path_basename "${archive_path}" ".xz"
      ;;
    gz)
      dybatpho::path_basename "${archive_path}" ".gz"
      ;;
    bz2)
      dybatpho::path_basename "${archive_path}" ".bz2"
      ;;
    zst)
      dybatpho::path_basename "${archive_path}" ".zst"
      ;;
    *)
      dybatpho::path_basename "${archive_path}"
      ;;
  esac
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
  local path rel stripped dir_path

  # `find -printf '%P'` would say this in one flag, but it is GNU-only: neither
  # BusyBox nor BSD has it, and this is the zip path of an extractor the library
  # documents as portable. The prefix comes off here instead.
  local find_dirs find_output                            # kcov(skip)
  find_dirs=$(find "${source_root}" -mindepth 1 -type d) # kcov(skip)
  find_output=$(printf '%s\n' "${find_dirs}" | sort)     # kcov(skip)
  while IFS= read -r path || [[ -n "${path}" ]]; do
    rel="${path#"${source_root}/"}"
    [[ -z "${rel}" || "${rel}" == "${path}" ]] && continue
    stripped=$(printf '%s\n' "${rel}" | awk -F/ -v n="${strip_components}" '
      NF > n { for (i = n + 1; i <= NF; i++) printf "%s%s", $i, (i < NF ? "/" : "") }
    ')
    [[ -z "${stripped}" ]] && continue
    mkdir -p "${destination}/${stripped}"
  done < <(printf '%s' "${find_output}")

  local find_files                                          # kcov(skip)
  find_files=$(find "${source_root}" -mindepth 1 ! -type d) # kcov(skip)
  find_output=$(printf '%s\n' "${find_files}" | sort)       # kcov(skip)
  while IFS= read -r path || [[ -n "${path}" ]]; do
    rel="${path#"${source_root}/"}"
    [[ -z "${rel}" || "${rel}" == "${path}" ]] && continue
    stripped=$(printf '%s\n' "${rel}" | awk -F/ -v n="${strip_components}" '
      NF > n { for (i = n + 1; i <= NF; i++) printf "%s%s", $i, (i < NF ? "/" : "") }
    ')
    [[ -z "${stripped}" ]] && continue
    dir_path=$(dybatpho::path_dirname "${destination}/${stripped}")
    mkdir -p "${dir_path}"
    mv "${source_root}/${rel}" "${destination}/${stripped}"
  done < <(printf '%s' "${find_output}")
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

  case "${format}" in
    tar.gz)
      dybatpho::require tar
      tar -C "${source_dir}" -czf "${output_path}" "${source_name}"
      ;;
    tar.xz)
      dybatpho::require tar
      tar -C "${source_dir}" -cJf "${output_path}" "${source_name}"
      ;;
    tar.bz2)
      dybatpho::require tar
      tar -C "${source_dir}" -cjf "${output_path}" "${source_name}"
      ;;
    tar.zst)
      dybatpho::require tar
      tar --zstd -C "${source_dir}" -cf "${output_path}" "${source_name}"
      ;;
    tar)
      dybatpho::require tar
      tar -C "${source_dir}" -cf "${output_path}" "${source_name}"
      ;;
    xz)
      dybatpho::require xz
      dybatpho::is file "${source_path}" || dybatpho::die \
        "Single-file archive formats require a file source: ${source_path}"
      xz -c "${source_path}" > "${output_path}"
      ;;
    gz)
      dybatpho::require gzip
      dybatpho::is file "${source_path}" || dybatpho::die \
        "Single-file archive formats require a file source: ${source_path}"
      gzip -c "${source_path}" > "${output_path}"
      ;;
    bz2)
      dybatpho::require bzip2
      dybatpho::is file "${source_path}" || dybatpho::die \
        "Single-file archive formats require a file source: ${source_path}"
      bzip2 -c "${source_path}" > "${output_path}"
      ;;
    zst)
      dybatpho::require zstd
      dybatpho::is file "${source_path}" || dybatpho::die \
        "Single-file archive formats require a file source: ${source_path}"
      zstd -q -c "${source_path}" > "${output_path}"
      ;;
    zip)
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
      ;;
    *) ;;
  esac
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

  case "${format}" in
    tar.gz)
      dybatpho::require tar
      tar -xzf "${archive_path}" -C "${destination}" "${strip_args[@]}"
      ;;
    tar.xz)
      dybatpho::require tar
      tar -xJf "${archive_path}" -C "${destination}" "${strip_args[@]}"
      ;;
    tar.bz2)
      dybatpho::require tar
      tar -xjf "${archive_path}" -C "${destination}" "${strip_args[@]}"
      ;;
    tar.zst)
      dybatpho::require tar
      tar --zstd -xf "${archive_path}" -C "${destination}" "${strip_args[@]}"
      ;;
    tar)
      dybatpho::require tar
      tar -xf "${archive_path}" -C "${destination}" "${strip_args[@]}"
      ;;
    zip)
      dybatpho::require unzip
      if ((strip_components == 0)); then
        unzip -q "${archive_path}" -d "${destination}"
      else
        local temp_dir
        dybatpho::create_temp temp_dir ""
        unzip -q "${archive_path}" -d "${temp_dir}"
        __dybatpho_archive_move_stripped "${temp_dir}" "${destination}" "${strip_components}"
      fi
      ;;
    xz)
      dybatpho::require xz
      ((strip_components == 0)) || dybatpho::die "strip-components is only supported for multi-entry archives"
      local archive_output_name_4
      archive_output_name_4=$(__dybatpho_archive_output_name "${archive_path}")
      xz -dc "${archive_path}" \
        > "$(dybatpho::path_join "${destination}" "${archive_output_name_4}")"
      ;;
    gz)
      dybatpho::require gzip
      ((strip_components == 0)) || dybatpho::die "strip-components is only supported for multi-entry archives"
      local archive_output_name_3
      archive_output_name_3=$(__dybatpho_archive_output_name "${archive_path}")
      gzip -dc "${archive_path}" \
        > "$(dybatpho::path_join "${destination}" "${archive_output_name_3}")"
      ;;
    bz2)
      dybatpho::require bzip2
      ((strip_components == 0)) || dybatpho::die "strip-components is only supported for multi-entry archives"
      local archive_output_name_2
      archive_output_name_2=$(__dybatpho_archive_output_name "${archive_path}")
      bzip2 -dc "${archive_path}" \
        > "$(dybatpho::path_join "${destination}" "${archive_output_name_2}")"
      ;;
    zst)
      dybatpho::require zstd
      ((strip_components == 0)) || dybatpho::die "strip-components is only supported for multi-entry archives"
      local archive_output_name
      archive_output_name=$(__dybatpho_archive_output_name "${archive_path}")
      zstd -d -q -c "${archive_path}" \
        > "$(dybatpho::path_join "${destination}" "${archive_output_name}")"
      ;;
    *) ;;
  esac
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

  case "${format}" in
    tar.gz)
      dybatpho::require tar
      tar -tzf "${archive_path}"
      ;;
    tar.xz)
      dybatpho::require tar
      tar -tJf "${archive_path}"
      ;;
    tar.bz2)
      dybatpho::require tar
      tar -tjf "${archive_path}"
      ;;
    tar.zst)
      dybatpho::require tar
      tar --zstd -tf "${archive_path}"
      ;;
    tar)
      dybatpho::require tar
      tar -tf "${archive_path}"
      ;;
    xz | gz | bz2 | zst)
      __dybatpho_archive_output_name "${archive_path}"
      ;;
    zip)
      dybatpho::require unzip
      unzip -Z1 "${archive_path}"
      ;;
    *) ;;
  esac
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
# @arg $1 string Archive file path
# @stdout One unsafe entry per line, empty when the archive is safe
# @tip Use `dybatpho::safe_extract` to validate and extract in one step; it
#   lives in the `safety` module, which `archive` does not load
#######################################
function dybatpho::archive_unsafe_entries {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local entry
  local archive_list_output
  archive_list_output=$(dybatpho::archive_list "${archive_path}")
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
# @exitcode 0 Every entry is a safe relative path
# @exitcode 1 At least one entry is absolute or traverses outside the destination
#######################################
function dybatpho::archive_is_safe {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local unsafe_entries
  unsafe_entries="$(dybatpho::archive_unsafe_entries "${archive_path}")" || return $?
  [[ -z "${unsafe_entries}" ]]
}
