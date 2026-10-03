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
  assert_equal "$(dybatpho::text_dedent $'  \n\t' | wc -l | tr -d ' ')" "2"

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

@test "dybatpho::text_columns asks for the table module when it is not loaded" {
  # `text` does not load `table`, so a script that only indents or strips text
  # does not pay for the renderer. A child shell started from a file, without
  # the functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules text\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'dybatpho::text_indent body'
    printf '%s\n' "dybatpho::text_columns 'a|bb'"
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_failure
  assert_line --index 0 "  body"
  assert_output --partial "dybatpho::text_columns needs the table module, load it with: dybatpho::load table"

  # Once the script loads it, the same call aligns.
  sed -i 's/--modules text/--modules text table/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line --index 1 "a  bb"
}

@test "dybatpho::text_box draws a single border sized to the widest line" {
  run_traced dybatpho::text_box $'alpha\nbe ta\n'
  assert_success
  assert_output << EOF
┌───────┐
│ alpha │
│ be ta │
│       │
└───────┘
EOF
}

@test "dybatpho::text_box sets a title into the top border and widens for it" {
  run_traced dybatpho::text_box "ab" "Release notes"
  assert_success
  assert_output << EOF
┌─ Release notes ─┐
│ ab              │
└─────────────────┘
EOF

  run_traced dybatpho::text_box $'alpha\nbeta' "Notes"
  assert_success
  assert_output << EOF
┌─ Notes ─┐
│ alpha   │
│ beta    │
└─────────┘
EOF
}

@test "dybatpho::text_box supports every border style and reads stdin" {
  run_traced dybatpho::text_box - "" ascii <<< 'a|b*c'
  assert_success
  assert_output << EOF
+-------+
| a|b*c |
+-------+
EOF

  assert_equal "$(dybatpho::text_box x "" double)" $'╔═══╗\n║ x ║\n╚═══╝'
  assert_equal "$(dybatpho::text_box x "" rounded)" $'╭───╮\n│ x │\n╰───╯'
  assert_equal "$(dybatpho::text_box x "" heavy)" $'┏━━━┓\n┃ x ┃\n┗━━━┛'
}

@test "dybatpho::text_box handles empty input" {
  run_traced dybatpho::text_box ""
  assert_success
  assert_output << EOF
┌──┐
│  │
└──┘
EOF
}

@test "dybatpho::text_box rejects an unknown style" {
  run --separate-stderr dybatpho::text_box "x" "" dotted
  assert_failure
  assert_stderr --partial "Unknown box style: dotted"
}

@test "dybatpho::text_box pads by visible width, ignoring ANSI sequences" {
  run_traced dybatpho::text_box $'\e[1mbold\e[0m\nplain'
  assert_success
  assert_output $'┌───────┐\n│ \e[1mbold\e[0m  │\n│ plain │\n└───────┘'
}

@test "dybatpho::text_box measures wide characters through screen when it is loaded" {
  run_traced dybatpho::text_box $'漢字\nab' "題"
  assert_success
  assert_output << EOF
┌─ 題 ─┐
│ 漢字 │
│ ab   │
└──────┘
EOF
}

@test "dybatpho::text_box counts characters when screen is not loaded" {
  unset -f __dybatpho_screen_width_into
  run_traced dybatpho::text_box $'漢字\nab'
  assert_success
  assert_output << EOF
┌────┐
│ 漢字 │
│ ab │
└────┘
EOF
}

@test "dybatpho::text_center pads each line on the left within a width" {
  run_traced dybatpho::text_center $'title\nsubtitle here\n\n  \nthis line is far too wide' 20
  assert_success
  assert_output << EOF
       title
   subtitle here


this line is far too wide
EOF
}

@test "dybatpho::text_center measures ANSI and wide text by what is shown" {
  assert_equal "$(dybatpho::text_center $'\e[1mab\e[0m' 6)" $'  \e[1mab\e[0m'
  assert_equal "$(dybatpho::text_center "漢字" 8)" "  漢字"

  unset -f __dybatpho_screen_width_into
  assert_equal "$(dybatpho::text_center "漢字" 8)" "   漢字"
}

@test "dybatpho::text_center defaults to the terminal width and reads stdin" {
  COLUMNS=10 run_traced dybatpho::text_center - <<< "ab"
  assert_success
  assert_output "    ab"
}

@test "dybatpho::text_center rejects a width that is not a positive integer" {
  run --separate-stderr dybatpho::text_center "x" 0
  assert_failure
  assert_stderr --partial "Width must be a positive integer: 0"

  run --separate-stderr dybatpho::text_center "x" wide
  assert_failure
  assert_stderr --partial "Width must be a positive integer: wide"
}

@test "dybatpho::text_number_lines numbers every line, blank ones included" {
  run_traced dybatpho::text_number_lines $'alpha\n\nbeta'
  assert_success
  assert_output $'1  alpha\n2  \n3  beta'
}

@test "dybatpho::text_number_lines right-aligns numbers from a custom start and separator" {
  run_traced dybatpho::text_number_lines $'alpha\nbeta' 09 ": "
  assert_success
  assert_output << EOF
 9: alpha
10: beta
EOF

  assert_equal "$(dybatpho::text_number_lines - 0 "" <<< "x")" "0x"
}

@test "dybatpho::text_number_lines rejects an invalid start line" {
  run --separate-stderr dybatpho::text_number_lines "x" -1
  assert_failure
  assert_stderr --partial "Start line must be a non-negative integer: -1"
}

@test "dybatpho::text_truncate_lines keeps the first lines and counts the rest" {
  run_traced dybatpho::text_truncate_lines $'one\ntwo\nthree\nfour' 2
  assert_success
  assert_output << EOF
one
two
… 2 more lines
EOF

  run_traced dybatpho::text_truncate_lines $'one\ntwo' 1
  assert_success
  assert_output $'one\n… 1 more line'
}

@test "dybatpho::text_truncate_lines prints a block that fits unchanged" {
  run_traced dybatpho::text_truncate_lines $'one\n two ' 2
  assert_success
  assert_output $'one\n two '

  run_traced dybatpho::text_truncate_lines - 5 <<< "only"
  assert_success
  assert_output "only"
}

@test "dybatpho::text_truncate_lines fills a custom marker and accepts a zero count" {
  run_traced dybatpho::text_truncate_lines $'a\nb\nc' 0 "(+{count} hidden, {count} total)"
  assert_success
  assert_output "(+3 hidden, 3 total)"
}

@test "dybatpho::text_truncate_lines rejects an invalid count" {
  run --separate-stderr dybatpho::text_truncate_lines "x" many
  assert_failure
  assert_stderr --partial "Line count must be a non-negative integer: many"
}
