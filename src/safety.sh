# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# parses its own arguments, so the raw form is what the reader sees.
# dyshellint disable=BSG050,BSG051
# @file safety.sh
# @brief Guards for destructive operations
# @namespace dybatpho
# @description
#   Wrappers that make irreversible operations explicit before they run:
#
#   - removing files and directories (`dybatpho::safe_rm`)
#   - overwriting existing files, including copy and move
#     (`dybatpho::safe_overwrite`, `dybatpho::safe_copy`, `dybatpho::safe_move`)
#   - extracting archives, with path-traversal validation
#     (`dybatpho::safe_extract`)
#   - changing system state through an external command
#     (`dybatpho::safe_system`)
#
#   Every wrapper applies the same three rules:
#
#   1. the target path is validated against protected paths and, when
#      `DYBATPHO_SAFE_ROOTS` is set, confined inside those roots;
#   2. the operation runs unattended only with `--force` (or `DYBATPHO_FORCE`),
#      otherwise it asks for confirmation on an interactive terminal;
#   3. a non-interactive run without `--force` refuses instead of guessing, and
#      `DRY_RUN` prints the command instead of executing it.
# @usage
#   ### Remove a build directory, asking first
#
#   ```bash
#   dybatpho::safe_rm --recursive "${build_dir}"
#   ```
#
#   ### Overwrite a config file unattended, keeping a backup
#
#   ```bash
#   dybatpho::safe_overwrite --force --backup "${config}" \
#     && printf '%s\n' "${rendered}" > "${config}"
#   ```
#
#   ### Extract an untrusted archive
#
#   ```bash
#   dybatpho::safe_extract --force "${tarball}" "${workdir}" 1
#   ```
#
#   ### Guard a system change
#
#   ```bash
#   dybatpho::safe_system "Restart nginx" -- systemctl restart nginx
#   ```
# @see
#   - `example/safety_ops.sh`
# @tip Confine a whole script with `DYBATPHO_SAFE_ROOTS="${workdir}"` so a bad path can never reach the rest of the
#   filesystem.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_FORCE bool Set to `true` to approve every guarded operation without prompting
DYBATPHO_FORCE="${DYBATPHO_FORCE:-false}"
# @env DYBATPHO_INTERACTIVE string `auto` detects a terminal on stdin, `true`/`false` override the detection
DYBATPHO_INTERACTIVE="${DYBATPHO_INTERACTIVE:-auto}"
# @env DYBATPHO_SAFE_ROOTS string Colon-separated roots; when set, guarded paths must stay inside one of them
DYBATPHO_SAFE_ROOTS="${DYBATPHO_SAFE_ROOTS:-}"
# @env DYBATPHO_PROTECTED_PATHS string Extra colon-separated paths that guarded operations must never touch
DYBATPHO_PROTECTED_PATHS="${DYBATPHO_PROTECTED_PATHS:-}"

#######################################
# @description Print every path that guarded operations must never touch.
# @noargs
# @stdout One protected absolute path per line
# @internal
#######################################
function __dybatpho_safety_protected_paths {
  printf '%s\n' \
    / /bin /boot /dev /etc /home /lib /lib32 /lib64 /libx32 /media /mnt /opt \
    /proc /root /run /sbin /srv /sys /tmp /usr /var
  if [[ -n "${HOME:-}" ]]; then
    printf '%s\n' "${HOME%/}"
  fi
  local -a extra_paths=()
  local extra_path
  IFS=':' read -r -a extra_paths <<< "${DYBATPHO_PROTECTED_PATHS}"
  for extra_path in "${extra_paths[@]}"; do
    [[ -n "${extra_path}" ]] || continue
    printf '%s\n' "${extra_path%/}"
  done
}

#######################################
# @description Turn a path into a normalized absolute path without touching the filesystem.
# @arg $1 string Path to resolve
# @stdout Normalized absolute path
# @internal
#######################################
function __dybatpho_safety_absolute_path {
  local path
  dybatpho::expect_args path -- "$@"
  dybatpho::path_is_abs "${path}" || path="${PWD%/}/${path}"
  dybatpho::path_normalize "${path}"
}

#######################################
# @description Approve an operation from a force flag, otherwise ask for confirmation.
# @arg $1 bool Force flag value
# @arg $2 string Question shown when confirmation is needed
# @exitcode 0 The operation is approved
# @exitcode 1 The operation is declined or can't be confirmed
# @internal
#######################################
function __dybatpho_safety_approve {
  local force question
  dybatpho::expect_args force question -- "$@"
  if dybatpho::is true "${force}"; then
    dybatpho::debug "Forced without confirmation: ${question}"
    return 0
  fi
  dybatpho::confirm "${question}"
}

#######################################
# @description Drop the leading components of an archive entry.
# @arg $1 string Entry path
# @arg $2 number Number of leading components to strip
# @stdout Stripped entry, empty when the entry has too few components
# @internal
#######################################
function __dybatpho_safety_strip_entry {
  local entry strip_components
  dybatpho::expect_args entry strip_components -- "$@"
  entry="${entry#./}"
  local index=0
  while ((index < strip_components)); do
    [[ "${entry}" == */* ]] || {
      printf ''
      return 0
    }
    entry="${entry#*/}"
    index=$((index + 1))
  done
  printf '%s\n' "${entry}"
}

#######################################
# @description Return success when the script can ask the user a question.
# @noargs
# @exitcode 0 Input is attached to a terminal, or `DYBATPHO_INTERACTIVE` forces interactive mode
# @exitcode 1 The script runs unattended
# @env DYBATPHO_INTERACTIVE string `auto` detects a terminal on stdin, `true`/`false` override the detection
#######################################
function dybatpho::is_interactive {
  case "${DYBATPHO_INTERACTIVE}" in
    auto | '')
      dybatpho::is_tty stdin
      ;;
    *)
      dybatpho::is true "${DYBATPHO_INTERACTIVE}"
      ;;
  esac
}

#######################################
# @description Ask a yes/no question and return the answer as an exit code.
# @arg $1 string Question to ask
# @arg $2 string Optional default answer used on an empty reply, default is `no`
# @exitcode 0 The answer is yes, or `DYBATPHO_FORCE` is enabled
# @exitcode 1 The answer is no, or the script isn't interactive
# @env DYBATPHO_FORCE bool Answer yes without prompting
# @stdout None; the question is written to stderr
#######################################
function dybatpho::confirm {
  local question
  dybatpho::expect_args question -- "$@"
  local default_answer="${2:-no}"
  if dybatpho::is true "${DYBATPHO_FORCE}"; then
    dybatpho::debug "DYBATPHO_FORCE answers yes: ${question}"
    return 0
  fi
  if ! dybatpho::is_interactive; then
    dybatpho::warn "Refusing without --force in a non-interactive shell: ${question}"
    return 1
  fi
  local hint answer
  if dybatpho::is true "${default_answer}"; then
    hint="Y/n"
  else
    hint="y/N"
  fi
  answer="$(dybatpho::prompt "${question} [${hint}]")" || return 1
  if [[ -z "${answer}" ]]; then
    dybatpho::is true "${default_answer}"
    return $?
  fi
  case "${answer}" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Validate a path before a destructive operation and print it as an absolute path.
# @arg $1 string Path to validate
# @arg $2 string Optional wording used in error messages, default is `path`
# @stdout Normalized absolute path
# @exitcode 1 Stop the script when the path is empty, protected, or outside `DYBATPHO_SAFE_ROOTS`
# @env DYBATPHO_SAFE_ROOTS string Colon-separated roots the path must stay inside when set
# @env DYBATPHO_PROTECTED_PATHS string Extra colon-separated paths that are always rejected
#######################################
function dybatpho::assert_safe_path {
  local path
  dybatpho::expect_args path -- "$@"
  local description="${2:-path}"
  [[ -n "${path//[[:space:]]/}" ]] || dybatpho::die "Refusing to use an empty ${description}"

  local absolute_path protected_path
  absolute_path="$(__dybatpho_safety_absolute_path "${path}")"
  local safety_protected_paths_output
  safety_protected_paths_output=$(__dybatpho_safety_protected_paths)
  while IFS= read -r protected_path || [[ -n "${protected_path}" ]]; do
    [[ "${absolute_path}" != "${protected_path}" ]] \
      || dybatpho::die "Refusing to touch protected ${description}: ${absolute_path}"
  done < <(printf '%s' "${safety_protected_paths_output}")

  if [[ -n "${DYBATPHO_SAFE_ROOTS}" ]]; then
    local -a roots=()
    local root root_absolute is_inside=false
    IFS=':' read -r -a roots <<< "${DYBATPHO_SAFE_ROOTS}"
    for root in "${roots[@]}"; do
      [[ -n "${root}" ]] || continue
      root_absolute="$(__dybatpho_safety_absolute_path "${root}")"
      if [[ "${absolute_path}" == "${root_absolute}" || "${absolute_path}" == "${root_absolute%/}/"* ]]; then
        is_inside=true
        break
      fi
    done
    dybatpho::is true "${is_inside}" \
      || dybatpho::die "Refusing to touch ${description} outside DYBATPHO_SAFE_ROOTS: ${absolute_path}"
  fi
  printf '%s\n' "${absolute_path}"
}

#######################################
# @description Remove files and directories after validating them and confirming the removal.
# @arg $1 string Option `--force`/`-f` to skip confirmation, or `--recursive`/`-r` to allow directories
# @arg $@ string Paths to remove, optionally after a `--` separator
# @exitcode 0 Every requested path is removed or already missing
# @exitcode 1 The removal is declined, or the script stops on an invalid path
# @env DRY_RUN string When true-like, print the `rm` commands instead of running them
# @tip Missing paths are skipped instead of failing, like `rm -f`
#######################################
function dybatpho::safe_rm {
  local force="${DYBATPHO_FORCE}" recursive=false
  local -a targets=()
  __dybatpho_helpers_options_into targets - '-f|--force=force -r|--recursive=recursive' '' '-*' \
    'dybatpho::safe_rm: unknown option: {option}' '' -- "$@"
  ((${#targets[@]})) || dybatpho::die "dybatpho::safe_rm: expected at least one path"

  local -a removals=()
  local target absolute_path
  for target in "${targets[@]}"; do
    absolute_path="$(dybatpho::assert_safe_path "${target}" "path")" || return $?
    if ! dybatpho::is exist "${absolute_path}" && ! dybatpho::is link "${absolute_path}"; then
      dybatpho::debug "Skipping missing path: ${absolute_path}"
      continue
    fi
    if dybatpho::is dir "${absolute_path}" && ! dybatpho::is link "${absolute_path}"; then
      dybatpho::is true "${recursive}" \
        || dybatpho::die "Refusing to remove a directory without --recursive: ${absolute_path}"
    fi
    removals+=("${absolute_path}")
  done
  ((${#removals[@]})) || return 0

  if ! __dybatpho_safety_approve "${force}" "Remove ${#removals[@]} path(s): ${removals[*]}?"; then
    dybatpho::warn "Aborted removal of ${#removals[@]} path(s)"
    return 1
  fi

  for absolute_path in "${removals[@]}"; do
    if dybatpho::is dir "${absolute_path}" && ! dybatpho::is link "${absolute_path}"; then
      dybatpho::dry_run rm -rf -- "${absolute_path}"
    else
      dybatpho::dry_run rm -f -- "${absolute_path}"
    fi
  done
}

#######################################
# @description Confirm that an existing file may be replaced, optionally keeping a backup.
# @arg $1 string Option `--force`/`-f` to skip confirmation, or `--backup`/`-b` to keep a `.bak` copy
# @arg $2 string Destination path to overwrite
# @exitcode 0 The destination is free, or replacing it is approved
# @exitcode 1 Replacing the destination is declined
# @env DRY_RUN string When true-like, print the backup command instead of running it
# @tip Call it as a guard: `dybatpho::safe_overwrite "${file}" && printf '%s' "${data}" > "${file}"`
#######################################
function dybatpho::safe_overwrite {
  local force="${DYBATPHO_FORCE}" backup=false
  local -a targets=()
  __dybatpho_helpers_options_into targets - '-f|--force=force -b|--backup=backup' '' '-*' \
    'dybatpho::safe_overwrite: unknown option: {option}' '' -- "$@"
  ((${#targets[@]} == 1)) || dybatpho::die "dybatpho::safe_overwrite: expected exactly one destination"

  local absolute_path
  absolute_path="$(dybatpho::assert_safe_path "${targets[0]}" "destination")" || return $?
  if dybatpho::is dir "${absolute_path}"; then
    dybatpho::die "Refusing to overwrite a directory: ${absolute_path}"
  fi
  if ! dybatpho::is exist "${absolute_path}"; then
    return 0
  fi
  if ! __dybatpho_safety_approve "${force}" "Overwrite existing file ${absolute_path}?"; then
    dybatpho::warn "Aborted overwrite of ${absolute_path}"
    return 1
  fi
  if dybatpho::is true "${backup}"; then
    dybatpho::dry_run cp -p -- "${absolute_path}" "${absolute_path}.bak"
  fi
}

#######################################
# @description Resolve the effective destination of a copy or move.
# @arg $1 string Source path
# @arg $2 string Destination path
# @stdout Destination path, expanded with the source name when the destination is a directory
# @internal
#######################################
function __dybatpho_safety_transfer_target {
  local source_path destination
  dybatpho::expect_args source_path destination -- "$@"
  if dybatpho::is dir "${destination}"; then
    local path_basename
    path_basename=$(dybatpho::path_basename "${source_path}")
    printf '%s\n' "${destination%/}/${path_basename}"
  else
    printf '%s\n' "${destination}"
  fi
}

#######################################
# @description Copy a file or directory, guarding the destination against an accidental overwrite.
# @arg $1 string Option `--force`/`-f` to skip confirmation, or `--backup`/`-b` to keep a `.bak` copy
# @arg $2 string Source path
# @arg $3 string Destination path or directory
# @exitcode 0 The copy is done
# @exitcode 1 The overwrite is declined, or the script stops when the source is missing
# @env DRY_RUN string When true-like, print the `cp` command instead of running it
#######################################
function dybatpho::safe_copy {
  __dybatpho_safety_transfer copy "$@"
}

#######################################
# @description Move a file or directory, guarding the destination against an accidental overwrite.
# @arg $1 string Option `--force`/`-f` to skip confirmation, or `--backup`/`-b` to keep a `.bak` copy
# @arg $2 string Source path
# @arg $3 string Destination path or directory
# @exitcode 0 The move is done
# @exitcode 1 The overwrite is declined, or the script stops when the source is missing
# @env DRY_RUN string When true-like, print the `mv` command instead of running it
#######################################
function dybatpho::safe_move {
  __dybatpho_safety_transfer move "$@"
}

#######################################
# @description Copy or move a path through the overwrite guard.
# @arg $1 string Mode, `copy` or `move`
# @arg $@ string Options, source, and destination forwarded from the public wrapper
# @exitcode 0 The transfer is done
# @exitcode 1 The overwrite is declined
# @internal
#######################################
function __dybatpho_safety_transfer {
  local mode
  dybatpho::expect_args mode -- "$@"
  shift
  local force="${DYBATPHO_FORCE}" backup=false
  local -a positional=()
  __dybatpho_helpers_options_into positional - '-f|--force=force -b|--backup=backup' '' '-*' \
    "dybatpho::safe_${mode}: unknown option: {option}" '' -- "$@"
  ((${#positional[@]} == 2)) || dybatpho::die "dybatpho::safe_${mode}: expected a source and a destination"

  local source_path="${positional[0]}" destination="${positional[1]}"
  dybatpho::is exist "${source_path}" || dybatpho::die "Source doesn't exist: ${source_path}"
  destination="$(__dybatpho_safety_transfer_target "${source_path}" "${destination}")"

  local -a guard_args=()
  if dybatpho::is true "${force}"; then
    guard_args+=(--force)
  fi
  if dybatpho::is true "${backup}"; then
    guard_args+=(--backup)
  fi
  dybatpho::safe_overwrite ${guard_args[@]+"${guard_args[@]}"} -- "${destination}" || return $?

  local parent_dir
  parent_dir="$(dybatpho::path_dirname "${destination}")"
  dybatpho::is dir "${parent_dir}" || dybatpho::dry_run mkdir -p -- "${parent_dir}"
  if [[ "${mode}" == copy ]]; then
    dybatpho::dry_run cp -R -p -- "${source_path}" "${destination}"
  else
    dybatpho::dry_run mv -f -- "${source_path}" "${destination}"
  fi
}

#######################################
# @description Extract an archive after rejecting entries that escape the destination.
# @arg $1 string Option `--force`/`-f` to skip confirmation
# @arg $2 string Archive file path
# @arg $3 string Optional destination directory, default is `.`
# @arg $4 number Optional strip-components count, default is `0`
# @exitcode 0 The archive is extracted
# @exitcode 1 Overwriting existing files is declined
# @exitcode 1 Stop the script when an entry is absolute or traverses outside the destination
# @exitcode 1 Stop the script when the `archive` module is not loaded
# @stdout Command output from the selected extractor, if any
# @tip Symlink targets stored inside an archive aren't inspected; extract untrusted archives into a scratch directory
# @tip The entries are listed and extracted by the `archive` module, which
#   `safety` does not load; load it alongside: `--modules safety archive`
#######################################
function dybatpho::safe_extract {
  # Only this guard needs `archive`, and registering it as a dependency would
  # load it into every script that confirms a prompt or removes a file -- and,
  # through `cli` and `tui`, into far more than that. The guard names an
  # internal helper on purpose: `dybatpho::` functions are exported and a child
  # shell inherits them without the internals they call, so testing the public
  # name would pass in a child that never loaded `archive` and then fail on the
  # first internal call.
  __dybatpho_helpers_need_module archive __dybatpho_archive_entry_is_safe "${FUNCNAME[0]}"
  local force="${DYBATPHO_FORCE}"
  local -a positional=()
  __dybatpho_helpers_options_into positional - '-f|--force=force' '' '-*' \
    'dybatpho::safe_extract: unknown option: {option}' '' -- "$@"
  ((${#positional[@]})) || dybatpho::die "dybatpho::safe_extract: expected an archive path"

  local archive_path="${positional[0]}"
  local destination="${positional[1]:-.}"
  local strip_components="${positional[2]:-0}"
  dybatpho::is file "${archive_path}" || dybatpho::die "Archive doesn't exist: ${archive_path}"
  [[ "${strip_components}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "strip-components must be a non-negative integer: ${strip_components}"

  local destination_path
  destination_path="$(dybatpho::assert_safe_path "${destination}" "destination")" || return $?

  local entry stripped_entry target_path
  local -a collisions=()
  local archive_list_output
  # An archive that cannot be listed cannot be checked, so it is not extracted.
  __dybatpho_archive_list_into archive_list_output "${archive_path}" \
    || dybatpho::die "Refusing to extract ${archive_path}: its entries can't be checked"
  while IFS= read -r entry || [[ -n "${entry}" ]]; do
    [[ -n "${entry}" ]] || continue
    __dybatpho_archive_entry_is_safe "${entry}" \
      || dybatpho::die "Refusing to extract entry outside ${destination_path}: ${entry}"
    stripped_entry="$(__dybatpho_safety_strip_entry "${entry}" "${strip_components}")"
    [[ -n "${stripped_entry}" ]] || continue
    target_path="$(dybatpho::path_normalize "${destination_path%/}/${stripped_entry}")"
    [[ "${target_path}" == "${destination_path%/}/"* ]] \
      || dybatpho::die "Refusing to extract entry outside ${destination_path}: ${entry}"
    if dybatpho::is exist "${target_path}" && ! dybatpho::is dir "${target_path}"; then
      collisions+=("${stripped_entry}")
    fi
  done < <(printf '%s' "${archive_list_output}")

  if ((${#collisions[@]})); then
    if ! __dybatpho_safety_approve "${force}" \
      "Extract ${archive_path} into ${destination_path}, overwriting ${#collisions[@]} existing file(s)?"; then
      dybatpho::warn "Aborted extraction of ${archive_path}"
      return 1
    fi
  fi
  dybatpho::archive_extract "${archive_path}" "${destination_path}" "${strip_components}"
}

#######################################
# @description Run a command that changes system state, after confirming it.
# @arg $1 string Option `--force`/`-f` to skip confirmation
# @arg $2 string Human-readable description of the change
# @arg $@ string A `--` separator followed by the command and its arguments
# @exitcode 0 The command ran successfully
# @exitcode 1 The change is declined, or the command failed
# @env DRY_RUN string When true-like, print the command instead of running it
# @example
#   dybatpho::safe_system "Restart nginx" -- systemctl restart nginx
#######################################
function dybatpho::safe_system {
  local __dybatpho_safety_system_force="${DYBATPHO_FORCE}" __dybatpho_safety_system_description=""
  local -a __dybatpho_safety_system_arguments=() __dybatpho_safety_system_parsed=() \
  __dybatpho_safety_system_command_args=()
  __dybatpho_helpers_options_into __dybatpho_safety_system_arguments __dybatpho_safety_system_parsed \
    '-f|--force=__dybatpho_safety_system_force' '' '-*' \
    'dybatpho::safe_system: unknown option: {option}' '' -- "$@"
  # Everything before `--` is the description, everything after it the command.
  local __dybatpho_safety_system_described="${#__dybatpho_safety_system_arguments[@]}"
  ((__dybatpho_safety_system_parsed[1] < 0)) \
    || __dybatpho_safety_system_described="${__dybatpho_safety_system_parsed[1]}"
  ((__dybatpho_safety_system_described <= 1)) || dybatpho::die \
    "dybatpho::safe_system: expected a single description before --"
  ((__dybatpho_safety_system_described == 0)) \
    || __dybatpho_safety_system_description="${__dybatpho_safety_system_arguments[0]}"
  __dybatpho_safety_system_command_args=("${__dybatpho_safety_system_arguments[@]:__dybatpho_safety_system_described}")
  [[ -n "${__dybatpho_safety_system_description}" ]] || dybatpho::die "dybatpho::safe_system: expected a description"
  ((${#__dybatpho_safety_system_command_args[@]})) || dybatpho::die "dybatpho::safe_system: expected a command after --"

  if ! __dybatpho_safety_approve "${__dybatpho_safety_system_force}" \
    "Apply system change: ${__dybatpho_safety_system_description}?"; then
    dybatpho::warn "Skipped system change: ${__dybatpho_safety_system_description}"
    return 1
  fi
  dybatpho::info "Applying system change: ${__dybatpho_safety_system_description}"
  dybatpho::dry_run "${__dybatpho_safety_system_command_args[@]}"
}
