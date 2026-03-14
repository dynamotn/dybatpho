setup() {
  load test_helper
}

@test "dybatpho::table_print aligns delimited rows into columns" {
  run dybatpho::table_print $'Name|Role|State\nAlice|Dev|Active\nBob|Ops|Paused'
  assert_success
  assert_output << EOF
Name   Role  State
Alice  Dev   Active
Bob    Ops   Paused
EOF
}

@test "dybatpho::table_box renders a boxed table with a header separator" {
  run dybatpho::table_box $'Name|Role\nAlice|Dev\nBob|Ops'
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
  run dybatpho::table_markdown $'Name,Role\nAlice,Dev\nBob,Ops' ","
  assert_success
  assert_output << EOF
| Name  | Role |
| ----- | ---- |
| Alice | Dev  |
| Bob   | Ops  |
EOF
}

@test "dybatpho::table_print reads from stdin when input is -" {
  run dybatpho::table_print - <<< $'Name|Role\nAlice|Dev\nBob|Ops\n'
  assert_success
  assert_output << EOF
Name   Role
Alice  Dev
Bob    Ops
EOF
}

@test "dybatpho::table_align supports per-column alignment and custom gap width" {
  run dybatpho::table_align $'Name|Count\nApples|3\nPears|12' "|" "left,right" 3
  assert_success
  assert_output << EOF
Name   Count
Apples     3
Pears     12
EOF
}

@test "dybatpho::table_csv renders comma-delimited rows in plain and markdown styles" {
  run dybatpho::table_csv $'Name,Count\nApples,3\nPears,12' plain "left,right"
  assert_success
  assert_output << EOF
Name    Count
Apples      3
Pears      12
EOF

  run dybatpho::table_csv $'Name,Count\nApples,3\nPears,12' markdown
  assert_success
  assert_output << EOF
| Name   | Count |
| ------ | ----- |
| Apples | 3     |
| Pears  | 12    |
EOF
}
