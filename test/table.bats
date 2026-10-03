setup() {
  load test_helper
}

@test "dybatpho::table_print aligns delimited rows into columns" {
  run_traced dybatpho::table_print $'Name|Role|State\nAlice|Dev|Active\nBob|Ops|Paused'
  assert_success
  assert_output - << EOF
Name   Role  State
Alice  Dev   Active
Bob    Ops   Paused
EOF
}

@test "dybatpho::table_box renders a boxed table with a header separator" {
  run_traced dybatpho::table_box $'Name|Role\nAlice|Dev\nBob|Ops'
  assert_success
  assert_output - << EOF
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
  assert_output - << EOF
| Name  | Role |
| ----- | ---- |
| Alice | Dev  |
| Bob   | Ops  |
EOF
}

@test "dybatpho::table_print reads from stdin when input is -" {
  run_traced dybatpho::table_print - <<< $'Name|Role\nAlice|Dev\nBob|Ops'
  assert_success
  assert_output - << EOF
Name   Role
Alice  Dev
Bob    Ops
EOF
}

@test "dybatpho::table_align supports per-column alignment and custom gap width" {
  run_traced dybatpho::table_align $'Name|Count\nApples|3\nPears|12' "|" "left,right" 3
  assert_success
  assert_output - << EOF
Name     Count
Apples       3
Pears       12
EOF
}

@test "dybatpho::table_csv renders comma-delimited rows in plain and markdown styles" {
  run_traced dybatpho::table_csv $'Name,Count\nApples,3\nPears,12' plain "left,right"
  assert_success
  assert_output - << EOF
Name    Count
Apples      3
Pears      12
EOF

  run_traced dybatpho::table_csv $'Name,Count\nApples,3\nPears,12' markdown
  assert_success
  assert_output - << EOF
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

@test "dybatpho::table_box pads a coloured cell by what the terminal shows" {
  # The escape codes used to count as columns, so a coloured cell got less
  # padding than a plain one and the right border broke out of line.
  run_traced dybatpho::table_box $'name,status\nweb,\e[32mok\e[0m\napi,down' ","
  assert_success
  assert_line --index 3 $'│ web  │ \e[32mok\e[0m     │'
  assert_line --index 4 '│ api  │ down   │'
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

@test "dybatpho::table_from_csv keeps quoted commas, quotes and line breaks in their cells" {
  local csv
  csv="$(printf 'name,note,qty\n"Doe, John",ok,3\n"He said ""hi""","line one\nline two",10\n,a|b,7')"
  run_traced dybatpho::table_from_csv "${csv}" box
  assert_success
  assert_output - << 'EOF'
┌──────────────┬───────────────────┬─────┐
│ name         │ note              │ qty │
├──────────────┼───────────────────┼─────┤
│ Doe, John    │ ok                │ 3   │
│ He said "hi" │ line one line two │ 10  │
│              │ a|b               │ 7   │
└──────────────┴───────────────────┴─────┘
EOF

  # Markdown escapes a pipe so the value cannot open a column of its own.
  run_traced dybatpho::table_from_csv "${csv}" markdown
  assert_success
  assert_line --index 4 '|              | a\|b              | 7   |'

  run_traced dybatpho::table_from_csv "${csv}" plain "left,left,right"
  assert_success
  assert_line --index 0 'name          note               qty'
  assert_line --index 1 'Doe, John     ok                   3'
}

@test "dybatpho::table_from_csv reads stdin, follows the csv delimiter and draws a lone dash" {
  DYBATPHO_CSV_DELIMITER=tab \
    run_traced dybatpho::table_from_csv - <<< "$(printf 'a\tb\n"x,y"\tz')"
  assert_success
  assert_output "$(printf 'a    b\nx,y  z')"

  # A table whose only cell is `-` is drawn, not taken as a request for stdin.
  run_traced dybatpho::table_from_csv - box <<< "-"
  assert_success
  assert_line --index 1 "│ - │"

  run_traced dybatpho::table_from_csv "" box
  assert_success
  assert_output ""
}

@test "dybatpho::table_from_json renders an array of objects from text, a file and stdin" {
  run_traced dybatpho::table_from_json '[{"name":"api","note":"a, b"},{"name":"web"}]' markdown
  assert_success
  assert_output - << 'EOF'
| name | note |
| ---- | ---- |
| api  | a, b |
| web  |      |
EOF

  local file="${BATS_TEST_TMPDIR}/rows.json"
  printf '[{"k":"v"}]' > "${file}"
  run_traced dybatpho::table_from_json "${file}"
  assert_success
  assert_output "$(printf 'k\nv')"

  # A caller's delimiter does not change how the conversion reads back.
  DYBATPHO_CSV_DELIMITER=";" \
    run_traced dybatpho::table_from_json - <<< '[{"k":"x;y"}]'
  assert_success
  assert_output "$(printf 'k\nx;y')"

  run_traced dybatpho::table_from_json ' [ ] '
  assert_success
  assert_output ""
}

@test "dybatpho::table_from_csv and table_from_json reject an unknown style" {
  run --separate-stderr dybatpho::table_from_csv "$(printf 'a\n1')" fancy
  assert_failure
  assert_stderr --partial "dybatpho::table_from_csv: Unsupported table style: fancy"

  run --separate-stderr dybatpho::table_from_json '[{"a":1}]' fancy
  assert_failure
  assert_stderr --partial "dybatpho::table_from_json: Unsupported table style: fancy"
}

@test "dybatpho::table_from_json reports a document that is not an array of objects" {
  # The conversion runs in a subshell, so its refusal comes back as a status
  # rather than ending the caller's shell.
  run_traced -1 --separate-stderr dybatpho::table_from_json '{"a":1}'
  assert_output ""
  assert_stderr --partial "not an array of objects"
}

@test "dybatpho::table_from_csv and table_from_json ask for the csv module when it is not loaded" {
  # `table` does not load `csv`, so a script that only drew plain tables does
  # not pay for the parser. A child shell started from a file, without the
  # functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules table\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'dybatpho::table_print "a,b" ","'
    printf '%s\n' "dybatpho::\${1} 'a,b' box"
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" table_from_csv
  assert_failure
  assert_line --index 0 "a  b"
  assert_output --partial "dybatpho::table_from_csv needs the csv module, load it with: dybatpho::load csv"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" table_from_json
  assert_failure
  assert_output --partial "dybatpho::table_from_json needs the csv module, load it with: dybatpho::load csv"

  # Once the script loads it, the same call renders.
  sed -i 's/--modules table/--modules table csv/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" table_from_csv
  assert_success
  assert_output --partial "│ a │ b │"
}
