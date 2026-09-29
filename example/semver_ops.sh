#!/usr/bin/env bash
# @file semver_ops.sh
# @brief Example showing semver utilities
# @description Demonstrates dybatpho::semver_valid, semver_parse, semver_compare, semver_release_type, semver_bump
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules semver

dybatpho::register_common_handlers

# @description Run the `SEMVER VALID` section of this example.
# @noargs
function _demo_valid {
  dybatpho::header "SEMVER VALID"
  local -a versions=("1.2.3" "v2.0.0-rc.1" "1.0.0+build.42" "1.2" "not-a-version" "")
  local v
  for v in "${versions[@]}"; do
    local semver_valid
    semver_valid=$(dybatpho::semver_valid "${v}" && echo valid || echo invalid)
    dybatpho::info "'${v}': ${semver_valid}"
  done
}

# @description Run the `SEMVER PARSE` section of this example.
# @noargs
function _demo_parse {
  dybatpho::header "SEMVER PARSE"
  local version="1.4.2-beta.3+exp.sha.abc123"
  dybatpho::info "Input: ${version}"
  local -a parts
  mapfile -t parts < <(dybatpho::semver_parse "${version}")
  dybatpho::print "  major         : ${parts[0]}"
  dybatpho::print "  minor         : ${parts[1]}"
  dybatpho::print "  patch         : ${parts[2]}"
  dybatpho::print "  pre-release   : ${parts[3]:-<none>}"
  dybatpho::print "  build-metadata: ${parts[4]:-<none>}"
}

# @description Run the `SEMVER COMPARE` section of this example.
# @noargs
function _demo_compare {
  dybatpho::header "SEMVER COMPARE"
  local -a pairs=(
    "1.0.0  1.0.0"
    "2.0.0  1.9.9"
    "1.0.0  2.0.0"
    "1.0.0-alpha  1.0.0"
    "1.0.0-alpha  1.0.0-alpha.1"
    "1.0.0-beta.2  1.0.0-beta.11"
    "1.0.0+build.1  1.0.0+build.2"
  )
  local pair v1 v2 result
  for pair in "${pairs[@]}"; do
    read -r v1 v2 <<< "${pair}"
    result=$(dybatpho::semver_compare "${v1}" "${v2}")
    case "${result}" in
      -1) dybatpho::info "${v1}  <  ${v2}" ;;
      0) dybatpho::info "${v1}  =  ${v2}" ;;
      1) dybatpho::info "${v1}  >  ${v2}" ;;
      *) ;;
    esac
  done
}

# @description Run the `SEMVER RELEASE TYPE` section of this example.
# @noargs
function _demo_release_type {
  dybatpho::header "SEMVER RELEASE TYPE"
  local -a pairs=(
    "1.0.0  2.0.0"
    "1.0.0  1.1.0"
    "1.0.0  1.0.1"
    "1.0.0  1.0.0-rc.1"
    "1.0.0-rc.1  1.0.0-rc.2"
    "1.0.0+build.1  1.0.0+build.2"
    "1.0.0  1.0.0"
  )
  local pair old new rtype
  for pair in "${pairs[@]}"; do
    read -r old new <<< "${pair}"
    rtype=$(dybatpho::semver_release_type "${old}" "${new}")
    dybatpho::info "${old}  ->  ${new}  :  ${rtype}"
  done
}

# @description Run the `SEMVER BUMP` section of this example.
# @noargs
function _demo_bump {
  dybatpho::header "SEMVER BUMP"
  local base="1.4.2-alpha.1+build.5"
  dybatpho::info "Base version: ${base}"
  local semver_bump_6
  semver_bump_6=$(dybatpho::semver_bump "${base}" major)
  dybatpho::print "  bump major             : ${semver_bump_6}"
  local semver_bump_5
  semver_bump_5=$(dybatpho::semver_bump "${base}" minor)
  dybatpho::print "  bump minor             : ${semver_bump_5}"
  local semver_bump_4
  semver_bump_4=$(dybatpho::semver_bump "${base}" patch)
  dybatpho::print "  bump patch             : ${semver_bump_4}"
  local semver_bump_3
  semver_bump_3=$(dybatpho::semver_bump "${base}" major "rc.1")
  dybatpho::print "  bump major + pre rc.1  : ${semver_bump_3}"
  local semver_bump_2
  semver_bump_2=$(dybatpho::semver_bump "${base}" patch "" "sha.abc123")
  dybatpho::print "  bump patch + build meta: ${semver_bump_2}"
  local semver_bump
  semver_bump=$(dybatpho::semver_bump "${base}" minor "beta.1" "exp.42")
  dybatpho::print "  bump minor + both      : ${semver_bump}"
}

# @description Run the `RANGE CONSTRAINTS` section of this example.
# @noargs
function _demo_ranges {
  dybatpho::header "RANGE CONSTRAINTS"
  # The question a dependency check actually asks, written as the requirement
  # itself rather than as a chain of comparisons.
  local pair version range
  for pair in "1.4.2|^1.2" "2.0.0|^1.2" "1.2.9|~1.2.3" "1.5.0|>=1.2 <1.9" "18.1.0|>=18" "3.1.0|^1.0 || ^3.0"; do
    version="${pair%%|*}"
    range="${pair#*|}"
    if dybatpho::semver_satisfies "${version}" "${range}"; then
      dybatpho::print "  $(printf '%-8s' "${version}") satisfies   ${range}"
    else
      dybatpho::print "  $(printf '%-8s' "${version}") misses      ${range}"
    fi
  done

  dybatpho::header "VERSIONS AS REAL COMMANDS REPORT THEM"
  # A range needs a complete version, and almost nothing in the wild says its
  # version that way. This is the step between the two.
  local reported
  for reported in "1.35" "git version 2.43.0" \
    "yq (https://github.com/mikefarah/yq/) version v4.53.3" \
    "UnZip 6.00 of 20 April 2009" "grep (GNU grep) 3.12-modified"; do
    local semver_coerce
    semver_coerce=$(dybatpho::semver_coerce "${reported}")
    dybatpho::print "  $(printf '%-52s' "${reported}") -> ${semver_coerce}"
  done
  # What the two are for together: deciding whether an installed tool is usable.
  local command_version
  command_version=$(dybatpho::command_version bash)
  local semver_coerce_2
  semver_coerce_2=$(dybatpho::semver_coerce "${command_version}")
  if dybatpho::semver_satisfies "${semver_coerce_2}" '>=4.3'; then
    dybatpho::print "  the running bash satisfies >=4.3"
  fi

  dybatpho::info "A pre-release stays out of a range that never named one:"
  if dybatpho::semver_satisfies "2.0.0-alpha" "^1.0.0"; then
    dybatpho::warn "  2.0.0-alpha satisfied ^1.0.0, which would be a nasty surprise"
  else
    dybatpho::print "  2.0.0-alpha does not satisfy ^1.0.0"
  fi

  # The shape a real check takes.
  local required=">=1.2"
  local installed="1.4.2"
  dybatpho::semver_satisfies "${installed}" "${required}" \
    || dybatpho::die "Need ${required}, found ${installed}"
  dybatpho::success "Dependency check passed: ${installed} satisfies ${required}"
}

# @description Run the `ORDERING VERSIONS` section of this example.
# @noargs
function _demo_ordering {
  dybatpho::header "ORDERING VERSIONS"
  # String order would put 1.10.0 before 1.9.0; version order does not.
  local semver_sort_2
  semver_sort_2=$(dybatpho::semver_sort 1.10.0 1.9.0 2.0.0 1.2.3 | tr '\n' ' ')
  dybatpho::info "Sorted: ${semver_sort_2}"
  local semver_sort
  semver_sort=$(dybatpho::semver_sort 2.0.0 2.0.0-rc.1 2.0.0-alpha | tr '\n' ' ')
  dybatpho::info "With pre-releases: ${semver_sort}"
  local semver_max
  semver_max=$(dybatpho::semver_max 1.10.0 1.9.0 2.0.0-rc.1)
  dybatpho::info "Highest: ${semver_max}"

  # A list of tags keeps its `v`, so the result is usable as a tag again.
  local printf
  printf=$(printf 'v1.2.0\nv1.10.0\nv1.9.0\n' | dybatpho::semver_max)
  dybatpho::info "From a tag list: ${printf}"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_valid
  _demo_parse
  _demo_compare
  _demo_release_type
  _demo_bump
  _demo_ranges
  _demo_ordering
  dybatpho::success "Semver operations demo complete"
}

_main "$@"
