setup() {
  load test_helper
  # Color is decided rather than detected, so the assertions below do not
  # depend on whether the suite runs attached to a terminal.
  export DYBATPHO_DIFF_COLOR=false
  FIRST="${BATS_TEST_TMPDIR}/a.txt"
  SECOND="${BATS_TEST_TMPDIR}/b.txt"
  printf 'alpha\nbeta\ngamma\n' > "${FIRST}"
  printf 'alpha\nBETA\ngamma\ndelta\n' > "${SECOND}"
}

@test "dybatpho::diff_text prints a unified diff and reports the difference" {
  run_traced -1 dybatpho::diff_text "${FIRST}" "${SECOND}" current proposed
  assert_output << EOF
--- current
+++ proposed
@@ -1,3 +1,4 @@
 alpha
-beta
+BETA
 gamma
+delta
EOF
}

@test "dybatpho::diff_text says nothing and succeeds when the two are identical" {
  run_traced -0 dybatpho::diff_text "${FIRST}" "${FIRST}"
  assert_output ""
}

@test "dybatpho::diff_text compares literal text and names the sides a and b" {
  # A temporary path in the header would mean nothing and would differ on
  # every run.
  run_traced -1 dybatpho::diff_text "one" "two"
  assert_line --index 0 "--- a"
  assert_line --index 1 "+++ b"
  assert_line --index 3 "-one"
  assert_line --index 4 "+two"
}

@test "dybatpho::diff_text reads a side from stdin" {
  run_traced -1 dybatpho::diff_text "${FIRST}" - < "${SECOND}"
  assert_output --partial "+delta"
}

@test "dybatpho::diff_text colors the diff when asked to" {
  DYBATPHO_DIFF_COLOR=true run_traced -1 dybatpho::diff_text "one" "two"
  assert_output --partial $'\033[31m-one\033[0m'
  assert_output --partial $'\033[32m+two\033[0m'
  assert_output --partial $'\033[36m@@'
}

@test "dybatpho::diff_text honors NO_COLOR when the choice is left to detection" {
  NO_COLOR=1 DYBATPHO_DIFF_COLOR="" run_traced -1 dybatpho::diff_text "one" "two"
  refute_output --partial $'\033['
}

@test "DYBATPHO_DIFF_CONTEXT sets how much context a diff carries" {
  printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n' > "${FIRST}"
  printf 'one\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n' > "${SECOND}"

  DYBATPHO_DIFF_CONTEXT=0 run_traced -1 dybatpho::diff_text "${FIRST}" "${SECOND}" a b
  assert_output << EOF
--- a
+++ b
@@ -7 +7 @@
-seven
+SEVEN
EOF
}

@test "dybatpho::diff_summary counts added lines, removed lines and hunks" {
  run_traced -1 dybatpho::diff_summary "${FIRST}" "${SECOND}"
  assert_output "+2 -1 ~2"
}

@test "dybatpho::diff_summary reports no change for identical input" {
  run_traced -0 dybatpho::diff_summary "${FIRST}" "${FIRST}"
  assert_output "+0 -0 ~0"
}

@test "dybatpho::diff_json reports keys added, removed and changed" {
  local first="${BATS_TEST_TMPDIR}/a.json" second="${BATS_TEST_TMPDIR}/b.json"
  printf '{"replicas":2,"labels":{"app":"api"},"gone":true}' > "${first}"
  printf '{"labels":{"app":"api","tier":"web"},"replicas":3}' > "${second}"

  run_traced -1 dybatpho::diff_json "${first}" "${second}"
  assert_output << EOF
- gone = true
+ labels.tier = "web"
~ replicas: 2 -> 3
EOF
}

@test "dybatpho::diff_json ignores key order and formatting" {
  # A line diff would call this a rewrite; comparing by path is the point of
  # the structural form.
  run_traced -0 dybatpho::diff_json '{"b":1,"a":2}' '{
    "a": 2,
    "b": 1
  }'
  assert_output ""
}

@test "dybatpho::diff_json walks into arrays by index" {
  run_traced -1 dybatpho::diff_json '{"xs":[1,2,3]}' '{"xs":[1,9,3,4]}'
  assert_output << EOF
~ xs.1: 2 -> 9
+ xs.3 = 4
EOF
}

@test "dybatpho::diff_json colors each kind of change differently" {
  DYBATPHO_DIFF_COLOR=true run_traced -1 dybatpho::diff_json '{"a":1,"b":2}' '{"a":9,"c":3}'
  assert_output --partial $'\033[33m~ a: 1 -> 9\033[0m'
  assert_output --partial $'\033[31m- b = 2\033[0m'
  assert_output --partial $'\033[32m+ c = 3\033[0m'
}

@test "dybatpho::diff_json tells an absent key from one holding null" {
  run_traced -1 dybatpho::diff_json '{"a":1,"b":null}' '{"a":1}'
  assert_output "- b = null"
}

@test "dybatpho::diff_json reports a change to an empty container" {
  # An empty object is a leaf as much as a scalar is; treating it as neither
  # would pass over a key whose value was replaced wholesale.
  run_traced -1 dybatpho::diff_json '{"a":{}}' '{"a":{"b":1}}'
  assert_output << EOF
- a = {}
+ a.b = 1
EOF
}

@test "dybatpho::diff_json compares two scalar documents" {
  run_traced -1 dybatpho::diff_json '5' '6'
  assert_output "~ .: 5 -> 6"
}

@test "dybatpho::diff_yaml compares two documents by key" {
  local first="${BATS_TEST_TMPDIR}/a.yaml" second="${BATS_TEST_TMPDIR}/b.yaml"
  printf 'replicas: 2\nlabels:\n  app: api\n' > "${first}"
  printf 'labels:\n  app: api\n  tier: web\nreplicas: 3\n' > "${second}"

  run_traced -1 dybatpho::diff_yaml "${first}" "${second}"
  assert_output << EOF
+ labels.tier = "web"
~ replicas: 2 -> 3
EOF
}

@test "dybatpho::diff_yaml treats quoting style as no change" {
  run_traced -0 dybatpho::diff_yaml "$(printf 'name: api\n')" "$(printf "name: 'api'\n")"
  assert_output ""
}

@test "dybatpho::diff_json reports when jq is not installed" {
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/no_jq.sh"
  cat > "${script}" << SCRIPT
. $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules diff
dybatpho::diff_json '{"a":1}' '{"a":2}'
SCRIPT

  PATH="$(path_without jq)" run --separate-stderr bash "${script}"
  assert_failure
  assert_stderr --partial "jq is required"
}

@test "dybatpho::assert_snapshot renders its mismatch through the diff module" {
  # The snapshot assertion used to dump a raw `diff -u`; the point of wiring it
  # here is that a failure reads like every other comparison the library shows.
  local snapshot_dir="${BATS_TEST_TMPDIR}/snapshots"
  mkdir -p "${snapshot_dir}"
  printf 'expected line\n' > "${snapshot_dir}/demo.snap"

  DYBATPHO_TEST_SNAPSHOT_DIR="${snapshot_dir}" \
    run_traced --separate-stderr -1 dybatpho::assert_snapshot demo "actual line"
  assert_stderr --partial "--- snapshot"
  assert_stderr --partial "+++ actual"
  assert_stderr --partial "-expected line"
  assert_stderr --partial "+actual line"
}

@test "dybatpho::assert_snapshot diffs the captured text even when it names a file" {
  # `dybatpho::diff_text` reads a side that names an existing file as that
  # file, so output that happens to be a path must not be resolved: the
  # snapshot is about what the command printed.
  local snapshot_dir="${BATS_TEST_TMPDIR}/snapshots"
  mkdir -p "${snapshot_dir}"
  printf 'expected\n' > "${snapshot_dir}/pathlike.snap"
  printf 'the contents of the named file\n' > "${BATS_TEST_TMPDIR}/named"

  DYBATPHO_TEST_SNAPSHOT_DIR="${snapshot_dir}" \
    run_traced --separate-stderr -1 dybatpho::assert_snapshot pathlike "${BATS_TEST_TMPDIR}/named"
  assert_stderr --partial "+${BATS_TEST_TMPDIR}/named"
  refute_stderr --partial "the contents of the named file"
}
