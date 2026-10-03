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
  assert_output - << EOF
apples
oranges
pears
grapes
EOF
  run_traced dybatpho::split "hello---world---my---name---is---dynamo" "---"
  assert_success
  assert_output - << EOF
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

@test "dybatpho::split treats a glob metacharacter delimiter literally" {
  assert_equal "$(dybatpho::split "a*b*c" "*")" "a
b
c"
  assert_equal "$(dybatpho::split "a?b?c" "?")" "a
b
c"
  assert_equal "$(dybatpho::split "a[x]b[x]c" "[x]")" "a
b
c"
}

@test "dybatpho::split keeps empty fields, including trailing ones" {
  # A command substitution eats trailing newlines, so the fields are counted
  # through `mapfile` instead of compared as one string.
  local -a fields=()
  mapfile -t fields < <(dybatpho::split "a,b,," ",")
  assert_equal "${#fields[@]}" 4
  assert_equal "${fields[0]}" "a"
  assert_equal "${fields[1]}" "b"
  assert_equal "${fields[2]}" ""
  assert_equal "${fields[3]}" ""

  mapfile -t fields < <(dybatpho::split ",a" ",")
  assert_equal "${#fields[@]}" 2
  assert_equal "${fields[0]}" ""
  assert_equal "${fields[1]}" "a"
}

@test "dybatpho::split does not leak a global named arr" {
  arr="untouched"
  dybatpho::split "x-y" "-" > /dev/null
  assert_equal "${arr}" "untouched"
}

@test "dybatpho::split with empty string" {
  assert_equal "$(dybatpho::split "" ",")" ""
}

@test "dybatpho::split with multi-character delimiter" {
  run_traced dybatpho::split "hello---world---dybatpho" "---"
  assert_success
  assert_output - << EOF
hello
world
dybatpho
EOF
}

@test "dybatpho::string_starts_with matches exact prefix" {
  dybatpho::string_starts_with "dybatpho-utils" "dybatpho"

  run_traced dybatpho::string_starts_with "dybatpho-utils" "utils"
  assert_failure
}

@test "dybatpho::string_starts_with handles empty prefix" {
  dybatpho::string_starts_with "dybatpho" ""
}

@test "dybatpho::string_ends_with matches exact suffix" {
  dybatpho::string_ends_with "archive.tar.gz" ".gz"

  run_traced dybatpho::string_ends_with "archive.tar.gz" ".tar"
  assert_failure
}

@test "dybatpho::string_ends_with handles empty suffix" {
  dybatpho::string_ends_with "dybatpho" ""
}

@test "dybatpho::string_contains matches exact substring" {
  dybatpho::string_contains "hello dybatpho world" "dybatpho"

  run_traced dybatpho::string_contains "hello dybatpho world" "python"
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

  run_traced dybatpho::string_is_blank " dybatpho "
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
  assert_output - << EOF
alpha beta
gamma
delta
EOF

  run_traced dybatpho::string_wrap "alpha beta gamma delta" 10 "> "
  assert_success
  assert_output - << EOF
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

@test "string helpers refuse a width or count that is not a whole number" {
  local helper
  for helper in string_truncate string_wrap string_repeat string_pad; do
    run --separate-stderr "dybatpho::${helper}" hello abc
    assert_failure
    assert_stderr --partial "dybatpho::${helper}: abc is not a whole number"
  done
  run --separate-stderr dybatpho::string_pad hello 08
  assert_failure
  assert_stderr --partial "08 is not a whole number"
  run_traced dybatpho::string_truncate hello -3
  assert_success
  assert_output ""
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

@test "dybatpho::string_to_snake reads every convention the input may arrive in" {
  assert_equal "$(dybatpho::string_to_snake fooBar)" "foo_bar"
  assert_equal "$(dybatpho::string_to_snake foo-bar-baz)" "foo_bar_baz"
  assert_equal "$(dybatpho::string_to_snake "Foo Bar")" "foo_bar"
  assert_equal "$(dybatpho::string_to_snake FOO_BAR)" "foo_bar"
  assert_equal "$(dybatpho::string_to_snake already_snake)" "already_snake"
  assert_equal "$(dybatpho::string_to_snake "deploy--to__prod")" "deploy_to_prod"
  assert_equal "$(dybatpho::string_to_snake "_foo_bar_")" "foo_bar"
}

@test "dybatpho::string_to_snake breaks a run of capitals where the word ends" {
  # `XMLHttpRequest` is the case that separates a real word splitter from a
  # regex: the break is before the last capital, not after the first.
  assert_equal "$(dybatpho::string_to_snake XMLHttpRequest)" "xml_http_request"
  assert_equal "$(dybatpho::string_to_snake HTTPServer)" "http_server"
  assert_equal "$(dybatpho::string_to_snake parseJSON)" "parse_json"
}

@test "dybatpho::string_to_snake keeps a digit attached to the word before it" {
  # Splitting at a digit would be guessing: `foo2bar` is one name, not two.
  assert_equal "$(dybatpho::string_to_snake foo2bar)" "foo2bar"
  assert_equal "$(dybatpho::string_to_snake s3_bucket)" "s3_bucket"
}

@test "the case helpers return nothing for input with no letters or digits" {
  assert_equal "$(dybatpho::string_to_snake "")" ""
  assert_equal "$(dybatpho::string_to_kebab "---")" ""
  assert_equal "$(dybatpho::string_to_camel "")" ""
  assert_equal "$(dybatpho::string_to_pascal "  ")" ""
}

@test "dybatpho::string_slugify transliterates a letter carrying a diacritic" {
  # Dropping the letter outright made the slug name nothing: `Thế Giới` came
  # out as `th-gi-i`, and two different titles could collapse onto the same
  # slug.
  assert_equal "$(dybatpho::string_slugify "Thế Giới")" "the-gioi"
  assert_equal "$(dybatpho::string_slugify "Đường Láng Hạ")" "duong-lang-ha"
  assert_equal "$(dybatpho::string_slugify "ĐẤT NƯỚC")" "dat-nuoc"
  assert_equal "$(dybatpho::string_slugify "Crème brûlée 2024")" "creme-brulee-2024"
  assert_equal "$(dybatpho::string_slugify "Žluťoučký kůň")" "zlutoucky-kun"
  assert_equal "$(dybatpho::string_slugify "Łódź")" "lodz"
}

@test "dybatpho::string_slugify expands the letters that stand for two" {
  assert_equal "$(dybatpho::string_slugify "Straße")" "strasse"
  assert_equal "$(dybatpho::string_slugify "Ærø & Œuvre")" "aero-oeuvre"
}

@test "dybatpho::string_slugify keeps the letter under a combining mark" {
  # Decomposed text is a plain letter followed by its mark. The mark is not a
  # word separator, so it comes off without splitting the word in two.
  assert_equal "$(dybatpho::string_slugify "$(printf 'cafe\xcc\x81 au lait')")" \
    "cafe-au-lait"
}

@test "dybatpho::string_to_kebab differs from slugify on word boundaries" {
  # Slugify is for prose and has no idea where the words are; this reads the
  # boundaries the naming convention implies.
  assert_equal "$(dybatpho::string_to_kebab XMLHttpRequest)" "xml-http-request"
  assert_equal "$(dybatpho::string_slugify XMLHttpRequest)" "xmlhttprequest"
  assert_equal "$(dybatpho::string_to_kebab deploy_to_prod)" "deploy-to-prod"
}

@test "dybatpho::string_to_camel and string_to_pascal differ only in the first word" {
  assert_equal "$(dybatpho::string_to_camel deploy_to_prod)" "deployToProd"
  assert_equal "$(dybatpho::string_to_pascal deploy_to_prod)" "DeployToProd"
  assert_equal "$(dybatpho::string_to_camel XMLHttpRequest)" "xmlHttpRequest"
  assert_equal "$(dybatpho::string_to_camel foo)" "foo"
  assert_equal "$(dybatpho::string_to_pascal foo)" "Foo"
}

@test "the case helpers round-trip through each other" {
  assert_equal "$(dybatpho::string_to_snake "$(dybatpho::string_to_camel deploy_to_prod)")" "deploy_to_prod"
  assert_equal "$(dybatpho::string_to_kebab "$(dybatpho::string_to_pascal deploy_to_prod)")" "deploy-to-prod"
  assert_equal "$(dybatpho::string_to_camel "$(dybatpho::string_to_kebab XMLHttpRequest)")" "xmlHttpRequest"
}

@test "single-letter words do not survive a trip through Pascal case" {
  # `a_b_c` becomes `ABC`, and nothing in `ABC` says whether it was three words
  # or one acronym. Reading it as an acronym is what makes `XMLHttpRequest`
  # work, so this is the cost of that rule rather than a defect.
  assert_equal "$(dybatpho::string_to_pascal a_b_c)" "ABC"
  assert_equal "$(dybatpho::string_to_kebab ABC)" "abc"
}

@test "dybatpho::string_quote produces a value the shell reads back unchanged" {
  # The contract is the round trip, not the exact spelling of the escape.
  local original quoted
  for original in "a b" "" "it's" 'say "hi"' 'a$b' 'x;rm -rf /' $'tab\there' '*'; do
    quoted="$(dybatpho::string_quote "${original}")"
    assert_equal "$(eval "printf '%s' ${quoted}")" "${original}"
  done
}

@test "dybatpho::string_quote turns the empty string into something visible" {
  # Unquoted, an empty value vanishes from the command it was part of.
  assert_equal "$(dybatpho::string_quote "")" "''"
}

@test "dybatpho::string_match hands back the whole match and every group" {
  local -a parts=()
  run_traced dybatpho::string_match parts "v1.24.3" '^v([0-9]+)\.([0-9]+)\.([0-9]+)$'
  assert_success
  assert_equal "${#parts[@]}" 4
  assert_equal "${parts[0]}" "v1.24.3"
  assert_equal "${parts[1]}" "1"
  assert_equal "${parts[2]}" "24"
  assert_equal "${parts[3]}" "3"
}

@test "dybatpho::string_match keeps an unused group as an empty element" {
  local -a parts=()
  run_traced dybatpho::string_match parts "key=" '^([a-z]+)=(.*)$'
  assert_success
  assert_equal "${#parts[@]}" 3
  assert_equal "${parts[1]}" "key"
  assert_equal "${parts[2]}" ""
  run_traced dybatpho::string_match parts "ab" '^(a)(x)?(b)$'
  assert_success
  assert_equal "${#parts[@]}" 4
  assert_equal "${parts[2]}" ""
  assert_equal "${parts[3]}" "b"
}

@test "dybatpho::string_match empties the array and returns 1 on a miss" {
  local -a parts=(stale)
  run_traced dybatpho::string_match parts "main" '^v[0-9]+$'
  assert_failure 1
  assert_equal "${#parts[@]}" 0
}

@test "dybatpho::string_match returns 2 for an invalid pattern" {
  local -a parts=()
  run_traced dybatpho::string_match parts "abc" '(['
  assert_failure 2
  assert_equal "${#parts[@]}" 0
}

@test "dybatpho::string_match reads special characters in the text literally" {
  local -a parts=()
  run_traced dybatpho::string_match parts 'say "hi" $HOME * ;' '^say "(.*)" (.*)$'
  assert_success
  assert_equal "${parts[1]}" "hi"
  assert_equal "${parts[2]}" '$HOME * ;'
  run_traced dybatpho::string_match parts "" '^$'
  assert_success
  assert_equal "${parts[0]}" ""
}

@test "dybatpho::string_match rejects an invalid array name" {
  run dybatpho::string_match "not valid" "a" "a"
  assert_failure
  assert_output --partial "Invalid variable name"
}

@test "dybatpho::string_distance measures edit distance" {
  run_traced dybatpho::string_distance kitten sitting
  assert_success
  assert_output "3"
  assert_equal "$(dybatpho::string_distance color color)" "0"
  assert_equal "$(dybatpho::string_distance color colour)" "1"
  assert_equal "$(dybatpho::string_distance Color color)" "1"
  assert_equal "$(dybatpho::string_distance "" abc)" "3"
  assert_equal "$(dybatpho::string_distance abc "")" "3"
  assert_equal "$(dybatpho::string_distance "" "")" "0"
  assert_equal "$(dybatpho::string_distance 'a b*' 'a_b?')" "2"
}

@test "dybatpho::string_distance counts characters, not bytes" {
  local probe="é"
  ((${#probe} == 1)) || skip "the test locale does not decode UTF-8"
  assert_equal "$(dybatpho::string_distance café cafe)" "1"
  assert_equal "$(dybatpho::string_distance 漢字 漢)" "1"
}

@test "dybatpho::cli_levenshtein answers as dybatpho::string_distance" {
  local a b
  for a in "" color kitten; do
    for b in "" colour sitting; do
      assert_equal "$(dybatpho::cli_levenshtein "${a}" "${b}")" "$(dybatpho::string_distance "${a}" "${b}")"
    done
  done
}

@test "dybatpho::string_closest returns every candidate at the best distance" {
  local -a guesses=()
  run_traced dybatpho::string_closest guesses "staus" 2 status start stash statuses
  assert_success
  assert_equal "${guesses[*]}" "status"
  run_traced dybatpho::string_closest guesses "cat" 1 bat hat cat dog
  assert_success
  assert_equal "${guesses[*]}" "cat"
  run_traced dybatpho::string_closest guesses "cot" 1 bat cat cut cat "" dog
  assert_success
  assert_equal "${guesses[*]}" "cat cut"
}

@test "dybatpho::string_closest returns 1 when nothing is close enough" {
  local -a guesses=(stale)
  run_traced dybatpho::string_closest guesses "deploy" 1 status build
  assert_failure 1
  assert_equal "${#guesses[@]}" 0
  run_traced dybatpho::string_closest guesses "deploy" 3
  assert_failure 1
  assert_equal "${#guesses[@]}" 0
}

@test "dybatpho::string_closest with distance 0 accepts only an exact match" {
  local -a guesses=()
  run_traced dybatpho::string_closest guesses "build" 0 builds build
  assert_success
  assert_equal "${guesses[*]}" "build"
  run_traced dybatpho::string_closest guesses "buil" 0 builds build
  assert_failure 1
}

@test "dybatpho::string_closest rejects an invalid maximum distance" {
  local -a guesses=()
  run dybatpho::string_closest guesses "a" -1 a
  assert_failure
  assert_output --partial "Invalid maximum distance"
  run dybatpho::string_closest guesses "a" two a
  assert_failure
  assert_output --partial "Invalid maximum distance"
  run dybatpho::string_closest "bad name" "a" 1 a
  assert_failure
  assert_output --partial "Invalid variable name"
}
