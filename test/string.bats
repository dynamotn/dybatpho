setup() {
  load test_helper
}

@test "dybatpho::trim output string" {
  run dybatpho::trim "	Hello,   dybatpho   "
  assert_success
  assert_output "Hello,   dybatpho"
}

@test "dybatpho::trim with empty string" {
  run dybatpho::trim ""
  assert_success
  assert_output ""
}

@test "dybatpho::trim with only spaces" {
  run dybatpho::trim "   "
  assert_success
  assert_output ""
}

@test "dybatpho::split output string" {
  run dybatpho::split "apples,oranges,pears,grapes" ","
  assert_success
  assert_output << EOF
apples
oranges
pears
grapes
EOF
  run dybatpho::split "hello---world---my---name---is---dynamo" ","
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
  run dybatpho::split "hello" ""
  assert_success
  assert_output "hello"
}

@test "dybatpho::split with empty string" {
  run dybatpho::split "" ","
  assert_success
  assert_output ""
}

@test "dybatpho::split with multi-character delimiter" {
  run dybatpho::split "hello---world---dybatpho" "---"
  assert_success
  assert_output << EOF
hello
world
dybatpho
EOF
}

@test "dybatpho::string_starts_with matches exact prefix" {
  run dybatpho::string_starts_with "dybatpho-utils" "dybatpho"
  assert_success

  run dybatpho::string_starts_with "dybatpho-utils" "utils"
  assert_failure
}

@test "dybatpho::string_starts_with handles empty prefix" {
  run dybatpho::string_starts_with "dybatpho" ""
  assert_success
}

@test "dybatpho::string_ends_with matches exact suffix" {
  run dybatpho::string_ends_with "archive.tar.gz" ".gz"
  assert_success

  run dybatpho::string_ends_with "archive.tar.gz" ".tar"
  assert_failure
}

@test "dybatpho::string_ends_with handles empty suffix" {
  run dybatpho::string_ends_with "dybatpho" ""
  assert_success
}

@test "dybatpho::string_contains matches exact substring" {
  run dybatpho::string_contains "hello dybatpho world" "dybatpho"
  assert_success

  run dybatpho::string_contains "hello dybatpho world" "python"
  assert_failure
}

@test "dybatpho::string_contains handles empty substring" {
  run dybatpho::string_contains "dybatpho" ""
  assert_success
}

@test "dybatpho::string_replace replaces all exact matches" {
  run dybatpho::string_replace "go,bash,go,rust" "go" "python"
  assert_success
  assert_output "python,bash,python,rust"
}

@test "dybatpho::string_replace keeps input when needle is empty" {
  run dybatpho::string_replace "dybatpho" "" "x"
  assert_success
  assert_output "dybatpho"
}

@test "dybatpho::string_replace keeps input when no match exists" {
  run dybatpho::string_replace "dybatpho" "rust" "bash"
  assert_success
  assert_output "dybatpho"
}

@test "dybatpho::string_trim_prefix removes only matching prefix" {
  run dybatpho::string_trim_prefix "refs/heads/main" "refs/heads/"
  assert_success
  assert_output "main"

  run dybatpho::string_trim_prefix "refs/tags/v1.0.0" "refs/heads/"
  assert_success
  assert_output "refs/tags/v1.0.0"
}

@test "dybatpho::string_trim_suffix removes only matching suffix" {
  run dybatpho::string_trim_suffix "archive.tar.gz" ".gz"
  assert_success
  assert_output "archive.tar"

  run dybatpho::string_trim_suffix "archive.tar.gz" ".zip"
  assert_success
  assert_output "archive.tar.gz"
}

@test "dybatpho::string_slugify lowercases and collapses separators" {
  run dybatpho::string_slugify "Hello, Dybatpho World!"
  assert_success
  assert_output "hello-dybatpho-world"
}

@test "dybatpho::string_slugify trims leading separators and keeps digits" {
  run dybatpho::string_slugify "  Release_2026 / RC1  "
  assert_success
  assert_output "release-2026-rc1"

  run dybatpho::string_slugify "!!!"
  assert_success
  assert_output ""
}

@test "dybatpho::string_is_blank detects whitespace-only values" {
  run dybatpho::string_is_blank "   "
  assert_success

  run dybatpho::string_is_blank $'\n\t'
  assert_success

  run dybatpho::string_is_blank " dybatpho "
  assert_failure
}

@test "dybatpho::string_trim_chars trims only listed boundary characters" {
  run dybatpho::string_trim_chars "__release__" "_"
  assert_success
  assert_output "release"

  run dybatpho::string_trim_chars "xy-release-zx" "xyz"
  assert_success
  assert_output "-release-"
}

@test "dybatpho::string_truncate preserves shorter strings and appends suffix" {
  run dybatpho::string_truncate "dybatpho" 20
  assert_success
  assert_output "dybatpho"

  run dybatpho::string_truncate "dybatpho-library" 10
  assert_success
  assert_output "dybatph..."
}

@test "dybatpho::string_truncate handles narrow widths and custom suffix" {
  run dybatpho::string_truncate "dybatpho" 2
  assert_success
  assert_output ".."

  run dybatpho::string_truncate "dybatpho" 6 "~"
  assert_success
  assert_output "dybat~"
}

@test "dybatpho::string_lines counts logical lines" {
  run dybatpho::string_lines ""
  assert_success
  assert_output "0"

  run dybatpho::string_lines $'alpha\nbeta\ngamma'
  assert_success
  assert_output "3"

  run dybatpho::string_lines $'alpha\n'
  assert_success
  assert_output "2"
}

@test "dybatpho::string_wrap wraps words and supports indentation" {
  run dybatpho::string_wrap "alpha beta gamma delta" 10
  assert_success
  assert_output << EOF
alpha beta
gamma
delta
EOF

  run dybatpho::string_wrap "alpha beta gamma delta" 10 "> "
  assert_success
  assert_output << EOF
alpha beta
> gamma
> delta
EOF
}

@test "dybatpho::string_repeat repeats text exact number of times" {
  run dybatpho::string_repeat "ab" 3
  assert_success
  assert_output "ababab"
}

@test "dybatpho::string_repeat with zero count prints empty string" {
  run dybatpho::string_repeat "ab" 0
  assert_success
  assert_output ""
}

@test "dybatpho::string_pad pads on the right with spaces by default" {
  run dybatpho::string_pad "go" 5
  assert_success
  assert_output "go   "
}

@test "dybatpho::string_pad pads with custom token and truncates extra pad" {
  run dybatpho::string_pad "go" 5 "."
  assert_success
  assert_output "go..."

  run dybatpho::string_pad "go" 5 "ab"
  assert_success
  assert_output "goaba"
}

@test "dybatpho::string_pad keeps input when already wide enough" {
  run dybatpho::string_pad "dybatpho" 3
  assert_success
  assert_output "dybatpho"
}

@test "dybatpho::url_encode output string" {
  run dybatpho::url_encode "https://github.com/dynamotn/dybatpho/?f=This is sample string"
  assert_success
  assert_output "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
}

@test "dybatpho::url_encode with special characters" {
  run dybatpho::url_encode "hello world!@#$%^&*()"
  assert_success
  assert_output "hello%20world%21%40%23%24%25%5E%26%2A%28%29"
}

@test "dybatpho::url_encode keeps unreserved characters" {
  run dybatpho::url_encode "AZaz09.~_-"
  assert_success
  assert_output "AZaz09.~_-"
}

@test "dybatpho::url_decode output string" {
  run dybatpho::url_decode "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
  assert_success
  assert_output "https://github.com/dynamotn/dybatpho/?f=This is sample string"
}

@test "dybatpho::url_decode with plus sign" {
  run dybatpho::url_decode "hello+world"
  assert_success
  assert_output "hello world"
}

@test "dybatpho::url_decode mixes encoded plus and spaces" {
  run dybatpho::url_decode "a%2Bb+c"
  assert_success
  assert_output "a+b c"
}

@test "dybatpho::lower output string" {
  run dybatpho::lower "dYbaTPHO"
  assert_success
  assert_output "dybatpho"
}

@test "dybatpho::lower with empty string" {
  run dybatpho::lower ""
  assert_success
  assert_output ""
}

@test "dybatpho::upper output string" {
  run dybatpho::upper "dYbaTPHO"
  assert_success
  assert_output "DYBATPHO"
}

@test "dybatpho::upper with empty string" {
  run dybatpho::upper ""
  assert_success
  assert_output ""
}
