setup() {
  load test_helper
}

@test "dybatpho::text_indent prefixes each line and supports custom indent strings" {
  run dybatpho::text_indent $'alpha\nbeta' "> "
  assert_success
  assert_output << EOF
> alpha
> beta
EOF
}

@test "dybatpho::text_indent reads from stdin when input is -" {
  run bash -lc 'source "'"${DYBATPHO_DIR}"'/init.sh" && printf "alpha\nbeta\n" | dybatpho::text_indent - "-- "'
  assert_success
  assert_output << EOF
-- alpha
-- beta
EOF
}

@test "dybatpho::text_dedent removes shared leading indentation" {
  run dybatpho::text_dedent $'    alpha\n      beta\n\n    gamma'
  assert_success
  assert_output << EOF
alpha
  beta

gamma
EOF
}

@test "dybatpho::text_strip_ansi removes color escape sequences" {
  run dybatpho::text_strip_ansi $'\e[1;32malpha\e[0m\n\e[0;34mbeta\e[0m'
  assert_success
  assert_output << EOF
alpha
beta
EOF
}

@test "dybatpho::text_bullet_list prefixes non-empty lines and preserves blanks" {
  run dybatpho::text_bullet_list $'alpha\n\nbeta' "*"
  assert_success
  assert_output << EOF
* alpha

* beta
EOF
}

@test "dybatpho::text_columns aligns delimited text with a custom gap" {
  run dybatpho::text_columns $'Key::Value\nname::dybatpho\nversion::1.0.0' "::" 1
  assert_success
  assert_output << EOF
Key     Value
name    dybatpho
version 1.0.0
EOF
}
