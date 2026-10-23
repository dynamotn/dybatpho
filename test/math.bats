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

@test "dybatpho::math_random reads a bound with a leading zero in base ten" {
  run_traced dybatpho::math_random 08 08
  assert_output "8"
  run_traced dybatpho::math_random -08 -08
  assert_output "-8"
}

# ---------------------------------------------------------------------------
# Leading zeros and 64-bit wrap in the scale and the exponent
# ---------------------------------------------------------------------------

@test "a scale written with a leading zero is read in base ten" {
  run_traced dybatpho::math_round 2.665 08
  assert_success
  assert_output "2.665"
  run_traced dybatpho::math_div 2 3 08
  assert_success
  assert_output "0.66666667"
  run_traced dybatpho::math_sqrt 2 09
  assert_success
  assert_output "1.414213562"
  DYBATPHO_MATH_SCALE=08 run_traced dybatpho::math_avg 1 2 4
  assert_success
  assert_output "2.33333333"
  DYBATPHO_MATH_SCALE=03 run_traced dybatpho::math_stddev 1 2 3 4
  assert_success
  assert_output "1.118"
}

@test "dybatpho::math_pow refuses an exponent past 64 bits instead of wrapping it" {
  # 2^64 + 1 wrapped to 1 and answered 2.
  run dybatpho::math_pow 2 18446744073709551617
  assert_failure
  assert_output --partial "Exponent magnitude must be at most"
  run_traced dybatpho::math_pow 2 0010
  assert_success
  assert_output "1024"
}

@test "dybatpho::math_percentile still interpolates through the shared sorted-list helper" {
  local value
  __dybatpho_math_percentile_sorted_into value 90 1 2 3 4 5 6 7 8 9 10
  assert_equal "${value}" "9.1"
  __dybatpho_math_percentile_sorted_into value 50 7
  assert_equal "${value}" "7"
}

# ---------------------------------------------------------------------------
# The `_into` variants
# ---------------------------------------------------------------------------

@test "dybatpho::math_add_into and dybatpho::math_sub_into fill the named variable" {
  local total=0 price scratch
  for price in 19.99 5.01 0.5; do
    dybatpho::math_add_into total "${total}" "${price}"
  done
  assert_equal "${total}" "25.5"
  run_traced dybatpho::math_add_into scratch 1 2
  assert_success
  assert_output ""
  dybatpho::math_add_into total 0.1 0.2 0.3
  assert_equal "${total}" "0.6"
  local left
  dybatpho::math_sub_into left 100 10 5
  assert_equal "${left}" "85"
  dybatpho::math_sub_into left 1 0.9
  assert_equal "${left}" "0.1"
}

@test "dybatpho::math_mul_into, dybatpho::math_div_into and dybatpho::math_round_into fill the named variable" {
  local result
  dybatpho::math_mul_into result 19.99 3
  assert_equal "${result}" "59.97"
  dybatpho::math_mul_into result 99999999999 99999999999 -1
  assert_equal "${result}" "-9999999999800000000001"
  dybatpho::math_div_into result 2 3 5
  assert_equal "${result}" "0.66667"
  DYBATPHO_MATH_SCALE=2 dybatpho::math_div_into result 10 4
  assert_equal "${result}" "2.5"
  dybatpho::math_round_into result 2.665 2
  assert_equal "${result}" "2.67"
  dybatpho::math_round_into result -0.5
  assert_equal "${result}" "-1"
  run_traced dybatpho::math_round_into result 1.005 2
  assert_success
}

@test "dybatpho::math_compare_into fills the named variable with -1, 0 or 1" {
  local order
  dybatpho::math_compare_into order 1.10 1.9
  assert_equal "${order}" "-1"
  dybatpho::math_compare_into order 2.50 +2.5
  assert_equal "${order}" "0"
  dybatpho::math_compare_into order -0 0.000
  assert_equal "${order}" "0"
  dybatpho::math_compare_into order 100000000000000000000 99999999999999999999.9
  assert_equal "${order}" "1"
  run_traced dybatpho::math_compare_into order 1 2
  assert_success
}

@test "the math _into variants stop on a bad value, scale or name" {
  run dybatpho::math_add_into total 1 abc
  assert_failure
  assert_output --partial "dybatpho::math_add_into: Not a number: 'abc'"
  run dybatpho::math_div_into total 1 0
  assert_failure
  assert_output --partial "Division by zero"
  run dybatpho::math_round_into total 1.5 x
  assert_failure
  assert_output --partial "dybatpho::math_round_into: Scale must be a non-negative integer, got 'x'"
  run dybatpho::math_sub_into "bad name" 1 2
  assert_failure
  assert_output --partial "Invalid variable name"
  run dybatpho::math_mul_into __dybatpho_x 1 2
  assert_failure
  assert_output --partial "is reserved"
}

@test "the math _into variants fill a caller variable named like their own locals" {
  # Every local carries the library prefix, so a caller's `total` or `value`
  # is the variable that gets the result.
  local a="" b="" name="" total="" operand=""
  dybatpho::math_add_into a 1 2
  dybatpho::math_sub_into b 5 2
  dybatpho::math_mul_into name 2 3
  dybatpho::math_compare_into total 2 1
  dybatpho::math_div_into operand 1 4
  assert_equal "${a}|${b}|${name}|${total}|${operand}" "3|3|6|1|0.25"
}

@test "the short-decimal arithmetic stays exact at the edge of 64 bits" {
  # Short operands add, multiply and compare in `$(( ))`; past seventeen
  # significant digits the digit path takes over, with the same answers.
  run_traced dybatpho::math_add 99999999999999999 1
  assert_output "100000000000000000"
  run_traced dybatpho::math_add 0.00000000000000001 99999999999999999
  assert_output "99999999999999999.00000000000000001"
  run_traced dybatpho::math_mul 999999999 999999999
  assert_output "999999998000000001"
  run_traced dybatpho::math_mul 9999999999 9999999999
  assert_output "99999999980000000001"
  run_traced dybatpho::math_sub 0.30 0.1 0.2
  assert_output "0"
  run_traced dybatpho::math_add -007.50 +2.25
  assert_output "-5.25"
  run_traced dybatpho::math_mul -0.5 0
  assert_output "0"
  run_traced dybatpho::math_compare 0.1 0.10000000000000000001
  assert_output "-1"
  run_traced dybatpho::math_compare -.5 -0.50
  assert_output "0"
}

# ---------------------------------------------------------------------------
# The awk engine for the list aggregates
# ---------------------------------------------------------------------------

# Values whose aggregates the two engines have to agree on, spelled the ways a
# script receives them.
math_engine_values() {
  printf '%s\n' 1.5 -2.25 +007 .5 7. -0 0.000 99999999999999999999.99999999 \
    -99999999999999999999.5 12345678901234567890.123456789012345 2.50 2.5 +2.5 \
    0.1 0.2 0.3 -.75 1000000 0.0000001 42
}

# Print every aggregate under the engine named in $1.
math_engine_run_all() {
  local -a values=()
  mapfile -t values < <(math_engine_values)
  local op
  for op in sum avg min max median "percentile 0" "percentile 33.3" "percentile 90" "percentile 100"; do
    # shellcheck disable=SC2086 # the operation's own words are split on purpose
    DYBATPHO_MATH_ENGINE="$1" dybatpho::math_${op} "${values[@]}"
  done
  # The root at the end of a deviation runs in Bash on either engine, and a
  # twenty-digit spread makes it slow under the coverage trace; the sums the
  # two engines feed it are what differ, and short values exercise them.
  DYBATPHO_MATH_ENGINE="$1" dybatpho::math_stddev 1.5 -2.25 +007 .5 7. -0 2.50 2.5 0.1 0.3 42 -.75
  DYBATPHO_MATH_ENGINE="$1" dybatpho::math_stddev --sample 1.5 -2.25 +007 .5 7. -0 2.50 2.5 0.1 0.3 42 -.75
  # Equal values written differently: the median is the middle one as written.
  DYBATPHO_MATH_ENGINE="$1" dybatpho::math_median 2.50 2.5 +2.5 2.500 1
  math_engine_values | DYBATPHO_MATH_ENGINE="$1" dybatpho::math_sum
}

# Print every aggregate under the engine named in $1, with the trace off.
# Under kcov, coverage is read from the trace, and kcov keeps what it reads
# until it exits; a reference answer, or the same Bash run again for another
# awk, adds no coverage but took gigabytes, and the runner killed the run.
math_engine_run_all_untraced() {
  (
    set +x
    math_engine_run_all "$1"
  )
}

@test "DYBATPHO_MATH_ENGINE=awk prints what the Bash engine prints" {
  local expected
  expected="$(math_engine_run_all_untraced bash)"
  run_traced math_engine_run_all awk
  assert_success
  assert_output "${expected}"
  assert_line --index 0 "12345678901235567953.723456879012345"
}

@test "the math awk engine agrees with the Bash engine under every awk installed" {
  local expected flavor found=0 bin
  expected="$(math_engine_run_all_untraced bash)"
  for flavor in awk gawk mawk original-awk nawk /usr/bin/awk busybox; do
    command -v "${flavor}" > /dev/null || continue
    if [[ "${flavor}" == "busybox" ]]; then
      busybox awk 'BEGIN { }' 2> /dev/null || continue
    fi
    bin="${BATS_TEST_TMPDIR}/awk-${flavor//\//_}"
    mkdir -p "${bin}"
    if [[ "${flavor}" == "busybox" ]]; then
      printf '#!/bin/sh\nexec busybox awk "$@"\n' > "${bin}/awk"
    else
      printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v "${flavor}")" > "${bin}/awk"
    fi
    chmod +x "${bin}/awk"
    # The Bash side is the same for every flavor, and the test above traces it.
    PATH="${bin}:${PATH}" run_traced math_engine_run_all_untraced awk
    assert_success
    assert_output "${expected}"
    found=$((found + 1))
  done
  ((found > 0))
}

@test "the math awk engine hands a value that is not a number to the Bash engine" {
  local engine
  for engine in bash awk; do
    DYBATPHO_MATH_ENGINE="${engine}" run dybatpho::math_sum 1 2 abc 3
    assert_failure
    assert_output --partial "dybatpho::math_sum: Not a number: 'abc'"
    DYBATPHO_MATH_ENGINE="${engine}" run dybatpho::math_median 1 1e3
    assert_failure
    assert_output --partial "dybatpho::math_median: Not a number: '1e3'"
    DYBATPHO_MATH_ENGINE="${engine}" run dybatpho::math_max 1 $'2\n3'
    assert_failure
    assert_output --partial "Not a number"
  done
}

@test "DYBATPHO_MATH_ENGINE picks the engine and refuses one it does not know" {
  local bin="${BATS_TEST_TMPDIR}/awk-log"
  local -a many=()
  mkdir -p "${bin}"
  printf '#!/bin/sh\necho run >> "%s/log"\nexec %s "$@"\n' "${bin}" "$(command -v awk)" > "${bin}/awk"
  chmod +x "${bin}/awk"
  mapfile -t many < <(seq 1 40)

  PATH="${bin}:${PATH}" run_traced dybatpho::math_sum 1 2 3
  assert_output "6"
  assert_file_not_exists "${bin}/log"
  PATH="${bin}:${PATH}" run_traced dybatpho::math_sum "${many[@]}"
  assert_output "820"
  assert_file_exists "${bin}/log"
  rm "${bin}/log"
  PATH="${bin}:${PATH}" DYBATPHO_MATH_ENGINE=bash run_traced dybatpho::math_sum "${many[@]}"
  assert_output "820"
  assert_file_not_exists "${bin}/log"
  PATH="$(path_without awk)" DYBATPHO_MATH_ENGINE=awk run_traced dybatpho::math_avg "${many[@]}"
  assert_output "20.5"

  DYBATPHO_MATH_ENGINE=fast run dybatpho::math_sum "${many[@]}"
  assert_failure
  assert_output --partial "dybatpho::math_sum: Unknown DYBATPHO_MATH_ENGINE: fast. Use auto, awk, or bash"
}

# ---------------------------------------------------------------------------
# The digit path, past what native arithmetic holds
# ---------------------------------------------------------------------------

@test "the digit path reads a leading plus and leading zeros" {
  run_traced dybatpho::math_add +0012345678901234567890 1
  assert_output "12345678901234567891"
  run_traced dybatpho::math_add -1 123456789012345678901
  assert_output "123456789012345678900"
}

@test "dybatpho::math_compare orders long values of opposite signs" {
  run_traced dybatpho::math_compare 123456789012345678901 -1
  assert_output "1"
  run_traced dybatpho::math_compare -123456789012345678901 1
  assert_output "-1"
}

@test "dybatpho::math_mod divides by a divisor longer than seventeen digits" {
  # Twice the divisor less one: the estimated quotient digit comes out one too
  # high and the exact check corrects it.
  run_traced dybatpho::math_mod 200000000000000017 100000000000000009
  assert_output "100000000000000008"
  # A nineteen-digit remainder estimates from its leading eighteen digits.
  run_traced dybatpho::math_mod 3000000000000000002 1000000000000000001
  assert_output "1000000000000000000"
}

@test "the Bash engine sorts a value written with a plus sign by value" {
  DYBATPHO_MATH_ENGINE=bash run_traced dybatpho::math_median +2.5 1.5 -0.5
  assert_output "1.5"
}
