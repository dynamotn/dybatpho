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
