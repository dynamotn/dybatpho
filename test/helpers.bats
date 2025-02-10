setup() {
  source "${DYBATPHO_DIR}/test/lib/support/load.bash"
  source "${DYBATPHO_DIR}/test/lib/assert/load.bash"
  source "${DYBATPHO_DIR}/init.sh"
}

@test "_require installed tool" {
  run _require "bash"
  assert_success
}

@test "_require not installed tool" {
  bats_require_minimum_version 1.5.0
  run -127 _require "dyfoooo"
  assert_failure
  assert_output --partial "dyfoooo isn't installed"
}
