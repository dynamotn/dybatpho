# shellcheck shell=bash
# This file keeps its declarations with the functions they describe.
# dyshellint disable=BSG033
# @file semver.sh
# @brief Utilities for working with Semantic Versioning (semver)
# @namespace dybatpho
# @description
#   This module contains helpers for parsing, validating, comparing semver strings,
#   and detecting the release type of a version bump.
#
#   Follows [Semantic Versioning 2.0.0](https://semver.org/) spec.
#   A leading `v` prefix (e.g. `v1.2.3`) is accepted and stripped automatically.
# @see
#   - https://semver.org/
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# Regex for a valid semver string (with optional leading v)
# Groups: 1=major 2=minor 3=patch 4=pre-release 5=build-metadata
export DYBATPHO_SEMVER_REGEX='^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-([a-zA-Z0-9._-]+))?(\+([a-zA-Z0-9._-]+))?$'

#######################################
# @description Return success when the string is a valid semver (with optional leading v).
# @arg $1 string Version string to validate
# @exitcode 0 Valid semver
# @exitcode 1 Invalid semver
#######################################
function dybatpho::semver_valid {
  local version
  dybatpho::expect_args version -- "$@"
  [[ "${version}" =~ ${DYBATPHO_SEMVER_REGEX} ]]
}

#######################################
# @description Parse a semver string and print its components, one per line.
# @arg $1 string Version string to parse
# @stdout Five lines: major, minor, patch, pre-release (empty if none), build-metadata (empty if none)
# @exitcode 0 Parsing succeeded
# @exitcode 1 The string is not a valid semver
#######################################
function dybatpho::semver_parse {
  local version
  dybatpho::expect_args version -- "$@"
  if ! [[ "${version}" =~ ${DYBATPHO_SEMVER_REGEX} ]]; then
    dybatpho::die "semver_parse: '${version}' is not a valid semver string" # kcov(skip)
  fi
  printf '%s\n' "${BASH_REMATCH[1]}" # major
  printf '%s\n' "${BASH_REMATCH[2]}" # minor
  printf '%s\n' "${BASH_REMATCH[3]}" # patch
  printf '%s\n' "${BASH_REMATCH[5]}" # pre-release (group 5; group 4 includes the leading -)
  printf '%s\n' "${BASH_REMATCH[7]}" # build-metadata (group 7; group 6 includes the leading +)
}

#######################################
# @description Compare two semver strings according to semver 2.0.0 precedence rules.
# @arg $1 string First version
# @arg $2 string Second version
# @stdout -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
# @exitcode 0 Always succeeds (comparison result is on stdout)
# @note Build metadata is ignored for comparison (per semver spec).
#######################################
function dybatpho::semver_compare {
  local v1 v2
  dybatpho::expect_args v1 v2 -- "$@"

  dybatpho::semver_valid "${v1}" || dybatpho::die "semver_compare: '${v1}' is not a valid semver"
  dybatpho::semver_valid "${v2}" || dybatpho::die "semver_compare: '${v2}' is not a valid semver"

  local -a parts1 parts2
  mapfile -t parts1 < <(dybatpho::semver_parse "${v1}")
  mapfile -t parts2 < <(dybatpho::semver_parse "${v2}")

  local major1="${parts1[0]}" minor1="${parts1[1]}" patch1="${parts1[2]}" pre1="${parts1[3]}"
  local major2="${parts2[0]}" minor2="${parts2[1]}" patch2="${parts2[2]}" pre2="${parts2[3]}"

  # Compare numeric core: major.minor.patch
  local -a numeric_fields=("${major1}:${major2}" "${minor1}:${minor2}" "${patch1}:${patch2}")
  local field
  for field in "${numeric_fields[@]}"; do
    local a="${field%%:*}" b="${field##*:}"
    if ((10#${a} > 10#${b})); then
      printf '1\n'
      return 0
    elif ((10#${a} < 10#${b})); then
      printf -- '-1\n'
      return 0
    fi
  done

  # Numeric cores are equal — compare pre-release
  # A version with a pre-release has lower precedence than one without
  if [[ -z "${pre1}" && -z "${pre2}" ]]; then
    printf '0\n'
    return 0
  elif [[ -n "${pre1}" && -z "${pre2}" ]]; then
    printf -- '-1\n'
    return 0
  elif [[ -z "${pre1}" && -n "${pre2}" ]]; then
    printf '1\n'
    return 0
  fi

  # Both have pre-release — compare identifier by identifier
  local -a ids1 ids2
  IFS='.' read -r -a ids1 <<< "${pre1}"
  IFS='.' read -r -a ids2 <<< "${pre2}"

  local max_len="${#ids1[@]}"
  ((${#ids2[@]} > max_len)) && max_len="${#ids2[@]}"

  local i
  for ((i = 0; i < max_len; i++)); do
    local id1="${ids1[i]-}" id2="${ids2[i]-}"

    # A shorter pre-release has lower precedence
    if [[ -z "${id1}" && -n "${id2}" ]]; then
      printf -- '-1\n'
      return 0
    elif [[ -n "${id1}" && -z "${id2}" ]]; then
      printf '1\n'
      return 0
    fi

    local is_num1=false is_num2=false
    [[ "${id1}" =~ ^[0-9]+$ ]] && is_num1=true
    [[ "${id2}" =~ ^[0-9]+$ ]] && is_num2=true

    if [[ "${is_num1}" == true && "${is_num2}" == true ]]; then
      if ((10#${id1} > 10#${id2})); then
        printf '1\n'
        return 0
      elif ((10#${id1} < 10#${id2})); then
        printf -- '-1\n'
        return 0
      fi
    elif [[ "${is_num1}" == true && "${is_num2}" == false ]]; then
      # Numeric identifiers have lower precedence than alphanumeric
      printf -- '-1\n'
      return 0
    elif [[ "${is_num1}" == false && "${is_num2}" == true ]]; then
      printf '1\n'
      return 0
    else
      # Both alphanumeric — lexicographic comparison
      if [[ "${id1}" > "${id2}" ]]; then
        printf '1\n'
        return 0
      elif [[ "${id1}" < "${id2}" ]]; then
        printf -- '-1\n'
        return 0
      fi
    fi
  done

  printf '0\n'
}

#######################################
# @description Bump a semver version by the specified part.
# @arg $1 string Version string to bump
# @arg $2 string Part to bump: major | minor | patch
# @arg $3 string Optional pre-release label to attach (e.g. "alpha.1")
# @arg $4 string Optional build-metadata to attach (e.g. "build.42")
# @stdout Bumped version string (no leading v, no pre-release/build unless supplied)
# @exitcode 0 Always succeeds
# @exitcode 1 The version is invalid or the part is not one of major/minor/patch
# @note Bumping major resets minor and patch to 0.
#       Bumping minor resets patch to 0.
#       Pre-release and build-metadata from the source version are always dropped;
#       pass $3/$4 to attach new ones to the result.
#######################################
function dybatpho::semver_bump {
  local version part
  dybatpho::expect_args version part -- "$@"
  local new_pre="${3-}"
  local new_build="${4-}"

  dybatpho::semver_valid "${version}" || dybatpho::die "semver_bump: '${version}' is not a valid semver"

  local -a parts
  mapfile -t parts < <(dybatpho::semver_parse "${version}")
  local major="${parts[0]}" minor="${parts[1]}" patch="${parts[2]}"

  case "${part}" in
    major)
      major=$((10#${major} + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((10#${minor} + 1))
      patch=0
      ;;
    patch)
      patch=$((10#${patch} + 1))
      ;;
    *)
      dybatpho::die "semver_bump: unknown part '${part}'. Must be one of: major, minor, patch"
      ;;
  esac

  local result="${major}.${minor}.${patch}"
  [[ -n "${new_pre}" ]] && result="${result}-${new_pre}"
  [[ -n "${new_build}" ]] && result="${result}+${new_build}"
  printf '%s\n' "${result}"
}

#######################################
# @description Detect the release type between two semver versions.
# @arg $1 string Old (base) version
# @arg $2 string New (next) version
# @stdout One of: major, minor, patch, pre-release, build, equal
#         - major       — major number increased
#         - minor       — minor number increased (major unchanged)
#         - patch       — patch number increased (major & minor unchanged)
#         - pre-release — numeric core is the same, pre-release label changed or added
#         - build       — everything else is the same, only build-metadata differs
#         - equal       — versions are identical (ignoring build-metadata per semver spec;
#                         use `build` when build-metadata differs but all else is equal)
# @exitcode 0 Always succeeds
# @exitcode 1 Either argument is not a valid semver
#######################################
function dybatpho::semver_release_type {
  local old_ver new_ver
  dybatpho::expect_args old_ver new_ver -- "$@"

  dybatpho::semver_valid "${old_ver}" || dybatpho::die "semver_release_type: '${old_ver}' is not valid"
  dybatpho::semver_valid "${new_ver}" || dybatpho::die "semver_release_type: '${new_ver}' is not valid"

  local -a old_parts new_parts
  mapfile -t old_parts < <(dybatpho::semver_parse "${old_ver}")
  mapfile -t new_parts < <(dybatpho::semver_parse "${new_ver}")

  local old_major="${old_parts[0]}" old_minor="${old_parts[1]}" old_patch="${old_parts[2]}"
  local old_pre="${old_parts[3]}" old_build="${old_parts[4]}"
  local new_major="${new_parts[0]}" new_minor="${new_parts[1]}" new_patch="${new_parts[2]}"
  local new_pre="${new_parts[3]}" new_build="${new_parts[4]}"

  if ((10#${new_major} != 10#${old_major})); then
    printf 'major\n'
  elif ((10#${new_minor} != 10#${old_minor})); then
    printf 'minor\n'
  elif ((10#${new_patch} != 10#${old_patch})); then
    printf 'patch\n'
  elif [[ "${new_pre}" != "${old_pre}" ]]; then
    printf 'pre-release\n'
  elif [[ "${new_build}" != "${old_build}" ]]; then
    printf 'build\n'
  else
    printf 'equal\n'
  fi
}

#######################################
# @description Fill a partial version out to `major.minor.patch`.
#   A range may name only part of a version, and `1.2` has to become `1.2.0`
#   before it can be compared against anything.
# @arg $1 string Partial version such as `1`, `1.2`, or `1.2.3`
# @stdout The version with its missing parts set to zero
# @internal
#######################################
function __dybatpho_semver_fill {
  local version major minor patch
  dybatpho::expect_args version -- "$@"
  IFS='.' read -r major minor patch <<< "${version}"
  printf '%s.%s.%s\n' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

#######################################
# @description Print how many parts of a version a range actually named.
#   `^1` and `^1.0.0` bound different ranges, so the caret and tilde rules need
#   to know which parts were written down.
# @arg $1 string Version or partial version
# @stdout `1`, `2`, or `3`
# @internal
#######################################
function __dybatpho_semver_specificity {
  local version core
  dybatpho::expect_args version -- "$@"
  core="${version%%[-+]*}"
  case "${core}" in
    *.*.*) printf '3\n' ;;
    *.*) printf '2\n' ;;
    *) printf '1\n' ;;
  esac
}

#######################################
# @description Expand one range comparator into plain `<operator> <version>` bounds.
#   Every shorthand a range may use — a caret, a tilde, a wildcard, a partial
#   version — turns into one or two simple comparisons here, so that the
#   matching itself only ever compares two complete versions.
#   The bounds are appended to a caller-supplied array rather than printed: a
#   command substitution would validate inside a subshell, where a rejected
#   comparator could not stop the caller from reporting a match.
# @arg $1 string Name of the array the bounds are appended to
# @arg $2 string A single comparator such as `^1.2`, `>=1.0.0`, or `1.2.x`
# @set The named array, with one `<operator> <version>` entry per bound
# @exitcode 1 The comparator cannot be understood
# @internal
#######################################
function __dybatpho_semver_expand {
  local -n __bounds_out="$1"
  shift
  local token operator core filled major minor patch parts
  dybatpho::expect_args token -- "$@"

  # A wildcard accepts anything, which is the same as having no lower bound.
  case "${token}" in
    '' | '*' | 'x' | 'X' | '*.*' | 'x.x' | 'X.X')
      __bounds_out+=(">= 0.0.0")
      return 0
      ;;
    *) ;;
  esac

  # Trailing wildcards say "any value here", which is exactly what leaving the
  # part off means, so they are stripped down to a partial version.
  token="${token%.[xX*]}"
  token="${token%.[xX*]}"

  operator=""
  case "${token}" in
    '>='* | '<='*)
      operator="${token:0:2}"
      core="${token:2}"
      ;;
    '>'* | '<'* | '='* | '^'* | '~'*)
      operator="${token:0:1}"
      core="${token:1}"
      ;;
    *) core="${token}" ;;
  esac
  core="${core# }"
  core="${core#v}"
  [[ -n "${core}" ]] || {
    __bounds_out+=(">= 0.0.0")
    return 0
  }

  parts="$(__dybatpho_semver_specificity "${core}")"
  filled="$(__dybatpho_semver_fill "${core}")"
  # The caller is named rather than indexed: this runs inside a command
  # substitution, where the call stack is one frame shorter than it looks.
  dybatpho::semver_valid "${filled}" \
    || dybatpho::die "${FUNCNAME[1]-${FUNCNAME[0]}}: Not a usable version in range: '${token}'"
  IFS='.' read -r major minor patch <<< "${filled%%[-+]*}"

  case "${operator}" in
    '>' | '>=' | '<' | '<=')
      __bounds_out+=("${operator} ${filled}")
      ;;
    '=')
      __bounds_out+=("= ${filled}")
      ;;
    '^')
      # A caret allows changes that do not alter the leftmost non-zero part,
      # which is what "compatible" means once a project is below 1.0.
      __bounds_out+=(">= ${filled}")
      if ((major > 0)) || ((parts == 1)); then
        __bounds_out+=("< $((major + 1)).0.0")
      elif ((minor > 0)) || ((parts == 2)); then
        __bounds_out+=("< ${major}.$((minor + 1)).0")
      else
        __bounds_out+=("< ${major}.${minor}.$((patch + 1))")
      fi
      ;;
    '~')
      __bounds_out+=(">= ${filled}")
      if ((parts == 1)); then
        __bounds_out+=("< $((major + 1)).0.0")
      else
        __bounds_out+=("< ${major}.$((minor + 1)).0")
      fi
      ;;
    *)
      # A bare version is exact only when it is complete; a partial one covers
      # everything it leaves unsaid.
      if ((parts == 3)); then
        __bounds_out+=("= ${filled}")
      elif ((parts == 2)); then
        __bounds_out+=(">= ${filled}")
        __bounds_out+=("< ${major}.$((minor + 1)).0")
      else
        __bounds_out+=(">= ${filled}")
        __bounds_out+=("< $((major + 1)).0.0")
      fi
      ;;
  esac
}

#######################################
# @description Return success when a version satisfies one comparison.
# @arg $1 string Version to test
# @arg $2 string Operator, one of `=`, `>`, `>=`, `<`, or `<=`
# @arg $3 string Version to compare against
# @exitcode 0 The comparison holds
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_semver_holds {
  local version operator bound result
  dybatpho::expect_args version operator bound -- "$@"
  result="$(dybatpho::semver_compare "${version}" "${bound}")"
  case "${operator}" in
    '=') ((result == 0)) ;;
    '>') ((result > 0)) ;;
    '>=') ((result >= 0)) ;;
    '<') ((result < 0)) ;;
    '<=') ((result <= 0)) ;;
    *) return 1 ;; # kcov(skip)
  esac
}

#######################################
# @description Return success when a version satisfies a range.
#   Ranges are written the way npm and Cargo write them: `^1.2.3` for anything
#   compatible, `~1.2.3` for patch updates, plain comparisons such as `>=1.2.0`,
#   partial versions and wildcards such as `1.2.x`, several comparators
#   separated by spaces meaning all of them, and `||` meaning either.
# @example
#   dybatpho::semver_satisfies "1.4.2" "^1.2"        # yes
#   dybatpho::semver_satisfies "2.0.0" "^1.2"        # no
#   dybatpho::semver_satisfies "1.2.9" "~1.2.3"      # yes
#   dybatpho::semver_satisfies "1.5.0" ">=1.2 <1.9"  # yes
#   dybatpho::semver_satisfies "3.1.0" "^1.0 || ^3.0"
#
# @example
#   dybatpho::semver_satisfies "$(jq -r .version package.json)" ">=18" \
#     || dybatpho::die "Node 18 or newer is required"
#
# @arg $1 string Version to test
# @arg $2 string Range expression
# @exitcode 0 The version satisfies the range
# @exitcode 1 It does not
# @tip A pre-release only satisfies a range that names a pre-release of the same
#   `major.minor.patch`, so `^1.0.0` does not quietly accept `2.0.0-alpha`
#######################################
function dybatpho::semver_satisfies {
  local version range alternative token bound operator
  dybatpho::expect_args version range -- "$@"
  version="${version#v}"
  dybatpho::semver_valid "${version}" \
    || dybatpho::die "${FUNCNAME[0]}: Not a valid version: '${version}'"

  local prerelease
  local semver_parse
  local semver_parse_2
  local semver_parse_3
  local semver_fields
  semver_fields=$(dybatpho::semver_parse "${version}")
  semver_parse_3=$(printf '%s\n' "${semver_fields}" | sed -n '4p')
  semver_parse_2=${semver_parse_3}
  semver_parse=${semver_parse_2}
  prerelease="${semver_parse}"
  local core="${version%%[-+]*}"

  # `||` separates alternatives; satisfying any one of them is enough.
  local -a alternatives=()
  local rest="${range}"
  while [[ "${rest}" == *"||"* ]]; do
    alternatives+=("${rest%%||*}")
    rest="${rest#*||}"
  done
  alternatives+=("${rest}")

  for alternative in "${alternatives[@]}"; do
    local satisfied=true
    local prerelease_allowed=true
    if [[ -n "${prerelease}" ]]; then
      # A pre-release is only in scope when the range asked for one on the very
      # same release, which keeps it out of ranges that never mentioned it.
      prerelease_allowed=false
    fi

    # Whitespace separates comparators that must all hold.
    local -a tokens=()
    read -r -a tokens <<< "${alternative}"
    ((${#tokens[@]})) || tokens=("*")

    for token in "${tokens[@]}"; do
      if [[ -n "${prerelease}" && "${token}" == *-* ]]; then
        local token_core="${token#[<>=^~]}"
        token_core="${token_core#[=]}"
        token_core="${token_core#v}"
        [[ "${token_core%%[-+]*}" == "${core}" ]] && prerelease_allowed=true
      fi
      local -a bounds=()
      __dybatpho_semver_expand bounds "${token}"
      local entry
      for entry in ${bounds[@]+"${bounds[@]}"}; do
        read -r operator bound <<< "${entry}"
        __dybatpho_semver_holds "${version}" "${operator}" "${bound}" || satisfied=false
      done
    done

    [[ "${satisfied}" == true && "${prerelease_allowed}" == true ]] && return 0
  done
  return 1
}

#######################################
# @description Print versions in order, lowest first.
#   Ordering follows the specification rather than string order, so `1.10.0`
#   comes after `1.9.0` and a pre-release comes before the release it precedes.
# @example
#   dybatpho::semver_sort 1.10.0 1.9.0 2.0.0-rc.1 2.0.0
#   git tag --list 'v*' | dybatpho::semver_sort
#
# @arg $@ string Versions to sort, or none to read them from standard input
# @stdin One version per line, when no argument is given
# @stdout The versions, one per line, lowest first
# @exitcode 1 One of the inputs is not a valid version
# @tip A leading `v` is accepted and preserved, so a list of tags sorts as it is
#######################################
function dybatpho::semver_sort {
  local -a versions=()
  if (($#)); then
    versions=("$@")
  else
    local line
    while IFS= read -r line; do
      [[ -n "${line}" ]] && versions+=("${line}")
    done
  fi
  ((${#versions[@]})) || return 0

  local version
  for version in "${versions[@]}"; do
    dybatpho::semver_valid "${version#v}" \
      || dybatpho::die "${FUNCNAME[0]}: Not a valid version: '${version}'"
  done

  # An insertion sort keeps the comparison in `dybatpho::semver_compare`, which
  # already knows the specification's ordering rules, rather than reimplementing
  # them for `sort`.
  local index position candidate
  for ((index = 1; index < ${#versions[@]}; index++)); do
    candidate="${versions[index]}"
    position=$((index - 1))
    while ((position >= 0)) \
      && (($(dybatpho::semver_compare "${versions[position]#v}" "${candidate#v}") > 0)); do
      versions[position + 1]="${versions[position]}"
      position=$((position - 1))
    done
    versions[position + 1]="${candidate}"
  done
  printf '%s\n' "${versions[@]}"
}

#######################################
# @description Print the highest of a list of versions.
# @example
#   latest="$(dybatpho::semver_max 1.10.0 1.9.0 2.0.0-rc.1)"
#   latest="$(git tag --list 'v*' | dybatpho::semver_max)"
#
# @arg $@ string Versions to compare, or none to read them from standard input
# @stdin One version per line, when no argument is given
# @stdout The highest version, as it was written
# @exitcode 1 No version was given, or one of them is not valid
#######################################
function dybatpho::semver_max {
  local sorted
  sorted="$(dybatpho::semver_sort "$@")"
  [[ -n "${sorted}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected at least one version"
  printf '%s\n' "${sorted}" | tail -n 1
}

# Words that open a real pre-release tail, as opposed to the build and
# packaging markers that sit in the same place. Matched against a lower-cased
# tail, and only where the word ends the tail or is followed by a separator, so
# that `modified` is not read as the `m` of a milestone.
__DYBATPHO_SEMVER_PRERELEASE_REGEX='^(alpha|beta|rc|pre|preview|dev|snapshot|nightly|canary|next)([.0-9-]|$)'

#######################################
# @description Normalize a version, as a real command reports it, into a semver
#   string the rest of this module accepts.
#   `dybatpho::semver_satisfies` insists on a complete version, and this is what
#   turns what a command actually printed into one.
#   `dybatpho::semver_compare` only looks at `major.minor.patch`, and almost
#   nothing in the wild says its version that way: `tar` answers `1.35`, `yq`
#   answers `v4.53.3` buried in a sentence, and `unzip` answers `6.00`. This
#   fills the missing fields with zero, drops a leading `v`, and strips the
#   leading zeros semver forbids.
#
#   A version with more than three fields, as several Windows tools report, is
#   cut down to the first three.
#
#   A trailing `-something` is only kept as a pre-release when it opens with a
#   word that names one. Distributions patch tools and say so in that same
#   place: this host's `grep` answers `3.12-modified`, and Debian builds answer
#   things like `1.2.3-1ubuntu2`. Read as semver, those rank *below* the plain
#   release, so `>=3.12` would reject the very grep that satisfies it. A build
#   marker is dropped; `1.7.1-rc1` keeps its pre-release and still ranks below
#   `1.7.1`, which is what a pre-release is supposed to do.
# @example
#   dybatpho::semver_coerce 1.35                   # 1.35.0
#   dybatpho::semver_coerce "git version 2.43.0"   # 2.43.0
#   dybatpho::semver_coerce v4                     # 4.0.0
#
# @arg $1 string A version, or any text with one in it
# @stdout The version as `major.minor.patch`, with the pre-release kept
# @exitcode 0 A version was found
# @exitcode 1 Stop the script when the text holds no version
# @see
#   - `dybatpho::command_version`
#######################################
function dybatpho::semver_coerce {
  local text
  dybatpho::expect_args text -- "$@"
  local core="" pre=""
  # shellcheck disable=SC2154 # declared by `src/os.sh`
  if [[ "${text}" =~ ${DYBATPHO_VERSION_SCAN_REGEX} ]]; then
    core="${BASH_REMATCH[1]}"
    pre="${BASH_REMATCH[4]-}"
    # Keep the tail only when it announces a pre-release. Anything else in that
    # position is a build or packaging marker, and dropping it is the safe way
    # to be wrong: an unrecognised marker makes the version count as the
    # release it was built from, rather than as something older.
    [[ "${pre,,}" =~ ${__DYBATPHO_SEMVER_PRERELEASE_REGEX} ]] || pre=""
  elif [[ "${text}" =~ ^[[:space:]]*v?([0-9]+)[[:space:]]*$ ]]; then
    # A lone number is how a constraint names a major release: `yq>=4`. The
    # scan pattern rejects it on purpose, so that a stray number inside a
    # sentence is never mistaken for a version.
    core="${BASH_REMATCH[1]}"
  else
    dybatpho::die "${FUNCNAME[0]}: No version found in '${text}'"
  fi

  local -a fields
  IFS='.' read -r -a fields <<< "${core}"
  local result
  # `10#` is what strips the leading zeros: `unzip` answers `6.00`, and `06`
  # is not a valid semver field.
  printf -v result '%d.%d.%d' \
    "$((10#${fields[0]-0}))" "$((10#${fields[1]-0}))" "$((10#${fields[2]-0}))"
  [[ -z "${pre}" ]] || result="${result}-${pre}"
  printf '%s\n' "${result}"
}
