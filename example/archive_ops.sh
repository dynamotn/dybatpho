#!/usr/bin/env bash
# @file archive_ops.sh
# @brief Example showing archive utilities
# @description Demonstrates dybatpho::archive_create, archive_extract, and archive_list across tar-based and single-file compressed formats
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _demo_archives {
  local workspace bundle_dir archive_path extract_dir
  dybatpho::create_temp workspace "/"
  bundle_dir="${workspace}/bundle"
  archive_path="${workspace}/bundle.tar.gz"
  extract_dir="${workspace}/extracted"
  mkdir -p "${bundle_dir}"
  printf 'hello archive\n' > "${bundle_dir}/hello.txt"

  dybatpho::header "CREATE ARCHIVE"
  dybatpho::archive_create "${bundle_dir}" "${archive_path}"
  dybatpho::info "Created: ${archive_path}"

  dybatpho::header "LIST ARCHIVE"
  dybatpho::archive_list "${archive_path}" | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done

  dybatpho::header "EXTRACT ARCHIVE"
  dybatpho::archive_extract "${archive_path}" "${extract_dir}"
  dybatpho::info "Extracted into: ${extract_dir}"
}

function _demo_single_file_formats {
  local workspace source_file archive_path extract_dir
  dybatpho::create_temp workspace "/"
  source_file="${workspace}/hello.txt"
  archive_path="${workspace}/hello.txt.xz"
  extract_dir="${workspace}/single-out"
  printf 'single file payload\n' > "${source_file}"

  dybatpho::header "SINGLE-FILE ARCHIVE"
  dybatpho::archive_create "${source_file}" "${archive_path}"
  dybatpho::info "Created: ${archive_path}"
  dybatpho::archive_list "${archive_path}" | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done
  dybatpho::archive_extract "${archive_path}" "${extract_dir}"
  dybatpho::info "Extracted file: ${extract_dir}/hello.txt"
}

function _main {
  _demo_archives
  _demo_single_file_formats
  dybatpho::success "Archive operations demo complete"
}

_main "$@"
