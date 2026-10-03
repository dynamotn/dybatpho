setup() {
  load test_helper
}

# ---------------------------------------------------------------------------
# dybatpho::semver_valid
# ---------------------------------------------------------------------------

@test "dybatpho::semver_valid accepts standard semver" {
  dybatpho::semver_valid "1.2.3"
}

@test "dybatpho::semver_valid accepts semver with leading v" {
  dybatpho::semver_valid "v1.2.3"
}

@test "dybatpho::semver_valid accepts semver with pre-release" {
  dybatpho::semver_valid "1.2.3-alpha.1"

  dybatpho::semver_valid "v2.0.0-rc.1"
}

@test "dybatpho::semver_valid accepts semver with build-metadata" {
  dybatpho::semver_valid "1.0.0+build.42"
}

@test "dybatpho::semver_valid accepts semver with pre-release and build-metadata" {
  dybatpho::semver_valid "1.0.0-beta.2+exp.sha.5114f85"
}

@test "dybatpho::semver_valid rejects missing patch" {
  run_traced dybatpho::semver_valid "1.2"
  assert_failure
}

@test "dybatpho::semver_valid rejects non-numeric version" {
  run_traced dybatpho::semver_valid "one.two.three"
  assert_failure
}

@test "dybatpho::semver_valid rejects empty string" {
  run_traced dybatpho::semver_valid ""
  assert_failure
}

@test "dybatpho::semver_valid rejects garbage input" {
  run_traced dybatpho::semver_valid "not-a-version"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::semver_parse
# ---------------------------------------------------------------------------

@test "dybatpho::semver_parse extracts major minor patch" {
  assert_equal "$(dybatpho::semver_parse "3.14.159")" "$(printf '%s\n' 3 14 159 '' '')"
}

@test "dybatpho::semver_parse strips leading v" {
  assert_equal "$(dybatpho::semver_parse "v1.0.0")" "$(printf '%s\n' 1 0 0 '' '')"
}

@test "dybatpho::semver_parse extracts pre-release label" {
  assert_equal "$(dybatpho::semver_parse "1.2.3-alpha.1")" "$(printf '%s\n' 1 2 3 'alpha.1' '')"
}

@test "dybatpho::semver_parse extracts build-metadata" {
  assert_equal "$(dybatpho::semver_parse "1.0.0+build.42")" "$(printf '%s\n' 1 0 0 '' 'build.42')"
}

@test "dybatpho::semver_parse extracts both pre-release and build-metadata" {
  assert_equal "$(dybatpho::semver_parse "1.0.0-beta.2+exp.sha.5114f85")" "$(printf '%s\n' 1 0 0 'beta.2' 'exp.sha.5114f85')"
}

@test "dybatpho::semver_parse dies on invalid input" {
  run dybatpho::semver_parse "not-semver"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::semver_compare
# ---------------------------------------------------------------------------

@test "dybatpho::semver_compare equal versions returns 0" {
  assert_equal "$(dybatpho::semver_compare "1.2.3" "1.2.3")" "0"
}

@test "dybatpho::semver_compare v-prefixed equal versions returns 0" {
  assert_equal "$(dybatpho::semver_compare "v1.2.3" "v1.2.3")" "0"
}

@test "dybatpho::semver_compare greater major returns 1" {
  assert_equal "$(dybatpho::semver_compare "2.0.0" "1.9.9")" "1"
}

@test "dybatpho::semver_compare lesser major returns -1" {
  assert_equal "$(dybatpho::semver_compare "1.0.0" "2.0.0")" "-1"
}

@test "dybatpho::semver_compare greater minor returns 1" {
  assert_equal "$(dybatpho::semver_compare "1.3.0" "1.2.9")" "1"
}

@test "dybatpho::semver_compare lesser minor returns -1" {
  assert_equal "$(dybatpho::semver_compare "1.2.0" "1.3.0")" "-1"
}

@test "dybatpho::semver_compare greater patch returns 1" {
  assert_equal "$(dybatpho::semver_compare "1.2.4" "1.2.3")" "1"
}

@test "dybatpho::semver_compare lesser patch returns -1" {
  assert_equal "$(dybatpho::semver_compare "1.2.2" "1.2.3")" "-1"
}

@test "dybatpho::semver_compare release is greater than pre-release" {
  assert_equal "$(dybatpho::semver_compare "1.0.0" "1.0.0-alpha")" "1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha" "1.0.0")" "-1"
}

@test "dybatpho::semver_compare pre-release identifiers compared correctly" {
  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha" "1.0.0-alpha.1")" "-1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha.1" "1.0.0-alpha.beta")" "-1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha.beta" "1.0.0-beta")" "-1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-beta" "1.0.0-beta.2")" "-1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-beta.2" "1.0.0-beta.11")" "-1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-beta.11" "1.0.0-rc.1")" "-1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-rc.1" "1.0.0")" "-1"
}

@test "dybatpho::semver_compare numeric pre-release id lower than alphanumeric" {
  assert_equal "$(dybatpho::semver_compare "1.0.0-1" "1.0.0-alpha")" "-1"
}

@test "dybatpho::semver_compare ignores build-metadata" {
  assert_equal "$(dybatpho::semver_compare "1.0.0+build.1" "1.0.0+build.2")" "0"

  assert_equal "$(dybatpho::semver_compare "1.0.0+build.1" "1.0.0")" "0"
}

@test "dybatpho::semver_compare dies on invalid first version" {
  run dybatpho::semver_compare "bad" "1.0.0"
  assert_failure
}

@test "dybatpho::semver_compare dies on invalid second version" {
  run dybatpho::semver_compare "1.0.0" "bad"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::semver_release_type
# ---------------------------------------------------------------------------

@test "dybatpho::semver_release_type detects major bump" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3" "2.0.0")" "major"
}

@test "dybatpho::semver_release_type detects minor bump" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3" "1.3.0")" "minor"
}

@test "dybatpho::semver_release_type detects patch bump" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3" "1.2.4")" "patch"
}

@test "dybatpho::semver_release_type detects pre-release change" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3-alpha.1" "1.2.3-alpha.2")" "pre-release"
}

@test "dybatpho::semver_release_type detects pre-release added" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3" "1.2.3-rc.1")" "pre-release"
}

@test "dybatpho::semver_release_type detects build-metadata change" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3+build.1" "1.2.3+build.2")" "build"
}

@test "dybatpho::semver_release_type detects equal versions" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3" "1.2.3")" "equal"
}

@test "dybatpho::semver_release_type works with v prefix" {
  assert_equal "$(dybatpho::semver_release_type "v1.0.0" "v2.0.0")" "major"

  assert_equal "$(dybatpho::semver_release_type "v1.0.0" "v1.1.0")" "minor"
}

@test "dybatpho::semver_release_type dies on invalid old version" {
  run dybatpho::semver_release_type "bad" "1.0.0"
  assert_failure
}

@test "dybatpho::semver_release_type dies on invalid new version" {
  run dybatpho::semver_release_type "1.0.0" "bad"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::semver_bump
# ---------------------------------------------------------------------------

@test "dybatpho::semver_bump increments major and resets minor and patch" {
  assert_equal "$(dybatpho::semver_bump "1.2.3" "major")" "2.0.0"
}

@test "dybatpho::semver_bump increments minor and resets patch" {
  assert_equal "$(dybatpho::semver_bump "1.2.3" "minor")" "1.3.0"
}

@test "dybatpho::semver_bump increments patch only" {
  assert_equal "$(dybatpho::semver_bump "1.2.3" "patch")" "1.2.4"
}

@test "dybatpho::semver_bump strips pre-release from source version" {
  assert_equal "$(dybatpho::semver_bump "1.2.3-alpha.1" "patch")" "1.2.4"
}

@test "dybatpho::semver_bump strips build-metadata from source version" {
  assert_equal "$(dybatpho::semver_bump "1.2.3+build.99" "minor")" "1.3.0"
}

@test "dybatpho::semver_bump attaches optional pre-release label" {
  assert_equal "$(dybatpho::semver_bump "1.2.3" "major" "rc.1")" "2.0.0-rc.1"
}

@test "dybatpho::semver_bump attaches optional build-metadata" {
  assert_equal "$(dybatpho::semver_bump "1.2.3" "patch" "" "build.42")" "1.2.4+build.42"
}

@test "dybatpho::semver_bump attaches pre-release and build-metadata together" {
  assert_equal "$(dybatpho::semver_bump "1.2.3" "minor" "beta.2" "exp.sha.abc")" "1.3.0-beta.2+exp.sha.abc"
}

@test "dybatpho::semver_bump works with leading v prefix" {
  assert_equal "$(dybatpho::semver_bump "v2.0.0" "patch")" "2.0.1"
}

@test "dybatpho::semver_bump dies on invalid version" {
  run dybatpho::semver_bump "not-semver" "patch"
  assert_failure
}

@test "dybatpho::semver_bump dies on unknown part" {
  run dybatpho::semver_bump "1.2.3" "build"
  assert_failure
}

@test "dybatpho::semver_compare covers reverse short and numeric pre-release ordering" {
  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha.1" "1.0.0-alpha")" "1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-beta.11" "1.0.0-beta.2")" "1"
}

@test "dybatpho::semver_compare compares alphanumeric identifiers in both directions" {
  assert_equal "$(dybatpho::semver_compare "1.0.0-beta" "1.0.0-alpha")" "1"

  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha" "1.0.0-alpha")" "0"

  assert_equal "$(dybatpho::semver_compare "1.0.0-alpha" "1.0.0-1")" "1"
}

@test "dybatpho::semver_release_type detects removed prerelease and build metadata" {
  assert_equal "$(dybatpho::semver_release_type "1.2.3-rc.1" "1.2.3")" "pre-release"

  assert_equal "$(dybatpho::semver_release_type "1.2.3" "1.2.3+build.1")" "build"

  assert_equal "$(dybatpho::semver_release_type "1.2.3+build.1" "1.2.3")" "build"
}

@test "dybatpho::semver_satisfies handles caret ranges, including below 1.0" {
  dybatpho::semver_satisfies "1.4.2" "^1.2"
  dybatpho::semver_satisfies "1.2.3" "^1.2.3"
  run_traced ! dybatpho::semver_satisfies "2.0.0" "^1.2"
  run_traced ! dybatpho::semver_satisfies "1.2.0" "^1.2.3"
  # Below 1.0 the leftmost non-zero part is the one held steady.
  dybatpho::semver_satisfies "0.2.5" "^0.2.3"
  run_traced ! dybatpho::semver_satisfies "0.3.0" "^0.2.3"
  dybatpho::semver_satisfies "0.0.3" "^0.0.3"
  run_traced ! dybatpho::semver_satisfies "0.0.4" "^0.0.3"
}

@test "dybatpho::semver_satisfies handles tilde ranges at every specificity" {
  dybatpho::semver_satisfies "1.2.9" "~1.2.3"
  run_traced ! dybatpho::semver_satisfies "1.3.0" "~1.2.3"
  dybatpho::semver_satisfies "1.2.0" "~1.2"
  run_traced ! dybatpho::semver_satisfies "1.3.0" "~1.2"
  dybatpho::semver_satisfies "1.3.0" "~1"
  run_traced ! dybatpho::semver_satisfies "2.0.0" "~1"
}

@test "dybatpho::semver_satisfies handles plain comparisons" {
  dybatpho::semver_satisfies "1.5.0" ">=1.2.0"
  dybatpho::semver_satisfies "18.1.0" ">=18"
  run_traced ! dybatpho::semver_satisfies "17.9.9" ">=18"
  dybatpho::semver_satisfies "1.0.0" "<=1.0.0"
  run_traced ! dybatpho::semver_satisfies "1.0.1" "<=1.0.0"
  dybatpho::semver_satisfies "1.2.3" "=1.2.3"
  run_traced ! dybatpho::semver_satisfies "1.2.4" "=1.2.3"
}

@test "dybatpho::semver_satisfies treats several comparators as all of them" {
  dybatpho::semver_satisfies "1.5.0" ">=1.2 <1.9"
  run_traced ! dybatpho::semver_satisfies "1.9.0" ">=1.2 <1.9"
  run_traced ! dybatpho::semver_satisfies "1.1.0" ">=1.2 <1.9"
}

@test "dybatpho::semver_satisfies treats a double pipe as either" {
  dybatpho::semver_satisfies "3.1.0" "^1.0 || ^3.0"
  dybatpho::semver_satisfies "1.9.9" "^1.0 || ^3.0"
  run_traced ! dybatpho::semver_satisfies "2.5.0" "^1.0 || ^3.0"
}

@test "dybatpho::semver_satisfies handles wildcards and partial versions" {
  dybatpho::semver_satisfies "9.9.9" "*"
  dybatpho::semver_satisfies "1.2.7" "1.2.x"
  run_traced ! dybatpho::semver_satisfies "1.3.0" "1.2.x"
  dybatpho::semver_satisfies "1.2.7" "1.2"
  dybatpho::semver_satisfies "1.9.0" "1"
  run_traced ! dybatpho::semver_satisfies "2.0.0" "1"
  dybatpho::semver_satisfies "1.2.3" "1.2.3"
}

@test "dybatpho::semver_satisfies keeps a pre-release out of a range that never asked for one" {
  # The trap this rule exists for: without it, 2.0.0-alpha sorts below 2.0.0 and
  # would slip into a range that stops short of 2.0.0.
  run_traced ! dybatpho::semver_satisfies "2.0.0-alpha" "^1.0.0"
  run_traced ! dybatpho::semver_satisfies "1.3.0-rc.1" ">=1.0.0"
  # A range that names a pre-release of the same release does accept it.
  dybatpho::semver_satisfies "1.2.3-rc.1" "^1.2.3-rc.1"
  dybatpho::semver_satisfies "1.2.4" "^1.2.3-rc.1"
}

@test "dybatpho::semver_satisfies accepts a leading v and rejects nonsense" {
  dybatpho::semver_satisfies "v1.4.2" "^1.2"
  run ! dybatpho::semver_satisfies "1.0.0" "^9.9"
  run ! dybatpho::semver_satisfies "notaversion" "^1.0"
  run ! dybatpho::semver_satisfies "1.0.0" "^notaversion"
}

@test "dybatpho::semver_sort orders by version rather than as strings" {
  run_traced -0 dybatpho::semver_sort 1.10.0 1.9.0 2.0.0 1.2.3
  assert_output "$(printf '1.2.3\n1.9.0\n1.10.0\n2.0.0')"
}

@test "dybatpho::semver_sort places a pre-release before its release" {
  run_traced -0 dybatpho::semver_sort 2.0.0 2.0.0-rc.1 2.0.0-alpha 2.0.0-beta.2
  assert_output "$(printf '2.0.0-alpha\n2.0.0-beta.2\n2.0.0-rc.1\n2.0.0')"
}

@test "dybatpho::semver_sort reads standard input and keeps a leading v" {
  local list="${BATS_TEST_TMPDIR}/versions"
  printf 'v1.10.0\nv1.9.0\nv2.0.0\n' > "${list}"
  run_traced -0 dybatpho::semver_sort < "${list}"
  assert_output "$(printf 'v1.9.0\nv1.10.0\nv2.0.0')"
}

@test "dybatpho::semver_sort accepts an empty list and rejects an invalid version" {
  run -0 dybatpho::semver_sort
  assert_output ""
  run ! dybatpho::semver_sort 1.2.3 nonsense
}

@test "dybatpho::semver_max reports the highest version" {
  assert_equal "$(dybatpho::semver_max 1.10.0 1.9.0 2.0.0-rc.1)" "2.0.0-rc.1"
  assert_equal "$(dybatpho::semver_max 1.0.0 2.0.0 2.0.0-rc.1)" "2.0.0"
  assert_equal "$(printf 'v1.2.0\nv1.10.0\nv1.9.0\n' | dybatpho::semver_max)" "v1.10.0"
  assert_equal "$(dybatpho::semver_max 1.2.3)" "1.2.3"
}

@test "dybatpho::semver_max needs at least one version" {
  run ! dybatpho::semver_max
  run ! dybatpho::semver_max nonsense
}

@test "dybatpho::semver_coerce fills the fields a real version leaves out" {
  assert_equal "$(dybatpho::semver_coerce 1.35)" "1.35.0"
  assert_equal "$(dybatpho::semver_coerce 4)" "4.0.0"
  assert_equal "$(dybatpho::semver_coerce v4)" "4.0.0"
  assert_equal "$(dybatpho::semver_coerce 1.2.3)" "1.2.3"
}

@test "dybatpho::semver_coerce finds the version inside what a command prints" {
  assert_equal "$(dybatpho::semver_coerce 'git version 2.43.0')" "2.43.0"
  assert_equal "$(dybatpho::semver_coerce 'jq-1.7.1')" "1.7.1"
  assert_equal "$(dybatpho::semver_coerce \
    'yq (https://github.com/mikefarah/yq/) version v4.53.3')" "4.53.3"
  assert_equal "$(dybatpho::semver_coerce 'GNU bash, version 5.2.21(1)-release')" "5.2.21"
}

@test "dybatpho::semver_coerce ignores a number that is not a version" {
  # zstd opens with `64-bits`, which a pattern accepting a bare run of digits
  # would answer instead of the version that follows it.
  assert_equal "$(dybatpho::semver_coerce \
    '*** zstd command line interface 64-bits v1.5.5, by Yann Collet ***')" "1.5.5"
}

@test "dybatpho::semver_coerce strips the leading zeros semver forbids" {
  assert_equal "$(dybatpho::semver_coerce 'UnZip 6.00 of 20 April 2009')" "6.0.0"
  assert [ "$(dybatpho::semver_valid "$(dybatpho::semver_coerce 'UnZip 6.00')" && echo yes)" = yes ]
}

@test "dybatpho::semver_coerce keeps only the first three fields" {
  assert_equal "$(dybatpho::semver_coerce 1.2.3.4)" "1.2.3"
}

@test "dybatpho::semver_coerce keeps a pre-release but drops a build marker" {
  assert_equal "$(dybatpho::semver_coerce 1.7.1-rc1)" "1.7.1-rc1"
  assert_equal "$(dybatpho::semver_coerce 2.0.0-BETA.2)" "2.0.0-BETA.2"
  # A distribution says it patched the tool in the same place a pre-release
  # goes. Read as a pre-release, the version would rank below the release it
  # actually is, and a `>=` on that release would reject it.
  assert_equal "$(dybatpho::semver_coerce 3.12-modified)" "3.12.0"
  assert_equal "$(dybatpho::semver_coerce 1.2.3-1ubuntu2)" "1.2.3"
}

@test "dybatpho::semver_coerce rejects text with no version in it" {
  run --separate-stderr ! dybatpho::semver_coerce "no digits here"
  assert_stderr --partial "No version found"
}

@test "dybatpho::semver_coerce hands a real version over to the range matcher" {
  # `semver_satisfies` insists on a complete version, which is the whole reason
  # `semver_coerce` exists: these two are always used together.
  dybatpho::semver_satisfies "$(dybatpho::semver_coerce 'yq version v4.53.3')" '>=4'
  dybatpho::semver_satisfies "$(dybatpho::semver_coerce 1.35)" '>=1.30'
  dybatpho::semver_satisfies "$(dybatpho::semver_coerce 3.12-modified)" '>=3.12'
  run_traced ! dybatpho::semver_satisfies "$(dybatpho::semver_coerce 'yq version v3.4.3')" '>=4'
}

@test "the sort agrees with the comparison it is built on" {
  # Sorting must not invent an order of its own: every adjacent pair of the
  # result has to compare as less-than-or-equal.
  local -a sorted
  mapfile -t sorted < <(dybatpho::semver_sort 2.0.0 1.0.0-rc.1 1.0.0 0.9.9 1.10.2 1.2.0)
  local index
  for ((index = 1; index < ${#sorted[@]}; index++)); do
    assert [ "$(dybatpho::semver_compare "${sorted[index - 1]}" "${sorted[index]}")" -le 0 ]
  done
}

@test "dybatpho::semver_sort keeps versions of equal precedence in the order given" {
  # Build metadata does not affect precedence, so these three tie; a stable
  # sort leaves them as written rather than reordering them by text.
  run_traced dybatpho::semver_sort 2.0.0 1.0.0+b v1.0.0 1.0.0+a 0.9.0
  assert_success
  assert_output "$(printf '%s\n' 0.9.0 1.0.0+b v1.0.0 1.0.0+a 2.0.0)"
}
