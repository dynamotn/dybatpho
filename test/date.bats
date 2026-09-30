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

  run_traced dybatpho::date_is_valid "2024-02-30"
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

  run_traced dybatpho::date_is_valid "2024-02-30"
  assert_failure

  run_traced dybatpho::date_parse "2024-02-30"
  assert_failure
}

@test "date parsing fails when no BSD input format matches" {
  stub_repeated date ": exit 1"

  # Called directly so the failing branch is exercised in this shell.
  run_traced ! __dybatpho_date_parse "not a date"

  run_traced dybatpho::date_parse "not a date"
  assert_failure
}

@test "dybatpho::date_is_leap_year applies all three rules" {
  # The century rule is the one that gets left out, and 1900 catches it.
  run -0 dybatpho::date_is_leap_year 2024
  run -0 dybatpho::date_is_leap_year 2000
  run ! dybatpho::date_is_leap_year 1900
  run ! dybatpho::date_is_leap_year 2100
  run ! dybatpho::date_is_leap_year 2023
  run --separate-stderr ! dybatpho::date_is_leap_year abcd
  assert_stderr --partial "is not a year"
}

@test "dybatpho::date_days_in_month answers for every month length" {
  assert_equal "$(dybatpho::date_days_in_month 2024 1)" "31"
  assert_equal "$(dybatpho::date_days_in_month 2024 4)" "30"
  assert_equal "$(dybatpho::date_days_in_month 2024 12)" "31"
  assert_equal "$(dybatpho::date_days_in_month 2024 2)" "29"
  assert_equal "$(dybatpho::date_days_in_month 2023 2)" "28"
  # A month read off a date carries a leading zero.
  assert_equal "$(dybatpho::date_days_in_month 2024 02)" "29"
  run --separate-stderr ! dybatpho::date_days_in_month 2024 13
  assert_stderr --partial "is not a month"
  run --separate-stderr ! dybatpho::date_days_in_month 2024 0
}

@test "dybatpho::date_month_start and date_month_end bound a month" {
  assert_equal "$(dybatpho::date_month_start 2024-02-17)" "2024-02-01"
  assert_equal "$(dybatpho::date_month_end 2024-02-17)" "2024-02-29"
  assert_equal "$(dybatpho::date_month_end 2023-02-17)" "2023-02-28"
  assert_equal "$(dybatpho::date_month_end 2024-04-05)" "2024-04-30"
  assert_equal "$(dybatpho::date_month_end 2024-12-01)" "2024-12-31"
  assert_equal "$(dybatpho::date_month_start 2024-02-17 '%F %T')" "2024-02-01 00:00:00"
}

@test "dybatpho::date_add shifts by every unit it measures" {
  assert_equal "$(dybatpho::date_add 2024-02-28 1 days '%F')" "2024-02-29"
  assert_equal "$(dybatpho::date_add 2023-02-28 1 days '%F')" "2023-03-01"
  assert_equal "$(dybatpho::date_add '2024-02-28 23:00:00' 2 hours '%F %T')" "2024-02-29 01:00:00"
  assert_equal "$(dybatpho::date_add '2024-01-01 00:00:00' 90 seconds '%F %T')" "2024-01-01 00:01:30"
  assert_equal "$(dybatpho::date_add 2024-03-01 -1 weeks '%F')" "2024-02-23"
  # Singular and plural name the same unit.
  assert_equal "$(dybatpho::date_add 2024-01-01 1 day '%F')" "2024-01-02"
}

@test "dybatpho::date_add refuses a unit whose length depends on the calendar" {
  # A month is not a fixed number of seconds, and the two `date` implementations
  # this module supports shift by one differently.
  run --separate-stderr ! dybatpho::date_add 2024-01-01 1 months
  assert_stderr --partial "Unknown time unit 'months'"
  run --separate-stderr ! dybatpho::date_add 2024-01-01 1 years
  run --separate-stderr ! dybatpho::date_add 2024-01-01 x days
  assert_stderr --partial "is not a whole number"
}

@test "dybatpho::date_add reports a bad unit even when errexit is switched off" {
  # `dybatpho::die` inside a command substitution only leaves that subshell, and
  # a caller writing `date_add ... || handler` turns errexit off for the whole
  # call. Without an explicit status check the unit went unvalidated and the
  # GNU date fallback happily answered `2024-02-01`.
  local status=0
  local output
  output="$( (dybatpho::date_add 2024-01-01 1 months '%F') 2> /dev/null )" || status=$?
  ((status != 0)) || fail "a bad unit was accepted, answering '${output}'"
  assert_equal "${output}" ""
}

@test "dybatpho::date_diff measures in the unit it is asked for" {
  assert_equal "$(dybatpho::date_diff 2024-01-01 2024-03-01 days)" "60"
  assert_equal "$(dybatpho::date_diff '2024-01-01 00:00:00' '2024-01-01 00:01:00')" "60"
  assert_equal "$(dybatpho::date_diff '2024-01-01 00:00:00' '2024-01-01 01:30:00' minutes)" "90"
  assert_equal "$(dybatpho::date_diff '2024-01-01 00:00:00' '2024-01-01 01:30:00' hours)" "1"
  run_traced --separate-stderr ! dybatpho::date_diff 2024-01-01 2024-01-02 fortnights
}

@test "dybatpho::date_diff truncates toward zero in both directions" {
  # 47 hours is one day, not two, and the sign does not change that.
  assert_equal "$(dybatpho::date_diff '2024-01-01 00:00:00' '2024-01-02 23:00:00' days)" "1"
  assert_equal "$(dybatpho::date_diff '2024-01-02 23:00:00' '2024-01-01 00:00:00' days)" "-1"
}

@test "dybatpho::date_add_days and date_diff_days keep answering as they did" {
  # Both now delegate to the general helpers rather than repeating them.
  assert_equal "$(dybatpho::date_add_days 2024-02-28 1)" "2024-02-29"
  assert_equal "$(dybatpho::date_add_days 2024-03-01 -1)" "2024-02-29"
  assert_equal "$(dybatpho::date_add_days 2024-01-01 1 '%F %T')" "2024-01-02 00:00:00"
  assert_equal "$(dybatpho::date_diff_days 2024-01-01 2024-03-01)" "60"
  assert_equal "$(dybatpho::date_diff_days 2024-03-01 2024-01-01)" "-60"
}

@test "dybatpho::date_seconds_to_hms writes a length of time, not a time of day" {
  assert_equal "$(dybatpho::date_seconds_to_hms 3661)" "1:01:01"
  assert_equal "$(dybatpho::date_seconds_to_hms 0)" "0:00:00"
  assert_equal "$(dybatpho::date_seconds_to_hms 59)" "0:00:59"
  # The hours are not wrapped at a day.
  assert_equal "$(dybatpho::date_seconds_to_hms 90000)" "25:00:00"
  assert_equal "$(dybatpho::date_seconds_to_hms -61)" "-0:01:01"
  run --separate-stderr ! dybatpho::date_seconds_to_hms 1.5
  assert_stderr --partial "is not a whole number of seconds"
}
