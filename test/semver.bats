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
  run dybatpho::semver_valid "1.2"
  assert_failure
}

@test "dybatpho::semver_valid rejects non-numeric version" {
  run dybatpho::semver_valid "one.two.three"
  assert_failure
}

@test "dybatpho::semver_valid rejects empty string" {
  run dybatpho::semver_valid ""
  assert_failure
}

@test "dybatpho::semver_valid rejects garbage input" {
  run dybatpho::semver_valid "not-a-version"
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
