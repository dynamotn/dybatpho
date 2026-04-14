#!/usr/bin/env bash
# @file semver.sh
# @brief Utilities for working with Semantic Versioning (semver)
# @description
#   This module contains helpers for parsing, validating, comparing semver strings,
#   and detecting the release type of a version bump.
#
#   Follows [Semantic Versioning 2.0.0](https://semver.org/) spec.
#   A leading `v` prefix (e.g. `v1.2.3`) is accepted and stripped automatically.
# @see
#   - https://semver.org/
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# Prevent multiple sourcing
[[ -n "${DYBATPHO_SEMVER_LOADED:-}" ]] && return 0
declare -r DYBATPHO_SEMVER_LOADED=true

# Regex for a valid semver string (with optional leading v)
# Groups: 1=major 2=minor 3=patch 4=pre-release 5=build-metadata
declare -r DYBATPHO_SEMVER_REGEX='^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-([a-zA-Z0-9._-]+))?(\+([a-zA-Z0-9._-]+))?$'

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
    dybatpho::die "semver_parse: '${version}' is not a valid semver string"
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
  IFS='.' read -r -a ids1 <<<"${pre1}"
  IFS='.' read -r -a ids2 <<<"${pre2}"

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
