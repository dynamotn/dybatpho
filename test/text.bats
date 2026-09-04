setup() {
  load test_helper
}

@test "dybatpho::text_indent prefixes each line and supports custom indent strings" {
  run_traced dybatpho::text_indent $'alpha\nbeta' "> "
  assert_success
  assert_output << EOF
> alpha
> beta
EOF
}

@test "dybatpho::text_indent reads from stdin when input is -" {
  run_traced dybatpho::text_indent - "-- " <<< $'alpha\nbeta\n'
  assert_success
  assert_output << EOF
-- alpha
-- beta
EOF
}

@test "dybatpho::text_dedent removes shared leading indentation" {
  run_traced dybatpho::text_dedent $'    alpha\n      beta\n\n    gamma'
  assert_success
  assert_output << EOF
alpha
  beta

gamma
EOF
}

@test "dybatpho::text_strip_ansi removes color escape sequences" {
  run_traced dybatpho::text_strip_ansi $'\e[1;32malpha\e[0m\n\e[0;34mbeta\e[0m'
  assert_success
  assert_output << EOF
alpha
beta
EOF
}

@test "dybatpho::text_bullet_list prefixes non-empty lines and preserves blanks" {
  run_traced dybatpho::text_bullet_list $'alpha\n\nbeta' "*"
  assert_success
  assert_output << EOF
* alpha

* beta
EOF
}

@test "dybatpho::text_columns aligns delimited text with a custom gap" {
  run_traced dybatpho::text_columns $'Key::Value\nname::dybatpho\nversion::1.0.0' "::" 1
  assert_success
  assert_output << EOF
Key     Value
name    dybatpho
version 1.0.0
EOF
}

@test "dybatpho::text_indent uses its default prefix and handles empty input" {
  assert_equal "$(dybatpho::text_indent "alpha")" "  alpha"

  assert_equal "$(dybatpho::text_indent "")" "  "
}

@test "dybatpho::text_dedent handles unindented and all-blank input" {
  run_traced dybatpho::text_dedent $'alpha\n  beta'
  assert_success
  assert_output << EOF
alpha
  beta
EOF

  assert_equal "$(dybatpho::text_dedent $' \n\t\nx')" $'\n\nx'

  # Every line is blank, so no shared indentation can be computed.
  assert_equal "$(dybatpho::text_dedent $'  \n\t' | wc -l)" "2"

  # Empty stdin produces a single empty line rather than no output.
  assert_equal "$(dybatpho::text_indent - "> " < /dev/null)" "> "
}

@test "dybatpho::text_indent and dybatpho::text_bullet_list read stdin without a trailing newline" {
  assert_equal "$(dybatpho::text_indent - "--" <<< "alpha")" "--alpha"

  assert_equal "$(dybatpho::text_bullet_list - <<< "alpha")" "- alpha"
}

@test "dybatpho::text_bullet_list uses the default marker for blank and non-blank lines" {
  run_traced dybatpho::text_bullet_list $'one\n\n two'
  assert_success
  assert_output << EOF
- one

-  two
EOF
}

@test "dybatpho::text_columns uses default delimiter and gap" {
  run_traced dybatpho::text_columns $'a|bb\nccc|d'
  assert_success
  assert_output << EOF
a    bb
ccc  d
EOF
}

@test "dybatpho::text_columns reports a missing table dependency" {
  unset -f dybatpho::table_align
  run --separate-stderr dybatpho::text_columns "a|b"
  assert_failure
  assert_stderr --partial "dybatpho::table_align is required"
}
