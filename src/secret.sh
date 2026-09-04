#!/usr/bin/env bash
# @file secret.sh
# @brief Utilities for handling secrets safely
# @description
#   This module reads secrets from files, environment variables, or stdin,
#   masks registered secrets in logs and error messages, and enforces safe
#   file permissions. Secrets are kept in shell variables only; they are never
#   exported, never written to shell history, and never placed in a shared
#   temporary file unless explicitly requested.
#
# @see
#   - `example/secret_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_SECRET_PLACEHOLDER string Text substituted for registered secrets. Default is `***`
DYBATPHO_SECRET_PLACEHOLDER="${DYBATPHO_SECRET_PLACEHOLDER:-***}"
# @env DYBATPHO_SECRET_MIN_LENGTH number Shortest value that may be registered for masking. Default is `4`
DYBATPHO_SECRET_MIN_LENGTH="${DYBATPHO_SECRET_MIN_LENGTH:-4}"
# @env DYBATPHO_SECRET_MAX_MODE string Most permissive octal mode allowed for a secret file. Default is `600`
DYBATPHO_SECRET_MAX_MODE="${DYBATPHO_SECRET_MAX_MODE:-600}"
# @env DYBATPHO_SECRET_STRICT_PERMS string When true-like, permission problems fail instead of warning. Default is `true`
DYBATPHO_SECRET_STRICT_PERMS="${DYBATPHO_SECRET_STRICT_PERMS:-true}"

# Registered secret values, longest first so overlapping values mask completely.
# This array is intentionally not exported to child processes.
declare -ga DYBATPHO_SECRET_VALUES=()
# @env DYBATPHO_SECRET_COUNT number Number of registered secrets; logging masks output only when above zero
declare -gi DYBATPHO_SECRET_COUNT=0

#######################################
# @description Report a permission problem as a fatal error or a warning.
# @arg $1 string Message
# @exitcode 1 Stop the script when `DYBATPHO_SECRET_STRICT_PERMS` is true-like
#######################################
function __dybatpho_secret_permission_error {
  local message
  dybatpho::expect_args message -- "$@"
  if dybatpho::is true "${DYBATPHO_SECRET_STRICT_PERMS}"; then
    dybatpho::die "${message}" # kcov(skip)
  fi
  dybatpho::warn "${message}"
}

#######################################
# @description Register one value for masking, keeping the registry sorted by length.
# @arg $1 string Secret value
# @arg $2 string Pass `true` to report skipped short values at debug level
#######################################
function __dybatpho_secret_register_one {
  local value="${1-}" quiet="${2:-false}"
  [[ -n "${value}" ]] || return 0
  if ((${#value} < DYBATPHO_SECRET_MIN_LENGTH)); then
    if [[ "${quiet}" == true ]]; then
      dybatpho::debug "Skipped masking a value shorter than ${DYBATPHO_SECRET_MIN_LENGTH} characters"
    else
      dybatpho::warn "Value shorter than ${DYBATPHO_SECRET_MIN_LENGTH} characters isn't registered for masking"
    fi
    return 0
  fi

  local existing
  for existing in ${DYBATPHO_SECRET_VALUES[@]+"${DYBATPHO_SECRET_VALUES[@]}"}; do
    [[ "${existing}" == "${value}" ]] && return 0
  done

  local -a merged=()
  local inserted=false
  for existing in ${DYBATPHO_SECRET_VALUES[@]+"${DYBATPHO_SECRET_VALUES[@]}"}; do
    if [[ "${inserted}" == false ]] && ((${#value} > ${#existing})); then
      merged+=("${value}")
      inserted=true
    fi
    merged+=("${existing}")
  done
  [[ "${inserted}" == false ]] && merged+=("${value}")
  DYBATPHO_SECRET_VALUES=(${merged[@]+"${merged[@]}"})
  DYBATPHO_SECRET_COUNT=${#DYBATPHO_SECRET_VALUES[@]}
}

#######################################
# @description Replace every registered secret inside a variable, in place.
# @arg $1 string Name of the variable to redact
#######################################
function __dybatpho_secret_mask_var {
  local __dybatpho_mask_name
  dybatpho::expect_args __dybatpho_mask_name -- "$@"
  ((DYBATPHO_SECRET_COUNT > 0)) || return 0
  local -n __dybatpho_mask_target="${__dybatpho_mask_name}"
  local __dybatpho_mask_value
  for __dybatpho_mask_value in ${DYBATPHO_SECRET_VALUES[@]+"${DYBATPHO_SECRET_VALUES[@]}"}; do
    __dybatpho_mask_target="${__dybatpho_mask_target//"${__dybatpho_mask_value}"/${DYBATPHO_SECRET_PLACEHOLDER}}"
  done
}

#######################################
# @description Print the octal permission mode of a path, following symbolic links.
# @arg $1 string Path
# @stdout Three or four digit octal mode
# @exitcode 1 The mode cannot be read
#######################################
function __dybatpho_secret_file_mode {
  local path
  dybatpho::expect_args path -- "$@"
  local mode
  if mode=$(stat -L -c '%a' "${path}" 2> /dev/null); then
    printf '%s\n' "${mode}"
    return 0
  fi
  # kcov(disabled)
  if mode=$(stat -L -f '%Lp' "${path}" 2> /dev/null); then
    printf '%s\n' "${mode}"
    return 0
  fi
  return 1
  # kcov(enabled)
}

#######################################
# @description Print the owner user id of a path.
# @arg $1 string Path
# @stdout Numeric user id
# @exitcode 1 The owner cannot be read
#######################################
function __dybatpho_secret_file_owner {
  local path
  dybatpho::expect_args path -- "$@"
  local owner
  if owner=$(stat -L -c '%u' "${path}" 2> /dev/null); then
    printf '%s\n' "${owner}"
    return 0
  fi
  # kcov(disabled)
  if owner=$(stat -L -f '%u' "${path}" 2> /dev/null); then
    printf '%s\n' "${owner}"
    return 0
  fi
  return 1
  # kcov(enabled)
}

#######################################
# @description Register secret values so they are masked in logs, errors, and masked output.
# @example
#   dybatpho::secret_register "${TOKEN}"
#   dybatpho::error "request failed with ${TOKEN}" # logs `request failed with ***`
#
# @arg $@ string Secret values
# @env DYBATPHO_SECRET_MIN_LENGTH number Values shorter than this are skipped to avoid redacting unrelated text
# @tip Multiline secrets also register each of their lines so line-based streams stay masked
#######################################
function dybatpho::secret_register {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  local value line
  for value in "$@"; do
    __dybatpho_secret_register_one "${value}"
    if [[ "${value}" == *$'\n'* ]]; then
      while IFS= read -r line; do
        [[ -n "${line}" ]] && __dybatpho_secret_register_one "${line}" true
      done <<< "${value}"
    fi
  done
}

#######################################
# @description Forget every registered secret so masking stops.
# @noargs
# @tip Registered values are process-local; this only clears the current shell
#######################################
function dybatpho::secret_forget {
  DYBATPHO_SECRET_VALUES=()
  DYBATPHO_SECRET_COUNT=0
}

#######################################
# @description Mask registered secrets in arguments or in stdin.
# @example
#   printf 'token=%s\n' "${TOKEN}" | dybatpho::secret_mask
#   dybatpho::secret_mask "authorization: ${TOKEN}"
#
# @arg $@ string Optional text to mask; stdin is read when no argument is given
# @stdout Input text with every registered secret replaced by the placeholder
# @tip Stdin is processed line by line, so register multiline secrets before streaming
# @tip Registered secrets stay in the current process, so run this in the shell that registered them
#######################################
# shellcheck disable=SC2120 # Arguments are optional; stdin is used without them.
function dybatpho::secret_mask {
  local text maskable=false
  # The registry is process-local and never exported, so a child shell only
  # passes text through instead of failing.
  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    maskable=true
  fi
  if (($# > 0)); then
    for text in "$@"; do
      [[ "${maskable}" == true ]] && __dybatpho_secret_mask_var text
      printf '%s\n' "${text}"
    done
    return 0
  fi
  while IFS= read -r text || [[ -n "${text}" ]]; do
    [[ "${maskable}" == true ]] && __dybatpho_secret_mask_var text
    printf '%s\n' "${text}"
  done
}

#######################################
# @description Run a command and mask registered secrets in its output.
# @example
#   dybatpho::secret_mask_run curl -H "Authorization: Bearer ${TOKEN}" "${url}"
#
# @arg $@ string Command and arguments
# @stdout Masked stdout and stderr of the command
# @exitcode * Exit code of the command
# @tip Output streams are merged so a secret split across both streams can't leak unmasked
#######################################
function dybatpho::secret_mask_run {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command"
  local status=0
  # shellcheck disable=SC2119 # Masking reads the piped stream, not our arguments.
  "$@" 2>&1 | dybatpho::secret_mask || status=$?
  return "${status}"
}

#######################################
# @description Print a non-reversible hint for a secret, revealing only its last characters.
# @arg $1 string Secret value
# @arg $2 number Characters to reveal, default is 4
# @stdout Placeholder followed by the revealed suffix
#######################################
function dybatpho::secret_hint {
  local value reveal
  dybatpho::expect_args value -- "$@"
  reveal="${2:-4}"
  [[ "${reveal}" =~ ^[0-9]+$ ]] || dybatpho::die "${FUNCNAME[0]}: Expected a number of revealed characters"
  if ((${#value} <= reveal * 2)); then
    printf '%s\n' "${DYBATPHO_SECRET_PLACEHOLDER}"
  else
    printf '%s%s\n' "${DYBATPHO_SECRET_PLACEHOLDER}" "${value: -reveal}"
  fi
}

#######################################
# @description Verify that a secret file is owned by the current user and isn't readable by others.
# @example
#   dybatpho::secret_check_permission ~/.config/app/token 600
#
# @arg $1 string File path
# @arg $2 string Most permissive octal mode allowed, default is `DYBATPHO_SECRET_MAX_MODE`
# @env DYBATPHO_SECRET_STRICT_PERMS string Set to a false-like value to warn instead of failing
# @exitcode 0 The file exists and its permissions are acceptable
# @exitcode 1 The file is missing, unreadable, or too permissive under strict mode
#######################################
function dybatpho::secret_check_permission {
  local path max_mode
  dybatpho::expect_args path -- "$@"
  max_mode="${2:-${DYBATPHO_SECRET_MAX_MODE}}"
  [[ "${max_mode}" =~ ^[0-7]{3,4}$ ]] || dybatpho::die "Invalid octal mode: ${max_mode}"

  dybatpho::is exist "${path}" || dybatpho::die "Secret file not found: ${path}"
  dybatpho::is file "${path}" || dybatpho::die "Secret path isn't a regular file: ${path}"
  dybatpho::is readable "${path}" || dybatpho::die "Secret file isn't readable: ${path}"
  dybatpho::is link "${path}" \
    && dybatpho::warn "Secret file is a symbolic link, permissions of its target are used: ${path}"

  local mode owner
  mode=$(__dybatpho_secret_file_mode "${path}") \
    || dybatpho::die "Cannot read permissions of secret file: ${path}"
  owner=$(__dybatpho_secret_file_owner "${path}") \
    || dybatpho::die "Cannot read owner of secret file: ${path}"

  if ((owner != EUID && EUID != 0)); then
    __dybatpho_secret_permission_error "Secret file isn't owned by the current user: ${path}"
  fi

  local extra_bits=$((8#${mode} & ~8#${max_mode} & 8#777))
  if ((extra_bits != 0)); then
    local mode_error
    printf -v mode_error 'Secret file %s has mode %04o, expected at most %04o' \
      "${path}" "$((8#${mode}))" "$((8#${max_mode}))"
    __dybatpho_secret_permission_error "${mode_error}"
  fi

  local parent parent_mode
  parent="$(dirname -- "${path}")"
  if parent_mode=$(__dybatpho_secret_file_mode "${parent}" 2> /dev/null); then
    if ((8#${parent_mode} & 8#022)); then
      dybatpho::warn "Directory of secret file is writable by group or others: ${parent}"
    fi
  fi
  return 0
}

#######################################
# @description Read a secret from a file into a variable and register it for masking.
# @example
#   local TOKEN
#   dybatpho::secret_from_file TOKEN ~/.config/app/token
#
# @arg $1 string Variable name that receives the secret
# @arg $2 string File path
# @set $1 string Secret content without trailing newlines
# @exitcode 1 The file is missing, empty, or has unsafe permissions
# @tip Permissions are validated with `dybatpho::secret_check_permission` before the file is read
#######################################
function dybatpho::secret_from_file {
  local __dybatpho_secret_var path
  dybatpho::expect_args __dybatpho_secret_var path -- "$@"
  [[ "${__dybatpho_secret_var}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid variable name: ${__dybatpho_secret_var}"
  dybatpho::secret_check_permission "${path}"

  local -n __dybatpho_secret_dest="${__dybatpho_secret_var}"
  __dybatpho_secret_dest="$(< "${path}")"
  [[ -n "${__dybatpho_secret_dest}" ]] || dybatpho::die "Secret file is empty: ${path}"
  dybatpho::secret_register "${__dybatpho_secret_dest}"
}

#######################################
# @description Read a secret from an environment variable and unset the source variable.
# @example
#   local TOKEN
#   dybatpho::secret_from_env TOKEN APP_TOKEN
#
# @arg $1 string Variable name that receives the secret
# @arg $2 string Environment variable holding the secret
# @arg $3 string Pass `keep` to leave the environment variable in place
# @set $1 string Secret value
# @exitcode 1 The environment variable is unset or empty
# @tip The source variable is unset by default so the secret isn't inherited by child processes
#######################################
function dybatpho::secret_from_env {
  local __dybatpho_secret_var name mode
  dybatpho::expect_args __dybatpho_secret_var name -- "$@"
  mode="${3:-unset}"
  [[ "${__dybatpho_secret_var}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid variable name: ${__dybatpho_secret_var}"
  [[ "${name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid environment variable name: ${name}"
  case "${mode}" in
    keep | unset) ;;                                                                   # kcov(skip)
    *) dybatpho::die "${FUNCNAME[0]}: Expected \`keep\` or \`unset\`, got: ${mode}" ;; # kcov(skip)
  esac

  [[ -n "${!name:-}" ]] || dybatpho::die "Environment variable \`${name}\` isn't set or is empty"
  local -n __dybatpho_secret_dest="${__dybatpho_secret_var}"
  __dybatpho_secret_dest="${!name}"
  dybatpho::secret_register "${__dybatpho_secret_dest}"
  [[ "${mode}" == unset ]] && unset -v "${name}"
  return 0
}

#######################################
# @description Read a secret from stdin, without echoing it when the input is a terminal.
# @example
#   local TOKEN
#   dybatpho::secret_from_stdin TOKEN "API token: "
#
# @arg $1 string Variable name that receives the secret
# @arg $2 string Optional prompt written to stderr when stdin is a terminal
# @set $1 string Secret value without its trailing newline
# @stderr Prompt text when stdin is a terminal
# @exitcode 1 No secret is provided
# @tip Reads a single line; use `dybatpho::secret_from_file` for multiline material such as private keys
#######################################
function dybatpho::secret_from_stdin {
  local __dybatpho_secret_var prompt
  dybatpho::expect_args __dybatpho_secret_var -- "$@"
  prompt="${2-}"
  [[ "${__dybatpho_secret_var}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid variable name: ${__dybatpho_secret_var}"

  local -n __dybatpho_secret_dest="${__dybatpho_secret_var}"
  __dybatpho_secret_dest=""
  if [[ -t 0 ]]; then
    # kcov(disabled)
    [[ -n "${prompt}" ]] && printf '%s' "${prompt}" >&2
    IFS= read -rs __dybatpho_secret_dest || true
    printf '\n' >&2
    # kcov(enabled)
  else
    IFS= read -r __dybatpho_secret_dest || true
  fi
  [[ -n "${__dybatpho_secret_dest}" ]] || dybatpho::die "No secret was read from stdin"
  dybatpho::secret_register "${__dybatpho_secret_dest}"
}

#######################################
# @description Read a secret from a source specification.
# @example
#   local TOKEN
#   dybatpho::secret_read TOKEN "file:${HOME}/.token"
#   dybatpho::secret_read TOKEN env:APP_TOKEN
#   dybatpho::secret_read TOKEN - "API token: "
#
# @arg $1 string Variable name that receives the secret
# @arg $2 string Source: `file:PATH`, `env:NAME`, `stdin`, or `-`
# @arg $3 string Optional prompt used by the stdin source
# @set $1 string Secret value
# @exitcode 1 The source is unsupported or the secret can't be read
#######################################
function dybatpho::secret_read {
  local variable source
  dybatpho::expect_args variable source -- "$@"
  case "${source}" in
    file:*) dybatpho::secret_from_file "${variable}" "${source#file:}" ;;
    env:*) dybatpho::secret_from_env "${variable}" "${source#env:}" ;;
    stdin | -) dybatpho::secret_from_stdin "${variable}" "${3-}" ;;
    *) dybatpho::die "Unsupported secret source: ${source}" ;; # kcov(skip)
  esac
}

#######################################
# @description Write a secret to a file that only its owner can read.
# @example
#   dybatpho::secret_write_file "${HOME}/.config/app/token" TOKEN
#
# @arg $1 string Destination file path
# @arg $2 string Variable name holding the secret
# @exitcode 1 The destination directory is missing or the write fails
# @tip The file is created with mode 600 through a private temporary file and moved into place atomically
#######################################
function dybatpho::secret_write_file {
  local path __dybatpho_secret_var
  dybatpho::expect_args path __dybatpho_secret_var -- "$@"
  [[ "${__dybatpho_secret_var}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid variable name: ${__dybatpho_secret_var}"
  local -n __dybatpho_secret_source="${__dybatpho_secret_var}"
  [[ -n "${__dybatpho_secret_source:-}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Variable \`${__dybatpho_secret_var}\` is empty"

  local directory
  directory="$(dirname -- "${path}")"
  dybatpho::is dir "${directory}" || dybatpho::die "Directory of secret file doesn't exist: ${directory}"

  local staging previous_umask
  previous_umask="$(umask)"
  umask 077
  staging="${path}.dybatpho_secret.${BASHPID}"
  : > "${staging}" || dybatpho::die "Cannot create secret file: ${staging}"
  chmod 600 "${staging}"
  printf '%s\n' "${__dybatpho_secret_source}" > "${staging}"
  umask "${previous_umask}"
  mv -f "${staging}" "${path}" || dybatpho::die "Cannot write secret file: ${path}"
}

#######################################
# @description Run a command that needs the secret as a file, without writing it to disk.
# @example
#   dybatpho::secret_with_file TOKEN gpg --passphrase-file '{}' --decrypt archive.gpg
#
# @arg $1 string Variable name holding the secret
# @arg $@ string Command and arguments; every `{}` is replaced by the secret file path
# @exitcode * Exit code of the command
# @tip The secret is exposed through `/dev/fd`, so it never reaches the filesystem on supported systems
#######################################
function dybatpho::secret_with_file {
  local __dybatpho_secret_var
  dybatpho::expect_args __dybatpho_secret_var -- "$@"
  shift
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command"
  [[ "${__dybatpho_secret_var}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid variable name: ${__dybatpho_secret_var}"
  local -n __dybatpho_secret_source="${__dybatpho_secret_var}"
  [[ -n "${__dybatpho_secret_source:-}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Variable \`${__dybatpho_secret_var}\` is empty"

  local descriptor path fallback=false
  exec {descriptor}< <(printf '%s\n' "${__dybatpho_secret_source}")
  path="/dev/fd/${descriptor}"
  if ! dybatpho::is readable "${path}"; then
    # kcov(disabled)
    exec {descriptor}<&-
    fallback=true
    dybatpho::warn "/dev/fd isn't available, falling back to a private temporary file"
    local previous_umask
    previous_umask="$(umask)"
    umask 077
    path="$(mktemp "${TMPDIR:-/tmp}/dybatpho_secret_${BASHPID}_XXXXXXXX")"
    umask "${previous_umask}"
    printf '%s\n' "${__dybatpho_secret_source}" > "${path}"
    # kcov(enabled)
  fi

  local -a command=()
  local argument
  for argument in "$@"; do
    command+=("${argument//\{\}/${path}}")
  done

  local status=0
  "${command[@]}" || status=$?
  if [[ "${fallback}" == true ]]; then
    # kcov(disabled)
    dybatpho::secret_shred "${path}"
    # kcov(enabled)
  else
    exec {descriptor}<&-
  fi
  return "${status}"
}

#######################################
# @description Stop the current shell from recording commands into a history file.
# @noargs
# @env DYBATPHO_REPL_HISTORY_FILE string Redirected to `/dev/null` so breakpoints don't persist secrets
# @tip Call this before any command that receives a secret on its command line
#######################################
function dybatpho::secret_no_history {
  unset -v HISTFILE
  HISTSIZE=0
  HISTFILESIZE=0
  export HISTSIZE HISTFILESIZE
  # shellcheck disable=SC2034 # Consumed by `dybatpho::breakpoint` in helpers.sh.
  DYBATPHO_REPL_HISTORY_FILE="/dev/null"
  set +o history 2> /dev/null || true
}

#######################################
# @description Overwrite and unset variables that hold secrets.
# @arg $@ string Variable names
# @tip Overwriting is best effort because Bash may keep copies of a string; masking stays active after a wipe
#######################################
function dybatpho::secret_wipe {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one variable name"
  local __dybatpho_secret_name
  for __dybatpho_secret_name in "$@"; do
    [[ "${__dybatpho_secret_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
      || dybatpho::die "${FUNCNAME[0]}: Invalid variable name: ${__dybatpho_secret_name}"
    [[ -v "${__dybatpho_secret_name}" ]] || continue
    local -n __dybatpho_secret_target="${__dybatpho_secret_name}"
    if [[ -n "${__dybatpho_secret_target}" ]]; then
      printf -v __dybatpho_secret_target '%*s' "${#__dybatpho_secret_target}" ''
    fi
    unset -n __dybatpho_secret_target
    unset -v "${__dybatpho_secret_name}"
  done
}

#######################################
# @description Remove files containing secrets, overwriting their content when possible.
# @arg $@ string File paths
# @tip Overwriting is skipped on copy-on-write or journaling filesystems that keep old blocks
#######################################
function dybatpho::secret_shred {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one file"
  local path
  for path in "$@"; do
    dybatpho::is file "${path}" || continue
    if dybatpho::is command shred; then
      shred -u -- "${path}" 2> /dev/null && continue
    fi
    local size
    size=$(__dybatpho_secret_file_size "${path}")
    if ((size > 0)); then
      dd if=/dev/zero of="${path}" bs=1 count="${size}" conv=notrunc 2> /dev/null || true
    fi
    rm -f -- "${path}"
  done
}

#######################################
# @description Print the size of a file in bytes.
# @arg $1 string Path
# @stdout Size in bytes, or `0` when it can't be determined
#######################################
function __dybatpho_secret_file_size {
  local path size
  dybatpho::expect_args path -- "$@"
  if size=$(stat -L -c '%s' "${path}" 2> /dev/null); then
    printf '%s\n' "${size}"
    return 0
  fi
  # kcov(disabled)
  if size=$(stat -L -f '%z' "${path}" 2> /dev/null); then
    printf '%s\n' "${size}"
    return 0
  fi
  printf '0\n'
  # kcov(enabled)
}
