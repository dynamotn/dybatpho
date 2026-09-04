setup() {
  load test_helper
}

@test "dybatpho::trim output string" {
  assert_equal "$(dybatpho::trim "	Hello,   dybatpho   ")" "Hello,   dybatpho"
}

@test "dybatpho::trim with empty string" {
  assert_equal "$(dybatpho::trim "")" ""
}

@test "dybatpho::trim with only spaces" {
  assert_equal "$(dybatpho::trim "   ")" ""
}

@test "dybatpho::split output string" {
  run_traced dybatpho::split "apples,oranges,pears,grapes" ","
  assert_success
  assert_output << EOF
apples
oranges
pears
grapes
EOF
  run_traced dybatpho::split "hello---world---my---name---is---dynamo" ","
  assert_success
  assert_output << EOF
hello
world
my
name
is
dynamo
EOF
}

@test "dybatpho::split with empty delimiter" {
  assert_equal "$(dybatpho::split "hello" "")" "hello"
}

@test "dybatpho::split with empty string" {
  assert_equal "$(dybatpho::split "" ",")" ""
}

@test "dybatpho::split with multi-character delimiter" {
  run_traced dybatpho::split "hello---world---dybatpho" "---"
  assert_success
  assert_output << EOF
hello
world
dybatpho
EOF
}

@test "dybatpho::string_starts_with matches exact prefix" {
  dybatpho::string_starts_with "dybatpho-utils" "dybatpho"

  run dybatpho::string_starts_with "dybatpho-utils" "utils"
  assert_failure
}

@test "dybatpho::string_starts_with handles empty prefix" {
  dybatpho::string_starts_with "dybatpho" ""
}

@test "dybatpho::string_ends_with matches exact suffix" {
  dybatpho::string_ends_with "archive.tar.gz" ".gz"

  run dybatpho::string_ends_with "archive.tar.gz" ".tar"
  assert_failure
}

@test "dybatpho::string_ends_with handles empty suffix" {
  dybatpho::string_ends_with "dybatpho" ""
}

@test "dybatpho::string_contains matches exact substring" {
  dybatpho::string_contains "hello dybatpho world" "dybatpho"

  run dybatpho::string_contains "hello dybatpho world" "python"
  assert_failure
}

@test "dybatpho::string_contains handles empty substring" {
  dybatpho::string_contains "dybatpho" ""
}

@test "dybatpho::string_replace replaces all exact matches" {
  assert_equal "$(dybatpho::string_replace "go,bash,go,rust" "go" "python")" "python,bash,python,rust"
}

@test "dybatpho::string_replace keeps input when needle is empty" {
  assert_equal "$(dybatpho::string_replace "dybatpho" "" "x")" "dybatpho"
}

@test "dybatpho::string_replace keeps input when no match exists" {
  assert_equal "$(dybatpho::string_replace "dybatpho" "rust" "bash")" "dybatpho"
}

@test "dybatpho::string_trim_prefix removes only matching prefix" {
  assert_equal "$(dybatpho::string_trim_prefix "refs/heads/main" "refs/heads/")" "main"

  assert_equal "$(dybatpho::string_trim_prefix "refs/tags/v1.0.0" "refs/heads/")" "refs/tags/v1.0.0"
}

@test "dybatpho::string_trim_suffix removes only matching suffix" {
  assert_equal "$(dybatpho::string_trim_suffix "archive.tar.gz" ".gz")" "archive.tar"

  assert_equal "$(dybatpho::string_trim_suffix "archive.tar.gz" ".zip")" "archive.tar.gz"
}

@test "dybatpho::string_slugify lowercases and collapses separators" {
  assert_equal "$(dybatpho::string_slugify "Hello, Dybatpho World!")" "hello-dybatpho-world"
}

@test "dybatpho::string_slugify trims leading separators and keeps digits" {
  assert_equal "$(dybatpho::string_slugify "  Release_2026 / RC1  ")" "release-2026-rc1"

  assert_equal "$(dybatpho::string_slugify "!!!")" ""
}

@test "dybatpho::string_is_blank detects whitespace-only values" {
  dybatpho::string_is_blank "   "

  dybatpho::string_is_blank $'\n\t'

  run dybatpho::string_is_blank " dybatpho "
  assert_failure
}

@test "dybatpho::string_trim_chars trims only listed boundary characters" {
  assert_equal "$(dybatpho::string_trim_chars "__release__" "_")" "release"

  assert_equal "$(dybatpho::string_trim_chars "xy-release-zx" "xyz")" "-release-"
}

@test "dybatpho::string_truncate preserves shorter strings and appends suffix" {
  assert_equal "$(dybatpho::string_truncate "dybatpho" 20)" "dybatpho"

  assert_equal "$(dybatpho::string_truncate "dybatpho-library" 10)" "dybatph..."
}

@test "dybatpho::string_truncate handles narrow widths and custom suffix" {
  assert_equal "$(dybatpho::string_truncate "dybatpho" 2)" ".."

  assert_equal "$(dybatpho::string_truncate "dybatpho" 6 "~")" "dybat~"
}

@test "dybatpho::string_lines counts logical lines" {
  assert_equal "$(dybatpho::string_lines "")" "0"

  assert_equal "$(dybatpho::string_lines $'alpha\nbeta\ngamma')" "3"

  assert_equal "$(dybatpho::string_lines $'alpha\n')" "2"
}

@test "dybatpho::string_wrap wraps words and supports indentation" {
  run_traced dybatpho::string_wrap "alpha beta gamma delta" 10
  assert_success
  assert_output << EOF
alpha beta
gamma
delta
EOF

  run_traced dybatpho::string_wrap "alpha beta gamma delta" 10 "> "
  assert_success
  assert_output << EOF
alpha beta
> gamma
> delta
EOF
}

@test "dybatpho::string_repeat repeats text exact number of times" {
  assert_equal "$(dybatpho::string_repeat "ab" 3)" "ababab"
}

@test "dybatpho::string_repeat with zero count prints empty string" {
  assert_equal "$(dybatpho::string_repeat "ab" 0)" ""
}

@test "dybatpho::string_pad pads on the right with spaces by default" {
  assert_equal "$(dybatpho::string_pad "go" 5)" "go   "
}

@test "dybatpho::string_pad pads with custom token and truncates extra pad" {
  assert_equal "$(dybatpho::string_pad "go" 5 ".")" "go..."

  assert_equal "$(dybatpho::string_pad "go" 5 "ab")" "goaba"
}

@test "dybatpho::string_pad keeps input when already wide enough" {
  assert_equal "$(dybatpho::string_pad "dybatpho" 3)" "dybatpho"
}

@test "dybatpho::url_encode output string" {
  assert_equal "$(dybatpho::url_encode "https://github.com/dynamotn/dybatpho/?f=This is sample string")" "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
}

@test "dybatpho::url_encode with special characters" {
  assert_equal "$(dybatpho::url_encode "hello world!@#$%^&*()")" "hello%20world%21%40%23%24%25%5E%26%2A%28%29"
}

@test "dybatpho::url_encode keeps unreserved characters" {
  assert_equal "$(dybatpho::url_encode "AZaz09.~_-")" "AZaz09.~_-"
}

@test "dybatpho::url_decode output string" {
  assert_equal "$(dybatpho::url_decode "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string")" "https://github.com/dynamotn/dybatpho/?f=This is sample string"
}

@test "dybatpho::url_decode with plus sign" {
  assert_equal "$(dybatpho::url_decode "hello+world")" "hello world"
}

@test "dybatpho::url_decode mixes encoded plus and spaces" {
  assert_equal "$(dybatpho::url_decode "a%2Bb+c")" "a+b c"
}

@test "dybatpho::lower output string" {
  assert_equal "$(dybatpho::lower "dYbaTPHO")" "dybatpho"
}

@test "dybatpho::lower with empty string" {
  assert_equal "$(dybatpho::lower "")" ""
}

@test "dybatpho::upper output string" {
  assert_equal "$(dybatpho::upper "dYbaTPHO")" "DYBATPHO"
}

@test "dybatpho::upper with empty string" {
  assert_equal "$(dybatpho::upper "")" ""
}

@test "dybatpho::string_trim_chars returns the input when no characters are given" {
  assert_equal "$(dybatpho::string_trim_chars "xxhellox" "")" "xxhellox"
}

@test "dybatpho::string_truncate returns an empty line for a non-positive width" {
  assert_equal "$(dybatpho::string_truncate "hello" 0)" ""
  assert_equal "$(dybatpho::string_truncate "hello" -3)" ""
}

@test "dybatpho::string_truncate keeps input shorter than the width" {
  assert_equal "$(dybatpho::string_truncate "hi" 10)" "hi"
}

@test "dybatpho::string_wrap passes input through for a non-positive width" {
  assert_equal "$(dybatpho::string_wrap "alpha beta" 0)" "alpha beta"
}

@test "dybatpho::string_wrap prints an empty line for blank input" {
  assert_equal "$(dybatpho::string_wrap "   " 10)" ""
}

@test "dybatpho::string_pad falls back to spaces for an empty pad token" {
  assert_equal "$(dybatpho::string_pad "ab" 5 "")" "ab   "
}
