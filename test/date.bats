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

@test "dybatpho::date_parse_duration reads seconds and parts with units" {
  local seconds
  dybatpho::date_parse_duration seconds 90
  assert_equal "${seconds}" "90"
  dybatpho::date_parse_duration seconds 90s
  assert_equal "${seconds}" "90"
  dybatpho::date_parse_duration seconds 5m
  assert_equal "${seconds}" "300"
  dybatpho::date_parse_duration seconds 1h30m
  assert_equal "${seconds}" "5400"
  dybatpho::date_parse_duration seconds "1h 30m"
  assert_equal "${seconds}" "5400"
  dybatpho::date_parse_duration seconds 2d
  assert_equal "${seconds}" "172800"
  dybatpho::date_parse_duration seconds "1w 2d 3h 4m 5s"
  assert_equal "${seconds}" "788645"
  dybatpho::date_parse_duration seconds 007s
  assert_equal "${seconds}" "7"
  dybatpho::date_parse_duration seconds 0
  assert_equal "${seconds}" "0"
  dybatpho::date_parse_duration seconds -5m
  assert_equal "${seconds}" "-300"
  # A negative zero is still zero.
  dybatpho::date_parse_duration seconds -0s
  assert_equal "${seconds}" "0"
}

@test "dybatpho::date_parse_duration undoes date_seconds_to_hms" {
  local seconds total
  for total in 0 59 3661 90000 -61; do
    dybatpho::date_parse_duration seconds "$(dybatpho::date_seconds_to_hms "${total}")"
    assert_equal "${seconds}" "${total}"
  done
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds 1:60:00
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds 1:5:00
}

@test "dybatpho::date_parse_duration reads ISO 8601 without calendar units" {
  local seconds
  dybatpho::date_parse_duration seconds PT1H30M
  assert_equal "${seconds}" "5400"
  dybatpho::date_parse_duration seconds P1DT2H
  assert_equal "${seconds}" "93600"
  dybatpho::date_parse_duration seconds P2W
  assert_equal "${seconds}" "1209600"
  dybatpho::date_parse_duration seconds PT45S
  assert_equal "${seconds}" "45"
  # Months and years depend on the calendar, as they do for date_add.
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds P1M
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds P1Y
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds P
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds PT
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds P1DT
}

@test "dybatpho::date_parse_duration refuses malformed input and leaves the target alone" {
  local seconds=unchanged input
  for input in "" h 1x 1.5h 1h1h 30m1h 1M "1h " " 1h" - --5 1y; do
    run_traced --separate-stderr ! dybatpho::date_parse_duration seconds "${input}"
    assert_stderr --partial "is not a duration"
  done
  dybatpho::date_parse_duration seconds bogus 2> /dev/null || true
  assert_equal "${seconds}" "unchanged"
  run ! dybatpho::date_parse_duration "not a name" 5m
}

@test "dybatpho::date_parse_duration refuses a duration Bash cannot count" {
  local seconds
  dybatpho::date_parse_duration seconds 9223372036854775807
  assert_equal "${seconds}" "9223372036854775807"
  dybatpho::date_parse_duration seconds 0009223372036854775807
  assert_equal "${seconds}" "9223372036854775807"
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds 9223372036854775808
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds 99999999999999999999
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds 15250284452472w
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds 1w9223372036854775807
  run_traced --separate-stderr ! dybatpho::date_parse_duration seconds P15250284452472W
}

@test "dybatpho::date_is_before and date_is_after order two dates strictly" {
  run_traced dybatpho::date_is_before 2024-02-28 2024-02-29
  assert_success
  run_traced ! dybatpho::date_is_before 2024-02-29 2024-02-28
  # The same moment is neither before nor after itself, however it is spelled.
  run_traced ! dybatpho::date_is_before 2024-02-29 "2024-02-29 00:00:00"
  run_traced ! dybatpho::date_is_after 2024-02-29 "2024-02-29 00:00:00"
  run_traced dybatpho::date_is_after 2024-03-01 2024-02-29
  assert_success
  run_traced ! dybatpho::date_is_after 2024-02-29 2024-03-01
  run_traced dybatpho::date_is_before "2024-02-29 12:00:00" "2024-02-29 12:00:01"
  assert_success
}

@test "dybatpho::date_is_before and date_is_after stop on a date they cannot read" {
  # Answering "no" for an unparseable date would read as a real answer.
  run --separate-stderr dybatpho::date_is_before 2024-02-30 2024-03-01
  assert_failure
  assert_stderr --partial "'2024-02-30' is not a valid date"
  run --separate-stderr dybatpho::date_is_after 2024-03-01 nope
  assert_failure
  assert_stderr --partial "'nope' is not a valid date"
}

@test "dybatpho::date_iso_week names the week-year beside the week" {
  assert_equal "$(dybatpho::date_iso_week 2024-02-29)" "2024-W09"
  # The first days of January can belong to the last week of the year before.
  assert_equal "$(dybatpho::date_iso_week 2021-01-01)" "2020-W53"
  assert_equal "$(dybatpho::date_iso_week 2016-01-03)" "2015-W53"
  assert_equal "$(dybatpho::date_iso_week 2027-01-03)" "2026-W53"
  # And the last days of December to week 1 of the next.
  assert_equal "$(dybatpho::date_iso_week 2024-12-30)" "2025-W01"
  assert_equal "$(dybatpho::date_iso_week 2026-01-01)" "2026-W01"
  # A year that starts on a Thursday has 53 weeks; a leap year starting on a
  # Wednesday does too, and an ordinary one has 52.
  assert_equal "$(dybatpho::date_iso_week 2020-12-31)" "2020-W53"
  assert_equal "$(dybatpho::date_iso_week 2015-12-31)" "2015-W53"
  assert_equal "$(dybatpho::date_iso_week 2023-12-31)" "2023-W52"
}

@test "dybatpho::date_iso_week writes the format it is given" {
  assert_equal "$(dybatpho::date_iso_week 2024-12-30 '%G%V')" "202501"
  assert_equal "$(dybatpho::date_iso_week 2024-02-29 '%G-W%V-%u')" "2024-W09-4"
  assert_equal "$(dybatpho::date_iso_week 2024-03-03 '%u')" "7"
  assert_equal "$(dybatpho::date_iso_week 2024-02-29 '%%V=%V %x %')" "%V=09 %x %"
  run_traced ! dybatpho::date_iso_week 2024-02-30
}

@test "dybatpho::date_in_tz writes a date as another timezone reads it" {
  [[ -f "${TZDIR:-/usr/share/zoneinfo}/Asia/Tokyo" ]] || skip "no zone database"
  assert_equal "$(dybatpho::date_in_tz '2024-02-29 12:00:00' Asia/Tokyo)" "2024-02-29 21:00:00 +0900"
  assert_equal "$(dybatpho::date_in_tz '2024-02-29 12:00:00' UTC '%F %T')" "2024-02-29 12:00:00"
  # The input is read in the module's timezone, and daylight saving applies.
  assert_equal \
    "$(DYBATPHO_DATE_TIMEZONE=Europe/Paris dybatpho::date_in_tz '2024-07-01 09:00:00' America/New_York '%F %R')" \
    "2024-07-01 03:00"
  run_traced ! dybatpho::date_in_tz 2024-02-30 Asia/Tokyo
}

@test "dybatpho::date_in_tz refuses a zone date would quietly treat as UTC" {
  run --separate-stderr dybatpho::date_in_tz 2024-02-29 Mars/Base
  assert_failure
  assert_stderr --partial "'Mars/Base' is not a timezone"
  run --separate-stderr ! dybatpho::date_in_tz 2024-02-29 ../../etc/passwd
  run --separate-stderr ! dybatpho::date_in_tz 2024-02-29 /usr/share/zoneinfo/UTC
  run --separate-stderr ! dybatpho::date_in_tz 2024-02-29 "EST5EDT,M3.2.0,M11.1.0"
  # A zone database moved elsewhere is followed through TZDIR.
  mkdir -p "${BATS_TEST_TMPDIR}/zones/Test"
  cp "${TZDIR:-/usr/share/zoneinfo}/UTC" "${BATS_TEST_TMPDIR}/zones/Test/Zone" 2> /dev/null \
    || skip "no zone database"
  TZDIR="${BATS_TEST_TMPDIR}/zones" run_traced dybatpho::date_in_tz 2024-02-29 Test/Zone '%F'
  assert_success
  assert_output "2024-02-29"
}
