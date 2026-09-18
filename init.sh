#!/usr/bin/env bash
# @file init.sh
# @brief Initial script
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
__dybatpho_init_source="${BASH_SOURCE[0]-}"

# Require bash >= v4
if ((BASH_VERSINFO[0] < 4)); then
  # kcov(disabled)
  echo "dybatpho requires bash v4 or greater"
  echo "Current Bash Version: ${BASH_VERSION}"
  exit 1
  # kcov(enabled)
fi

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
DYBATPHO_CORE_MODULES="string logging helpers process file secret"
# @env DYBATPHO_OPTIONAL_MODULES string Modules that are only loaded when requested
DYBATPHO_OPTIONAL_MODULES="array text lock network date json config archive git table cli os notification semver testing safety metrics ai agent"
# The loaded set describes the current shell, so it is deliberately neither
# exported nor seeded from the environment. A child shell that sources `init.sh`
# again has to source the module files itself: only `dybatpho::` functions cross
# the process boundary, while the internal helpers they call do not, so
# inheriting the list would leave those functions half-defined.
# @env DYBATPHO_LOADED_MODULES string Modules loaded so far, in load order
DYBATPHO_LOADED_MODULES=""
# Modules whose dependencies are still being resolved, used to stop a
# dependency cycle from recursing forever.
__dybatpho_loading_modules=""
export DYBATPHO_CORE_MODULES DYBATPHO_OPTIONAL_MODULES

# Dependencies between optional modules. Core modules are implicit, so only the
# optional-to-optional edges are listed here. Cycles are allowed: function calls
# resolve at run time, so modules may reference each other.
declare -A __dybatpho_module_deps=(
  [text]="table"
  [table]="text"
  [notification]="network"
  [archive]="safety"
  [safety]="archive cli"
  [testing]="json network text"
  [ai]="network json"
  [agent]="cli safety json"
)

#######################################
# @description Source one module file. Every module lives at
#   `src/<name>.sh`, so the name is all the map that is needed.
# @arg $1 string Module name
# @exitcode 0 The module file is sourced
# @exitcode 1 The module is registered but has no file under `src/`
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
#######################################
function __dybatpho_export_functions {
  eval "$(declare -F | sed -e 's/-f /-fx /' | grep 'x dybatpho::')"
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
    *) dybatpho::die "dybatpho::module_list: Unknown selection '${selection}', expected loaded, all, core or optional" ;;
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
