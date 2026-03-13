setup() {
  load test_helper
}

@test "dybatpho::date_now defaults to unix timestamp format" {
  stub date ": echo '1709210096'"
  run dybatpho::date_now
  assert_success
  assert_output "1709210096"
  unstub date
}

@test "dybatpho::date_today uses custom format" {
  stub date ": echo '2024-02-29'"
  run dybatpho::date_today "%F"
  assert_success
  assert_output "2024-02-29"
  unstub date
}

@test "dybatpho::date_is_valid accepts valid dates and rejects invalid ones" {
  run dybatpho::date_is_valid "2024-02-29"
  assert_success

  run dybatpho::date_is_valid "2024-02-30"
  assert_failure
}

@test "dybatpho::date_parse converts a date string to unix timestamp" {
  run dybatpho::date_parse "2024-02-29 12:34:56"
  assert_success
  assert_output "1709210096"
}

@test "dybatpho::date_format formats a unix timestamp" {
  run dybatpho::date_format "1709210096"
  assert_success
  assert_output "2024-02-29 12:34:56"

  run dybatpho::date_format "1709210096" "%Y-%m-%d"
  assert_success
  assert_output "2024-02-29"
}

@test "dybatpho::date_add_days shifts a date forward and backward" {
  run dybatpho::date_add_days "2024-03-01" 10
  assert_success
  assert_output "2024-03-11"

  run dybatpho::date_add_days "2024-03-01" -1
  assert_success
  assert_output "2024-02-29"
}

@test "dybatpho::date_diff_days prints signed day difference" {
  run dybatpho::date_diff_days "2024-03-01" "2024-03-11"
  assert_success
  assert_output "10"

  run dybatpho::date_diff_days "2024-03-11" "2024-03-01"
  assert_success
  assert_output "-10"
}
