setup() {
  load test_helper
}

@test "dybatpho::require installed tool" {
  run dybatpho::require "bash"
  assert_success
}

@test "dybatpho::require not installed tool" {
  bats_require_minimum_version 1.5.0
  run -127 dybatpho::require "dyfoooo"
  assert_failure
  assert_output --partial "dyfoooo isn't installed"
}

@test "dybatpho::is with empty" {
  run dybatpho::is
  assert_failure
}

@test "dybatpho::is command" {
  run dybatpho::is "command" "bash"
  assert_success
  run dybatpho::is "command" "dyfoooo"
  assert_failure
}

@test "dybatpho::is file" {
  run dybatpho::is "file" "${BASH_SOURCE[0]}"
  assert_success
  run dybatpho::is "file" "dyfoooo"
  assert_failure
}

@test "dybatpho::is dir" {
  run dybatpho::is "dir" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  run dybatpho::is "dir" "dyfoooo"
  assert_failure
}

@test "dybatpho::is link" {
  local temp=$(mktemp)
  trap "rm -f $temp" EXIT
  ln -sf "${BASH_SOURCE[0]}" "$temp"
  run dybatpho::is "link" "$temp"
  assert_success
  run dybatpho::is "link" "dyfoooo"
  assert_failure
}

@test "dybatpho::is exist" {
  run dybatpho::is "exist" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  run dybatpho::is "exist" "dyfoooo"
  assert_failure
}

@test "dybatpho::is readable" {
  run dybatpho::is "readable" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  run dybatpho::is "readable" "/root"
  assert_failure
}

@test "dybatpho::is writeable" {
  run dybatpho::is "writeable" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  run dybatpho::is "writeable" "/root"
  assert_failure
}

@test "dybatpho::is executable" {
  run dybatpho::is "executable" "${DYBATPHO_DIR}/test.sh"
  assert_success
  run dybatpho::is "executable" "/root"
  assert_failure
}

@test "dybatpho::is set" {
  local dyfoooo=""
  run dybatpho::is "set" "$dyfoooo"
  assert_failure
  dyfoooo="v"
  run dybatpho::is "set" "$dyfoooo"
  assert_success
}

@test "dybatpho::is empty" {
  local dyfoooo=""
  run dybatpho::is "empty" "$dyfoooo"
  assert_success
}

@test "dybatpho::is number" {
  run dybatpho::is "number" "1.11"
  assert_success
  run dybatpho::is "number" "1a"
  assert_failure
}

@test "dybatpho::is int" {
  run dybatpho::is "int" "11"
  assert_success
  run dybatpho::is "int" "1.11"
  assert_failure
  run dybatpho::is "int" "1a"
  assert_failure
}

@test "dybatpho::is true" {
  run dybatpho::is "true" "0"
  assert_success
  run dybatpho::is "true" "tRuE"
  assert_success
  run dybatpho::is "true" "YeS"
  assert_success
  run dybatpho::is "true" "oN"
  assert_success
  run dybatpho::is "true" ""
  assert_failure
  run dybatpho::is "true" "dyfoooo"
  assert_failure
}

@test "dybatpho::is false" {
  run dybatpho::is "false" "1"
  assert_success
  run dybatpho::is "false" "FaLsE"
  assert_success
  run dybatpho::is "false" "nO"
  assert_success
  run dybatpho::is "false" "oFf"
  assert_success
  run dybatpho::is "false" ""
  assert_failure
  run dybatpho::is "false" "dyfoooo"
  assert_failure
}
