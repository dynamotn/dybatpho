setup() {
  load test_helper
}

@test "dybatpho::md_heading renders an ATX heading and escapes its text" {
  run_traced dybatpho::md_heading 2 "Release v2 [beta]"
  assert_success
  assert_output '## Release v2 \[beta\]'
}

@test "dybatpho::md_heading refuses a level outside 1 to 6" {
  # `dybatpho::die` exits, so `run_traced` has no subshell to absorb it.
  run --separate-stderr dybatpho::md_heading 7 "Too deep"
  assert_failure
  assert_stderr --partial "Heading level must be 1 to 6"

  run --separate-stderr dybatpho::md_heading 0 "Too shallow"
  assert_failure
}

@test "dybatpho::md_list renders a bullet list and escapes each item" {
  run_traced dybatpho::md_list $'first *item*\nsecond'
  assert_success
  assert_output - << EOF
- first \*item\*
- second
EOF
}

@test "dybatpho::md_list numbers the items when the marker is ordered" {
  run_traced dybatpho::md_list $'first\nsecond\nthird' "1."
  assert_success
  assert_output - << EOF
1. first
2. second
3. third
EOF

  run_traced dybatpho::md_list $'a\nb' "3)"
  assert_success
  assert_line --index 0 "3) a"
  assert_line --index 1 "4) b"
}

@test "dybatpho::md_list keeps blank lines and takes a custom marker" {
  run_traced dybatpho::md_list $'alpha\n\nbeta' "*"
  assert_success
  assert_output - << EOF
* alpha

* beta
EOF
}

@test "dybatpho::md_list reads a trailing newline the same from an argument and from stdin" {
  # The argument used to gain an empty last item that stdin did not.
  local literal piped
  literal="$(dybatpho::md_list $'a\nb\n'; printf .)"
  piped="$(printf 'a\nb\n' | dybatpho::md_list -; printf .)"
  assert_equal "${literal}" $'- a\n- b\n.'
  assert_equal "${literal}" "${piped}"
}

@test "dybatpho::md_list escapes an item that would otherwise start a block" {
  # A value read from elsewhere can start with `-` or `#`; unescaped it nests a
  # list or opens a heading inside the item.
  run_traced dybatpho::md_list $'- already a bullet\n# not a heading'
  assert_success
  assert_output - << EOF
- \- already a bullet
- \# not a heading
EOF
}

@test "dybatpho::md_list reads from stdin when input is -" {
  run_traced dybatpho::md_list - <<< $'one\ntwo\n'
  assert_success
  assert_line --index 0 "- one"
  assert_line --index 1 "- two"
}

@test "dybatpho::md_task_list renders checked and unchecked items" {
  run_traced dybatpho::md_task_list $'x|Write the spec\n|Ship it\ntrue|Done too\nno|Not yet'
  assert_success
  assert_output - << EOF
- [x] Write the spec
- [ ] Ship it
- [x] Done too
- [ ] Not yet
EOF
}

@test "dybatpho::md_task_list treats a line without the delimiter as unchecked" {
  run_traced dybatpho::md_task_list $'Plain line\n\nX::Done' "::"
  assert_success
  assert_output - << EOF
- [ ] Plain line

- [x] Done
EOF
}

@test "dybatpho::md_link escapes the text and percent-encodes the URL" {
  run_traced dybatpho::md_link "the *docs*" "https://example.com/a b(c)"
  assert_success
  assert_output '[the \*docs\*](https://example.com/a%20b%28c%29)'
}

@test "dybatpho::md_link renders an optional title with quotes escaped" {
  run_traced dybatpho::md_link "x" "https://example.com" 'A "quoted" title'
  assert_success
  assert_output '[x](https://example.com "A \"quoted\" title")'
}

@test "dybatpho::md_badge encodes the shields.io segments" {
  run_traced dybatpho::md_badge "build status" "passing-fast" "green"
  assert_success
  assert_output '![build status: passing-fast](https://img.shields.io/badge/build_status-passing--fast-green)'
}

@test "dybatpho::md_badge defaults the color and wraps the badge in a link" {
  run_traced dybatpho::md_badge "docs" "latest"
  assert_success
  assert_output --partial "-latest-blue)"

  run_traced dybatpho::md_badge "v" "1.0" "blue" "https://example.com/r e"
  assert_success
  assert_output '[![v: 1.0](https://img.shields.io/badge/v-1.0-blue)](https://example.com/r%20e)'
}

@test "dybatpho::md_badge percent-encodes characters that would break the badge URL" {
  # `/` would add a path segment, `?` and `#` would end the path, `%` would
  # start an escape, and `)` would close the Markdown image early.
  run_traced dybatpho::md_badge "a/b?" "50%#1 (ok)" "#ff0000"
  assert_success
  assert_output '![a/b?: 50%#1 (ok)](https://img.shields.io/badge/a%2Fb%3F-50%25%231_%28ok%29-%23ff0000)'
}

@test "dybatpho::md_code_block fences the body without escaping it" {
  run_traced dybatpho::md_code_block bash 'ls -la *.sh'
  assert_success
  assert_output - << EOF
\`\`\`bash
ls -la *.sh
\`\`\`
EOF
}

@test "dybatpho::md_code_block grows the fence past a body that contains one" {
  # A block showing fenced Markdown ends at the body's own fence otherwise.
  run_traced dybatpho::md_code_block markdown $'```sh\necho hi\n```'
  assert_success
  assert_line --index 0 '````markdown'
  assert_line --index 4 '````'
}

@test "dybatpho::md_code_block reads stdin and takes an empty language" {
  run_traced dybatpho::md_code_block "" - <<< $'line one\nline two\n'
  assert_success
  assert_line --index 0 '```'
  assert_line --index 1 'line one'
}

@test "dybatpho::md_code_block refuses a language containing a backtick" {
  run --separate-stderr dybatpho::md_code_block 'ba`sh' 'x'
  assert_failure
  assert_stderr --partial "must not contain a backtick"
}

@test "dybatpho::md_table renders through the table module" {
  run_traced dybatpho::md_table $'Name::Role\nAlice::Dev' "::"
  assert_success
  assert_output - << EOF
| Name  | Role |
| ----- | ---- |
| Alice | Dev  |
EOF
}

@test "dybatpho::md_table asks for the table module when it is not loaded" {
  # `markdown` does not load `table`, so a script that only builds headings and
  # lists does not pay for the renderer. A child shell started from a file --
  # not \`bash -c\`, whose empty \`BASH_SOURCE\` the kcov hook trips over --
  # and without the functions this process exports, shows what such a script
  # sees.
  local script="${BATS_TEST_TMPDIR}/no_table.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules markdown\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'dybatpho::md_heading 2 Report'
    printf '%s\n' "dybatpho::md_table 'a|b'"
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_failure
  assert_line --index 0 "## Report"
  assert_output --partial "dybatpho::md_table needs the table module, load it with: dybatpho::load table"

  # Once the script loads it, the same call renders.
  sed -i 's/--modules markdown/--modules markdown table/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_output --partial "| a | b |"
}

@test "dybatpho::md_collapsible escapes the summary and keeps the body as Markdown" {
  run_traced dybatpho::md_collapsible "Full log *raw*" $'first\nsecond'
  assert_success
  assert_output - << EOF
<details>
<summary>Full log \*raw\*</summary>

first
second

</details>
EOF
}

@test "dybatpho::md_raw keeps a prebuilt fragment out of the escape" {
  local link
  link="$(dybatpho::md_link "docs" "https://example.com")"
  run_traced dybatpho::md_list "see $(dybatpho::md_raw "${link}") now"
  assert_success
  assert_output '- see [docs](https://example.com) now'
}

@test "dybatpho::md_raw copies through a fragment whose closing mark was cut" {
  # A truncated raw region must not escape the half that survived; the caller
  # gets back the Markdown they built rather than its source text.
  local marked truncated
  marked="$(dybatpho::md_raw '**bold**')"
  truncated="${marked%"${marked: -1}"}"
  run_traced dybatpho::md_heading 3 "${truncated}"
  assert_success
  assert_output '### **bold**'
}

@test "dybatpho::md_escape escapes inline and line-leading syntax" {
  run_traced dybatpho::md_escape 'a_b|c <x> [y] `z` ~w~'
  assert_success
  assert_output 'a\_b\|c \<x\> \[y\] \`z\` \~w\~'

  run_traced dybatpho::md_escape $'# heading\n1. item\n+ plus\nmid - dash'
  assert_success
  assert_output - << EOF
\# heading
\1. item
\+ plus
mid - dash
EOF
}

@test "dybatpho::md_escape doubles a backslash before escaping anything else" {
  run_traced dybatpho::md_escape 'path\to*file'
  assert_success
  assert_output 'path\\to\*file'
}

@test "dybatpho::md_escape reads stdin and handles empty input" {
  run_traced dybatpho::md_escape - <<< $'*one*\n*two*\n'
  assert_success
  assert_output - << EOF
\*one\*
\*two\*
EOF

  run_traced dybatpho::md_escape ""
  assert_success
  assert_output ""

  # Stdin that closes without a single line reads as one empty line, so a
  # builder renders an empty block rather than reaching into an empty array.
  run_traced dybatpho::md_escape - < /dev/null
  assert_success
  assert_output ""
}

@test "dybatpho::md_mention renders a mention with or without the leading @" {
  run_traced dybatpho::md_mention "dynamotn"
  assert_success
  assert_output "@dynamotn"

  run_traced dybatpho::md_mention "@some-org/team"
  assert_success
  assert_output "@some-org/team"
}

@test "dybatpho::md_mention refuses a name that is not an account" {
  run --separate-stderr dybatpho::md_mention "not a name"
  assert_failure
  assert_stderr --partial "Invalid account name"
}

@test "dybatpho::md_emoji renders a shortcode with or without the colons" {
  run_traced dybatpho::md_emoji "rocket"
  assert_success
  assert_output ":rocket:"

  run_traced dybatpho::md_emoji ":+1:"
  assert_success
  assert_output ":+1:"
}

@test "dybatpho::md_emoji refuses a shortcode that cannot render" {
  run --separate-stderr dybatpho::md_emoji "two words"
  assert_failure
  assert_stderr --partial "Invalid emoji shortcode"
}
