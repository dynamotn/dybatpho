# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe; it parses its own
# arguments, so the raw form is what the reader sees.
# dyshellint disable=BSG050,BSG033,BSG051
# @file doctor.sh
# @brief Utilities for checking that the environment can run what a script loaded
# @namespace dybatpho
# @description
#   This module answers the question a user asks after a script fails with
#   `yq isn't installed` on line 400: what else is missing? A dybatpho module
#   only calls an external tool when the caller reaches the function that needs
#   it, so a missing dependency surfaces halfway through the work instead of at
#   the start.
#
#   `dybatpho::doctor` reports the Bash version, the library version, and every
#   external command the loaded modules can call, marking each one found or
#   missing. It reads as a report rather than a failure, so a user can run it
#   before the real script and fix everything at once.
#
#   Dependencies are declared per module, split in two:
#
#   - **required** — the module's main functions cannot work without it, such as
#     `curl` for `network`;
#   - **optional** — only part of the module needs it, such as `zstd` for
#     `archive` or `gpg` for signing a release.
#
#   A dependency written as `a|b` is satisfied by any one of the alternatives:
#   `file` hashes with whichever of `sha256sum`, `shasum`, or `openssl` exists.
#
#   A dependency may also name a version, as in `yq>=4`, using the range syntax
#   of `dybatpho::semver_satisfies` minus the spaces, which separate one spec
#   from the next here. Being installed is then not enough: the wrong major
#   release of a tool is its own kind of missing, and `yq` is the example that
#   prompted this, since the Go `yq` this library calls and the Python program
#   of the same name share nothing but a name.
#
#   A dependency is reported as one of four statuses:
#
#   - **ok** — installed, and new enough when a version was asked for;
#   - **missing** — no alternative is installed;
#   - **outdated** — installed, but the version does not satisfy the constraint;
#   - **unknown** — installed, but the version could not be read.
#
#   Only **required** dependencies that are missing or outdated make
#   `dybatpho::doctor` fail. An optional entry is information rather than a
#   problem, and so is `unknown`: a probe that could not read a version has not
#   shown that anything is wrong.
#
#   The report also walks the module dependency graph with
#   `dybatpho::array_toposort`, the same edges the loader follows. An explicit
#   `--modules` list is widened to every module it pulls in, in load order, so
#   the tools a dependency needs are reported too. An edge naming a module the
#   registry does not know fails the report, because the loader would stop on
#   it; a cycle is only noted, because the loader allows one.
# @see
#   - `example/doctor_ops.sh`
#   - `scripts/bundle.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_BASH_MINIMUM string Lowest Bash version the library supports
DYBATPHO_BASH_MINIMUM="4.3"

# External commands each module can call. A module absent from both maps calls
# nothing outside Bash and the POSIX tools every system ships. Keep an entry
# here on the module that runs the command itself: a module pulls its own
# dependencies in through the registry, and `dybatpho::doctor` reports those
# modules on their own rows.
# @env DYBATPHO_DOCTOR_REQUIRED array Required external commands per module
declare -gA DYBATPHO_DOCTOR_REQUIRED=(
  [ai]="curl"
  [archive]="tar"
  [forge]="curl git"
  [git]="git"
  # The YAML helpers call `yq eval`, which is the Go `yq`. The unrelated Python
  # `yq` and the Go one before v4 both take a different expression syntax, so a
  # plain presence check would pass on a host where every YAML call then fails.
  [json]="yq>=4"
  [network]="curl"
  # Raw mode is what makes a key reach the application before Return does, and
  # there is no way to ask for it from Bash alone.
  [screen]="stty"
)
# @env DYBATPHO_DOCTOR_OPTIONAL array Optional external commands per module
declare -gA DYBATPHO_DOCTOR_OPTIONAL=(
  [agent]="git"
  [ai]="claude|llm|ollama"
  # Only `dybatpho::cache_key` needs one, and any of the three will do.
  [cache]="sha256sum|shasum|cksum"
  [archive]="unzip zip gzip bzip2 xz zstd"
  # An incremental snapshot links unchanged files with `rsync --link-dest`
  # when it is there, and walks the source in Bash when it is not.
  [backup]="rsync"
  # Same Go `yq` v4 the `json` module needs: `config` reads a document's tag
  # and parses TOML with `-p toml`, neither of which the Python `yq` or the
  # pre-v4 Go one understands.
  [config]="jq yq>=4"
  # Only `dybatpho::csv_from_json` needs one, and either will do: the module
  # parses and writes CSV in Bash alone.
  [csv]="jq|yq>=4"
  # `dybatpho::diff_text` needs nothing external beyond `diff`; comparing by
  # key is built on one `jq` filter, and YAML reaches JSON through `yq`.
  [diff]="jq yq>=4"
  [file]="sha256sum|shasum|openssl"
  # Either will do, and neither is required: a script already running as root
  # needs no escalation at all.
  [privilege]="sudo|doas"
  [json]="jq"
  # `timeout` bounds the connection `dybatpho::port_open` makes. Without it the
  # probe still works and waits as long as the system's own TCP timeout.
  [network]="sha256sum md5sum timeout"
  # `dybatpho::notify_desktop` needs one of the first two and
  # `dybatpho::notify_email` a `sendmail`; every other notifier is an HTTP
  # request made through `network`.
  [notification]="notify-send|osascript sendmail"
  [os]="hostname nproc|sysctl|getconf tput"
  [release]="gpg"
)

#######################################
# @description Rank a status, so that the least satisfying alternative of a spec
#   is not the one that gets reported.
#   When no alternative satisfies the spec, the most specific complaint is the
#   useful one: `outdated` names a version to upgrade, `unknown` names a command
#   that is at least installed, and `missing` says the least.
# @arg $1 string Status
# @stdout The rank, higher being more worth reporting
# @internal
#######################################
function __dybatpho_doctor_rank {
  case "$1" in
    outdated) printf '3' ;;
    unknown) printf '2' ;;
    *) printf '1' ;;
  esac
}

#######################################
# Where a command name ends and a version range begins. The operator characters
# are listed with `^` in a position where it is an ordinary member, and the
# pattern is held in a variable rather than written inline: an unquoted pattern
# goes through quote removal first, so an escaped `\^` would arrive at the regex
# engine as a bare `^` at the head of the bracket expression and negate it,
# which matches nearly every character instead of none.
__DYBATPHO_DOCTOR_SPEC_REGEX='^([^<>=^~]+)([<>=^~].*)$'

#######################################
# @description Split a dependency alternative into its command and version range.
#   A range here cannot contain a space, because the maps separate one spec from
#   the next with one. `^4` says what `>=4 <5` would have said.
# @arg $1 string One alternative, such as `yq` or `yq>=4`
# @stdout Two lines: the command name, and the range or an empty line
# @internal
#######################################
function __dybatpho_doctor_split {
  if [[ "$1" =~ ${__DYBATPHO_DOCTOR_SPEC_REGEX} ]]; then
    printf '%s\n%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s\n\n' "$1"
  fi
}

#######################################
# @description Decide whether a dependency spec is satisfied, and how.
#   A spec is one alternative, or several separated by `|` when any one of them
#   will do. An alternative may carry a version constraint, as in `yq>=4`, in
#   which case being installed is not enough on its own.
#
#   Only an alternative that carries a constraint is asked for its version. A
#   report has no business running every tool on the host to print a table, and
#   the version of a dependency nothing has an opinion about is not news.
# @arg $1 string Dependency spec, such as `curl`, `sha256sum|shasum`, or `yq>=4`
# @stdout One line of `status<TAB>path<TAB>version`, where status is `ok`,
#   `outdated`, `unknown`, or `missing`
# @exitcode 0 An alternative is installed and satisfies its constraint
# @exitcode 1 No alternative does
# @internal
#######################################
function __dybatpho_doctor_resolve {
  local spec="$1"
  local alternative command_name constraint path version
  local status="missing" best_status="missing" best_path="" best_version=""
  local -a parts
  for alternative in ${spec//|/ }; do
    mapfile -t -n 2 parts < <(__dybatpho_doctor_split "${alternative}")
    command_name="${parts[0]}"
    constraint="${parts[1]-}"

    path="$(command -v "${command_name}" 2> /dev/null || true)"
    [[ -n "${path}" ]] || continue

    if [[ -z "${constraint}" ]]; then
      printf '%s\t%s\t%s\n' "ok" "${path}" ""
      return 0
    fi

    if version="$(dybatpho::command_version "${command_name}")"; then
      local semver_coerce
      semver_coerce=$(dybatpho::semver_coerce "${version}")
      if dybatpho::semver_satisfies "${semver_coerce}" "${constraint}"; then
        printf '%s\t%s\t%s\n' "ok" "${path}" "${version}"
        return 0
      fi
      status="outdated"
    else
      status="unknown"
      version=""
    fi

    local best_rank rank
    best_rank=$(__dybatpho_doctor_rank "${best_status}")
    rank=$(__dybatpho_doctor_rank "${status}")
    if ((rank > best_rank)); then
      best_status="${status}"
      best_path="${path}"
      best_version="${version}"
    fi
  done
  printf '%s\t%s\t%s\n' "${best_status}" "${best_path}" "${best_version}"
  return 1
}

#######################################
# @description Print the external commands a module can call.
# @example
#   dybatpho::doctor_requirements archive required
#
# @arg $1 string Module name
# @arg $2 string Kind, one of `all` (default), `required`, or `optional`
# @stdout One dependency spec per line, required specs first
# @exitcode 0 Print the dependencies, including nothing for a module that has none
# @exitcode 1 Stop the script when the module is unknown or the kind is invalid
#######################################
function dybatpho::doctor_requirements {
  local module
  dybatpho::expect_args module -- "$@"
  local kind="${2:-all}"
  __dybatpho_module_exists "${module}" \
    || dybatpho::die "${FUNCNAME[0]}: Unknown module '${module}'"
  local specs=""
  case "${kind}" in
    all) specs="${DYBATPHO_DOCTOR_REQUIRED[${module}]-} ${DYBATPHO_DOCTOR_OPTIONAL[${module}]-}" ;;
    required) specs="${DYBATPHO_DOCTOR_REQUIRED[${module}]-}" ;;
    optional) specs="${DYBATPHO_DOCTOR_OPTIONAL[${module}]-}" ;;
    *) dybatpho::die "${FUNCNAME[0]}: Unknown kind '${kind}', expected all, required or optional" ;;
  esac
  local spec
  for spec in ${specs}; do
    printf '%s\n' "${spec}"
  done
}

#######################################
# @description Return success when the running Bash is new enough for the library.
# @noargs
# @exitcode 0 Bash is at least `DYBATPHO_BASH_MINIMUM`
# @exitcode 1 Bash is older than the supported minimum
#######################################
function dybatpho::doctor_bash_supported {
  ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3)))
}

#######################################
# @description Resolve the module list a report covers.
# @arg $1 string Name of the array variable that receives the module names
# @arg $2 string Scope, either `loaded`, `all`, or an explicit module list
# @set The named array, to module names in registry or load order
# @exitcode 1 Stop the script when an explicitly named module is unknown
# @internal
#######################################
function __dybatpho_doctor_scope {
  local -n __scope_out="$1"
  local scope="$2"
  local names
  # shellcheck disable=SC2154 # the module lists are declared by `init.sh`
  case "${scope}" in
    loaded) names="${DYBATPHO_LOADED_MODULES}" ;;
    all) names="${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES}" ;;
    *) names="${scope//,/ }" ;;
  esac
  __scope_out=()
  local module
  for module in ${names}; do
    __dybatpho_module_exists "${module}" \
      || dybatpho::die "dybatpho::doctor: Unknown module '${module}'"
    __scope_out+=("${module}")
  done
}

#######################################
# @description Walk the module dependency graph a report covers.
#   The report follows the same registry edges the loader does, ordered by
#   `dybatpho::array_toposort`, rather than taking them on trust. An edge that
#   names a module the registry does not know stops every script loading the
#   module that declares it, so it is a failure. A cycle is only noted: the
#   loader allows one on purpose, since calls between modules resolve at run
#   time.
#
#   Widening a list matters for an explicit `--modules`. A script asking for
#   `forge` also loads `json`, and a check on `forge` alone would leave the
#   `yq` that `json` needs for the script to discover halfway through.
# @arg $1 string Name of the array holding the modules; widened in place with `expand`
# @arg $2 string Name of the array receiving `module -> dependency` for each unknown edge
# @arg $3 string Name of the variable set to 1 when the graph holds a cycle, else 0
# @arg $4 string `expand` to replace the modules by everything they reach, in
#   load order, with every dependency ahead of the module that needs it
# @set The named arrays and flag
# @internal
#######################################
function __dybatpho_doctor_graph {
  local -n __graph_modules="$1"
  local -n __graph_unknown="$2"
  local -n __graph_cycle="$3"
  local expand="${4-}"
  __graph_unknown=()
  __graph_cycle=0
  # Without roots `dybatpho::array_toposort` orders the whole graph, which is
  # not what an empty scope asked about.
  ((${#__graph_modules[@]})) || return 0

  # `dybatpho::array_toposort` refuses a name under the library's own prefix,
  # so the edges are copied into a local first.
  local -A module_edges=()
  local module
  # shellcheck disable=SC2154 # the dependency map is declared by `init.sh`
  for module in ${__dybatpho_module_deps[@]+"${!__dybatpho_module_deps[@]}"}; do
    module_edges["${module}"]="${__dybatpho_module_deps[${module}]}"
  done

  local -a order=()
  dybatpho::array_toposort module_edges order "${__graph_modules[@]}" \
    || __graph_cycle=1

  # The order also holds every name an edge points at, so an unknown one is
  # dropped from the modules and reported against the module that named it.
  local -a known=()
  for module in ${order[@]+"${order[@]}"}; do
    if __dybatpho_module_exists "${module}"; then
      known+=("${module}")
    fi
  done
  local dep
  for module in ${known[@]+"${known[@]}"}; do
    for dep in ${module_edges[${module}]-}; do
      __dybatpho_module_exists "${dep}" \
        || __graph_unknown+=("${module} -> ${dep}")
    done
  done

  if [[ "${expand}" == "expand" ]]; then
    __graph_modules=(${known[@]+"${known[@]}"})
  fi
}

#######################################
# @description Collect every dependency row a scope produces.
#   A row is `module<TAB>spec<TAB>kind<TAB>status<TAB>path<TAB>version`, which
#   keeps the text and JSON renderers reading the same data.
# @arg $1 string Name of the array variable that receives the rows
# @arg $@ string Module names to inspect
# @set The named array, to one row per dependency
# @internal
#######################################
function __dybatpho_doctor_rows {
  local -n __rows_out="$1"
  shift
  __rows_out=()
  local module kind specs spec status path version resolved
  for module in "$@"; do
    for kind in required optional; do
      case "${kind}" in
        required) specs="${DYBATPHO_DOCTOR_REQUIRED[${module}]-}" ;;
        optional) specs="${DYBATPHO_DOCTOR_OPTIONAL[${module}]-}" ;;
        *) ;;
      esac
      for spec in ${specs}; do
        # The exit code only repeats what the status says, and a non-zero one
        # would end the report under `errexit`.
        resolved="$(__dybatpho_doctor_resolve "${spec}" || true)"
        IFS=$'\t' read -r status path version <<< "${resolved}"
        __rows_out+=("${module}"$'\t'"${spec}"$'\t'"${kind}"$'\t'"${status}"$'\t'"${path}"$'\t'"${version}")
      done
    done
  done
}

#######################################
# @description Print the report as aligned text.
# @arg $1 string Name of the array variable holding the rows
# @arg $2 string Name of the array variable holding the unknown module edges
# @arg $3 number 1 when the module graph holds a cycle, else 0
# @arg $@ string Module names covered by the report
# @stdout The environment summary, the dependency table, and a closing summary
# @internal
#######################################
function __dybatpho_doctor_report_text {
  local -n __rows_in="$1"
  local -n __unknown_in="$2"
  local cycle="$3"
  shift 3
  local bash_status="ok"
  dybatpho::doctor_bash_supported || bash_status="unsupported"
  local version
  version=$(dybatpho::version)
  printf 'dybatpho %s (%s)\n' "${version}" "${DYBATPHO_DIR}"
  printf 'bash     %s [%s, minimum %s]\n' \
    "${BASH_VERSION}" "${bash_status}" "${DYBATPHO_BASH_MINIMUM}"
  local system machine
  system=$(uname -s)
  machine=$(uname -m)
  printf 'platform %s/%s\n' "${system}" "${machine}"
  printf 'modules  %s\n' "$*"
  local graph=""
  if ((${#__unknown_in[@]})); then
    graph="unknown dependency"
  fi
  if ((cycle)); then
    graph="${graph:+${graph}, }cycle (allowed, calls between modules resolve at run time)"
  fi
  printf 'graph    %s\n' "${graph:-ok}"

  if ((${#__rows_in[@]} == 0)); then
    printf '\nNo external dependency is needed by these modules.\n'
    return 0
  fi

  # Width of the two variable columns, so the table stays readable whatever the
  # module and command names are.
  local module_width=6 spec_width=10 row module spec
  for row in "${__rows_in[@]}"; do
    IFS=$'\t' read -r module spec _ _ _ _ <<< "${row}"
    ((${#module} <= module_width)) || module_width=${#module}
    ((${#spec} <= spec_width)) || spec_width=${#spec}
  done

  local kind status path version detail
  printf '\n%-*s  %-*s  %-8s  %s\n' \
    "${module_width}" "MODULE" "${spec_width}" "DEPENDENCY" "KIND" "STATUS"
  for row in "${__rows_in[@]}"; do
    IFS=$'\t' read -r module spec kind status path version <<< "${row}"
    # The version comes first in the parenthesis because it is what the reader
    # is checking when a spec carries a constraint; the path answers "which one
    # did you find", which only matters once there is any doubt.
    detail="${version}"
    detail="${detail}${detail:+${path:+, }}${path}"
    printf '%-*s  %-*s  %-8s  %s\n' \
      "${module_width}" "${module}" "${spec_width}" "${spec}" "${kind}" \
      "${status}${detail:+ (${detail})}"
  done
}

#######################################
# @description Print the report as a single JSON object.
#   Strings go through the core logging escaper rather than `jq`, because a
#   diagnostic that needs a tool the user may be missing is of no use; that
#   escaper spells every control character, so a path or version holding one
#   still yields valid JSON.
# @arg $1 string Name of the array variable holding the rows
# @arg $2 string Name of the array variable holding the unknown module edges
# @arg $3 number 1 when the module graph holds a cycle, else 0
# @arg $@ string Module names covered by the report
# @stdout One JSON object describing the environment and every dependency
# @internal
#######################################
function __dybatpho_doctor_report_json {
  local -n __rows_in="$1"
  local -n __unknown_in="$2"
  local cycle="$3"
  shift 3
  local bash_ok="false"
  dybatpho::doctor_bash_supported && bash_ok="true"
  local version
  version=$(dybatpho::version)
  local version_json directory_json bash_json system_json machine_json
  __dybatpho_log_json_escape_into version_json "${version}"
  __dybatpho_log_json_escape_into directory_json "${DYBATPHO_DIR}"
  __dybatpho_log_json_escape_into bash_json "${BASH_VERSION}"
  local system machine
  system=$(uname -s)
  machine=$(uname -m)
  __dybatpho_log_json_escape_into system_json "${system}"
  __dybatpho_log_json_escape_into machine_json "${machine}"
  printf '{"version":"%s"' "${version_json}"
  printf ',"directory":"%s"' "${directory_json}"
  printf ',"bash":{"version":"%s","minimum":"%s","ok":%s}' \
    "${bash_json}" "${DYBATPHO_BASH_MINIMUM}" "${bash_ok}"
  printf ',"platform":{"system":"%s","machine":"%s"}' \
    "${system_json}" "${machine_json}"
  local module module_json first=1
  printf ',"modules":['
  for module in "$@"; do
    ((first)) || printf ','
    first=0
    __dybatpho_log_json_escape_into module_json "${module}"
    printf '"%s"' "${module_json}"
  done
  printf ']'
  local cycle_json="false" edge edge_json
  ((cycle == 0)) || cycle_json="true"
  printf ',"graph":{"cycle":%s,"unknown":[' "${cycle_json}"
  first=1
  for edge in ${__unknown_in[@]+"${__unknown_in[@]}"}; do
    ((first)) || printf ','
    first=0
    __dybatpho_log_json_escape_into edge_json "${edge}"
    printf '"%s"' "${edge_json}"
  done
  printf ']}'
  local row spec kind status path version spec_json path_json
  first=1
  printf ',"dependencies":['
  for row in "${__rows_in[@]}"; do
    IFS=$'\t' read -r module spec kind status path version <<< "${row}"
    ((first)) || printf ','
    first=0
    __dybatpho_log_json_escape_into module_json "${module}"
    __dybatpho_log_json_escape_into spec_json "${spec}"
    __dybatpho_log_json_escape_into path_json "${path}"
    __dybatpho_log_json_escape_into version_json "${version}"
    printf '{"module":"%s","dependency":"%s","kind":"%s","status":"%s","path":"%s","version":"%s"}' \
      "${module_json}" "${spec_json}" "${kind}" "${status}" \
      "${path_json}" "${version_json}"
  done
  printf ']'
}

#######################################
# @description Report the environment the loaded modules need, and what is missing.
# @example
#   dybatpho::doctor              # the modules this shell loaded
#   dybatpho::doctor --all        # every module in the registry
#   dybatpho::doctor --modules "json git" --json
#
# @arg $@ string Options: `--all`, `--modules <list>`, `--json`, `--quiet`
# @stdout The report, as aligned text or as one JSON object with `--json`
# @exitcode 0 Every required dependency is installed and Bash is supported
# @exitcode 1 A required dependency is missing, Bash is too old, or an option is invalid
#######################################
function dybatpho::doctor {
  local scope="loaded" format="text" quiet="false"
  while (($#)); do
    case "$1" in
      --all) scope="all" ;;
      --modules)
        [[ -n "${2-}" ]] || dybatpho::die "${FUNCNAME[0]}: --modules expects a module list"
        scope="$2"
        shift
        ;;
      --json) format="json" ;;
      --quiet) quiet="true" ;;
      *) dybatpho::die "${FUNCNAME[0]}: Unknown option '$1'" ;;
    esac
    shift
  done

  local -a modules=()
  __dybatpho_doctor_scope modules "${scope}"
  # The loaded set already holds every dependency, and `--all` the whole
  # registry, so only an explicit list has anything to widen.
  local expand="expand"
  case "${scope}" in
    loaded | all) expand="" ;;
    *) ;;
  esac
  local -a graph_unknown=()
  local graph_cycle=0
  __dybatpho_doctor_graph modules graph_unknown graph_cycle "${expand}"
  local -a rows=()
  __dybatpho_doctor_rows rows ${modules[@]+"${modules[@]}"}

  # Collect what is missing before printing, so the text summary and the exit
  # code describe the same run.
  local row spec kind status version
  local -a missing_required=() missing_optional=() unknown=()
  local -a outdated_required=() outdated_optional=()
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r _ spec kind status _ version <<< "${row}"
    case "${status}" in
      missing)
        if [[ "${kind}" == "required" ]]; then
          missing_required+=("${spec}")
        else
          missing_optional+=("${spec}")
        fi
        ;;
      outdated)
        if [[ "${kind}" == "required" ]]; then
          outdated_required+=("${spec} (found ${version})")
        else
          outdated_optional+=("${spec} (found ${version})")
        fi
        ;;
      unknown) unknown+=("${spec}") ;;
      *) ;;
    esac
  done

  local healthy=0
  ((${#missing_required[@]} == 0)) || healthy=1
  # A required tool that is installed but too old fails the report for the same
  # reason a missing one does: the module that declared the constraint will not
  # work. An optional one does not, matching how an optional missing tool is
  # treated. A version that could not be read fails nothing at all, because "I
  # could not tell" is not the same claim as "it is wrong".
  ((${#outdated_required[@]} == 0)) || healthy=1
  dybatpho::doctor_bash_supported || healthy=1
  # A dependency the registry cannot resolve makes the loader stop, so the
  # module declaring it fails before any external command comes into play.
  ((${#graph_unknown[@]} == 0)) || healthy=1

  if [[ "${quiet}" == "true" ]]; then
    return "${healthy}"
  fi

  if [[ "${format}" == "json" ]]; then
    local ok="true"
    ((healthy == 0)) || ok="false"
    __dybatpho_doctor_report_json rows graph_unknown "${graph_cycle}" \
      ${modules[@]+"${modules[@]}"}
    printf ',"ok":%s}\n' "${ok}"
    return "${healthy}"
  fi

  __dybatpho_doctor_report_text rows graph_unknown "${graph_cycle}" \
    ${modules[@]+"${modules[@]}"}
  printf '\n'
  if ((${#missing_optional[@]} > 0)); then
    printf 'Optional, some functions are unavailable: %s\n' "${missing_optional[*]}"
  fi
  if ((${#outdated_optional[@]} > 0)); then
    printf 'Optional, too old: %s\n' "${outdated_optional[*]}"
  fi
  if ((${#unknown[@]} > 0)); then
    printf 'Installed, version could not be read: %s\n' "${unknown[*]}"
  fi
  if ((${#missing_required[@]} > 0)); then
    printf 'Missing required: %s\n' "${missing_required[*]}"
  fi
  if ((${#outdated_required[@]} > 0)); then
    printf 'Required, too old: %s\n' "${outdated_required[*]}"
  fi
  local edge
  for edge in ${graph_unknown[@]+"${graph_unknown[@]}"}; do
    printf 'Unknown module dependency: %s\n' "${edge}"
  done
  dybatpho::doctor_bash_supported \
    || printf 'Bash %s is older than the supported minimum %s\n' \
      "${BASH_VERSION}" "${DYBATPHO_BASH_MINIMUM}"
  ((healthy)) || printf 'No required dependency is missing.\n'
  return "${healthy}"
}
