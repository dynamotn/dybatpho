setup() {
  load test_helper
}

@test "dybatpho::json_query prefers yq for JSON queries" {
  local args_file="${BATS_TEST_TMPDIR}/yq-json-args"
  stub yq ": echo \"\$*\" > ${args_file}; echo '\"1.0.0\"'"
  run dybatpho::json_query "package.json" ".version"
  assert_success
  assert_output '"1.0.0"'
  run cat "${args_file}"
  assert_success
  assert_output "eval -o=json .version package.json"
  unstub yq
}

@test "dybatpho::json_has prefers yq -e semantics" {
  local args_file="${BATS_TEST_TMPDIR}/yq-json-has-args"
  stub yq ": echo \"\$*\" > ${args_file}; exit 0"
  run dybatpho::json_has "package.json" ".name"
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "eval -e .name package.json"
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
  run dybatpho::json_pretty "package.json"
  assert_success
  assert_output << EOF
{
  "name": "dybatpho"
}
EOF

  run dybatpho::json_pretty "package.json" "${output_file}"
  assert_success
  run cat "${output_file}"
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
  run dybatpho::json_to_yaml "package.json"
  assert_success
  assert_output "name: dybatpho"
  run cat "${args_file}"
  assert_success
  assert_output "eval -P . package.json"

  run dybatpho::json_to_yaml "package.json" "${output_file}"
  assert_success
  run cat "${output_file}"
  assert_success
  assert_output "name: dybatpho"
  unstub yq
}

@test "dybatpho::yaml_query delegates to yq eval" {
  local args_file="${BATS_TEST_TMPDIR}/yq-args"
  stub yq ": echo \"\$*\" > ${args_file}; echo 'dybatpho'"
  run dybatpho::yaml_query "compose.yaml" ".services.app.image"
  assert_success
  assert_output "dybatpho"
  run cat "${args_file}"
  assert_success
  assert_output "eval .services.app.image compose.yaml"
  unstub yq
}

@test "dybatpho::yaml_has uses yq eval -e semantics" {
  local args_file="${BATS_TEST_TMPDIR}/yq-has-args"
  stub yq ": echo \"\$*\" > ${args_file}; exit 0"
  run dybatpho::yaml_has "compose.yaml" ".services.app"
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "eval -e .services.app compose.yaml"
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
  run dybatpho::yaml_pretty "compose.yaml"
  assert_success
  assert_output << EOF
name: dybatpho
enabled: true
EOF

  run dybatpho::yaml_pretty "compose.yaml" "${output_file}"
  assert_success
  run cat "${output_file}"
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
  run dybatpho::yaml_to_json "compose.yaml"
  assert_success
  assert_output '{"name":"dybatpho"}'
  run cat "${args_file}"
  assert_success
  assert_output "eval -o=json . compose.yaml"

  run dybatpho::yaml_to_json "compose.yaml" "${output_file}"
  assert_success
  run cat "${output_file}"
  assert_success
  assert_output '{"name":"dybatpho"}'
  unstub yq
}
