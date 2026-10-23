#!/usr/bin/env bash
# dyshellint disable=BSG050,BSG043,BSG011,BSG033,BSG037,BSG053,BSG040
# A `$(...)` inside an argument passes a value on, the way this code calls the library; the inner command prints its
# own diagnostic when it fails, so a separate assignment for each would only add lines.
# shellcheck disable=SC2312 # values are passed on through $(...)
# @file init.sh
# @brief Initial script
# @namespace dybatpho
# @description This script should be sourced before any of
# the other scripts in this repo. Other scripts
# make use of ${DYBATPHO_DIR} to find each other.
#
#   Sourcing `init.sh` with no arguments loads the core modules only. A script
#   names the modules it needs, and dybatpho resolves the dependencies for it:
#
#   ```sh
#   . dybatpho/init.sh --modules logging git semver   # positional form
#   DYBATPHO_MODULES="logging git semver" . dybatpho/init.sh # environment form
#   . dybatpho/init.sh --modules all                  # the whole library
#   ```
#
#   Every module set includes the core modules, and can be widened later with
#   `dybatpho::load`.
#
#   By default the bootstrap turns on strict mode in the sourcing shell —
#   `set -euo pipefail`, `extglob`, and `inherit_errexit` on Bash 4.4+ — and
#   leaves globbing alone: an unmatched pattern stays literal, as Bash does by
#   default. `--no-strict` leaves every `set` and `shopt` option of the caller
#   as it was:
#
#   ```sh
#   . dybatpho/init.sh --no-strict --modules logging
#   ```
#
#   Nothing is exported to child processes unless the script asks for it, with
#   `DYBATPHO_EXPORT_FUNCTIONS=true` before sourcing or a call to
#   `dybatpho::export_functions`. Sourcing never ends the calling shell: a
#   failed bootstrap returns 1, and the caller decides what to do.
#
# @see
#   - `example/init_modules.sh`

# Capture the current source path before strict mode. Some shells invoked through
# `bash -c/-lc` may expose an empty `BASH_SOURCE` array transiently.
# The loaders answer with a status their caller handles — a missing module
# stops the bootstrap with a message, not with an unexplained `errexit`.
# shellcheck disable=SC2310
__dybatpho_init_source="${BASH_SOURCE[0]-}"

# Require bash >= v4.3. The library builds on two features that arrived in that
# release: nameref variables (`local -n`), which many modules use to return a
# value without a subshell, and `wait -n`, which the worker pool needs.
# A sourced file ends with `return`, which leaves the caller running so that it
# can report the problem its own way; `return` fails outside a sourced file or
# function, and only then does `exit` stop the program.
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  # kcov(disabled)
  echo "dybatpho requires bash v4.3 or greater" >&2
  echo "Current Bash Version: ${BASH_VERSION}" >&2
  # shellcheck disable=SC2317 # reached when the file is executed rather than sourced
  return 1 2> /dev/null || exit 1
  # kcov(enabled)
fi

# dyshellint disable=BSG043
if [[ -n "${__dybatpho_init_source}" && "${__dybatpho_init_source}" == "${0}" ]]; then
  # kcov(disabled)
  echo "dybatpho can't be executed directly. Please source dybatpho." >&2
  exit 1
  # kcov(enabled)
fi

if [[ -z "${__dybatpho_init_source}" ]]; then
  echo "dybatpho couldn't resolve its source path. Please source init.sh from a file-backed shell context." >&2
  unset __dybatpho_init_source
  return 1
fi

# A child process of a script that called `dybatpho::export_functions` reaches
# this file through `BASH_ENV`, which Bash sources before the child's own
# commands. That is the only way in with nothing below it on the call stack and
# no calling line, and with `BASH_ENV` naming this very file. In that case the
# child gets the parent's module set, and its own options are left alone: the
# child did not ask for strict mode, and its arguments are not meant for here.
__dybatpho_init_hook=false
if [[ -n "${DYBATPHO_EXPORT_MODULES+set}" && ${#BASH_SOURCE[@]} -eq 1 && "${BASH_LINENO[0]-}" == 0 &&
  "${__dybatpho_init_source}" == "${BASH_ENV-}" ]]; then
  __dybatpho_init_hook=true
fi

# Read the options. `--modules` and `--no-strict` have to start the argument
# list because a sourced script inherits the caller's positional parameters
# when no argument is passed to `source`, and that marker is what tells the two
# apart.
__dybatpho_init_strict=true
__dybatpho_requested="${DYBATPHO_MODULES-}"
if [[ "${__dybatpho_init_hook}" == true ]]; then
  __dybatpho_init_strict=false
  __dybatpho_requested="${DYBATPHO_EXPORT_MODULES}"
elif [[ "${1-}" == "--modules" || "${1-}" == "--no-strict" ]]; then
  __dybatpho_init_modules_given=false
  __dybatpho_init_list=""
  for __dybatpho_module in "$@"; do
    case "${__dybatpho_module}" in
      --no-strict) __dybatpho_init_strict=false ;;
      --modules) __dybatpho_init_modules_given=true ;;
      *) __dybatpho_init_list="${__dybatpho_init_list} ${__dybatpho_module}" ;;
    esac
  done
  [[ "${__dybatpho_init_modules_given}" == true ]] && __dybatpho_requested="${__dybatpho_init_list}"
  unset __dybatpho_init_modules_given __dybatpho_init_list
fi

# Get path to root of repository and export to subshell
# The directory is cut from the path rather than asked of `dirname`, which is a
# process of its own on every script start. `CDPATH` is cleared for the `cd`:
# with it set, a relative path such as `lib/dybatpho` is looked up there first,
# so the library resolved to whatever directory of that name `CDPATH` held, and
# `cd` printed that path into the value as well.
__dybatpho_init_dir="."
[[ "${__dybatpho_init_source}" == */* ]] && __dybatpho_init_dir="${__dybatpho_init_source%/*}"
DYBATPHO_DIR="$(CDPATH='' cd -- "${__dybatpho_init_dir:-/}" && pwd)"
unset __dybatpho_init_source __dybatpho_init_dir
# The file a child process sources through `BASH_ENV` once the functions are
# exported; a bundle points it at itself.
__dybatpho_entry_file="${DYBATPHO_DIR}/init.sh"

# Module registry
# @env DYBATPHO_CORE_MODULES string Modules that call each other and are always loaded
DYBATPHO_CORE_MODULES="string os logging helpers process file secret array"
# @env DYBATPHO_OPTIONAL_MODULES string Modules that are only loaded when requested
DYBATPHO_OPTIONAL_MODULES="math text lock network date json validate config archive"
DYBATPHO_OPTIONAL_MODULES+=" git table cli tui screen notification semver testing safety"
DYBATPHO_OPTIONAL_MODULES+=" metrics ai agent pkg release parallel doctor i18n forge cache"
DYBATPHO_OPTIONAL_MODULES+=" markdown csv backup diff queue schedule privilege"
# The loaded set describes the current shell, so it is deliberately neither
# exported nor seeded from the environment. A child shell that sources `init.sh`
# again has to source the module files itself: no function crosses the process
# boundary unless `dybatpho::export_functions` arranged it, and even then the
# child re-sources the library rather than trusting a list.
# @env DYBATPHO_LOADED_MODULES string Modules loaded so far, in load order
DYBATPHO_LOADED_MODULES=""
# The version is a property of this copy of the library rather than of the
# shell, so a value already in the environment is honored as an override.
# @env DYBATPHO_VERSION string Cached library version, see `dybatpho::version`
DYBATPHO_VERSION="${DYBATPHO_VERSION-}"
# Modules whose dependencies are still being resolved, used to stop a
# dependency cycle from recursing forever.
__dybatpho_loading_modules=""
# @env DYBATPHO_EXPORT_FUNCTIONS bool When true-like before sourcing, call `dybatpho::export_functions` once the modules
#   are loaded, default is `false`
# @env DYBATPHO_EXPORT_MODULES string Module set a child process loads through `BASH_ENV`, set by
#   `dybatpho::export_functions` and kept current by `dybatpho::load`
# @env DYBATPHO_EXPORT_BASH_ENV string The `BASH_ENV` in place before `dybatpho::export_functions`, sourced first by
#   every child

# Dependencies between optional modules. Core modules are implicit, so only the
# optional-to-optional edges are listed here. Cycles are allowed: function calls
# resolve at run time, so modules may reference each other. The map is global
# even when `init.sh` is sourced from inside a function: `dybatpho::load` and
# `dybatpho::doctor` read it long after that function has returned.
declare -gA __dybatpho_module_deps=(
  [table]="text"
  [csv]="math"
  [backup]="archive safety date"
  [queue]="lock date"
  [schedule]="date"
  [notification]="network"
  [cli]="validate"
  [config]="validate"
  [safety]="cli"
  [tui]="cli safety"
  [testing]="text"
  [ai]="network json cache"
  [agent]="cli safety json"
  [pkg]="safety"
  [release]="semver git"
  [forge]="network json git"
  # A dependency may name a version, and comparing versions is what `semver` is
  # for. The edge is cheap here: a diagnostic is not on anyone's hot path, which
  # is why the version constraint lives in the report rather than in `config`,
  # whose own `yq` call would drag `semver` into every script loading `config`.
  [doctor]="semver"
)

# Soft dependencies: a module that calls another one from only a few of its
# functions does not load it up front. The first call that needs it loads it on
# demand, through `__dybatpho_helpers_need_module`, so a script that never takes
# that path never pays for the other module or the tools it needs. Every module
# named here must also be in the registry; `test/init.bats` checks that each
# call site that asks for a module is listed. A load that happens inside
# `$(...)` lives only as long as that subshell, so the next substitution loads
# the module again; a script on a hot path names the module up front instead.
declare -gA __dybatpho_module_soft_deps=(
  [helpers]="semver"
  [network]="json"
  [safety]="archive"
  [text]="table"
  [table]="csv"
  [csv]="json"
  [markdown]="table"
  [diff]="json"
  [backup]="diff"
  [cache]="lock"
  [schedule]="lock"
  [notification]="validate"
  [release]="archive"
  [i18n]="date"
  [parallel]="date"
  [metrics]="math network"
  [testing]="json diff"
)

# Stability tier of every registered module. A `stable` module keeps its public
# contract across minor releases: a function is deprecated for at least one
# minor release before it is removed. An `experimental` module may change in any
# minor release. A stable module depends only on stable modules, which
# `test/init.bats` checks, so a script that keeps to stable modules is never
# broken by an experimental one underneath it.
declare -gA __dybatpho_module_tiers=(
  [string]="stable" [os]="stable" [logging]="stable" [helpers]="stable"
  [process]="stable" [file]="stable" [secret]="stable" [array]="stable"
  [math]="stable" [lock]="stable" [network]="stable" [date]="stable"
  [json]="stable" [validate]="stable" [config]="stable" [archive]="stable"
  [git]="stable" [cli]="stable" [semver]="stable" [safety]="stable"
  [text]="experimental" [table]="experimental" [tui]="experimental"
  [screen]="experimental" [notification]="experimental"
  [testing]="experimental" [metrics]="experimental" [ai]="experimental"
  [agent]="experimental" [pkg]="experimental" [release]="experimental"
  [parallel]="experimental" [doctor]="experimental" [i18n]="experimental"
  [forge]="experimental" [cache]="experimental" [markdown]="experimental"
  [csv]="experimental" [backup]="experimental" [diff]="experimental"
  [queue]="experimental" [schedule]="experimental" [privilege]="experimental"
)

#######################################
# @description Source one module file. Every module lives at
#   `src/<name>.sh`, so the name is all the map that is needed.
# @arg $1 string Module name
# @exitcode 0 The module file is sourced
# @exitcode 1 The module is registered but has no file under `src/`
# @internal
#######################################
function __dybatpho_source_module {
  local file="${DYBATPHO_DIR}/src/${1}.sh"
  if [[ ! -f ${file} ]]; then
    echo "dybatpho: module '${1}' is registered but ${file} does not exist." >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "${file}"
}

#######################################
# @description Return success when a name is a known dybatpho module.
# @arg $1 string Module name
# @exitcode 0 The module is part of the registry
# @exitcode 1 The module is unknown
# @internal
#######################################
function __dybatpho_module_exists {
  [[ " ${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES} " == *" ${1} "* ]]
}

#######################################
# @description Source a module and its dependencies, at most once each.
# @arg $1 string Module name
# @set DYBATPHO_LOADED_MODULES
# @exitcode 0 The module and its dependencies are loaded
# @exitcode 1 The module is unknown
# @internal
#######################################
function __dybatpho_load_module {
  local module="$1"
  [[ " ${DYBATPHO_LOADED_MODULES} " == *" ${module} "* ]] && return 0
  # A module already being resolved is part of a dependency cycle. Stop here:
  # the module that started the cycle finishes sourcing it, and function calls
  # resolve at run time rather than at source time.
  [[ " ${__dybatpho_loading_modules} " == *" ${module} "* ]] && return 0
  if ! __dybatpho_module_exists "${module}"; then
    echo "dybatpho: unknown module '${module}'." >&2
    echo "dybatpho: known modules are ${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" >&2
    return 1
  fi
  __dybatpho_loading_modules="${__dybatpho_loading_modules:+${__dybatpho_loading_modules} }${module}"
  local dep
  for dep in ${__dybatpho_module_deps[${module}]-}; do
    __dybatpho_load_module "${dep}" || return 1
  done
  __dybatpho_source_module "${module}" || return 1
  # Record after sourcing so that the list reads in real load order, with every
  # dependency ahead of the module that pulled it in.
  DYBATPHO_LOADED_MODULES="${DYBATPHO_LOADED_MODULES:+${DYBATPHO_LOADED_MODULES} }${module}"
  __dybatpho_loading_modules="${__dybatpho_loading_modules% "${module}"}"
  __dybatpho_loading_modules="${__dybatpho_loading_modules#"${module}"}"
}

#######################################
# @description Make the loaded library available to child Bash processes.
#   Nothing crosses the process boundary by default: exporting every function
#   made each child start several times slower, could push the environment past
#   what `execve` accepts (`find -exec ... +` then fails with "environment too
#   large"), and still left a child with public functions whose internal helpers
#   and module state were missing.
#
#   This call instead points `BASH_ENV` at the library, so every non-interactive
#   Bash child -- `bash -c`, `bash script.sh`, `xargs bash -c`, `find -exec bash`
#   -- sources it before running its own commands, with the same module set as
#   this shell and without changing the child's `set` or `shopt` options. A child
#   therefore has the complete library: public functions, internal helpers and
#   module state, freshly initialized. A value `BASH_ENV` already held is kept
#   and still sourced first, so coverage tools and the caller's own hook keep
#   working. `dybatpho::load` keeps the exported module set current.
#
#   Setting `DYBATPHO_EXPORT_FUNCTIONS=true` before sourcing `init.sh` does the
#   same as calling this right after it.
#
#   What does not cross: state the parent changed at run time through function
#   calls, such as registered secrets or cleanup paths; only exported variables
#   reach the child. Interactive shells and Bash started as `sh` do not read
#   `BASH_ENV`, and each child pays for sourcing the library (a few tens of
#   milliseconds for the core modules).
# @example
#   . dybatpho/init.sh --modules semver
#   dybatpho::export_functions
#   bash -c 'dybatpho::semver_compare 1.2.0 1.10.0' # -1
#
# @set BASH_ENV
# @set DYBATPHO_EXPORT_MODULES
# @set DYBATPHO_EXPORT_BASH_ENV
# @noargs
# @exitcode 0 The library is exported
# @exitcode 1 Stop the script when the library path holds `$`, a backquote or a backslash, which `BASH_ENV` would expand
#######################################
function dybatpho::export_functions {
  local entry="${__dybatpho_entry_file}"
  # Bash expands the value of `BASH_ENV` before sourcing it, so a path holding
  # an expansion character would name another file, or run a command.
  case "${entry}" in
    *'$'* | *'`'* | *\\*)
      local why="Can't export through BASH_ENV from a path holding \$, \` or \\"
      dybatpho::die "dybatpho::export_functions: ${why}: ${entry}"
      ;;
    *) ;;
  esac
  if [[ "${BASH_ENV-}" != "${entry}" ]]; then
    DYBATPHO_EXPORT_BASH_ENV="${BASH_ENV-}"
    export DYBATPHO_EXPORT_BASH_ENV
    export BASH_ENV="${entry}"
  fi
  DYBATPHO_EXPORT_MODULES="${DYBATPHO_LOADED_MODULES}"
  export DYBATPHO_EXPORT_MODULES
  __dybatpho_export_enabled=true
}

#######################################
# @description Print the version of the library this shell loaded, including the
#   commit it is at.
#   The release version is read from the `VERSION` file next to `init.sh`, which
#   is what a release stamps and what a vendored or bundled copy carries. When
#   the copy is a Git working tree, the short commit is appended as SemVer build
#   metadata — `2.0.0+af745ff`, and `+af745ff.dirty` when the tree has
#   uncommitted changes — so a bug report names the exact code that ran rather
#   than the last tag before it. A checkout without a `VERSION` file falls back
#   to `git describe`, which carries the commit of its own. Only the library's
#   own repository is consulted: a copy vendored inside another project reports
#   its stamped version alone, because that project's commits say nothing about
#   which dybatpho is installed.
# @example
#   . dybatpho/init.sh
#   dybatpho::version   # 2.0.0+af745ff
#
# @env DYBATPHO_VERSION string Version to report, resolved on first call and cached; set it to override the resolution
# @set DYBATPHO_VERSION
# @noargs
# @stdout The version, without a leading `v`, or `unknown` when it cannot be resolved
# @exitcode 0 Always
#######################################
function dybatpho::version {
  if [[ -z "${DYBATPHO_VERSION}" ]]; then
    local version=""
    local file="${DYBATPHO_DIR}/VERSION"
    if [[ -r "${file}" ]]; then
      # `read` reports failure on a last line without a newline, and the value
      # it stored is still the one wanted.
      read -r version < "${file}" || true
    fi
    # Only this library's own repository may name a commit. A copy vendored
    # inside another project sits in *that* project's working tree, whose
    # commits say nothing about which dybatpho is installed.
    # An empty prefix means this directory *is* the repository root, which the
    # library's own checkout is and a vendored copy in a subdirectory is not.
    # Comparing prefixes rather than paths keeps the test working when the
    # checkout is reached through a symlink.
    local own_repo="false"
    [[ -z "$(git -C "${DYBATPHO_DIR}" rev-parse --show-prefix 2> /dev/null || printf 'vendored/')" ]] \
      && own_repo="true"
    if [[ -n "${version// /}" ]]; then
      # A stamped version names the release; the commit names the code. Both
      # matter in a report, so the commit rides along as build metadata, which
      # SemVer allows and ignores when comparing.
      local commit=""
      [[ "${own_repo}" == "true" ]] \
        && commit="$(git -C "${DYBATPHO_DIR}" rev-parse --short HEAD 2> /dev/null || true)"
      if [[ -n "${commit}" ]]; then
        version="${version}+${commit}"
        git -C "${DYBATPHO_DIR}" diff --quiet HEAD 2> /dev/null || version="${version}.dirty"
      fi
    elif [[ "${own_repo}" == "true" ]]; then
      # No stamp: `git describe` answers with the last tag, the distance from it,
      # and the commit, which is the same information in one string.
      version="$(git -C "${DYBATPHO_DIR}" describe --tags --always --dirty 2> /dev/null || true)"
    fi
    version="${version#v}"
    DYBATPHO_VERSION="${version:-unknown}"
  fi
  printf '%s\n' "${DYBATPHO_VERSION}"
}

#######################################
# @description Load one or more modules after `init.sh` has already been sourced.
# @example
#   . dybatpho/init.sh --modules logging
#   dybatpho::load json config
#
# @arg $@ string Module names; dependencies are resolved automatically
# @set DYBATPHO_LOADED_MODULES
# @exitcode 0 Every requested module is loaded
# @exitcode 1 Stop the script when no module is given or a module is unknown
#######################################
function dybatpho::load {
  (($#)) || dybatpho::die "dybatpho::load: Expected at least one module name"
  local module
  for module in "$@"; do
    __dybatpho_load_module "${module}" \
      || dybatpho::die "dybatpho::load: Can't load module '${module}'"
  done
  # A child process loads what this shell has loaded, so the exported set has
  # to follow every widening of it.
  if [[ "${__dybatpho_export_enabled:-false}" == true ]]; then
    dybatpho::export_functions
  fi
}

#######################################
# @description Return success when a module is already loaded.
# @arg $1 string Module name
# @exitcode 0 The module is loaded
# @exitcode 1 The module is not loaded
#######################################
function dybatpho::module_loaded {
  local module
  dybatpho::expect_args module -- "$@"
  [[ " ${DYBATPHO_LOADED_MODULES} " == *" ${module} "* ]]
}

#######################################
# @description Print module names, one per line.
#   `stable` and `experimental` select by stability tier across the whole
#   registry; see `dybatpho::module_tier`.
# @example
#   dybatpho::module_list experimental   # modules that may change in a minor release
#
# @arg $1 string [default: loaded] Selection, one of `loaded`, `all`, `core`, `optional`, `stable`, or `experimental`
# @stdout Module names in registry order, or in load order for `loaded`
# @exitcode 0 Print the requested list
# @exitcode 1 Stop the script when the selection is unknown
#######################################
function dybatpho::module_list {
  local selection="${1:-loaded}"
  local modules tier=""
  case "${selection}" in
    loaded) modules="${DYBATPHO_LOADED_MODULES}" ;;
    all) modules="${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" ;;
    core) modules="${DYBATPHO_CORE_MODULES}" ;;
    optional) modules="${DYBATPHO_OPTIONAL_MODULES}" ;;
    stable | experimental)
      modules="${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}"
      tier="${selection}"
      ;;
    *)
      local expected="loaded, all, core, optional, stable or experimental"
      dybatpho::die "dybatpho::module_list: Unknown selection '${selection}', expected ${expected}"
      ;;
  esac
  local module
  for module in ${modules}; do
    [[ -z "${tier}" || "${__dybatpho_module_tiers[${module}]-experimental}" == "${tier}" ]] || continue
    printf '%s\n' "${module}"
  done
}

#######################################
# @description Print the stability tier of a module.
#   A `stable` module keeps its public contract across minor releases, and a
#   function is deprecated for at least one minor release before it is
#   removed. An `experimental` module may change in any minor release.
# @example
#   dybatpho::module_tier json   # stable
#   dybatpho::module_tier tui    # experimental
#
# @arg $1 string Module name
# @stdout `stable` or `experimental`
# @exitcode 0 The module is known
# @exitcode 1 Stop the script when the module is unknown
#######################################
function dybatpho::module_tier {
  local module
  dybatpho::expect_args module -- "$@"
  __dybatpho_module_exists "${module}" \
    || dybatpho::die "dybatpho::module_tier: Unknown module '${module}'"
  printf '%s\n' "${__dybatpho_module_tiers[${module}]-experimental}"
}

# Resolve the requested module set.
__dybatpho_requested="${__dybatpho_requested//,/ }"
# No request means the core modules only. A script states what it needs, and
# `all` is available for the scripts that really do want the whole library.
[[ -n "${__dybatpho_requested// /}" ]] || __dybatpho_requested="core"

__dybatpho_selection=""
for __dybatpho_module in ${__dybatpho_requested}; do
  case "${__dybatpho_module}" in
    all) __dybatpho_selection="${__dybatpho_selection} ${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" ;;
    core) ;; # Always loaded below
    *)
      # A wrong name is reported before anything changes in the caller's shell,
      # so a bootstrap that fails leaves its options as they were.
      if ! __dybatpho_module_exists "${__dybatpho_module}"; then
        echo "dybatpho: unknown module '${__dybatpho_module}'." >&2
        echo "dybatpho: known modules are ${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" >&2
        unset __dybatpho_requested __dybatpho_selection __dybatpho_module __dybatpho_init_strict __dybatpho_init_hook
        return 1
      fi
      __dybatpho_selection="${__dybatpho_selection} ${__dybatpho_module}"
      ;;
  esac
done

# Default shell options. `nullglob` and `globstar` are left alone: they change
# what every glob in the caller's script means, and the library guards each of
# its own globs instead.
if [[ "${__dybatpho_init_strict}" == true ]]; then
  set -euo pipefail # Strict mode
  shopt -s extglob  # Extended globbing
  # Errexit is off inside `$(...)` unless this option passes it down, so a
  # failing command there would be ignored and the substitution would carry on.
  # The option arrived in Bash 4.4; Bash 4.3 keeps its default behaviour.
  if ((BASH_VERSINFO[0] > 4 || BASH_VERSINFO[1] >= 4)); then
    shopt -s inherit_errexit
  fi
fi

# A child reached through `BASH_ENV` first sources whatever `BASH_ENV` named
# before `dybatpho::export_functions` replaced it.
if [[ "${__dybatpho_init_hook}" == true && -n "${DYBATPHO_EXPORT_BASH_ENV-}" &&
  "${DYBATPHO_EXPORT_BASH_ENV}" != "${BASH_ENV-}" && -r "${DYBATPHO_EXPORT_BASH_ENV}" ]]; then
  # shellcheck source=/dev/null
  . "${DYBATPHO_EXPORT_BASH_ENV}"
fi

for __dybatpho_module in ${DYBATPHO_CORE_MODULES} ${__dybatpho_selection}; do
  if ! __dybatpho_load_module "${__dybatpho_module}"; then
    unset __dybatpho_requested __dybatpho_selection __dybatpho_module __dybatpho_init_strict __dybatpho_init_hook
    return 1
  fi
done
unset __dybatpho_requested __dybatpho_selection __dybatpho_module __dybatpho_init_strict

if [[ "${__dybatpho_init_hook}" == true || "${__dybatpho_export_enabled:-false}" == true ]] \
  || dybatpho::is true "${DYBATPHO_EXPORT_FUNCTIONS:-false}"; then
  unset __dybatpho_init_hook
  dybatpho::export_functions
else
  unset __dybatpho_init_hook
fi
