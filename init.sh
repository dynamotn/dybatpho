#!/usr/bin/env bash
# dyshellint disable=BSG050,BSG043,BSG011,BSG033,BSG037,BSG053,BSG040
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
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  # kcov(disabled)
  echo "dybatpho requires bash v4.3 or greater"
  echo "Current Bash Version: ${BASH_VERSION}"
  exit 1
  # kcov(enabled)
fi

# dyshellint disable=BSG043
if [[ -n "${__dybatpho_init_source}" && "${__dybatpho_init_source}" == "${0}" ]]; then
  # kcov(disabled)
  echo "dybatpho can't be executed directly. Please source dybatpho."
  exit 1
  # kcov(enabled)
fi

# Default shell options
set -euo pipefail          # Strict mode
shopt -s nullglob globstar # Safer and better globbing
shopt -s extglob           # Extended globbing

# Get path to root of repository and export to subshell
if [[ -z "${__dybatpho_init_source}" ]]; then
  echo "dybatpho couldn't resolve its source path. Please source init.sh from a file-backed shell context."
  exit 1
fi
DYBATPHO_DIR="$(cd -- "$(dirname "${__dybatpho_init_source}")" && pwd)"
unset __dybatpho_init_source
export DYBATPHO_DIR

# Module registry
# @env DYBATPHO_CORE_MODULES string Modules that call each other and are always loaded
DYBATPHO_CORE_MODULES="string os logging helpers process file secret"
# @env DYBATPHO_OPTIONAL_MODULES string Modules that are only loaded when requested
DYBATPHO_OPTIONAL_MODULES="array math text lock network date json validate config archive"
DYBATPHO_OPTIONAL_MODULES+=" git table cli tui screen notification semver testing safety"
DYBATPHO_OPTIONAL_MODULES+=" metrics ai agent pkg release parallel doctor i18n forge cache"
DYBATPHO_OPTIONAL_MODULES+=" markdown csv backup diff queue schedule privilege"
# The loaded set describes the current shell, so it is deliberately neither
# exported nor seeded from the environment. A child shell that sources `init.sh`
# again has to source the module files itself: only `dybatpho::` functions cross
# the process boundary, while the internal helpers they call do not, so
# inheriting the list would leave those functions half-defined.
# @env DYBATPHO_LOADED_MODULES string Modules loaded so far, in load order
DYBATPHO_LOADED_MODULES=""
# The version is a property of this copy of the library rather than of the
# shell, so a value already in the environment is honored as an override.
# @env DYBATPHO_VERSION string Cached library version, see `dybatpho::version`
DYBATPHO_VERSION="${DYBATPHO_VERSION-}"
# Modules whose dependencies are still being resolved, used to stop a
# dependency cycle from recursing forever.
__dybatpho_loading_modules=""
export DYBATPHO_CORE_MODULES DYBATPHO_OPTIONAL_MODULES

# Dependencies between optional modules. Core modules are implicit, so only the
# optional-to-optional edges are listed here. Cycles are allowed: function calls
# resolve at run time, so modules may reference each other.
declare -A __dybatpho_module_deps=(
  [table]="text"
  [csv]="math"
  [backup]="archive safety date diff"
  [queue]="lock date"
  [schedule]="lock date"
  [parallel]="date"
  [notification]="network validate"
  [archive]="safety"
  [cli]="config validate"
  [config]="validate"
  [safety]="cli"
  [tui]="cli safety"
  [testing]="text"
  [ai]="network json cache"
  [cache]="lock"
  [agent]="cli safety json"
  [pkg]="safety"
  [release]="semver git archive"
  [forge]="network json git"
  [i18n]="date"
  # A dependency may name a version, and comparing versions is what `semver` is
  # for. The edge is cheap here: a diagnostic is not on anyone's hot path, which
  # is why the version constraint lives in the report rather than in `config`,
  # whose own `yq` call would drag `semver` into every script loading `cli`.
  [doctor]="semver"
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
# @description Filter functions and re-export only dybatpho functions to subshells.
# @noargs
# @internal
#######################################
function __dybatpho_export_functions {
  local exports
  exports=$(declare -F | sed -e 's/-f /-fx /' | grep 'x dybatpho::')
  eval "${exports}"
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
  __dybatpho_export_functions
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
# @arg $1 string Selection, one of `loaded` (default), `all`, `core`, or `optional`
# @stdout Module names in registry order, or in load order for `loaded`
# @exitcode 0 Print the requested list
# @exitcode 1 Stop the script when the selection is unknown
#######################################
function dybatpho::module_list {
  local selection="${1:-loaded}"
  local modules
  case "${selection}" in
    loaded) modules="${DYBATPHO_LOADED_MODULES}" ;;
    all) modules="${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" ;;
    core) modules="${DYBATPHO_CORE_MODULES}" ;;
    optional) modules="${DYBATPHO_OPTIONAL_MODULES}" ;;
    *) dybatpho::die \
      "dybatpho::module_list: Unknown selection '${selection}', expected loaded, all, core or optional" ;;
  esac
  local module
  for module in ${modules}; do
    printf '%s\n' "${module}"
  done
}

# Resolve the requested module set. `--modules` has to be the first argument
# because a sourced script inherits the caller's positional parameters when no
# argument is passed to `source`, and that marker is what tells the two apart.
__dybatpho_requested="${DYBATPHO_MODULES-}"
if [[ "${1-}" == "--modules" ]]; then
  shift
  __dybatpho_requested="$*"
fi
__dybatpho_requested="${__dybatpho_requested//,/ }"
# No request means the core modules only. A script states what it needs, and
# `all` is available for the scripts that really do want the whole library.
[[ -n "${__dybatpho_requested// /}" ]] || __dybatpho_requested="core"

__dybatpho_selection=""
for __dybatpho_module in ${__dybatpho_requested}; do
  case "${__dybatpho_module}" in
    all) __dybatpho_selection="${__dybatpho_selection} ${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" ;;
    core) ;; # Always loaded below
    *) __dybatpho_selection="${__dybatpho_selection} ${__dybatpho_module}" ;;
  esac
done

for __dybatpho_module in ${DYBATPHO_CORE_MODULES} ${__dybatpho_selection}; do
  __dybatpho_load_module "${__dybatpho_module}" || exit 1
done
unset __dybatpho_requested __dybatpho_selection __dybatpho_module

__dybatpho_export_functions
