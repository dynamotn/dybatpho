setup() {
  load test_helper
}

# @description Print a PATH that has the stubs and the few tools they need, but
#   no real `yq`. Dropping to `/usr/bin:/bin` is not enough: a stock Ubuntu
#   runner ships `yq` in `/usr/bin`.
# @stdout PATH value
__json_path_without_yq() {
  local bin="${BATS_TEST_TMPDIR}/no-yq-bin" tool
  mkdir -p "${bin}"
  for tool in bash cat rm sed tr; do
    ln -sf "$(command -v "${tool}")" "${bin}/${tool}"
  done
  printf '%s\n' "${BATS_MOCK_BINDIR}:${bin}"
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
  run_traced dybatpho::json_has "package.json" ".missing"
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
  run_traced dybatpho::yaml_has "compose.yaml" ".missing"
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
  PATH="$(__json_path_without_yq)"

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
  run_traced dybatpho::json_query "data.json" ".value"
  assert_failure 9
  run_traced dybatpho::yaml_query "data.yaml" ".value"
  assert_failure 9
  unstub yq
}

# ---------------------------------------------------------------------------
# In-memory document helpers
# ---------------------------------------------------------------------------

@test "dybatpho::json_string no arg" {
  run dybatpho::json_string
  assert_failure
}

@test "dybatpho::json_string quotes and escapes a value" {
  assert_equal "$(dybatpho::json_string 'plain')" '"plain"'
  assert_equal "$(dybatpho::json_string 'he said "hi"')" '"he said \"hi\""'
  assert_equal "$(dybatpho::json_string 'back\slash')" '"back\\slash"'
  assert_equal "$(dybatpho::json_string "$(printf 'l1\nl2')")" '"l1\nl2"'
}

@test "dybatpho::json_string encodes an empty value" {
  assert_equal "$(dybatpho::json_string '')" '""'
}

@test "dybatpho::json_string escapes every control character JSON requires" {
  assert_equal "$(dybatpho::json_string "$(printf 'a\tb')")" '"a\tb"'
  assert_equal "$(dybatpho::json_string "$(printf 'a\rb')")" '"a\rb"'
  assert_equal "$(dybatpho::json_string "$(printf 'a\bb')")" '"a\bb"'
  assert_equal "$(dybatpho::json_string "$(printf 'a\fb')")" '"a\fb"'
  # No short escape exists for these, so they go out as \u00XX.
  assert_equal "$(dybatpho::json_string "$(printf 'a\001\037b')")" '"a\u0001\u001fb"'
  assert_equal "$(dybatpho::json_string "$(printf 'a\177b')")" '"a\u007fb"'
}

@test "dybatpho::json_string passes UTF-8 through instead of escaping it" {
  # Quoting is done in the shell now, one character at a time. Walking bytes
  # rather than characters would cut a multi-byte one in half, and treating a
  # character as a control one by a locale-collated range would escape it.
  assert_equal "$(dybatpho::json_string 'héllo 日本語 đường')" \
    '"héllo 日本語 đường"'
}

@test "dybatpho::json_string needs neither yq nor jq" {
  # It is the one JSON helper that is pure shell, so a script that only builds
  # values keeps working on a host with no JSON tool installed.
  local saved_path="${PATH}"
  PATH="${BATS_TEST_TMPDIR}"
  hash -r
  run_traced dybatpho::json_string 'still works'
  PATH="${saved_path}"
  hash -r
  assert_success
  assert_output '"still works"'
}

@test "dybatpho::json_object rejects an odd number of arguments" {
  run --separate-stderr dybatpho::json_object name
  assert_failure
  assert_stderr --partial "even number of arguments"
}

@test "dybatpho::json_object builds an empty object with no arguments" {
  assert_equal "$(dybatpho::json_object)" "{}"
}

@test "dybatpho::json_object escapes every value" {
  local document
  document=$(dybatpho::json_object status ok message 'it "worked"')
  assert_equal "$(dybatpho::json_get "${document}" '.status')" "ok"
  assert_equal "$(dybatpho::json_get "${document}" '.message')" 'it "worked"'
}

@test "dybatpho::json_object keeps a value that looks like YAML as a string" {
  local document
  document=$(dybatpho::json_object note 'key: value' flag 'true')
  assert_equal "$(dybatpho::json_get "${document}" '.note')" "key: value"
  assert_equal "$(dybatpho::json_eval "${document}" '.flag')" '"true"'
}

@test "dybatpho::json_object nests an already encoded document" {
  local document
  document=$(dybatpho::json_object name api ports:json '[80,443]' meta:json '{"tier":1}')
  assert_equal "$(dybatpho::json_get "${document}" '.ports[1]')" "443"
  assert_equal "$(dybatpho::json_get "${document}" '.meta.tier')" "1"
}

@test "dybatpho::json_object accepts a name containing spaces" {
  local document
  document=$(dybatpho::json_object 'two words' value)
  # Bracket syntax is the form both backends accept for an awkward key.
  assert_equal "$(dybatpho::json_get "${document}" '.["two words"]')" "value"
}

@test "dybatpho::json_eval no arg" {
  run dybatpho::json_eval
  assert_failure
}

@test "dybatpho::json_eval returns compact JSON" {
  assert_equal "$(dybatpho::json_eval '{"a":[1,2]}' '.a')" "[1,2]"
  assert_equal "$(dybatpho::json_eval '[]' '. + [{"a":1}]')" '[{"a":1}]'
}

@test "dybatpho::json_get no arg" {
  run dybatpho::json_get
  assert_failure
}

@test "dybatpho::json_get returns a bare scalar" {
  assert_equal "$(dybatpho::json_get '{"a":"x y"}' '.a')" "x y"
  assert_equal "$(dybatpho::json_get '{"a":"x: y"}' '.a')" "x: y"
  assert_equal "$(dybatpho::json_get '{"a":2}' '.a')" "2"
}

@test "dybatpho::json_get falls back through the alternative operator" {
  assert_equal "$(dybatpho::json_get '{}' '.missing // "none"')" "none"
}

@test "dybatpho::json_valid no arg" {
  run dybatpho::json_valid
  assert_failure
}

@test "dybatpho::json_valid separates documents from prose" {
  run_traced dybatpho::json_valid '{"a":1}'
  assert_success
  run_traced dybatpho::json_valid '[1,2]'
  assert_success
  run_traced dybatpho::json_valid 'definitely not json'
  assert_failure
  run_traced dybatpho::json_valid '{"a":'
  assert_failure
}

@test "dybatpho::json_valid accepts null and false and refuses blank text on both backends" {
  # `jq -e` fails on a document whose value is `null` or `false`, which is a
  # statement about the value, not about whether the text is JSON.
  command -v yq > /dev/null || skip "yq is not installed"
  local saved_path="${PATH}" backend document
  for backend in yq jq; do
    if [[ "${backend}" == jq ]]; then
      PATH="$(__json_path_jq_only)"
      hash -r
    fi
    for document in null false 0 '"text"' '{"a":null}'; do
      dybatpho::json_valid "${document}" \
        || { PATH="${saved_path}"; printf '%s refused %s\n' "${backend}" "${document}" >&2; return 1; }
    done
    for document in ' ' '{' 'not json'; do
      ! dybatpho::json_valid "${document}" \
        || { PATH="${saved_path}"; printf '%s accepted [%s]\n' "${backend}" "${document}" >&2; return 1; }
    done
  done
  PATH="${saved_path}"
  hash -r
}

@test "the in-memory helpers round-trip a document through both directions" {
  local document
  document=$(dybatpho::json_object text "$(printf 'quote " and\nnewline')")
  dybatpho::json_valid "${document}"
  assert_equal "$(dybatpho::json_get "${document}" '.text')" "$(printf 'quote " and\nnewline')"
}

@test "JSON has and pretty helpers also fall back to jq" {
  local output_file="${BATS_TEST_TMPDIR}/jq-pretty.json"
  local old_path="${PATH}"
  stub jq \
    ": exit 0" \
    ": printf '{\"ok\":true}\n'" \
    ": printf '{\"ok\":true}\n'"
  PATH="$(__json_path_without_yq)"

  dybatpho::json_has "data.json" ".ok"

  assert_equal "$(dybatpho::json_pretty "data.json")" '{"ok":true}'

  dybatpho::json_pretty "data.json" "${output_file}"
  assert_equal "$(cat "${output_file}")" '{"ok":true}'

  unstub jq
  PATH="${old_path}"
}

# ---------------------------------------------------------------------------
# Editing documents
# ---------------------------------------------------------------------------

# @description Print a PATH holding the real `jq` and the tools the editing
#   helpers reach for, but no `yq`, so the fallback runs for real.
# @stdout PATH value
__json_path_jq_only() {
  local bin="${BATS_TEST_TMPDIR}/jq-only-bin" tool
  mkdir -p "${bin}"
  for tool in bash cat chmod date env jq mktemp mv rm sed tr; do
    ln -sf "$(command -v "${tool}")" "${bin}/${tool}"
  done
  printf '%s\n' "${bin}"
}

# @description Run a command once with `yq` and once with only `jq`, and fail
#   unless both print the same thing.
# @arg $@ string Command to run
# @stdout The shared output
__json_both_backends() {
  local with_yq with_jq saved_path="${PATH}"
  with_yq="$("$@")" || return
  PATH="$(__json_path_jq_only)"
  hash -r
  with_jq="$("$@")" || {
    PATH="${saved_path}"
    hash -r
    return 1
  }
  PATH="${saved_path}"
  hash -r
  assert_equal "${with_jq}" "${with_yq}"
  printf '%s\n' "${with_yq}"
}

# @description Compact a JSON document so assertions do not depend on layout.
# @arg $1 string JSON document
# @stdout Compact JSON
__json_compact() {
  jq -c . <<< "$1"
}

__json_fixture() {
  local file="${BATS_TEST_TMPDIR}/doc.json"
  printf '%s\n' '{"a":{"b":[1,2]},"k":"v"}' > "${file}"
  printf '%s\n' "${file}"
}

@test "dybatpho::json_set sets a nested value and creates what is missing" {
  local file result
  file="$(__json_fixture)"
  result="$(__json_both_backends dybatpho::json_set "${file}" a.c.d hello)"
  assert_equal "$(__json_compact "${result}")" '{"a":{"b":[1,2],"c":{"d":"hello"}},"k":"v"}'

  result="$(__json_both_backends dybatpho::json_set "${file}" .a.b.1 two)"
  assert_equal "$(__json_compact "${result}")" '{"a":{"b":[1,"two"]},"k":"v"}'

  result="$(__json_both_backends dybatpho::json_set "${file}" a.new.0.z x)"
  assert_equal "$(__json_compact "${result}")" '{"a":{"b":[1,2],"new":[{"z":"x"}]},"k":"v"}'
}

@test "dybatpho::json_set stores a string unless --json says otherwise" {
  local file result
  file="$(__json_fixture)"
  result="$(__json_both_backends dybatpho::json_set "${file}" n 42)"
  assert_equal "$(jq -c .n <<< "${result}")" '"42"'

  result="$(__json_both_backends dybatpho::json_set --json "${file}" n 42)"
  assert_equal "$(jq -c .n <<< "${result}")" '42'
  result="$(__json_both_backends dybatpho::json_set --json "${file}" n true)"
  assert_equal "$(jq -c .n <<< "${result}")" 'true'
  result="$(__json_both_backends dybatpho::json_set --json "${file}" n null)"
  assert_equal "$(jq -c .n <<< "${result}")" 'null'
  result="$(__json_both_backends dybatpho::json_set --json "${file}" n '{"x":[1,{"y":2}]}')"
  assert_equal "$(jq -c .n <<< "${result}")" '{"x":[1,{"y":2}]}'
}

@test "dybatpho::json_set never reads the path or the value as a filter" {
  local file result value
  file="$(__json_fixture)"
  value="$(printf 'it "worked"\n$(whoami) ; .k = 1 | \\')"
  result="$(__json_both_backends dybatpho::json_set "${file}" note "${value}")"
  assert_equal "$(jq -r .note <<< "${result}")" "${value}"
  assert_equal "$(jq -r .k <<< "${result}")" "v"

  result="$(__json_both_backends dybatpho::json_set "${file}" '"] | \.k = 1 | \.["x' y)"
  assert_equal "$(jq -r .k <<< "${result}")" "v"
  assert_equal "$(jq -r '.["\"] | .k = 1 | .[\"x"]' <<< "${result}")" "y"
}

@test "dybatpho::json_set reads escapes in a path" {
  local file result
  file="$(__json_fixture)"
  result="$(__json_both_backends dybatpho::json_set "${file}" 'k\.dot' v)"
  assert_equal "$(jq -r '.["k.dot"]' <<< "${result}")" "v"
  result="$(__json_both_backends dybatpho::json_set "${file}" 'a.\0' zero)"
  assert_equal "$(jq -r '.a["0"]' <<< "${result}")" "zero"
  result="$(__json_both_backends dybatpho::json_set "${file}" 'back\\slash' v)"
  assert_equal "$(jq -r '.["back\\slash"]' <<< "${result}")" "v"
  result="$(__json_both_backends dybatpho::json_set "${file}" 'two words' v)"
  assert_equal "$(jq -r '.["two words"]' <<< "${result}")" "v"
}

@test "dybatpho::json_set refuses a path through the wrong kind of value" {
  local file saved_path="${PATH}" path
  file="$(__json_fixture)"
  for path in k.x a.0 a.b.x; do
    run_traced --separate-stderr dybatpho::json_set "${file}" "${path}" 1
    assert_failure
    assert_stderr --partial "Cannot set '${path}'"

    PATH="$(__json_path_jq_only)"
    run_traced --separate-stderr dybatpho::json_set "${file}" "${path}" 1
    PATH="${saved_path}"
    assert_failure
    assert_stderr --partial "Cannot set '${path}'"
  done
}

@test "dybatpho::json_set rejects a malformed path, value, or argument list" {
  local file path
  file="$(__json_fixture)"
  for path in '' '.' '..' 'a..b' 'a.' 'a\' '1234567890123456789'; do
    run --separate-stderr dybatpho::json_set "${file}" "${path}" v
    assert_failure
    assert_stderr --partial "Invalid path"
  done
  run --separate-stderr dybatpho::json_set --json "${file}" a 'not json'
  assert_failure
  assert_stderr --partial "not valid JSON"
  run --separate-stderr dybatpho::json_set "${file}" a
  assert_failure
  assert_stderr --partial "Expected [--json]"
}

@test "dybatpho::json_set writes a file in place, and leaves it alone on failure" {
  local file
  file="$(__json_fixture)"
  dybatpho::json_set "${file}" k changed "${file}"
  assert_equal "$(jq -c . "${file}")" '{"a":{"b":[1,2]},"k":"changed"}'

  run_traced dybatpho::json_set "${file}" k.x 1 "${file}"
  assert_failure
  assert_equal "$(jq -c . "${file}")" '{"a":{"b":[1,2]},"k":"changed"}'
}

@test "dybatpho::json_set reads stdin" {
  local result
  result="$(printf '%s' '{"a":1}' | dybatpho::json_set - b 2)"
  assert_equal "$(__json_compact "${result}")" '{"a":1,"b":"2"}'
}

@test "dybatpho::json_del removes keys and elements" {
  local file result
  file="$(__json_fixture)"
  result="$(__json_both_backends dybatpho::json_del "${file}" k)"
  assert_equal "$(__json_compact "${result}")" '{"a":{"b":[1,2]}}'
  result="$(__json_both_backends dybatpho::json_del "${file}" a.b.0)"
  assert_equal "$(__json_compact "${result}")" '{"a":{"b":[2]},"k":"v"}'
}

@test "dybatpho::json_del leaves the document alone when the path is absent" {
  local file result path
  file="$(__json_fixture)"
  for path in missing a.b.9 k.x zz.q.0 a.0 a.b.x; do
    result="$(__json_both_backends dybatpho::json_del "${file}" "${path}")"
    assert_equal "$(__json_compact "${result}")" '{"a":{"b":[1,2]},"k":"v"}'
  done
}

@test "dybatpho::json_del writes in place and rejects a malformed path" {
  local file
  file="$(__json_fixture)"
  dybatpho::json_del "${file}" a "${file}"
  assert_equal "$(jq -c . "${file}")" '{"k":"v"}'
  run --separate-stderr dybatpho::json_del "${file}" 'a..b'
  assert_failure
  assert_stderr --partial "Invalid path"
  run --separate-stderr dybatpho::json_del "${file}"
  assert_failure
  assert_stderr --partial "Expected <input> <path>"
}

@test "dybatpho::json_merge deep-merges objects, the overlay winning" {
  local base="${BATS_TEST_TMPDIR}/base.json" overlay="${BATS_TEST_TMPDIR}/overlay.json" result
  printf '%s\n' '{"a":{"x":1,"l":[1,2]},"keep":true}' > "${base}"
  printf '%s\n' '{"a":{"y":2,"l":[3]},"keep":null}' > "${overlay}"
  result="$(__json_both_backends dybatpho::json_merge "${base}" "${overlay}")"
  assert_equal "$(__json_compact "${result}")" '{"a":{"x":1,"l":[3],"y":2},"keep":null}'

  result="$(dybatpho::json_merge - "${overlay}" < "${base}")"
  assert_equal "$(__json_compact "${result}")" '{"a":{"x":1,"l":[3],"y":2},"keep":null}'

  dybatpho::json_merge "${base}" "${overlay}" "${base}"
  assert_equal "$(jq -c . "${base}")" '{"a":{"x":1,"l":[3],"y":2},"keep":null}'
}

@test "dybatpho::json_merge refuses a document that is not an object" {
  local base="${BATS_TEST_TMPDIR}/base.json" other="${BATS_TEST_TMPDIR}/other.json"
  local saved_path="${PATH}" document
  printf '%s\n' '{"a":1}' > "${base}"
  for document in '[1,2]' 'null' '"text"'; do
    printf '%s\n' "${document}" > "${other}"
    run_traced --separate-stderr dybatpho::json_merge "${base}" "${other}"
    assert_failure
    assert_stderr --partial "both documents must be objects"
    PATH="$(__json_path_jq_only)"
    run_traced --separate-stderr dybatpho::json_merge "${other}" "${base}"
    PATH="${saved_path}"
    assert_failure
    assert_stderr --partial "both documents must be objects"
  done
  run --separate-stderr dybatpho::json_merge "${base}"
  assert_failure
  assert_stderr --partial "Expected <base> <overlay>"
}

@test "the JSON editing helpers propagate a malformed document" {
  local file="${BATS_TEST_TMPDIR}/broken.json" saved_path="${PATH}"
  printf '%s\n' '{"a":' > "${file}"
  run_traced dybatpho::json_set "${file}" a 1
  assert_failure
  run_traced dybatpho::json_del "${file}" a
  assert_failure
  PATH="$(__json_path_jq_only)"
  run_traced dybatpho::json_set "${file}" a 1
  PATH="${saved_path}"
  assert_failure
}

@test "the editing helpers fail clearly without a backend" {
  local empty_path="${BATS_TEST_TMPDIR}/empty-bin" saved_path="${PATH}"
  mkdir -p "${empty_path}"
  PATH="${empty_path}"
  run -127 dybatpho::json_set data.json a 1
  PATH="${saved_path}"
  assert_output --partial "Neither yq nor jq is installed"

  PATH="$(__json_path_jq_only)"
  run -127 dybatpho::yaml_set data.yaml a 1
  PATH="${saved_path}"
  assert_output --partial "yq"
}

@test "dybatpho::yaml_set edits a YAML document and keeps its comments" {
  local file="${BATS_TEST_TMPDIR}/values.yaml"
  printf 'name: app # the service\nimage:\n  tag: "1.0"\n' > "${file}"
  dybatpho::yaml_set "${file}" image.tag 2.0 "${file}"
  dybatpho::yaml_set --json "${file}" replicas 3 "${file}"
  dybatpho::yaml_set "${file}" port 8080 "${file}"
  run_traced cat "${file}"
  assert_success
  assert_output << 'EOF2'
name: app # the service
image:
  tag: "2.0"
replicas: 3
port: "8080"
EOF2
  run_traced --separate-stderr dybatpho::yaml_set "${file}" name.x 1
  assert_failure
  assert_stderr --partial "Cannot set 'name.x'"
}

@test "dybatpho::yaml_del removes a path and ignores an absent one" {
  local file="${BATS_TEST_TMPDIR}/values.yaml"
  printf 'a: 1 # one\nb:\n  - x\n  - y\n' > "${file}"
  run_traced dybatpho::yaml_del "${file}" b.0
  assert_success
  assert_output << 'EOF2'
a: 1 # one
b:
  - y
EOF2
  run_traced dybatpho::yaml_del "${file}" b.5
  assert_success
  assert_output "$(cat "${file}")"
  run --separate-stderr dybatpho::yaml_del "${file}" ''
  assert_failure
  assert_stderr --partial "Invalid path"
}

@test "dybatpho::yaml_merge deep-merges mappings" {
  local base="${BATS_TEST_TMPDIR}/base.yaml" overlay="${BATS_TEST_TMPDIR}/overlay.yaml"
  local list="${BATS_TEST_TMPDIR}/list.yaml"
  printf 'a: 1 # kept\nb:\n  x: 1\n' > "${base}"
  printf 'b:\n  y: 2\n' > "${overlay}"
  printf -- '- 1\n' > "${list}"
  run_traced dybatpho::yaml_merge "${base}" "${overlay}"
  assert_success
  assert_output << 'EOF2'
a: 1 # kept
b:
  x: 1
  y: 2
EOF2
  run_traced --separate-stderr dybatpho::yaml_merge "${base}" "${list}"
  assert_failure
  assert_stderr --partial "both documents must be objects"
}
