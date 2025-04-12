#!/usr/bin/env bash
# @file file.sh
# @brief Utilities for file handling
# @description
#   This module containss functions to file handling
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Show content of file
# @arg $1 string File path
# @stderr Content of file
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
# @description Create temporary file or folder and cleanup it on exit
# @arg $1 string Variable name to get file/folder path
# @arg $2 string Extension of file name, use `/` or empty for folder
# @arg $3 string Prefix of file/folder name, default is `temp`
# @arg $4 string Parent folder for file/folder, default is `$TMPDIR`
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

  extension=${extension%%/} # Remove '/' and after in extension, for security
  local pid="$$"
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
