setup() {
  load test_helper
}

# ---------------------------------------------------------------------------
# dybatpho::math_is_number / dybatpho::math_is_integer
# ---------------------------------------------------------------------------

@test "dybatpho::math_is_number accepts the decimal spellings" {
  local value
  for value in 0 12 -12 +12 1.5 -0.5 +.25 "7." 000123; do
    run_traced dybatpho::math_is_number "${value}"
    assert_success
  done
}

@test "dybatpho::math_is_number rejects anything that is not plain decimal" {
  local value
  for value in "" " " abc 1e3 0x10 "1,5" "1 2" "--1" "1.2.3" "."; do
    run_traced dybatpho::math_is_number "${value}"
    assert_failure
  done
}

@test "dybatpho::math_is_integer treats a zero fraction as whole" {
  run_traced dybatpho::math_is_integer "2.00"
  assert_success
  run_traced dybatpho::math_is_integer "-7"
  assert_success
  run_traced dybatpho::math_is_integer "2.01"
  assert_failure
  run_traced dybatpho::math_is_integer "abc"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::math_add / dybatpho::math_sub
# ---------------------------------------------------------------------------

@test "dybatpho::math_add is exact where floating point is not" {
  run_traced dybatpho::math_add 0.1 0.2
  assert_output "0.3"
  run_traced dybatpho::math_add 19.99 5.01 0.5
  assert_output "25.5"
}

@test "dybatpho::math_add handles signs and zero" {
  run_traced dybatpho::math_add -2.5 2.5
  assert_output "0"
  run_traced dybatpho::math_add -2 -3
  assert_output "-5"
  run_traced dybatpho::math_add -7 2
  assert_output "-5"
}

@test "dybatpho::math_add is not limited to 64 bits" {
  run_traced dybatpho::math_add 9223372036854775807 1
  assert_output "9223372036854775808"
}

@test "dybatpho::math_add dies on a value that is not a number" {
  run dybatpho::math_add 1 abc
  assert_failure
  assert_output --partial "Not a number: 'abc'"
}

@test "dybatpho::math_sub subtracts every operand from the first" {
  run_traced dybatpho::math_sub 1 0.9
  assert_output "0.1"
  run_traced dybatpho::math_sub 100 10 5
  assert_output "85"
  run_traced dybatpho::math_sub 1 6
  assert_output "-5"
  run_traced dybatpho::math_sub -1 -1
  assert_output "0"
}

# ---------------------------------------------------------------------------
# dybatpho::math_mul / dybatpho::math_div
# ---------------------------------------------------------------------------

@test "dybatpho::math_mul keeps every digit of both operands" {
  run_traced dybatpho::math_mul 19.99 3
  assert_output "59.97"
  run_traced dybatpho::math_mul 0.1 0.2
  assert_output "0.02"
  run_traced dybatpho::math_mul 99999999999 99999999999
  assert_output "9999999999800000000001"
}

@test "dybatpho::math_mul follows the sign rules and absorbs zero" {
  run_traced dybatpho::math_mul -2 3
  assert_output "-6"
  run_traced dybatpho::math_mul -2 -3
  assert_output "6"
  run_traced dybatpho::math_mul -2 0
  assert_output "0"
  run_traced dybatpho::math_mul 2 3 4
  assert_output "24"
}

@test "dybatpho::math_div rounds half away from zero at the requested scale" {
  run_traced dybatpho::math_div 10 4
  assert_output "2.5"
  run_traced dybatpho::math_div 2 3 5
  assert_output "0.66667"
  run_traced dybatpho::math_div 1 3 0
  assert_output "0"
  run_traced dybatpho::math_div 2 3 0
  assert_output "1"
  run_traced dybatpho::math_div 1 -2
  assert_output "-0.5"
}

@test "dybatpho::math_div divides values smaller than the divisor" {
  run_traced dybatpho::math_div 0.001 4 5
  assert_output "0.00025"
}

@test "dybatpho::math_div takes its default scale from the environment" {
  DYBATPHO_MATH_SCALE=2 run_traced dybatpho::math_div 2 3
  assert_output "0.67"
}

@test "dybatpho::math_div dies on a zero divisor" {
  run dybatpho::math_div 1 0
  assert_failure
  assert_output --partial "Division by zero"
  run dybatpho::math_div 1 0.0
  assert_failure
}

@test "dybatpho::math_div dies on a scale that is not a count" {
  run dybatpho::math_div 1 2 -1
  assert_failure
  assert_output --partial "Scale must be a non-negative integer"
}

# ---------------------------------------------------------------------------
# dybatpho::math_mod / dybatpho::math_pow
# ---------------------------------------------------------------------------

@test "dybatpho::math_mod takes its sign from the dividend" {
  run_traced dybatpho::math_mod 17 5
  assert_output "2"
  run_traced dybatpho::math_mod -17 5
  assert_output "-2"
  run_traced dybatpho::math_mod 17 -5
  assert_output "2"
  run_traced dybatpho::math_mod 10 5
  assert_output "0"
}

@test "dybatpho::math_mod refuses fractions and a zero divisor" {
  run dybatpho::math_mod 1.5 2
  assert_failure
  assert_output --partial "Expected whole numbers"
  run dybatpho::math_mod 5 0
  assert_failure
  assert_output --partial "Division by zero"
}

@test "dybatpho::math_pow raises to a whole power exactly" {
  run_traced dybatpho::math_pow 2 10
  assert_output "1024"
  run_traced dybatpho::math_pow 1.05 3
  assert_output "1.157625"
  run_traced dybatpho::math_pow 5 0
  assert_output "1"
  run_traced dybatpho::math_pow -2 3
  assert_output "-8"
}

@test "dybatpho::math_pow divides for a negative exponent" {
  run_traced dybatpho::math_pow 2 -3
  assert_output "0.125"
  run_traced dybatpho::math_pow 3 -1 4
  assert_output "0.3333"
  run dybatpho::math_pow 0 -1
  assert_failure
  assert_output --partial "Zero cannot be raised to a negative power"
}

@test "dybatpho::math_pow refuses an exponent it cannot finish" {
  run dybatpho::math_pow 2 1.5
  assert_failure
  assert_output --partial "Exponent must be a whole number"
  run dybatpho::math_pow 2 99999
  assert_failure
  assert_output --partial "Exponent magnitude must be at most"
}

# ---------------------------------------------------------------------------
# dybatpho::math_abs / dybatpho::math_neg / comparisons
# ---------------------------------------------------------------------------

@test "dybatpho::math_abs and dybatpho::math_neg normalize the sign" {
  run_traced dybatpho::math_abs -12.5
  assert_output "12.5"
  run_traced dybatpho::math_abs 12.5
  assert_output "12.5"
  run_traced dybatpho::math_neg 12.5
  assert_output "-12.5"
  run_traced dybatpho::math_neg -12.5
  assert_output "12.5"
  run_traced dybatpho::math_neg 0
  assert_output "0"
  run_traced dybatpho::math_neg -0.0
  assert_output "0"
}

@test "dybatpho::math_compare orders by value rather than by string" {
  run_traced dybatpho::math_compare 1.10 1.9
  assert_output "-1"
  run_traced dybatpho::math_compare 2.50 2.5
  assert_output "0"
  run_traced dybatpho::math_compare 10 9
  assert_output "1"
  run_traced dybatpho::math_compare -1 -2
  assert_output "1"
  run_traced dybatpho::math_compare -1 1
  assert_output "-1"
  run_traced dybatpho::math_compare -0.0 0
  assert_output "0"
}

@test "dybatpho::math_gt, math_lt and math_eq report through the exit code" {
  run_traced dybatpho::math_gt 2 1
  assert_success
  run_traced dybatpho::math_gt 1 2
  assert_failure
  run_traced dybatpho::math_lt 1 2
  assert_success
  run_traced dybatpho::math_lt 2 1
  assert_failure
  run_traced dybatpho::math_eq 2.50 2.5
  assert_success
  run_traced dybatpho::math_eq 2.5 2.6
  assert_failure
}

# ---------------------------------------------------------------------------
# rounding
# ---------------------------------------------------------------------------

@test "dybatpho::math_trunc drops the fraction toward zero" {
  run_traced dybatpho::math_trunc 2.9
  assert_output "2"
  run_traced dybatpho::math_trunc -2.9
  assert_output "-2"
  run_traced dybatpho::math_trunc 0.9
  assert_output "0"
}

@test "dybatpho::math_floor and dybatpho::math_ceil round in one direction" {
  run_traced dybatpho::math_floor 2.9
  assert_output "2"
  run_traced dybatpho::math_floor -2.1
  assert_output "-3"
  run_traced dybatpho::math_floor 3
  assert_output "3"
  run_traced dybatpho::math_ceil 2.1
  assert_output "3"
  run_traced dybatpho::math_ceil -2.9
  assert_output "-2"
  run_traced dybatpho::math_ceil 3
  assert_output "3"
}

@test "dybatpho::math_round rounds halves away from zero" {
  run_traced dybatpho::math_round 2.665 2
  assert_output "2.67"
  run_traced dybatpho::math_round 1.005 2
  assert_output "1.01"
  run_traced dybatpho::math_round 0.5
  assert_output "1"
  run_traced dybatpho::math_round -0.5
  assert_output "-1"
  run_traced dybatpho::math_round 2.4
  assert_output "2"
  run_traced dybatpho::math_round 9.99 1
  assert_output "10"
}

@test "dybatpho::math_round rejects a scale that is not a count" {
  run dybatpho::math_round 1.5 x
  assert_failure
  assert_output --partial "Scale must be a non-negative integer"
}

# ---------------------------------------------------------------------------
# aggregates
# ---------------------------------------------------------------------------

@test "dybatpho::math_min and dybatpho::math_max answer with the written value" {
  run_traced dybatpho::math_min 3 1.5 2
  assert_output "1.5"
  run_traced dybatpho::math_max 3 1.5 2
  assert_output "3"
  run_traced dybatpho::math_min -3 -1 0
  assert_output "-3"
  run_traced dybatpho::math_max 2.50 2.5
  assert_output "2.50"
}

@test "dybatpho::math_min and dybatpho::math_max read standard input" {
  assert_equal "$(printf '3\n1.5\n2\n' | dybatpho::math_min)" "1.5"
  assert_equal "$(printf '3 1.5\n2\n' | dybatpho::math_max)" "3"
}

@test "dybatpho::math_min dies on an empty list" {
  run dybatpho::math_min < /dev/null
  assert_failure
  assert_output --partial "Expected at least one value"
}

@test "dybatpho::math_max dies on an empty list" {
  run dybatpho::math_max < /dev/null
  assert_failure
  assert_output --partial "Expected at least one value"
}

@test "dybatpho::math_sum totals arguments and standard input" {
  run_traced dybatpho::math_sum 19.99 5.01 0.5
  assert_output "25.5"
  assert_equal "$(printf '1.5\n2.5\n' | dybatpho::math_sum)" "4"
}

@test "dybatpho::math_sum reads a glob character on standard input literally" {
  # Values on a line were split by an unquoted expansion, which also expanded
  # `*` to the names of the files in the working directory.
  local dir="${BATS_TEST_TMPDIR}/glob"
  mkdir -p "${dir}"
  : > "${dir}/9"
  cd "${dir}"
  run --separate-stderr dybatpho::math_sum < <(printf '1 * 3\n')
  assert_failure
  assert_stderr --partial "Not a number: '*'"

  assert_equal "$(printf '1 2\n3\n' | dybatpho::math_sum)" "6"
}

@test "dybatpho::math_sum reads a last line that has no newline" {
  # `printf` and `<<<`-less pipelines often end without one; the last value
  # still counts.
  assert_equal "$(printf '1 2\n3' | dybatpho::math_sum)" "6"
  assert_equal "$(printf '4' | dybatpho::math_max)" "4"
}

@test "dybatpho::math_sum of nothing is zero" {
  assert_equal "$(dybatpho::math_sum < /dev/null)" "0"
}

@test "dybatpho::math_avg divides the total by the count" {
  run_traced dybatpho::math_avg 10 20 30
  assert_output "20"
  run_traced dybatpho::math_avg 10 20 25
  assert_output "18.3333333333"
  DYBATPHO_MATH_SCALE=2 run_traced dybatpho::math_avg 10 20 25
  assert_output "18.33"
}

@test "dybatpho::math_avg dies on an empty list" {
  run dybatpho::math_avg < /dev/null
  assert_failure
  assert_output --partial "Expected at least one value"
}


# ---------------------------------------------------------------------------
# statistics
# ---------------------------------------------------------------------------

@test "dybatpho::math_median answers the middle value as written" {
  run_traced dybatpho::math_median 7 1 3
  assert_output "3"
  run_traced dybatpho::math_median 5
  assert_output "5"
  run_traced dybatpho::math_median 010 9 011
  assert_output "010"
}

@test "dybatpho::math_median averages the two middle values exactly" {
  run_traced dybatpho::math_median 1 2 3 10
  assert_output "2.5"
  run_traced dybatpho::math_median -1.5 2
  assert_output "0.25"
  run_traced dybatpho::math_median 0.1 0.2
  assert_output "0.15"
}

@test "dybatpho::math_median orders decimals and negatives by value" {
  run_traced dybatpho::math_median 1.10 1.9 -3 -20 0
  assert_output "0"
  run_traced dybatpho::math_median 99999999999999999999 1 2
  assert_output "2"
}

@test "dybatpho::math_median reads standard input" {
  assert_equal "$(printf '3 1\n2\n' | dybatpho::math_median)" "2"
}

@test "dybatpho::math_median dies on an empty list" {
  run dybatpho::math_median < /dev/null
  assert_failure
  assert_output --partial "Expected at least one value"
}

@test "dybatpho::math_median dies on a value that is not a number" {
  run dybatpho::math_median 1 x
  assert_failure
  assert_output --partial "dybatpho::math_median: Not a number: 'x'"
}

@test "dybatpho::math_percentile interpolates between the nearest ranks" {
  run_traced dybatpho::math_percentile 90 1 2 3 4 5 6 7 8 9 10
  assert_output "9.1"
  run_traced dybatpho::math_percentile 25 1.5 -2 10 0.25
  assert_output "-0.3125"
  run_traced dybatpho::math_percentile 99.9 0 1000
  assert_output "999"
}

@test "dybatpho::math_percentile meets the minimum, median and maximum" {
  run_traced dybatpho::math_percentile 0 3 1 2
  assert_output "1"
  run_traced dybatpho::math_percentile 50 3 1 2
  assert_output "2"
  run_traced dybatpho::math_percentile 100 3 1 2
  assert_output "3"
  run_traced dybatpho::math_percentile 75 42
  assert_output "42"
}

@test "dybatpho::math_percentile reads standard input" {
  assert_equal "$(seq 1 100 | dybatpho::math_percentile 99)" "99.01"
}

@test "dybatpho::math_percentile dies on a percentile outside 0 to 100" {
  local percentile
  for percentile in 101 -1 abc 1e2; do
    run dybatpho::math_percentile "${percentile}" 1 2
    assert_failure
    assert_output --partial "Percentile must be a number from 0 to 100, got '${percentile}'"
  done
}

@test "dybatpho::math_percentile dies on an empty list" {
  run dybatpho::math_percentile 50 < /dev/null
  assert_failure
  assert_output --partial "Expected at least one value"
}

@test "dybatpho::math_sqrt is exact where the root is" {
  run_traced dybatpho::math_sqrt 16
  assert_output "4"
  run_traced dybatpho::math_sqrt 0.25
  assert_output "0.5"
  run_traced dybatpho::math_sqrt 0
  assert_output "0"
  run_traced dybatpho::math_sqrt 152415787532388367504942236884722755800955129
  assert_output "12345678901234567890123"
}

@test "dybatpho::math_sqrt rounds half away from zero at the scale" {
  run_traced dybatpho::math_sqrt 2
  assert_output "1.4142135624"
  run_traced dybatpho::math_sqrt 2 5
  assert_output "1.41421"
  run_traced dybatpho::math_sqrt 8 0
  assert_output "3"
  run_traced dybatpho::math_sqrt 0.0001 2
  assert_output "0.01"
  run_traced dybatpho::math_sqrt 0.000001234 3
  assert_output "0.001"
}

@test "dybatpho::math_sqrt dies on a negative value" {
  run dybatpho::math_sqrt -4
  assert_failure
  assert_output --partial "No square root of a negative number: '-4'"
}

@test "dybatpho::math_sqrt dies on a bad scale or a non-number" {
  run dybatpho::math_sqrt 4 x
  assert_failure
  assert_output --partial "Scale must be a non-negative integer, got 'x'"
  run dybatpho::math_sqrt four
  assert_failure
  assert_output --partial "Not a number: 'four'"
}

@test "dybatpho::math_stddev is the population deviation by default" {
  run_traced dybatpho::math_stddev 2 4 4 4 5 5 7 9
  assert_output "2"
  run_traced dybatpho::math_stddev 5
  assert_output "0"
  run_traced dybatpho::math_stddev -1 1
  assert_output "1"
  run_traced dybatpho::math_stddev 1.5 2.5
  assert_output "0.5"
  run_traced dybatpho::math_stddev 0.1 0.3
  assert_output "0.1"
  DYBATPHO_MATH_SCALE=3 run_traced dybatpho::math_stddev 1 2 3 4
  assert_output "1.118"
}

@test "dybatpho::math_stddev --sample divides by one less than the count" {
  run_traced dybatpho::math_stddev --sample 2 4 4 4 5 5 7 9
  assert_output "2.1380899353"
  assert_equal "$(printf '10 20\n' | dybatpho::math_stddev --sample)" "7.0710678119"
}

@test "dybatpho::math_stddev dies on an empty list or a lone sample" {
  run dybatpho::math_stddev < /dev/null
  assert_failure
  assert_output --partial "Expected at least one value"
  run dybatpho::math_stddev --sample 4
  assert_failure
  assert_output --partial "A sample standard deviation needs at least two values"
}

@test "dybatpho::math_stddev dies on a bad scale" {
  DYBATPHO_MATH_SCALE=x run dybatpho::math_stddev 1 2
  assert_failure
  assert_output --partial "Scale must be a non-negative integer, got 'x'"
}
# ---------------------------------------------------------------------------
# ranges and ratios
# ---------------------------------------------------------------------------

@test "dybatpho::math_clamp holds a value inside its bounds" {
  run_traced dybatpho::math_clamp 42 0 10
  assert_output "10"
  run_traced dybatpho::math_clamp -3 0 10
  assert_output "0"
  run_traced dybatpho::math_clamp 7.5 0 10
  assert_output "7.5"
}

@test "dybatpho::math_clamp dies on reversed bounds" {
  run dybatpho::math_clamp 1 10 0
  assert_failure
  assert_output --partial "is above upper bound"
}

@test "dybatpho::math_percent reports a share of a whole" {
  run_traced dybatpho::math_percent 42 200
  assert_output "21"
  run_traced dybatpho::math_percent 1 3 2
  assert_output "33.33"
  run_traced dybatpho::math_percent 0 5
  assert_output "0"
}

@test "dybatpho::math_percent dies when the whole is zero" {
  run dybatpho::math_percent 1 0
  assert_failure
  assert_output --partial "Division by zero"
}

# ---------------------------------------------------------------------------
# whole-number helpers
# ---------------------------------------------------------------------------

@test "dybatpho::math_gcd reduces every value it is given" {
  run_traced dybatpho::math_gcd 12 18
  assert_output "6"
  run_traced dybatpho::math_gcd 24 36 60
  assert_output "12"
  run_traced dybatpho::math_gcd -12 18
  assert_output "6"
  run_traced dybatpho::math_gcd 0 5
  assert_output "5"
  run_traced dybatpho::math_gcd 7 13
  assert_output "1"
}

@test "dybatpho::math_lcm multiplies without repeating a common factor" {
  run_traced dybatpho::math_lcm 4 6
  assert_output "12"
  run_traced dybatpho::math_lcm 2 3 5
  assert_output "30"
  run_traced dybatpho::math_lcm 0 5
  assert_output "0"
}

@test "dybatpho::math_gcd and dybatpho::math_lcm refuse fractions" {
  run dybatpho::math_gcd 1.5 3
  assert_failure
  assert_output --partial "Expected whole numbers"
  run dybatpho::math_lcm 1.5 3
  assert_failure
  assert_output --partial "Expected whole numbers"
}

# ---------------------------------------------------------------------------
# dybatpho::math_random
# ---------------------------------------------------------------------------

@test "dybatpho::math_random stays inside its inclusive range" {
  local draw index
  for ((index = 0; index < 50; index++)); do
    draw="$(dybatpho::math_random 1 6)"
    ((draw >= 1 && draw <= 6)) || fail "drew ${draw}, outside 1..6"
  done
  run_traced dybatpho::math_random 4 4
  assert_output "4"
}

@test "dybatpho::math_random covers a small range" {
  # Fifty draws over two values miss one of them only once in 2^49 runs, so a
  # failure here means the generator is stuck rather than unlucky.
  local -A seen=()
  local draw index
  for ((index = 0; index < 50; index++)); do
    draw="$(dybatpho::math_random 0 1)"
    seen["${draw}"]=1
  done
  assert_equal "${#seen[@]}" 2
}

@test "dybatpho::math_random accepts negative bounds" {
  local draw index
  for ((index = 0; index < 20; index++)); do
    draw="$(dybatpho::math_random -5 -1)"
    ((draw >= -5 && draw <= -1)) || fail "drew ${draw}, outside -5..-1"
  done
}

@test "dybatpho::math_random rejects bounds it cannot honor" {
  run dybatpho::math_random 5 1
  assert_failure
  assert_output --partial "is above upper bound"
  run dybatpho::math_random 1.5 6
  assert_failure
  assert_output --partial "Bounds must be whole numbers"
  run dybatpho::math_random -9999999999999999999 9999999999999999999
  assert_failure
  assert_output --partial "outside the range Bash can draw from"
}

# ---------------------------------------------------------------------------
# module contract
# ---------------------------------------------------------------------------

@test "math loads on its own, without an optional module beside it" {
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/math_alone.sh"
  printf '%s\n' ". '${DYBATPHO_DIR}/init.sh' --modules math" \
    "dybatpho::math_add 1 2" > "${script}"
  run_traced bash "${script}"
  assert_success
  assert_output "3"
}

@test "dybatpho::math_gt, math_lt and math_eq stop the script on a value that is not a number" {
  # In a condition `set -e` is off, so a refusal raised inside `$(...)` used to
  # end only the subshell: the caller read the empty answer as "no" and went
  # on. A script started from a file shows what a real caller sees.
  local script="${BATS_TEST_TMPDIR}/compare.sh" fn
  for fn in math_gt math_lt math_eq; do
    {
      printf '. %q --modules math\n' "${DYBATPHO_DIR}/init.sh"
      printf 'if dybatpho::%s abc 1; then :; fi\n' "${fn}"
      printf '%s\n' 'printf "carried on\n"'
    } > "${script}"
    run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
    assert_failure
    assert_output --partial "Not a number: 'abc'"
    refute_output --partial "carried on"
  done
}
