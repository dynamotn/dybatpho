setup() {
  . "${DYBATPHO_DIR}/test/lib/support/load.bash"
  . "${DYBATPHO_DIR}/test/lib/assert/load.bash"
  . "${DYBATPHO_DIR}/init.sh"
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
