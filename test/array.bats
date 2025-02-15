setup() {
  load test_helper
}

@test "dybatpho::array_reverse output" {
  run dybatpho::array_reverse
  assert_success
  refute_output
  run dybatpho::array_reverse 1 2 3 4 5
  assert_success
  assert_line --index 0 5
  assert_line --index 1 4
  assert_line --index 2 3
  assert_line --index 3 2
  assert_line --index 4 1
}

@test "dybatpho::array_unique output" {
  run dybatpho::array_unique
  assert_success
  refute_output
  run dybatpho::array_unique 1 1 2 2 3 3 3 3 3 4 4 4 4 4 5 5 5 5 5 5
  assert_success
  assert_line --index 0 1
  assert_line --index 1 2
  assert_line --index 2 3
  assert_line --index 3 4
  assert_line --index 4 5
}
