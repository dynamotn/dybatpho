setup() {
  load test_helper
}

@test "dybatpho::text_indent prefixes each line and supports custom indent strings" {
  run_traced dybatpho::text_indent $'alpha\nbeta' "> "
  assert_success
  assert_output - << EOF
> alpha
> beta
EOF
}

@test "dybatpho::text_indent reads from stdin when input is -" {
  run_traced dybatpho::text_indent - "-- " <<< $'alpha\nbeta'
  assert_success
  assert_output - << EOF
-- alpha
-- beta
EOF
}

@test "dybatpho::text_dedent removes shared leading indentation" {
  run_traced dybatpho::text_dedent $'    alpha\n      beta\n\n    gamma'
  assert_success
  assert_output - << EOF
alpha
  beta

gamma
EOF
}

@test "dybatpho::text_sanitize removes what can disguise a line, and keeps the text" {
  export LC_ALL=C.UTF-8
  local input
  # Color, a bare carriage return, a bell, DEL, a C1 control, a right-to-left
  # override, a zero-width space, a byte-order mark and a tag character.
  input=$'\e[31mred\e[0m'$'\r''over'$'\a''x'$'\x7f''y'$'\xc2\x85''z'
  input+=$'\xe2\x80\xae''rtl'$'\xe2\x80\x8b''zw'$'\xef\xbb\xbf''bom'$'\xf3\xa0\x80\x81''tag'
  run_traced dybatpho::text_sanitize "${input}"
  assert_success
  assert_output "redoverxyzrtlzwbomtag"
  # Tabs, newlines and ordinary Unicode stay.
  run_traced dybatpho::text_sanitize $'a\tb\nc\xc3\xa9 \xe6\x97\xa5'
  assert_line --index 0 $'a\tb'
  assert_line --index 1 $'c\xc3\xa9 \xe6\x97\xa5'
}

@test "dybatpho::text_sanitize does not let a removed character join its neighbours into a control" {
  export LC_ALL=C.UTF-8
  # Each removal joins the bytes around it: into CSI (U+009B) through a zero-width
  # space, a C1 control, or a tag character; into a right-to-left override (U+202E)
  # through a zero-width space or a byte-order mark; into a zero-width space again.
  local input expected
  local -a cases=(
    $'a\xc2\xe2\x80\x8b\x9b31mRED' 'a31mRED'
    $'a\xc2\xc2\x80\x9b31m' 'a31m'
    $'a\xc2\xf3\xa0\x80\x81\x9b2J' 'a2J'
    $'a\xe2\x80\xe2\x80\x8b\xaecba' 'acba'
    $'a\xe2\x80\xef\xbb\xbf\xaecba' 'acba'
    # The last byte left is a lone continuation byte, which shows as U+FFFD.
    $'a\xe2\x80\xe2\x80\x8b\x8b\xaecba' $'a\xaecba'
  )
  for ((i = 0; i < ${#cases[@]}; i += 2)); do
    input="${cases[i]}" expected="${cases[i + 1]}"
    run_traced dybatpho::text_sanitize "${input}"
    assert_output "${expected}"
  done
}

@test "dybatpho::text_sanitize removes C1 bytes an 8-bit terminal would obey, and overlong forms" {
  # A raw 0x9B is CSI to a terminal in 8-bit mode; under UTF-8 it is dropped
  # when no lead byte comes before it, and outside UTF-8 always.
  LC_ALL=C.UTF-8 run_traced dybatpho::text_sanitize $'a\x9b2Jb\n\x9bx'
  assert_line --index 0 'a2Jb'
  assert_line --index 1 'x'
  LC_ALL=C run_traced dybatpho::text_sanitize $'a\x9b2Jb\xc3\xa9'
  assert_output $'a2Jb\xc3\xa9'
  # An overlong ESC, and bytes no UTF-8 character starts with.
  LC_ALL=C.UTF-8 run_traced dybatpho::text_sanitize $'a\xc0\x9b[2Jb\xff'
  assert_output 'a[2Jb'
}

@test "dybatpho::text_sanitize removes every kind of escape sequence whole" {
  export LC_ALL=C.UTF-8
  local -a cases=(
    $'a\eP1$qm\e\\b' 'ab'
    $'a\e_hidden\ab' 'ab'
    $'a\e^private\e\\b' 'ab'
    $'a\eXstring\xc2\x9cb' 'ab'
    $'a\e]0;title\xc2\x9cb' 'ab'
    $'a\e_unended' 'a'
    $'a\e_x\e[31mb' 'ab'
    $'a\ecb' 'ab'
    $'a\e78b' 'a8b'
    $'a\e[31' 'a'
    $'a\e(' 'a'
    $'a\e' 'a'
  )
  for ((i = 0; i < ${#cases[@]}; i += 2)); do
    run_traced dybatpho::text_sanitize "${cases[i]}"
    assert_output "${cases[i + 1]}"
  done
}

@test "dybatpho::text_sanitize stays linear-bounded on nested input, and ignores the caller's nocasematch" {
  export LC_ALL=C.UTF-8
  # Each round peels one layer of `\xc2`...`\x80`; past four rounds every byte from
  # 0x80 up goes at once, so a deeply nested line cannot stall the caller.
  local nested="a" i
  for ((i = 0; i < 3000; i++)); do nested+=$'\xc2'; done
  for ((i = 0; i < 3000; i++)); do nested+=$'\x80'; done
  nested+="b"
  SECONDS=0
  run_traced dybatpho::text_sanitize "${nested}"
  assert_output "ab"
  ((SECONDS < 10))
  # Under nocasematch `ESC p` must not open a DCS string and hide what follows.
  shopt -s nocasematch
  run_traced dybatpho::text_sanitize $'a\epVISIBLE status=FAILED'
  assert_output "aVISIBLE status=FAILED"
  shopt -q nocasematch
  shopt -u nocasematch
}

@test "dybatpho::text_sanitize removes 8-bit introduced sequences and controls inside a sequence" {
  export LC_ALL=C.UTF-8
  run_traced dybatpho::text_sanitize $'a\xc2\x9b31mb'
  assert_output "ab"
  run_traced dybatpho::text_sanitize $'a\xc2\x9d0;title\xc2\x9cb'
  assert_output "ab"
  run_traced dybatpho::text_sanitize $'a\e\x01[31mb'
  assert_output "ab"
  # Outside UTF-8, a UTF-8 letter ending in such a byte does not swallow the line.
  LC_ALL=C run_traced dybatpho::text_sanitize $'\xc4\x9fxyz'
  assert_output $'\xc4xyz'
}

@test "dybatpho::text_sanitize caps the characters it prints, newlines included" {
  export LC_ALL=C.UTF-8
  run_traced dybatpho::text_sanitize $'abcd\nefgh' 6
  assert_output $'abcd\ne'
  run_traced dybatpho::text_sanitize $'\xc3\xa9\xc3\xa9\xc3\xa9' 2
  assert_output $'\xc3\xa9\xc3\xa9'
  # A cap used up by a line break ends the output there, without an empty line.
  local result
  result="$(dybatpho::text_sanitize $'ab\ncd' 3 && printf x)"
  assert_equal "${result}" $'ab\nx'
  result="$(dybatpho::text_sanitize 'ab' 0 && printf x)"
  assert_equal "${result}" 'x'
  run -1 dybatpho::text_sanitize "x" abc
  assert_output --partial "number of characters"
}

@test "dybatpho::text_sanitize reads standard input given -" {
  run_traced dybatpho::text_sanitize - <<< $'plain\x1b]0;title\x07text'
  assert_success
  assert_output "plaintext"
}

@test "dybatpho::text_strip_ansi removes color escape sequences" {
  run_traced dybatpho::text_strip_ansi $'\e[1;32malpha\e[0m\n\e[0;34mbeta\e[0m'
  assert_success
  assert_output - << EOF
alpha
beta
EOF
}

@test "dybatpho::text_strip_ansi removes hyperlinks and the reset tput sgr0 prints" {
  # `tput sgr0` on xterm is `\e(B\e[m`; a hyperlink is an OSC 8 pair, ended by
  # either a string terminator or a bell.
  run_traced dybatpho::text_strip_ansi \
    $'\e[31malert\e(B\e[m\n\e]8;;https://x.org\e\\site\e]8;;\e\\\n\e]8;;u\alink\e]8;;\a'
  assert_success
  assert_output $'alert\nsite\nlink'

  run_traced dybatpho::text_box $'plain\n\e[31malert\e(B\e[m' "" ascii
  assert_line --index 1 '| plain |'
  assert_line --index 2 $'| \e[31malert\e(B\e[m |'
}

@test "dybatpho::text_strip_ansi takes time in proportion to the escapes on a line" {
  # Each escape used to rescan and copy the line: 12000 of them took ~17s.
  local text
  printf -v text '\e[1;32mab\e[0m%.0s' {1..12000}
  local started="${SECONDS}"
  run_traced dybatpho::text_strip_ansi "${text}"
  assert_success
  assert_equal "${#output}" "24000"
  # Loose enough for a loaded CI runner, where the linear walk took 12s.
  assert [ "$((SECONDS - started))" -le 30 ]
}

@test "dybatpho::text_bullet_list prefixes non-empty lines and preserves blanks" {
  run_traced dybatpho::text_bullet_list $'alpha\n\nbeta' "*"
  assert_success
  assert_output - << EOF
* alpha

* beta
EOF
}

@test "dybatpho::text_columns aligns delimited text with a custom gap" {
  run_traced dybatpho::text_columns $'Key::Value\nname::dybatpho\nversion::1.0.0' "::" 1
  assert_success
  assert_output - << EOF
Key     Value
name    dybatpho
version 1.0.0
EOF
}

@test "dybatpho::text_indent reads a trailing newline the same from an argument and from stdin" {
  # `mapfile <<<` adds a newline of its own, so an argument ending in one used
  # to grow an extra, indented empty line that the same text on stdin did not.
  local literal piped
  literal="$(dybatpho::text_indent $'a\nb\n' "> "; printf .)"
  piped="$(printf 'a\nb\n' | dybatpho::text_indent - "> "; printf .)"
  assert_equal "${literal}" $'> a\n> b\n.'
  assert_equal "${literal}" "${piped}"

  # A blank line before the end is still a line of its own.
  literal="$(dybatpho::text_indent $'a\n\n' "> "; printf .)"
  assert_equal "${literal}" $'> a\n> \n.'
}

@test "dybatpho::text_indent uses its default prefix and handles empty input" {
  assert_equal "$(dybatpho::text_indent "alpha")" "  alpha"

  assert_equal "$(dybatpho::text_indent "")" "  "
}

@test "dybatpho::text_dedent handles unindented and all-blank input" {
  run_traced dybatpho::text_dedent $'alpha\n  beta'
  assert_success
  assert_output - << EOF
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
  assert_output - << EOF
- one

-  two
EOF
}

@test "dybatpho::text_columns uses default delimiter and gap" {
  run_traced dybatpho::text_columns $'a|bb\nccc|d'
  assert_success
  assert_output - << EOF
a    bb
ccc  d
EOF
}

@test "dybatpho::text_columns loads the table module on demand when it is not loaded" {
  # `text` does not load `table` up front, so a script that only indents or
  # strips text does not pay for the renderer. A child shell started from a file, without
  # the functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules text\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'dybatpho::text_indent body'
    printf '%s\n' "dybatpho::text_columns 'a|bb'"
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line --index 0 "  body"
  assert_line --index 1 "a  bb"

  # A script that names it up front gets the same columns.
  sed_in_place 's/--modules text/--modules text table/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line --index 1 "a  bb"
}

@test "dybatpho::text_box draws a single border sized to the widest line" {
  run_traced dybatpho::text_box $'alpha\nbe ta\n'
  assert_success
  assert_output - << EOF
┌───────┐
│ alpha │
│ be ta │
└───────┘
EOF
}

@test "dybatpho::text_box sets a title into the top border and widens for it" {
  run_traced dybatpho::text_box "ab" "Release notes"
  assert_success
  assert_output - << EOF
┌─ Release notes ─┐
│ ab              │
└─────────────────┘
EOF

  run_traced dybatpho::text_box $'alpha\nbeta' "Notes"
  assert_success
  assert_output - << EOF
┌─ Notes ─┐
│ alpha   │
│ beta    │
└─────────┘
EOF
}

@test "dybatpho::text_box supports every border style and reads stdin" {
  run_traced dybatpho::text_box - "" ascii <<< 'a|b*c'
  assert_success
  assert_output - << EOF
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
  assert_output - << EOF
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

@test "dybatpho::text_box measures wide characters by the columns they take" {
  run_traced dybatpho::text_box $'漢字\nab' "題"
  assert_success
  assert_output - << EOF
┌─ 題 ─┐
│ 漢字 │
│ ab   │
└──────┘
EOF
}

@test "dybatpho::text_box sizes wide characters by the columns they take" {
  # The measurement is the core one: a box drawn by character count used to
  # come out too narrow. Bytes, characters and columns all differ for this line
  # (8, 3 and 5), so a box sized by any measure but the columns is wrong.
  run_traced dybatpho::text_box $'日本é\nab'
  assert_success
  assert_output - << EOF
┌───────┐
│ 日本é │
│ ab    │
└───────┘
EOF
}

@test "dybatpho::text_center pads each line on the left within a width" {
  run_traced dybatpho::text_center $'title\nsubtitle here\n\n  \nthis line is far too wide' 20
  assert_success
  assert_output - << EOF
       title
   subtitle here


this line is far too wide
EOF
}

@test "dybatpho::text_center measures ANSI and wide text by what is shown" {
  assert_equal "$(dybatpho::text_center $'\e[1mab\e[0m' 6)" $'  \e[1mab\e[0m'
  assert_equal "$(dybatpho::text_center "漢字" 8)" "  漢字"
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
  assert_output - << EOF
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
  assert_output - << EOF
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

@test "dybatpho::text_number_lines and dybatpho::text_truncate_lines refuse a count past 2^63 - 1" {
  run --separate-stderr dybatpho::text_number_lines $'a\nb' 99999999999999999999
  assert_failure
  assert_stderr --partial "9223372036854775807"
  run --separate-stderr dybatpho::text_truncate_lines $'a\nb' 9223372036854775808
  assert_failure
  assert_stderr --partial "9223372036854775807"
  assert_equal "$(dybatpho::text_truncate_lines $'a\nb' 9223372036854775807)" $'a\nb'
}
