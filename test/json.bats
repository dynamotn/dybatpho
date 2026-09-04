setup() {
  load test_helper
}

@test "dybatpho::json_query prefers yq for JSON queries" {
  local args_file="${BATS_TEST_TMPDIR}/yq-json-args"
  stub yq ": echo \"\$*\" > ${args_file}; echo '\"1.0.0\"'"
  assert_equal "$(dybatpho::json_query "package.json" ".version")" '"1.0.0"'
  assert_equal "$(cat "${args_file}")" "eval -o=json .version package.json"
  unstub yq
}

@test "dybatpho::json_has prefers yq -e semantics" {
  local args_file="${BATS_TEST_TMPDIR}/yq-json-has-args"
  stub yq ": echo \"\$*\" > ${args_file}; exit 0"
  dybatpho::json_has "package.json" ".name"
  assert_equal "$(cat "${args_file}")" "eval -e .name package.json"
  unstub yq

  stub yq ": exit 1"
  run dybatpho::json_has "package.json" ".missing"
  assert_failure
  unstub yq
}

@test "dybatpho::json_pretty prints or writes formatted JSON through yq" {
  local output_file="${BATS_TEST_TMPDIR}/pretty.json"
  stub yq \
    ": printf '{\n  \"name\": \"dybatpho\"\n}\n'" \
    ": printf '{\n  \"name\": \"dybatpho\"\n}\n'"
  run_traced dybatpho::json_pretty "package.json"
  assert_success
  assert_output << EOF
{
  "name": "dybatpho"
}
EOF

  dybatpho::json_pretty "package.json" "${output_file}"
  run_traced cat "${output_file}"
  assert_success
  assert_output << EOF
{
  "name": "dybatpho"
}
EOF
  unstub yq
}

@test "dybatpho::json_to_yaml delegates to yq" {
  local args_file="${BATS_TEST_TMPDIR}/json-to-yaml-args"
  local output_file="${BATS_TEST_TMPDIR}/converted.yaml"
  stub yq \
    ": echo \"\$*\" > ${args_file}; printf 'name: dybatpho\n'" \
    ": echo \"\$*\" > ${args_file}; printf 'name: dybatpho\n'"
  assert_equal "$(dybatpho::json_to_yaml "package.json")" "name: dybatpho"
  assert_equal "$(cat "${args_file}")" "eval -P . package.json"

  dybatpho::json_to_yaml "package.json" "${output_file}"
  assert_equal "$(cat "${output_file}")" "name: dybatpho"
  unstub yq
}

@test "dybatpho::yaml_query delegates to yq eval" {
  local args_file="${BATS_TEST_TMPDIR}/yq-args"
  stub yq ": echo \"\$*\" > ${args_file}; echo 'dybatpho'"
  assert_equal "$(dybatpho::yaml_query "compose.yaml" ".services.app.image")" "dybatpho"
  assert_equal "$(cat "${args_file}")" "eval .services.app.image compose.yaml"
  unstub yq
}

@test "dybatpho::yaml_has uses yq eval -e semantics" {
  local args_file="${BATS_TEST_TMPDIR}/yq-has-args"
  stub yq ": echo \"\$*\" > ${args_file}; exit 0"
  dybatpho::yaml_has "compose.yaml" ".services.app"
  assert_equal "$(cat "${args_file}")" "eval -e .services.app compose.yaml"
  unstub yq

  stub yq ": exit 1"
  run dybatpho::yaml_has "compose.yaml" ".missing"
  assert_failure
  unstub yq
}

@test "dybatpho::yaml_pretty prints or writes formatted YAML" {
  local output_file="${BATS_TEST_TMPDIR}/pretty.yaml"
  stub yq \
    ": printf 'name: dybatpho\nenabled: true\n'" \
    ": printf 'name: dybatpho\nenabled: true\n'"
  run_traced dybatpho::yaml_pretty "compose.yaml"
  assert_success
  assert_output << EOF
name: dybatpho
enabled: true
EOF

  dybatpho::yaml_pretty "compose.yaml" "${output_file}"
  run_traced cat "${output_file}"
  assert_success
  assert_output << EOF
name: dybatpho
enabled: true
EOF
  unstub yq
}

@test "dybatpho::yaml_to_json delegates to yq json output" {
  local args_file="${BATS_TEST_TMPDIR}/yaml-to-json-args"
  local output_file="${BATS_TEST_TMPDIR}/converted.json"
  stub yq \
    ": echo \"\$*\" > ${args_file}; printf '{\"name\":\"dybatpho\"}\n'" \
    ": echo \"\$*\" > ${args_file}; printf '{\"name\":\"dybatpho\"}\n'"
  assert_equal "$(dybatpho::yaml_to_json "compose.yaml")" '{"name":"dybatpho"}'
  assert_equal "$(cat "${args_file}")" "eval -o=json . compose.yaml"

  dybatpho::yaml_to_json "compose.yaml" "${output_file}"
  assert_equal "$(cat "${output_file}")" '{"name":"dybatpho"}'
  unstub yq
}

@test "JSON helpers fall back to jq when yq is unavailable" {
  local args_file="${BATS_TEST_TMPDIR}/jq-json-args"
  local old_path="${PATH}"
  stub jq ": echo \"\$*\" > ${args_file}; printf '42\n'"
  PATH="${BATS_MOCK_BINDIR}:/usr/bin:/bin"

  assert_equal "$(dybatpho::json_query "data.json" ".answer" --arg name value)" "42"
  assert_equal "$(cat "${args_file}")" '.answer data.json --arg name value'

  unstub jq
  PATH="${old_path}"
}

@test "JSON helpers fail clearly when neither backend is installed" {
  local empty_path="${BATS_TEST_TMPDIR}/empty-bin"
  local old_path="${PATH}"
  mkdir -p "${empty_path}"
  PATH="${empty_path}"
  run -127 dybatpho::json_query "data.json" "."
  PATH="${old_path}"
  assert_failure 127
  assert_output --partial "Neither yq nor jq is installed"
}

@test "JSON and YAML helpers propagate backend failures" {
  stub_repeated yq ": exit 9"
  run dybatpho::json_query "data.json" ".value"
  assert_failure 9
  run dybatpho::yaml_query "data.yaml" ".value"
  assert_failure 9
  unstub yq
}

@test "JSON has and pretty helpers also fall back to jq" {
  local output_file="${BATS_TEST_TMPDIR}/jq-pretty.json"
  local old_path="${PATH}"
  stub jq \
    ": exit 0" \
    ": printf '{\"ok\":true}\n'" \
    ": printf '{\"ok\":true}\n'"
  PATH="${BATS_MOCK_BINDIR}:/usr/bin:/bin"

  dybatpho::json_has "data.json" ".ok"

  assert_equal "$(dybatpho::json_pretty "data.json")" '{"ok":true}'

  dybatpho::json_pretty "data.json" "${output_file}"
  assert_equal "$(cat "${output_file}")" '{"ok":true}'

  unstub jq
  PATH="${old_path}"
}
