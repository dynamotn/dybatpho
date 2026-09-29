# shellcheck shell=bash
# @file cache.sh
# @brief Utilities for remembering an answer on disk until it goes stale
# @namespace dybatpho
# @description
#   A script that asks a slow question more than once -- an API listing, a
#   dependency resolution, a `--version` probe across a fleet -- ends up writing
#   the same four lines: work out a file name, check how old the file is,
#   compare that against a number of seconds, and remember to create the
#   directory. `dybatpho::file_age_seconds` even documents that shape as its own
#   example. This module is that shape, written once.
#
#   The centre of it is `dybatpho::cache_run`, which memoizes what a command
#   prints:
#
#   ```sh
#   releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"
#   ```
#
#   A failing command is never stored. Caching a failure turns one bad minute
#   into an hour of them, and the caller cannot tell the difference between a
#   remembered error and a fresh one.
#
#   Entries are written through `dybatpho::file_write_atomic`, so a reader sees
#   either the previous entry or the complete new one, never half of a write in
#   progress.
# @see
#   - `example/cache_ops.sh`
#   - `dybatpho::file_age_seconds`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CACHE_DIR string Directory holding cache entries, default is the XDG cache directory for `dybatpho`
# @env DYBATPHO_CACHE_NAMESPACE string Subdirectory grouping related entries, default is `default`; empty puts entries
#   directly in the cache directory
# @env DYBATPHO_CACHE_TTL number Seconds an entry stays fresh when a call does not say, default is `3600`
DYBATPHO_CACHE_DIR="${DYBATPHO_CACHE_DIR:-$(dybatpho::xdg_cache_dir dybatpho)}"
DYBATPHO_CACHE_NAMESPACE="${DYBATPHO_CACHE_NAMESPACE-default}"
DYBATPHO_CACHE_TTL="${DYBATPHO_CACHE_TTL:-3600}"

# Entries carry a suffix so that clearing a namespace can be specific about what
# it deletes. The cache directory is named by an environment variable, and a
# helper that removed every file it found in one would be a poor thing to point
# at the wrong path by accident.
readonly __DYBATPHO_CACHE_SUFFIX=".cache"

# A key becomes a file name, so it may only hold what a file name should. An
# arbitrary value goes through `dybatpho::cache_key` first.
__DYBATPHO_CACHE_KEY_REGEX='^[A-Za-z0-9][A-Za-z0-9._-]*$'

#######################################
# @description Print the directory entries are written to.
#   This is `DYBATPHO_CACHE_DIR` with the namespace below it, or the cache
#   directory itself when the namespace is empty.
# @noargs
# @example
#   dybatpho::cache_dir                                   # ~/.cache/dybatpho/default
#   DYBATPHO_CACHE_NAMESPACE=gh dybatpho::cache_dir        # ~/.cache/dybatpho/gh
#
# @env DYBATPHO_CACHE_DIR string Directory holding cache entries
# @env DYBATPHO_CACHE_NAMESPACE string Subdirectory grouping related entries
# @stdout The directory entries live in
#######################################
function dybatpho::cache_dir {
  printf '%s\n' "${DYBATPHO_CACHE_DIR}${DYBATPHO_CACHE_NAMESPACE:+/${DYBATPHO_CACHE_NAMESPACE}}"
}

#######################################
# @description Turn any values into a key that is safe as a file name.
#   Call this when the thing that identifies an entry is a URL, a request body,
#   or anything else that is not already a short name.
# @example
#   key="$(dybatpho::cache_key "${url}" "${token_owner}")"
#
# @arg $@ string Values identifying the entry; each is hashed in order
# @stdout A hexadecimal key
# @exitcode 1 Stop the script when no value is given or no hashing command exists
#######################################
function dybatpho::cache_key {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  local hasher
  hasher="$(dybatpho::coalesce_cmd sha256sum shasum cksum)" \
    || dybatpho::die "${FUNCNAME[0]}: No hashing command found; install one of sha256sum, shasum, or cksum"
  # Each value is followed by a newline so that two different splits of the
  # same text cannot hash to the same key.
  printf '%s\n' "$@" | "${hasher}" | cut -d' ' -f1
}

#######################################
# @description Print the path an entry is stored at.
# @example
#   dybatpho::cache_path releases
#
# @arg $1 string Entry key
# @env DYBATPHO_CACHE_DIR string Directory holding cache entries
# @env DYBATPHO_CACHE_NAMESPACE string Subdirectory grouping related entries
# @stdout The path of the entry, whether or not it exists
# @exitcode 1 Stop the script when the key cannot be a file name
#######################################
function dybatpho::cache_path {
  local key
  dybatpho::expect_args key -- "$@"
  [[ "${key}" =~ ${__DYBATPHO_CACHE_KEY_REGEX} ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${key}' cannot be a file name; hash it with dybatpho::cache_key"
  local cache_dir
  cache_dir=$(dybatpho::cache_dir)
  printf '%s/%s%s\n' "${cache_dir}" "${key}" "${__DYBATPHO_CACHE_SUFFIX}"
}

#######################################
# @description Return success when an entry exists and is still fresh.
#   An entry is fresh while `age < ttl`, so a time to live of one hour means an
#   entry lives one hour. `0` therefore makes nothing fresh, which is the way to
#   force a refresh without deleting anything. There is no value meaning "never
#   expires": an entry that never goes stale is a file, and
#   `dybatpho::file_write_atomic` writes those.
# @example
#   if dybatpho::cache_has releases 3600; then ... ; fi
#
# @arg $1 string Entry key
# @arg $2 number Seconds the entry stays fresh, default is `DYBATPHO_CACHE_TTL`
# @env DYBATPHO_CACHE_TTL number Default time to live
# @exitcode 0 The entry exists and is fresh
# @exitcode 1 There is no entry, or it is older than the time to live
#######################################
function dybatpho::cache_has {
  local key
  dybatpho::expect_args key -- "$@"
  local ttl="${2:-${DYBATPHO_CACHE_TTL}}"
  [[ "${ttl}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${ttl}' is not a number of seconds"
  local path
  path="$(dybatpho::cache_path "${key}")" || return 1
  dybatpho::is file "${path}" || return 1
  local age
  age="$(dybatpho::file_age_seconds "${path}")" || return 1
  ((age < ttl))
}

#######################################
# @description Print an entry when it is still fresh.
# @example
#   if body="$(dybatpho::cache_get releases 3600)"; then
#     dybatpho::debug "Using the remembered listing"
#   fi
#
# @arg $1 string Entry key
# @arg $2 number Seconds the entry stays fresh, default is `DYBATPHO_CACHE_TTL`
# @env DYBATPHO_CACHE_TTL number Default time to live
# @stdout The stored entry
# @exitcode 0 A fresh entry was printed
# @exitcode 1 There is no entry, or it is older than the time to live
# @see
#   - `dybatpho::cache_run`
#######################################
function dybatpho::cache_get {
  local key
  dybatpho::expect_args key -- "$@"
  dybatpho::cache_has "${key}" "${2-}" || return 1
  local path
  path="$(dybatpho::cache_path "${key}")" || return 1
  cat "${path}"
}

#######################################
# @description Store standard input as an entry.
#   The write goes through `dybatpho::file_write_atomic`, so a reader sees the
#   previous entry or the whole new one, and two writers cannot interleave.
# @example
#   printf '%s\n' "${body}" | dybatpho::cache_set releases
#
# @arg $1 string Entry key
# @stdin The content to store
# @env DYBATPHO_CACHE_DIR string Directory holding cache entries
# @env DRY_RUN string When true-like, report the write instead of performing it
# @exitcode 0 The entry was written
# @exitcode 1 Stop the script when the key cannot be a file name or the write fails
#######################################
function dybatpho::cache_set {
  local key
  dybatpho::expect_args key -- "$@"
  local path
  path="$(dybatpho::cache_path "${key}")" || return 1
  # A dry run creates no directory, and `dybatpho::file_write_atomic` requires
  # one before it looks at `DRY_RUN`, so the report is made here instead.
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  if dybatpho::is true "${DRY_RUN}"; then
    # Drain standard input, so that whatever is feeding this is not cut off by
    # a closed pipe.
    cat > /dev/null
    dybatpho::dry_run write "${path}"
    return 0
  fi
  # A cache entry is whatever the caller decided was expensive to obtain: an API
  # response, a token introspection, a query result. None of that is public, and
  # under the usual `umask 022` a new file lands 0644 and the directory 0755, so
  # every account on the host could read it. The entry is written under
  # `umask 077` and the directory is created 0700 instead, which is the same
  # treatment `dybatpho::secret_write_file` already gives a secret.
  local previous_umask status=0
  previous_umask="$(umask)"
  umask 077
  # `dybatpho::ensure_dir` prints the directory it made sure of, and this
  # function is on the writing end of a pipe: that path would be read as part
  # of what the caller stored.
  local cache_dir
  cache_dir=$(dybatpho::cache_dir)
  dybatpho::ensure_dir "${cache_dir}" 700 > /dev/null || status=$?
  if ((status == 0)); then
    dybatpho::file_write_atomic "${path}" || status=$?
  fi
  umask "${previous_umask}"
  return "${status}"
}

#######################################
# @description Remove one entry.
# @example
#   dybatpho::cache_forget releases
#
# @arg $1 string Entry key
# @exitcode 0 The entry is gone, whether or not it was there
# @exitcode 1 Stop the script when the key cannot be a file name
#######################################
function dybatpho::cache_forget {
  local key
  dybatpho::expect_args key -- "$@"
  local path
  path="$(dybatpho::cache_path "${key}")" || return 1
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run remove "${path}"
    return 0
  fi
  rm -f "${path}"
}

#######################################
# @description Remove every entry in the current namespace.
#   Only files this module wrote are removed, recognised by their suffix. The
#   cache directory is named by an environment variable, and emptying whatever
#   a path happens to contain is not a thing a helper should offer to do.
# @example
#   dybatpho::cache_clear
#   DYBATPHO_CACHE_NAMESPACE=gh dybatpho::cache_clear
#
# @noargs
# @env DYBATPHO_CACHE_DIR string Directory holding cache entries
# @env DYBATPHO_CACHE_NAMESPACE string Namespace to empty
# @env DRY_RUN string When true-like, report the removal instead of performing it
# @exitcode 0 The namespace holds no entries, whether or not it did before
#######################################
function dybatpho::cache_clear {
  local directory
  directory="$(dybatpho::cache_dir)"
  dybatpho::is dir "${directory}" || return 0
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run clear "${directory}"
    return 0
  fi
  dybatpho::debug "cache: clearing ${directory}"
  find "${directory}" -maxdepth 1 -type f -name "*${__DYBATPHO_CACHE_SUFFIX}" -delete
}

#######################################
# @description Print what a command prints, running it only when the remembered
#   answer has gone stale.
#   This is the whole module in one call: ask once, reuse the answer until it
#   expires, and put the command's own output through unchanged either way.
#
#   A command that fails is not stored, and its exit status is returned as it
#   is. Remembering a failure would turn one bad minute into a whole time to
#   live of them, and the caller could not tell a remembered error from a fresh
#   one. Standard error is not captured either way, so a warning the command
#   prints is seen every time rather than once.
# @example
#   releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"
#
# @example
#   # Without a time to live, DYBATPHO_CACHE_TTL decides.
#   dybatpho::cache_run tags -- git ls-remote --tags origin
#
# @arg $1 string Entry key
# @arg $2 number Optional seconds the entry stays fresh, before `--`
# @arg $@ string `--` followed by the command and its arguments
# @env DYBATPHO_CACHE_TTL number Default time to live
# @stdout The command's output, from the entry or from running it
# @exitcode 0 The output came from a fresh entry, or the command succeeded
# @exitcode other The command failed, with its own exit status, and nothing was stored
# @exitcode 1 Stop the script when no command is given after `--`
# @see
#   - `dybatpho::cache_get`
#######################################
function dybatpho::cache_run {
  local key
  dybatpho::expect_args key -- "$@"
  shift
  local ttl="${DYBATPHO_CACHE_TTL}"
  if [[ "${1-}" != "--" ]]; then
    ttl="${1-}"
    shift
  fi
  [[ "${1-}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: ${key} [ttl] -- command [args...]"
  shift
  (($# > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  local cached
  if cached="$(dybatpho::cache_get "${key}" "${ttl}")"; then
    dybatpho::debug "cache: hit ${key}"
    printf '%s\n' "${cached}"
    return 0
  fi

  dybatpho::debug "cache: miss ${key}, running $1"
  local output status=0
  output="$("$@")" || status=$?
  if ((status != 0)); then
    return "${status}"
  fi
  printf '%s\n' "${output}" | dybatpho::cache_set "${key}"
  printf '%s\n' "${output}"
}
