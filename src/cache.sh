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
#
#   The `lock` module guards the background refresh `dybatpho::cache_run
#   --stale` starts, so that a burst of callers finding the same stale entry
#   runs the command once. Plain caching needs no lock, so the module does not
#   load it: a script that serves stale entries loads `lock` as well, and
#   `--stale` and `dybatpho::cache_wait` stop with a message naming it when it
#   is missing.
# @tip Load `lock` as well to serve stale entries: `--modules cache lock`
# @see
#   - `example/cache_ops.sh`
#   - `dybatpho::file_age_seconds`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CACHE_DIR string Directory holding cache entries, default is the XDG cache directory for `dybatpho`
# @env DYBATPHO_CACHE_NAMESPACE string Subdirectory grouping related entries, default is `default`; empty puts entries
#   directly in the cache directory
# @env DYBATPHO_CACHE_TTL number Seconds an entry stays fresh when a call does not say, default is `3600`
# @env DYBATPHO_CACHE_STALE number Seconds `dybatpho::cache_run` may serve an expired entry while it refreshes in the
#   background, default is `0` (never)
DYBATPHO_CACHE_DIR="${DYBATPHO_CACHE_DIR:-$(dybatpho::xdg_cache_dir dybatpho)}"
DYBATPHO_CACHE_NAMESPACE="${DYBATPHO_CACHE_NAMESPACE-default}"
DYBATPHO_CACHE_TTL="${DYBATPHO_CACHE_TTL:-3600}"
DYBATPHO_CACHE_STALE="${DYBATPHO_CACHE_STALE:-0}"

# Entries carry a suffix so that clearing a namespace can be specific about what
# it deletes. The cache directory is named by an environment variable, and a
# helper that removed every file it found in one would be a poor thing to point
# at the wrong path by accident.
[[ -n "${__DYBATPHO_CACHE_SUFFIX-}" ]] || readonly __DYBATPHO_CACHE_SUFFIX=".cache"

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
  local __dybatpho_cache_dir
  __dybatpho_cache_dir_into __dybatpho_cache_dir
  printf '%s\n' "${__dybatpho_cache_dir}"
}

#######################################
# @description Set a variable to the directory of the current namespace, in the
#   caller's shell, so that a missing `HOME` stops the public function that
#   needed the directory instead of only a command substitution.
# @arg $1 string Name of the variable receiving the directory
# @set The named variable
# @internal
#######################################
function __dybatpho_cache_dir_into {
  local __dybatpho_cache_dir_var
  dybatpho::expect_args __dybatpho_cache_dir_var -- "$@"
  local -n __dybatpho_cache_dir_ref="${__dybatpho_cache_dir_var}"
  __dybatpho_cache_base_into __dybatpho_cache_dir_ref
  __dybatpho_cache_dir_ref+="${DYBATPHO_CACHE_NAMESPACE:+/${DYBATPHO_CACHE_NAMESPACE}}"
}

#######################################
# @description Resolve the directory the cache lives in.
#   Emptied after loading, `DYBATPHO_CACHE_DIR` would put entries at the root
#   of the filesystem, so an empty value falls back to the user cache, as it
#   does when the module loads.
# @arg $1 string Name of the variable receiving the directory
# @set The named variable
# @internal
#######################################
function __dybatpho_cache_base_into {
  local __dybatpho_cache_base_var
  dybatpho::expect_args __dybatpho_cache_base_var -- "$@"
  local -n __dybatpho_cache_base_ref="${__dybatpho_cache_base_var}"
  __dybatpho_cache_base_ref="${DYBATPHO_CACHE_DIR}"
  [[ -z "${__dybatpho_cache_base_ref}" ]] || return 0
  # A refusal names the public function the script called.
  local __dybatpho_cache_base_who="${FUNCNAME[1]}" __dybatpho_cache_base_fn
  for __dybatpho_cache_base_fn in "${FUNCNAME[@]:1}"; do
    if [[ "${__dybatpho_cache_base_fn}" == dybatpho::* ]]; then
      __dybatpho_cache_base_who="${__dybatpho_cache_base_fn}"
      break
    fi
  done
  __dybatpho_xdg_dir_into __dybatpho_cache_base_ref "${__dybatpho_cache_base_who}" \
    XDG_CACHE_HOME ".cache" dybatpho
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
  local path
  __dybatpho_cache_path_into path "${key}"
  printf '%s\n' "${path}"
}

#######################################
# @description Work out the path an entry is stored at, into a variable.
#   Every accessor resolves its path through this rather than
#   `$(dybatpho::cache_path …)`: a key that cannot be a file name has to stop
#   the script, and from inside a command substitution the stop would end only
#   the subshell while the caller read it as a cache miss.
# @arg $1 string Name of the variable receiving the path
# @arg $2 string Entry key
# @set The named variable
# @exitcode 1 Stop the script when the key cannot be a file name
# @internal
#######################################
function __dybatpho_cache_path_into {
  local __dybatpho_cache_path_var __dybatpho_cache_path_key
  dybatpho::expect_args __dybatpho_cache_path_var __dybatpho_cache_path_key -- "$@"
  local -n __dybatpho_cache_path_out="${__dybatpho_cache_path_var}"
  if ! [[ "${__dybatpho_cache_path_key}" =~ ${__DYBATPHO_CACHE_KEY_REGEX} ]]; then
    local __dybatpho_cache_path_hint="hash it with dybatpho::cache_key"
    dybatpho::die "${FUNCNAME[1]}: '${__dybatpho_cache_path_key}' cannot be a file name; ${__dybatpho_cache_path_hint}"
  fi
  local __dybatpho_cache_path_dir
  __dybatpho_cache_base_into __dybatpho_cache_path_dir
  __dybatpho_cache_path_dir+="${DYBATPHO_CACHE_NAMESPACE:+/${DYBATPHO_CACHE_NAMESPACE}}"
  __dybatpho_cache_path_out="${__dybatpho_cache_path_dir}/${__dybatpho_cache_path_key}${__DYBATPHO_CACHE_SUFFIX}"
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
  local path age
  __dybatpho_cache_path_into path "${key}"
  __dybatpho_cache_age age "${path}" || return 1
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
  __dybatpho_cache_path_into path "${key}"
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
  __dybatpho_cache_path_into path "${key}"
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
  __dybatpho_cache_dir_into cache_dir
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
  __dybatpho_cache_path_into path "${key}"
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
  __dybatpho_cache_dir_into directory
  dybatpho::is dir "${directory}" || return 0
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run clear "${directory}"
    return 0
  fi
  dybatpho::debug "cache: clearing ${directory}"
  find "${directory}" -maxdepth 1 -type f -name "*${__DYBATPHO_CACHE_SUFFIX}" -delete
}

#######################################
# @description Read the age of an entry into a variable.
# @arg $1 string Name of the variable receiving the age in seconds
# @arg $2 string Path of the entry
# @set The named variable
# @exitcode 0 The entry exists and its age was read
# @exitcode 1 There is no entry, or its age cannot be read
# @internal
#######################################
function __dybatpho_cache_age {
  local __dybatpho_cache_age_var __dybatpho_cache_age_path __dybatpho_cache_age_value
  dybatpho::expect_args __dybatpho_cache_age_var __dybatpho_cache_age_path -- "$@"
  local -n __dybatpho_cache_age_out="${__dybatpho_cache_age_var}"
  dybatpho::is file "${__dybatpho_cache_age_path}" || return 1
  __dybatpho_cache_age_value="$(dybatpho::file_age_seconds "${__dybatpho_cache_age_path}")" \
    || return 1
  __dybatpho_cache_age_out="${__dybatpho_cache_age_value}"
}

#######################################
# @description Print the lock path that guards the background refresh of an
#   entry. It sits beside the entry, so a namespace keeps its own refreshes, and
#   it does not end in the entry suffix, so clearing a namespace never mistakes
#   it for an entry.
# @arg $1 string Path of the entry
# @stdout The lock path
# @internal
#######################################
function __dybatpho_cache_refresh_lock {
  local path
  dybatpho::expect_args path -- "$@"
  printf '%s.lock\n' "${path%"${__DYBATPHO_CACHE_SUFFIX}"}"
}

#######################################
# @description Run a command and store what it prints, leaving the entry alone
#   when the command fails.
# @arg $1 string Entry key
# @arg $@ string The command and its arguments
# @exitcode 0 The command succeeded and its output was stored
# @exitcode other The command failed, with its own exit status
# @internal
#######################################
function __dybatpho_cache_refresh {
  local __dybatpho_cache_refresh_key
  dybatpho::expect_args __dybatpho_cache_refresh_key -- "$@"
  shift
  local __dybatpho_cache_refresh_output __dybatpho_cache_refresh_status=0
  __dybatpho_cache_refresh_output="$("$@")" || __dybatpho_cache_refresh_status=$?
  ((__dybatpho_cache_refresh_status == 0)) || return "${__dybatpho_cache_refresh_status}"
  printf '%s\n' "${__dybatpho_cache_refresh_output}" | dybatpho::cache_set "${__dybatpho_cache_refresh_key}"
}

#######################################
# @description Start refreshing an entry in the background, unless a refresh of
#   it is already running.
#   The lock beside the entry is taken here, before the refresh is started, and
#   released by the refresh when it ends however it ends. Taking it first means
#   there is no moment in which a refresh has been started but holds nothing,
#   so a burst of calls that all find the same stale entry starts one refresh,
#   and `dybatpho::cache_wait` cannot miss one that has not begun yet. The
#   refresh's output and diagnostics go nowhere: the caller has already been
#   answered, and a command substitution waiting on the caller must not be kept
#   open by a process it does not know about.
# @arg $1 string Entry key
# @arg $2 string Path of the entry
# @arg $@ string The command and its arguments
# @internal
#######################################
function __dybatpho_cache_refresh_background {
  local __dybatpho_cache_refresh_bg_key __dybatpho_cache_refresh_bg_path
  dybatpho::expect_args __dybatpho_cache_refresh_bg_key __dybatpho_cache_refresh_bg_path -- "$@"
  shift 2
  local __dybatpho_cache_refresh_bg_lock
  __dybatpho_cache_refresh_bg_lock="$(__dybatpho_cache_refresh_lock "${__dybatpho_cache_refresh_bg_path}")"
  if ! dybatpho::lock_acquire "${__dybatpho_cache_refresh_bg_lock}" 0 > /dev/null 2>&1; then
    dybatpho::debug "cache: ${__dybatpho_cache_refresh_bg_key} is already being refreshed"
    return 0
  fi
  dybatpho::debug "cache: stale ${__dybatpho_cache_refresh_bg_key}, refreshing in the background"
  (
    # The lock records the calling shell, which a subshell shares, so the
    # refresh is entitled to release it. A signal ends the subshell through
    # `exit`, which is what makes the EXIT handler run.
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'dybatpho::lock_release "${__dybatpho_cache_refresh_bg_lock}" > /dev/null 2>&1 || true' EXIT
    __dybatpho_cache_refresh "${__dybatpho_cache_refresh_bg_key}" "$@"
  ) < /dev/null > /dev/null 2>&1 & # kcov(skip) - run by the --stale tests; kcov never records a subshell's closing line
}

#######################################
# @description Stop unless the `lock` module is loaded.
#   Only serving a stale entry takes a lock, to start one background refresh
#   per entry and to let `dybatpho::cache_wait` see it. Registering `lock` as a
#   dependency would load it into every script that only caches, `ai` among
#   them, so the two paths that need it ask for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `lock`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `lock` module is not loaded
# @internal
#######################################
function __dybatpho_cache_need_lock {
  __dybatpho_helpers_need_module lock __dybatpho_lock_try "${FUNCNAME[1]}"
}

#######################################
# @description Wait until no background refresh of an entry is running.
#   `dybatpho::cache_run --stale` answers from an expired entry and refreshes it
#   behind the caller's back. Usually that is the point, but a script that is
#   about to exit, or that wants the refreshed answer for a later step, calls
#   this first. The refresh usually runs in a command substitution's subshell,
#   which a bare `wait` in the calling shell knows nothing about.
# @example
#   status="$(dybatpho::cache_run status 300 --stale 86400 -- fetch_status)"
#   dybatpho::cache_wait status 30 || dybatpho::warn "status refresh still running"
#
# @arg $1 string Entry key
# @arg $2 number Seconds to wait at most, default is `60`
# @env DYBATPHO_LOCK_POLL_INTERVAL number Seconds to sleep between checks
# @exitcode 0 No refresh of the entry is running
# @exitcode 1 A refresh was still running when the time ran out
#######################################
function dybatpho::cache_wait {
  local key
  dybatpho::expect_args key -- "$@"
  __dybatpho_cache_need_lock
  local timeout="${2:-60}"
  [[ "${timeout}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${timeout}' is not a number of seconds"
  local path lock start
  __dybatpho_cache_path_into path "${key}"
  lock="$(__dybatpho_cache_refresh_lock "${path}")"
  start="${SECONDS}"
  while dybatpho::lock_is_held "${lock}"; do
    ((SECONDS - start < timeout)) || return 1
    # shellcheck disable=SC2154 # declared by `src/lock.sh`, which the guard above requires
    sleep "${DYBATPHO_LOCK_POLL_INTERVAL}"
  done
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
#
#   `--stale <seconds>` adds a grace window after the time to live: an entry
#   older than the time to live but younger than the two together is printed
#   at once, as it is, while the command runs again in the background to
#   replace it. The caller never waits for a slow source that answered recently,
#   and the answer is at most one refresh behind. Only one refresh of an entry
#   runs at a time, guarded by a lock beside the entry, and a refresh that fails
#   keeps the entry it was meant to replace. An entry older than the window is
#   a miss, and the command runs in the foreground as usual.
#   `dybatpho::cache_wait` waits for a refresh to finish.
# @example
#   releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"
#
# @example
#   # Without a time to live, DYBATPHO_CACHE_TTL decides.
#   dybatpho::cache_run tags -- git ls-remote --tags origin
#
# @example
#   # Fresh for five minutes, then served stale for up to a day while it refreshes.
#   dybatpho::cache_run status 300 --stale 86400 -- curl -fsS "${status_url}"
#
# @arg $1 string Entry key
# @arg $2 number Optional seconds the entry stays fresh, before `--`
# @arg $@ string Optional `--stale <seconds>`, then `--` followed by the command and its arguments
# @env DYBATPHO_CACHE_TTL number Default time to live
# @env DYBATPHO_CACHE_STALE number Default grace window in seconds, `0` (none) unless set
# @stdout The command's output, from the entry or from running it
# @exitcode 0 The output came from a fresh or stale entry, or the command succeeded
# @exitcode other The command failed, with its own exit status, and nothing was stored
# @exitcode 1 Stop the script when no command is given after `--`, a time is not a number of seconds, or a
#   grace window is asked for without the `lock` module loaded
# @see
#   - `dybatpho::cache_get`
#   - `dybatpho::cache_wait`
#######################################
function dybatpho::cache_run {
  local __dybatpho_cache_run_key
  dybatpho::expect_args __dybatpho_cache_run_key -- "$@"
  shift
  local __dybatpho_cache_run_ttl="${DYBATPHO_CACHE_TTL}" __dybatpho_cache_run_stale="${DYBATPHO_CACHE_STALE}" \
    __dybatpho_cache_run_ttl_given=false
  local __dybatpho_cache_run_usage="${FUNCNAME[0]}: Expected: ${__dybatpho_cache_run_key}"
  __dybatpho_cache_run_usage+=" [ttl] [--stale seconds] -- command [args...]"
  while (($# > 0)) && [[ "$1" != "--" ]]; do
    case "$1" in
      --stale)
        (($# >= 2)) || dybatpho::die "${__dybatpho_cache_run_usage}"
        __dybatpho_cache_run_stale="$2"
        shift 2
        ;;
      --stale=*)
        __dybatpho_cache_run_stale="${1#--stale=}"
        shift
        ;;
      *)
        [[ "${__dybatpho_cache_run_ttl_given}" == false ]] || dybatpho::die "${__dybatpho_cache_run_usage}"
        __dybatpho_cache_run_ttl="$1"
        __dybatpho_cache_run_ttl_given=true
        shift
        ;;
    esac
  done
  [[ "${1-}" == "--" ]] || dybatpho::die "${__dybatpho_cache_run_usage}"
  shift
  (($# > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"
  [[ "${__dybatpho_cache_run_ttl}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${__dybatpho_cache_run_ttl}' is not a number of seconds"
  [[ "${__dybatpho_cache_run_stale}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${__dybatpho_cache_run_stale}' is not a number of seconds for --stale"
  ((__dybatpho_cache_run_stale == 0)) || __dybatpho_cache_need_lock

  local __dybatpho_cache_run_path __dybatpho_cache_run_age __dybatpho_cache_run_cached
  __dybatpho_cache_path_into __dybatpho_cache_run_path "${__dybatpho_cache_run_key}"
  if __dybatpho_cache_age __dybatpho_cache_run_age "${__dybatpho_cache_run_path}"; then
    if ((__dybatpho_cache_run_age < __dybatpho_cache_run_ttl)); then
      dybatpho::debug "cache: hit ${__dybatpho_cache_run_key}"
      __dybatpho_cache_run_cached="$(cat "${__dybatpho_cache_run_path}")"
      printf '%s\n' "${__dybatpho_cache_run_cached}"
      return 0
    fi
    if ((__dybatpho_cache_run_stale > 0 && __dybatpho_cache_run_age < __dybatpho_cache_run_ttl + \
      __dybatpho_cache_run_stale)); then
      __dybatpho_cache_run_cached="$(cat "${__dybatpho_cache_run_path}")"
      __dybatpho_cache_refresh_background "${__dybatpho_cache_run_key}" "${__dybatpho_cache_run_path}" "$@"
      printf '%s\n' "${__dybatpho_cache_run_cached}"
      return 0
    fi
  fi

  dybatpho::debug "cache: miss ${__dybatpho_cache_run_key}, running $1"
  local __dybatpho_cache_run_output __dybatpho_cache_run_status=0
  __dybatpho_cache_run_output="$("$@")" || __dybatpho_cache_run_status=$?
  if ((__dybatpho_cache_run_status != 0)); then
    return "${__dybatpho_cache_run_status}"
  fi
  printf '%s\n' "${__dybatpho_cache_run_output}" | dybatpho::cache_set "${__dybatpho_cache_run_key}"
  printf '%s\n' "${__dybatpho_cache_run_output}"
}

#######################################
# @description Read every entry of the current namespace into an array, oldest
#   first, as `<mtime> <bytes> <path>` lines. Entries written in the same second
#   are ordered by path, so the order never depends on the file system.
# @arg $1 string Name of the array receiving the records
# @set The named array, empty when the namespace holds no entries
# @internal
#######################################
function __dybatpho_cache_scan {
  local __dybatpho_cache_scan_var
  dybatpho::expect_args __dybatpho_cache_scan_var -- "$@"
  local -n __dybatpho_cache_scan_out="${__dybatpho_cache_scan_var}"
  __dybatpho_cache_scan_out=()
  local __dybatpho_cache_scan_dir
  __dybatpho_cache_dir_into __dybatpho_cache_scan_dir
  dybatpho::is dir "${__dybatpho_cache_scan_dir}" || return 0
  local -a __dybatpho_cache_scan_records=()
  local __dybatpho_cache_scan_path __dybatpho_cache_scan_mtime __dybatpho_cache_scan_size
  local __dybatpho_cache_scan_line
  for __dybatpho_cache_scan_path in "${__dybatpho_cache_scan_dir}"/*"${__DYBATPHO_CACHE_SUFFIX}"; do
    # An unmatched glob stays as the pattern, and a symbolic link or a
    # directory with the suffix is not something this module wrote.
    [[ -f "${__dybatpho_cache_scan_path}" && ! -L "${__dybatpho_cache_scan_path}" ]] || continue
    __dybatpho_cache_scan_mtime="$(dybatpho::file_mtime "${__dybatpho_cache_scan_path}")"
    __dybatpho_cache_scan_size="$(dybatpho::file_size "${__dybatpho_cache_scan_path}")"
    __dybatpho_cache_scan_line="${__dybatpho_cache_scan_mtime} ${__dybatpho_cache_scan_size}"
    __dybatpho_cache_scan_records+=("${__dybatpho_cache_scan_line} ${__dybatpho_cache_scan_path}")
  done
  ((${#__dybatpho_cache_scan_records[@]} > 0)) || return 0
  local __dybatpho_cache_scan_sorted
  __dybatpho_cache_scan_sorted="$(printf '%s\n' "${__dybatpho_cache_scan_records[@]}" | sort -k1,1n -k3)"
  mapfile -t __dybatpho_cache_scan_out <<< "${__dybatpho_cache_scan_sorted}"
}

#######################################
# @description Read a size such as `512`, `64K`, `10M` or `1G` into a number of
#   bytes. The suffixes are binary, so `1K` is 1024 bytes.
# @arg $1 string Name of the variable receiving the bytes
# @arg $2 string The size
# @set The named variable
# @exitcode 0 The size was read
# @exitcode 1 The size is not a number with an optional `K`, `M` or `G`
# @internal
#######################################
function __dybatpho_cache_bytes {
  local __dybatpho_cache_bytes_var __dybatpho_cache_bytes_text
  dybatpho::expect_args __dybatpho_cache_bytes_var __dybatpho_cache_bytes_text -- "$@"
  local -n __dybatpho_cache_bytes_out="${__dybatpho_cache_bytes_var}"
  [[ "${__dybatpho_cache_bytes_text}" =~ ^([0-9]+)([KkMmGg]?)$ ]] || return 1
  local number="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
  case "${unit}" in
    [Kk]) __dybatpho_cache_bytes_out=$((10#${number} * 1024)) ;;
    [Mm]) __dybatpho_cache_bytes_out=$((10#${number} * 1024 * 1024)) ;;
    [Gg]) __dybatpho_cache_bytes_out=$((10#${number} * 1024 * 1024 * 1024)) ;;
    *) __dybatpho_cache_bytes_out=$((10#${number})) ;;
  esac
}

#######################################
# @description Remove old entries until the namespace fits the limits given.
#   Entries older than `--older-than` go first. Then, while the namespace holds
#   more than `--max-entries` entries or more than `--max-size` bytes, the
#   oldest remaining entry is removed. Oldest means least recently written: an
#   entry's modification time is also its age, so reading an entry cannot mark
#   it as used without making it look fresh, and the entry the cache refreshed
#   longest ago is the one it would refetch first anyway.
#
#   Like `dybatpho::cache_clear`, only files this module wrote are considered,
#   and only in the current namespace.
# @example
#   dybatpho::cache_prune --older-than 604800
#   dybatpho::cache_prune --max-entries 500 --max-size 50M
#
# @arg $@ string At least one of `--older-than <seconds>`, `--max-entries <count>`, `--max-size <size>`;
#   a size takes an optional binary `K`, `M` or `G` suffix
# @env DYBATPHO_CACHE_DIR string Directory holding cache entries
# @env DYBATPHO_CACHE_NAMESPACE string Namespace to prune
# @env DRY_RUN string When true-like, report each removal instead of performing it
# @exitcode 0 The namespace fits the limits, whether or not anything was removed
# @exitcode 1 Stop the script when no limit is given, an option is unknown, or a limit is malformed
# @see
#   - `dybatpho::cache_stats`
#######################################
# dyshellint disable=BSG050 every argument is an option, parsed in the loop below
function dybatpho::cache_prune {
  local older_than="" max_entries="" max_size="" max_bytes=""
  local usage="${FUNCNAME[0]}: Expected --older-than <seconds>, --max-entries <count>, or --max-size <size>"
  while (($# > 0)); do
    case "$1" in
      --older-than | --max-entries | --max-size)
        (($# >= 2)) || dybatpho::die "${FUNCNAME[0]}: $1 needs a value"
        case "$1" in
          --older-than) older_than="$2" ;;
          --max-entries) max_entries="$2" ;;
          *) max_size="$2" ;;
        esac
        shift 2
        ;;
      --older-than=*)
        older_than="${1#*=}"
        shift
        ;;
      --max-entries=*)
        max_entries="${1#*=}"
        shift
        ;;
      --max-size=*)
        max_size="${1#*=}"
        shift
        ;;
      # Exercised under `run` by "cache_prune refuses a missing or malformed limit".
      *) dybatpho::die "${usage}; got '$1'" ;; # kcov(skip)
    esac
  done
  [[ -n "${older_than}${max_entries}${max_size}" ]] || dybatpho::die "${usage}"
  [[ -z "${older_than}" || "${older_than}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${older_than}' is not a number of seconds"
  [[ -z "${max_entries}" || "${max_entries}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${max_entries}' is not a number of entries"
  if [[ -n "${max_size}" ]]; then
    __dybatpho_cache_bytes max_bytes "${max_size}" \
      || dybatpho::die "${FUNCNAME[0]}: '${max_size}' is not a size; use bytes or a K, M, or G suffix"
  fi

  local -a records=() kept=()
  __dybatpho_cache_scan records
  ((${#records[@]} > 0)) || return 0

  local now record mtime size path count=0 total=0
  now="$(date +%s)"
  for record in "${records[@]}"; do
    read -r mtime size path <<< "${record}"
    if [[ -n "${older_than}" ]] && ((now - mtime > older_than)); then
      __dybatpho_cache_prune_remove "${path}"
      continue
    fi
    kept+=("${record}")
    count=$((count + 1))
    total=$((total + size))
  done

  for record in "${kept[@]}"; do
    if ! { [[ -n "${max_entries}" ]] && ((count > max_entries)); } \
      && ! { [[ -n "${max_bytes}" ]] && ((total > max_bytes)); }; then
      break
    fi
    read -r mtime size path <<< "${record}"
    __dybatpho_cache_prune_remove "${path}"
    count=$((count - 1))
    total=$((total - size))
  done
}

#######################################
# @description Remove one entry on behalf of `dybatpho::cache_prune`, or report
#   the removal under `DRY_RUN`.
# @arg $1 string Path of the entry
# @internal
#######################################
function __dybatpho_cache_prune_remove {
  local path
  dybatpho::expect_args path -- "$@"
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run remove "${path}"
    return 0
  fi
  dybatpho::debug "cache: pruning ${path}"
  rm -f -- "${path}"
}

#######################################
# @description Describe the current namespace: how many entries it holds, how
#   many bytes they take, how many are still fresh, and how old the oldest and
#   newest are.
#   Freshness is judged against the time to live given, or
#   `DYBATPHO_CACHE_TTL`, the same way `dybatpho::cache_has` judges one entry.
#   Ages are in seconds. A namespace that was never written reports zero
#   everywhere rather than failing, so a report or a metric can always be made.
#
#   Hits and misses are not counted. `dybatpho::cache_run` is usually called in
#   a command substitution, whose subshell would take any count with it, and a
#   count kept on disk would turn every read into a write.
# @example
#   dybatpho::cache_stats
#   # namespace  default
#   # directory  /home/me/.cache/dybatpho/default
#   # entries    3
#   # bytes      1800
#   # fresh      1
#   # stale      2
#   # oldest     7200
#   # newest     5
#
# @example
#   dybatpho::cache_stats 600 --json | jq .stale
#
# @arg $1 number Optional seconds an entry stays fresh, default is `DYBATPHO_CACHE_TTL`
# @arg $@ string Optional `--json`, for one JSON object of the counts instead of aligned lines
# @env DYBATPHO_CACHE_DIR string Directory holding cache entries
# @env DYBATPHO_CACHE_NAMESPACE string Namespace to describe
# @env DYBATPHO_CACHE_TTL number Default time to live
# @stdout The report; the JSON form holds `entries`, `bytes`, `fresh`, `stale`, `oldest_age` and `newest_age`
# @exitcode 0 The report was printed
# @exitcode 1 Stop the script when the time to live is not a number of seconds or an option is unknown
# @see
#   - `dybatpho::cache_prune`
#######################################
# dyshellint disable=BSG050 the time to live and `--json` may come in either order
function dybatpho::cache_stats {
  local ttl="${DYBATPHO_CACHE_TTL}" json=false
  while (($# > 0)); do
    case "$1" in
      --json) json=true ;;
      # Exercised under `run` by "cache_stats refuses a malformed time to live or option".
      -*) dybatpho::die "${FUNCNAME[0]}: Unknown option '$1'; expected [ttl] [--json]" ;; # kcov(skip)
      *) ttl="$1" ;;
    esac
    shift
  done
  [[ "${ttl}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${ttl}' is not a number of seconds"

  local -a records=()
  __dybatpho_cache_scan records
  local now record mtime size path age
  local entries=0 bytes=0 fresh=0 stale=0 oldest=0 newest=0
  now="$(date +%s)"
  for record in "${records[@]}"; do
    read -r mtime size path <<< "${record}"
    age=$((now - mtime))
    ((age >= 0)) || age=0
    entries=$((entries + 1))
    bytes=$((bytes + size))
    if ((age < ttl)); then
      fresh=$((fresh + 1))
    else
      stale=$((stale + 1))
    fi
    # Records come oldest first, so the first sets the oldest age and the last
    # the newest.
    ((entries > 1)) || oldest="${age}"
    newest="${age}"
  done

  if [[ "${json}" == true ]]; then
    printf '{"entries":%d,"bytes":%d,"fresh":%d,"stale":%d,"oldest_age":%d,"newest_age":%d}\n' \
      "${entries}" "${bytes}" "${fresh}" "${stale}" "${oldest}" "${newest}"
    return 0
  fi
  local directory
  __dybatpho_cache_dir_into directory
  printf '%-10s %s\n' \
    namespace "${DYBATPHO_CACHE_NAMESPACE:-(none)}" \
    directory "${directory}" \
    entries "${entries}" \
    bytes "${bytes}" \
    fresh "${fresh}" \
    stale "${stale}" \
    oldest "${oldest}" \
    newest "${newest}"
}
