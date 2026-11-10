setup() {
  load test_helper
  dybatpho::profile_reset
}

# One report row, as `name calls total self`, from the TSV report.
_row() {
  dybatpho::profile_report --tsv | awk -F '\t' -v name="$1" '$1 == name { print $2, $3, $4 }'
}

@test "dybatpho::profile_begin and profile_end time nested blocks, self time apart" {
  dybatpho::profile_begin outer
  sleep 0.1
  dybatpho::profile_begin inner
  sleep 0.2
  dybatpho::profile_end inner
  dybatpho::profile_end outer
  local calls total self
  read -r calls total self <<< "$(_row inner)"
  assert_equal "${calls}" 1
  ((${total%.*} >= 190))
  read -r calls total self <<< "$(_row outer)"
  assert_equal "${calls}" 1
  # outer's total covers inner's 200ms; its self time is its own 100ms.
  ((${total%.*} >= 290))
  ((${self%.*} >= 90 && ${self%.*} < 190))
}

@test "dybatpho::profile_report sums the calls of a block marked several times" {
  local _
  for _ in 1 2 3; do
    dybatpho::profile_begin step
    dybatpho::profile_end step
  done
  local calls total self
  read -r calls total self <<< "$(_row step)"
  assert_equal "${calls}" 3
}

@test "dybatpho::profile_end stops on a block that is not the innermost open one, or none at all" {
  run -1 --separate-stderr dybatpho::profile_end nothing
  assert_stderr --partial "No profile block is open"
  dybatpho::profile_begin outer
  dybatpho::profile_begin inner
  run -1 --separate-stderr dybatpho::profile_end outer
  assert_stderr --partial "profile_end outer, but the innermost open block is inner"
}

@test "dybatpho::profile_run returns the command's exit code and records the block either way" {
  run_traced -3 dybatpho::profile_run failing -- bash -c 'exit 3'
  local calls total self
  read -r calls total self <<< "$(_row failing)"
  assert_equal "${calls}" 1
  run_traced -0 dybatpho::profile_run passing -- true
}

@test "dybatpho::profile_report prints a sorted table, or TSV with a header" {
  dybatpho::profile_run quick -- true
  dybatpho::profile_run slow -- sleep 0.1
  run_traced -0 dybatpho::profile_report --tsv
  assert_line --index 0 $'name\tcalls\ttotal_ms\tself_ms'
  assert_line --index 1 --regexp $'^slow\t1\t[0-9]+\\.[0-9]{3}\t[0-9]+\\.[0-9]{3}$'
  assert_line --index 2 --partial $'quick\t1\t'
  run_traced -0 dybatpho::profile_report
  assert_line --index 0 --regexp '^name +calls +total ms +self ms$'
  assert_line --index 1 --regexp '^slow '
}

@test "dybatpho::profile_reset forgets every record and open block" {
  dybatpho::profile_run finished -- true
  dybatpho::profile_begin left-open
  dybatpho::profile_reset
  run_traced -0 dybatpho::profile_report --tsv
  assert_output $'name\tcalls\ttotal_ms\tself_ms'
  run -1 --separate-stderr dybatpho::profile_end left-open
}

# Run a script in a fresh Bash, with the library loaded, from a file.
_profile_child() {
  local script="${BATS_TEST_TMPDIR}/child.sh"
  # shellcheck disable=SC2154 # DYBATPHO_DIR is set by test_helper
  printf '%s\n' ". '${DYBATPHO_DIR}/init.sh' --modules profile" "$@" > "${script}"
  bash "${script}"
}

@test "dybatpho::profile_start times every function under DYBATPHO_PROFILE=true" {
  ((BASH_VERSINFO[0] >= 5)) || skip "per-function timing needs Bash 5"
  run -0 _profile_child \
    'g() { sleep 0.1; }' \
    'f() { sleep 0.1; g; }' \
    'DYBATPHO_PROFILE=true' \
    'dybatpho::profile_start' 'f' 'dybatpho::profile_stop' \
    'dybatpho::profile_report --tsv'
  assert_line --regexp $'^f\t1\t'
  assert_line --regexp $'^g\t1\t'
  refute_line --regexp '(^|\t)(__)?dybatpho'
  local f_total g_total
  f_total="$(awk -F '\t' '$1 == "f" { print int($3) }' <<< "${output}")"
  g_total="$(awk -F '\t' '$1 == "g" { print int($3) }' <<< "${output}")"
  ((f_total >= g_total + 90))
}

@test "dybatpho::profile_start does nothing unless DYBATPHO_PROFILE asks, and puts a visible caller trap back" {
  run -0 _profile_child \
    "trap 'true' DEBUG" \
    'f() { true; }' \
    'dybatpho::profile_start' 'f' 'dybatpho::profile_stop' \
    'dybatpho::profile_report --tsv' \
    'trap -p DEBUG'
  refute_line --regexp $'^f\t'
  assert_line "trap -- 'true' DEBUG"
  ((BASH_VERSINFO[0] >= 5)) || skip "the profiled half needs Bash 5"
  # A function sees the caller's DEBUG trap only under functrace, as under Bats.
  run -0 _profile_child \
    'set -T' "trap 'true' DEBUG" \
    'f() { true; }' \
    'DYBATPHO_PROFILE=true' \
    'dybatpho::profile_start' 'f' 'dybatpho::profile_stop' \
    'trap -p DEBUG'
  assert_line "trap -- 'true' DEBUG"
}

@test "dybatpho::profile_report never evaluates a block name" {
  local name="x\$(touch ${BATS_TEST_TMPDIR}/pwned)"
  dybatpho::profile_run "${name}" -- true
  dybatpho::profile_run other -- true
  dybatpho::profile_report --tsv > /dev/null
  assert_file_not_exists "${BATS_TEST_TMPDIR}/pwned"
}
