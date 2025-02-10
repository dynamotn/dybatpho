setup() {
  source "${DYBATPHO_DIR}/test/lib/support/load.bash"
  source "${DYBATPHO_DIR}/test/lib/assert/load.bash"
  source "${DYBATPHO_DIR}/init.sh"
}

@test "_lower output string" {
  run _lower "dYbaTPHO"
  assert_success
  assert_output "dybatpho"
}

@test "_upper output string" {
  run _upper "dYbaTPHO"
  assert_success
  assert_output "DYBATPHO"
}
