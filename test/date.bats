setup() {
  load test_helper
}

@test "dybatpho::date_now defaults to unix timestamp format" {
  stub date ": echo '1709210096'"
  assert_equal "$(dybatpho::date_now)" "1709210096"
  unstub date
}

@test "dybatpho::date_today uses custom format" {
  stub date ": echo '2024-02-29'"
  assert_equal "$(dybatpho::date_today "%F")" "2024-02-29"
  unstub date
}

@test "dybatpho::date_is_valid accepts valid dates and rejects invalid ones" {
  dybatpho::date_is_valid "2024-02-29"

  run dybatpho::date_is_valid "2024-02-30"
  assert_failure
}

@test "dybatpho::date_parse converts a date string to unix timestamp" {
  assert_equal "$(dybatpho::date_parse "2024-02-29 12:34:56")" "1709210096"
}

@test "dybatpho::date_format formats a unix timestamp" {
  assert_equal "$(dybatpho::date_format "1709210096")" "2024-02-29 12:34:56"

  assert_equal "$(dybatpho::date_format "1709210096" "%Y-%m-%d")" "2024-02-29"
}

@test "dybatpho::date_add_days shifts a date forward and backward" {
  assert_equal "$(dybatpho::date_add_days "2024-03-01" 10)" "2024-03-11"

  assert_equal "$(dybatpho::date_add_days "2024-03-01" -1)" "2024-02-29"
}

@test "dybatpho::date_diff_days prints signed day difference" {
  assert_equal "$(dybatpho::date_diff_days "2024-03-01" "2024-03-11")" "10"

  assert_equal "$(dybatpho::date_diff_days "2024-03-11" "2024-03-01")" "-10"
}

@test "date helpers fall back to BSD date flags" {
  # BSD date has no --version and no -d; it parses with -j -f and formats with -r.
  stub_repeated date ": case \"\$1\" in --version) exit 1 ;; -j) [[ \$3 == '%Y-%m-%d %H:%M:%S' ]] && echo '1709210096' || exit 1 ;; -r) [[ \$3 == '+%Y-%m-%d %H:%M:%S' ]] && echo '2024-02-29 12:34:56' || echo '2024-02-29' ;; *) exit 1 ;; esac"

  assert_equal "$(dybatpho::date_parse "2024-02-29 12:34:56")" "1709210096"
  assert_equal "$(dybatpho::date_format "1709210096" "%F")" "2024-02-29"
  assert_equal "$(dybatpho::date_add_days "2024-02-29 12:34:56" 1)" "2024-02-29"
}

@test "BSD date parsing rejects dates that roll over" {
  # BSD `date -j -f` accepts 2024-02-30 and answers with 2024-03-01, which must
  # not be reported as a valid date.
  stub_repeated date ": case \"\$1\" in --version) exit 1 ;; -j) [[ \$3 == '%Y-%m-%d' ]] && echo '1709251200' || exit 1 ;; -r) echo '2024-03-01' ;; *) exit 1 ;; esac"

  run dybatpho::date_is_valid "2024-02-30"
  assert_failure

  run dybatpho::date_parse "2024-02-30"
  assert_failure
}

@test "date parsing fails when no BSD input format matches" {
  stub_repeated date ": exit 1"

  # Called directly so the failing branch is exercised in this shell.
  run ! __dybatpho_date_parse "not a date"

  run dybatpho::date_parse "not a date"
  assert_failure
}
