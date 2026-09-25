setup() {
  load test_helper
}

@test "dybatpho::table_print aligns delimited rows into columns" {
  run_traced dybatpho::table_print $'Name|Role|State\nAlice|Dev|Active\nBob|Ops|Paused'
  assert_success
  assert_output << EOF
Name   Role  State
Alice  Dev   Active
Bob    Ops   Paused
EOF
}

@test "dybatpho::table_box renders a boxed table with a header separator" {
  run_traced dybatpho::table_box $'Name|Role\nAlice|Dev\nBob|Ops'
  assert_success
  assert_output << EOF
┌───────┬──────┐
│ Name  │ Role │
├───────┼──────┤
│ Alice │ Dev  │
│ Bob   │ Ops  │
└───────┴──────┘
EOF
}

@test "dybatpho::table_markdown renders a markdown table and honors custom delimiters" {
  run_traced dybatpho::table_markdown $'Name,Role\nAlice,Dev\nBob,Ops' ","
  assert_success
  assert_output << EOF
| Name  | Role |
| ----- | ---- |
| Alice | Dev  |
| Bob   | Ops  |
EOF
}

@test "dybatpho::table_print reads from stdin when input is -" {
  run_traced dybatpho::table_print - <<< $'Name|Role\nAlice|Dev\nBob|Ops\n'
  assert_success
  assert_output << EOF
Name   Role
Alice  Dev
Bob    Ops
EOF
}

@test "dybatpho::table_align supports per-column alignment and custom gap width" {
  run_traced dybatpho::table_align $'Name|Count\nApples|3\nPears|12' "|" "left,right" 3
  assert_success
  assert_output << EOF
Name   Count
Apples     3
Pears     12
EOF
}

@test "dybatpho::table_csv renders comma-delimited rows in plain and markdown styles" {
  run_traced dybatpho::table_csv $'Name,Count\nApples,3\nPears,12' plain "left,right"
  assert_success
  assert_output << EOF
Name    Count
Apples      3
Pears      12
EOF

  run_traced dybatpho::table_csv $'Name,Count\nApples,3\nPears,12' markdown
  assert_success
  assert_output << EOF
| Name   | Count |
| ------ | ----- |
| Apples | 3     |
| Pears  | 12    |
EOF
}

@test "dybatpho::table_align centers cells and clamps oversized content" {
  run_traced dybatpho::table_align $'Name|Count\nApples|3\nOk|12' "|" "center,center" 2
  assert_success
  assert_line --index 0 --partial " Name   Count"
  assert_line --index 1 --partial "Apples    3"
  assert_line --index 2 --partial "  Ok     12"
}

@test "dybatpho::table_csv renders the box style" {
  run_traced dybatpho::table_csv $'Name,Count\nApples,3' box
  assert_success
  assert_line --index 0 "┌────────┬───────┐"
}

@test "dybatpho::table_markdown widens narrow separators to three dashes" {
  run_traced dybatpho::table_markdown $'A|B\n1|2' "|"
  assert_success
  assert_line --index 1 "| --- | --- |"
}

@test "dybatpho::table_print handles empty rows and cells without a display helper" {
  run_traced dybatpho::table_print $'\nAlpha|Beta' "|"
  assert_success
}

@test "dybatpho::table_align pads rows that have more cells than the first row" {
  run_traced dybatpho::table_align $'A|B\nlonger|x|extra' "|" "center,center,center"
  assert_success
  assert_line --index 1 --partial "longer"
  assert_line --index 1 --partial "extra"
}

@test "dybatpho::table_csv refuses a quoted field instead of splitting through it" {
  # It splits on every comma, so a comma inside a quoted field used to become a
  # column separator: the row gained a cell, stopped matching its header, and
  # nothing said so.
  run --separate-stderr dybatpho::table_csv "$(printf 'name,note\n"Doe, John",ok')" markdown
  assert_failure
  assert_stderr --partial "quoted field"
  assert_stderr --partial "DYBATPHO_TABLE_CSV_STRICT=false"

  run --separate-stderr dybatpho::table_csv "$(printf 'a,b\n"He said ""hi""",x')" markdown
  assert_failure
}

@test "dybatpho::table_csv still splits when the caller says the data has no quoting" {
  # `env` cannot run a shell function, so the variable is set for the call.
  DYBATPHO_TABLE_CSV_STRICT=false \
    run_traced dybatpho::table_csv "$(printf 'name,note\n"Doe, John",ok')" markdown
  assert_success
  assert_output --partial '"Doe'
}

@test "dybatpho::table_csv leaves a quote that is not a field boundary alone" {
  # `5" pipe` is data, not CSV quoting, and refusing it would be a false alarm.
  run_traced dybatpho::table_csv "$(printf 'size,note\n5" pipe,ok')" markdown
  assert_success
  assert_output --partial '5" pipe'
}

@test "dybatpho::table_csv still reads stdin once and renders it" {
  # The check and the renderer both need the input, and standard input can only
  # be read once.
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/csv_stdin.sh"
  printf '%s\n' "printf 'web 1/1 Running\napi 1/1 Running\n' | tr -s ' ' ',' \
    | { . $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules table && dybatpho::table_csv - markdown; }" > "${script}"
  run_traced bash "${script}"
  assert_success
  assert_output --partial "Running"
}
