setup() {
  load test_helper
}

@test "dybatpho::require installed tool" {
  run dybatpho::require "bash"
  assert_success
}

@test "dybatpho::require not installed tool" {
  bats_require_minimum_version 1.5.0
  run -127 dybatpho::require "dyfoooo"
  assert_failure
  assert_output --partial "dyfoooo isn't installed"
}
