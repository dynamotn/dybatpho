setup() {
  load test_helper
}

@test "dybatpho::array_print output" {
  arr=()
  run dybatpho::array_print "arr"
  assert_success
  refute_output
  arr=(2 33 55 "b c" 11)
  run dybatpho::array_print "arr"
  assert_line --index 0 2
  assert_line --index 1 33
  assert_line --index 2 55
  assert_line --index 3 "b c"
  assert_line --index 4 11
}

@test "dybatpho::array_reverse output" {
  arr=()
  run dybatpho::array_reverse "arr"
  assert_success
  refute_output
  run dybatpho::array_reverse "arr" "--"
  assert_success
  refute_output
  arr=(1)
  run dybatpho::array_reverse "arr" "--"
  assert_success
  assert_line --index 0 1
  arr=(1 2 "b c" 4 5)
  run dybatpho::array_reverse "arr" "--"
  assert_success
  assert_line --index 0 5
  assert_line --index 1 4
  assert_line --index 2 "b c"
  assert_line --index 3 2
  assert_line --index 4 1
}

@test "dybatpho::array_unique output" {
  arr=()
  run dybatpho::array_unique "arr" "--"
  assert_success
  refute_output
  arr=(1 1 2 2 3 3 3 3 3 4 4 4 4 4 5 5 5 5 5 5)
  run dybatpho::array_unique "arr" "--"
  assert_success
  assert_output "5
4
3
2
1"
}

@test "dybatpho::array_unique with spaces in elements" {
  # shellcheck disable=2034
  arr=("hello world" "hello world" "foo bar")
  run dybatpho::array_unique "arr" "--"
  assert_success
  assert_line --index 0 "hello world"
  assert_line --index 1 "foo bar"
}
