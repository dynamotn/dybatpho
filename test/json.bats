setup() {
  load test_helper
}

# @description Skip the test when the Go `yq` v4 is not installed.
__json_need_yq() {
  command -v yq > /dev/null || skip "yq is not installed"
  [[ "$(yq --version 2>&1)" =~ version\ v?[4-9] ]] || skip "the yq on PATH is not the Go yq v4"
}

# @description Put a fake `yq` that answers `--version` with the given line
#   first on `PATH`, and print that `PATH`.
# @arg $1 string Version line
# @stdout PATH value
__json_path_with_fake_yq() {
  local bin="${BATS_TEST_TMPDIR}/fake-yq-bin"
  mkdir -p "${bin}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" > "${bin}/yq"
  chmod +x "${bin}/yq"
  printf '%s\n' "${bin}:${PATH}"
}

__json_query_fixture() {
  local file="${BATS_TEST_TMPDIR}/query.json"
  printf '%s\n' '{"b":2,"a":1.5,"list":[3,1,2],"name":"api","flag":false}' > "${file}"
  printf '%s\n' "${file}"
}

__yaml_query_fixture() {
  local file="${BATS_TEST_TMPDIR}/query.yaml"
  printf '%s\n' '# the service' 'name: api' 'version: "1.0"' 'replicas: 3' \
    'tags: [web, edge]' 'image:' '  repo: example/api' '  tag: "2.0"' > "${file}"
  printf '%s\n' "${file}"
}

@test "dybatpho::json_query runs a jq filter and forwards jq options" {
  local file
  file="$(__json_query_fixture)"
  run_traced dybatpho::json_query "${file}" '.name'
  assert_success
  assert_output '"api"'
  run_traced dybatpho::json_query "${file}" '.[$k]' --arg k name
  assert_success
  assert_output '"api"'
  run_traced dybatpho::json_query "${file}" '.list' -c
  assert_success
  assert_output '[3,1,2]'
  run_traced dybatpho::json_query - '.list[0]' < "${file}"
  assert_success
  assert_output '3'
}

@test "dybatpho::json_query speaks jq: sorted keys, add, the ? operator, and def" {
  local file
  file="$(__json_query_fixture)"
  assert_equal "$(dybatpho::json_query "${file}" 'keys' -c)" '["a","b","flag","list","name"]'
  assert_equal "$(dybatpho::json_query "${file}" '.list | add')" '6'
  assert_equal "$(dybatpho::json_query "${file}" '[.name[]?] | length')" '0'
  assert_equal "$(dybatpho::json_query "${file}" 'def twice: . * 2; .b | twice')" '4'
  assert_equal "$(dybatpho::json_query "${file}" '.name | ascii_upcase' -r)" 'API'
}

@test "the JSON helpers print the same thing with or without yq installed" {
  # The filter language used to follow whichever program was found first, so
  # `keys` came back in another order, `add` and `?` failed, and numbers were
  # reformatted from one machine to the next. Hiding `yq` must change nothing.
  local file with without saved_path="${PATH}" filter document
  file="$(__json_query_fixture)"
  document="$(cat "${file}")"
  for filter in 'keys' '.a' '.list | sort' 'to_entries | map(.key)' '.list | add' '.flag' \
    '[.name[]?]' '{z: 1, a: 2}'; do
    with="$(dybatpho::json_query "${file}" "${filter}" -c)"
    PATH="$(path_without yq)"
    without="$(dybatpho::json_query "${file}" "${filter}" -c)"
    PATH="${saved_path}"
    assert_equal "${without}" "${with}"
  done
  with="$(dybatpho::json_get "${document}" '.a, .name, .list')$(dybatpho::json_eval "${document}" 'keys')"
  with+="$(dybatpho::json_object b 1 a:json '[1.5]')"
  PATH="$(path_without yq)"
  without="$(dybatpho::json_get "${document}" '.a, .name, .list')$(dybatpho::json_eval "${document}" 'keys')"
  without+="$(dybatpho::json_object b 1 a:json '[1.5]')"
  PATH="${saved_path}"
  assert_equal "${without}" "${with}"
}

@test "dybatpho::json_has follows jq -e and folds no output into a plain failure" {
  local file
  file="$(__json_query_fixture)"
  run_traced dybatpho::json_has "${file}" '.name'
  assert_success
  run_traced dybatpho::json_has "${file}" '.missing'
  assert_failure 1
  run_traced dybatpho::json_has "${file}" '.flag'
  assert_failure 1
  run_traced dybatpho::json_has "${file}" 'empty'
  assert_failure 1
  run_traced dybatpho::json_has "${file}" '.list | not_a_function'
  assert_failure
  assert [ "${status}" -ne 1 ]
}

@test "dybatpho::json_pretty prints or writes formatted JSON through jq" {
  local output_file="${BATS_TEST_TMPDIR}/pretty.json" input="${BATS_TEST_TMPDIR}/in.json"
  printf '%s\n' '{"name":"dybatpho","tags":["a"]}' > "${input}"
  run_traced dybatpho::json_pretty "${input}"
  assert_success
  assert_output "$(printf '{\n  "name": "dybatpho",\n  "tags": [\n    "a"\n  ]\n}')"
  dybatpho::json_pretty "${input}" "${output_file}"
  assert_equal "$(cat "${output_file}")" "${output}"
  dybatpho::json_pretty "${input}" "${input}"
  assert_equal "$(cat "${input}")" "${output}"
}

@test "dybatpho::json_to_yaml converts through yq" {
  __json_need_yq
  local input="${BATS_TEST_TMPDIR}/in.json" output_file="${BATS_TEST_TMPDIR}/converted.yaml"
  printf '%s\n' '{"name":"dybatpho","tags":["a","b"]}' > "${input}"
  run_traced dybatpho::json_to_yaml "${input}"
  assert_success
  assert_output "$(printf 'name: dybatpho\ntags:\n  - a\n  - b')"
  dybatpho::json_to_yaml "${input}" "${output_file}"
  assert_equal "$(cat "${output_file}")" "${output}"
}

@test "dybatpho::yaml_query runs a jq filter over a YAML document" {
  __json_need_yq
  local file
  file="$(__yaml_query_fixture)"
  run_traced dybatpho::yaml_query "${file}" '.image.repo'
  assert_success
  assert_output 'example/api'
  # Filters `yq` rejected or answered differently now behave as in `jq`.
  run_traced dybatpho::yaml_query "${file}" 'keys | join(",")'
  assert_output 'image,name,replicas,tags,version'
  run_traced dybatpho::yaml_query "${file}" '.tags | add'
  assert_output 'webedge'
  run_traced dybatpho::yaml_query "${file}" '[.name[]?] | length'
  assert_output '0'
  run_traced dybatpho::yaml_query "${file}" '.[$key]' --arg key version
  assert_output '1.0'
  run_traced dybatpho::yaml_query - '.replicas + 1' < "${file}"
  assert_output '4'
}

@test "dybatpho::yaml_query prints each result as YAML, one scalar per line" {
  __json_need_yq
  local file
  file="$(__yaml_query_fixture)"
  run_traced dybatpho::yaml_query "${file}" '.tags[]'
  assert_success
  assert_output "$(printf 'web\nedge')"
  run_traced dybatpho::yaml_query "${file}" '.image'
  assert_output "$(printf 'repo: example/api\ntag: "2.0"')"
  run_traced dybatpho::yaml_query "${file}" '.missing[]?'
  assert_success
  assert_output ''
  # A trailing comment in the filter must not swallow what wraps it.
  run_traced dybatpho::yaml_query "${file}" '.name # the name'
  assert_output 'api'
}

@test "dybatpho::yaml_has follows jq -e semantics" {
  __json_need_yq
  local file
  file="$(__yaml_query_fixture)"
  run_traced dybatpho::yaml_has "${file}" '.image.tag'
  assert_success
  run_traced dybatpho::yaml_has "${file}" '.missing'
  assert_failure 1
  run_traced dybatpho::yaml_has "${file}" '.tags | index("edge")'
  assert_success
  run_traced dybatpho::yaml_has "${file}" '.tags[] | select(. == "none")'
  assert_failure 1
}

@test "dybatpho::yaml_pretty prints or writes formatted YAML" {
  __json_need_yq
  local input="${BATS_TEST_TMPDIR}/in.yaml" output_file="${BATS_TEST_TMPDIR}/pretty.yaml"
  printf '{name: dybatpho, enabled: true}\n' > "${input}"
  run_traced dybatpho::yaml_pretty "${input}"
  assert_success
  assert_output "$(printf 'name: dybatpho\nenabled: true')"
  dybatpho::yaml_pretty "${input}" "${output_file}"
  assert_equal "$(cat "${output_file}")" "${output}"
}

@test "dybatpho::yaml_to_json prints JSON laid out by jq" {
  __json_need_yq
  local file output_file="${BATS_TEST_TMPDIR}/converted.json"
  file="$(__yaml_query_fixture)"
  run_traced dybatpho::yaml_to_json "${file}"
  assert_success
  assert_output "$(jq . <<< '{"name":"api","version":"1.0","replicas":3,"tags":["web","edge"],"image":{"repo":"example/api","tag":"2.0"}}')"
  dybatpho::yaml_to_json "${file}" "${output_file}"
  assert_equal "$(cat "${output_file}")" "${output}"
}

@test "dybatpho::yaml_query reads a TOML file by its extension" {
  __json_need_yq
  local file="${BATS_TEST_TMPDIR}/conf.toml"
  printf 'name = "api"\n[server]\nport = 8080\n' > "${file}"
  run_traced dybatpho::yaml_query "${file}" '.server.port'
  assert_success
  assert_output '8080'
}

@test "the JSON helpers need jq and say so, even with yq installed" {
  local file
  file="$(__json_query_fixture)"
  PATH="$(path_without jq)" run -127 dybatpho::json_query "${file}" '.'
  assert_output --partial "dybatpho::json_query: jq is not installed"
  PATH="$(path_without jq)" run -127 dybatpho::json_eval '{}' '.'
  assert_output --partial "jq is not installed"
  PATH="$(path_without jq)" run -127 dybatpho::json_object a b
  assert_output --partial "jq is not installed"
  PATH="$(path_without jq)" run -127 dybatpho::json_set "${file}" a 1
  assert_output --partial "jq is not installed"
}

@test "the YAML helpers need yq and say so, while the JSON ones keep working" {
  local yaml file saved_path="${PATH}" function
  yaml="$(__yaml_query_fixture)"
  file="$(__json_query_fixture)"
  PATH="$(path_without yq)"
  run_traced dybatpho::json_query "${file}" '.name'
  PATH="${saved_path}"
  assert_success
  assert_output '"api"'
  for function in dybatpho::yaml_query dybatpho::yaml_has; do
    PATH="$(path_without yq)" run -127 "${function}" "${yaml}" '.name'
    assert_output --partial "${function}: yq is not installed; YAML support needs the Go yq v4"
  done
  PATH="$(path_without yq)" run -127 dybatpho::yaml_to_json "${yaml}"
  assert_output --partial "yq is not installed"
  PATH="$(path_without yq)" run -127 dybatpho::json_to_yaml "${file}"
  assert_output --partial "yq is not installed"
  PATH="$(path_without yq)" run -127 dybatpho::yaml_set "${yaml}" a 1
  assert_output --partial "dybatpho::yaml_set: yq is not installed"
}

@test "the YAML helpers refuse the Python yq and a Go yq older than v4 by name" {
  local yaml
  yaml="$(__yaml_query_fixture)"
  PATH="$(__json_path_with_fake_yq 'yq 3.4.3')" run -127 dybatpho::yaml_query "${yaml}" '.name'
  assert_output --partial "the yq on PATH is the Python yq (yq 3.4.3), not the Go one"
  PATH="$(__json_path_with_fake_yq 'yq version 3.4.1')" run -127 dybatpho::yaml_pretty "${yaml}"
  assert_output --partial "the yq on PATH is too old (yq version 3.4.1)"
  PATH="$(__json_path_with_fake_yq 'something else')" run -127 dybatpho::yaml_has "${yaml}" '.name'
  assert_output --partial "cannot tell which yq is on PATH (something else)"
}

@test "the yq check runs once for as long as PATH is unchanged" {
  __json_need_yq
  local yaml count="${BATS_TEST_TMPDIR}/yq-version-calls" real_yq bin="${BATS_TEST_TMPDIR}/counting-yq"
  local saved_path="${PATH}"
  yaml="$(__yaml_query_fixture)"
  real_yq="$(command -v yq)"
  mkdir -p "${bin}"
  printf '#!/usr/bin/env bash\n[[ "$1" != --version ]] || printf x >> %q\nexec %q "$@"\n' \
    "${count}" "${real_yq}" > "${bin}/yq"
  chmod +x "${bin}/yq"
  PATH="${bin}:${PATH}"
  dybatpho::yaml_query "${yaml}" '.name' > /dev/null
  dybatpho::yaml_query "${yaml}" '.name' > /dev/null
  dybatpho::yaml_has "${yaml}" '.name'
  PATH="${saved_path}"
  assert_equal "$(cat "${count}")" "x"
}

@test "JSON and YAML helpers propagate a malformed document or filter" {
  local broken="${BATS_TEST_TMPDIR}/broken.json"
  printf '%s\n' '{"a":' > "${broken}"
  run_traced dybatpho::json_query "${broken}" '.a'
  assert_failure
  run_traced dybatpho::json_pretty "${broken}"
  assert_failure
  run_traced dybatpho::json_eval '{"a":' '.a'
  assert_failure
  __json_need_yq
  local yaml="${BATS_TEST_TMPDIR}/broken.yaml"
  printf 'a: [1,\n' > "${yaml}"
  run_traced dybatpho::yaml_query "${yaml}" '.a'
  assert_failure
  run_traced dybatpho::yaml_has "${yaml}" '.a'
  assert_failure
  run_traced dybatpho::yaml_to_json "${yaml}"
  assert_failure
  run_traced dybatpho::yaml_query "$(__yaml_query_fixture)" '.name | not_a_function'
  assert_failure
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

@test "dybatpho::json_string needs no jq" {
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

@test "dybatpho::json_valid accepts null and false and refuses blank text" {
  # `jq -e` fails on a document whose value is `null` or `false`, which is a
  # statement about the value, not about whether the text is JSON.
  local document
  for document in null false 0 '"text"' '{"a":null}'; do
    run_traced dybatpho::json_valid "${document}"
    assert_success
  done
  for document in ' ' '{' 'not json'; do
    run_traced dybatpho::json_valid "${document}"
    assert_failure
  done
}

@test "the in-memory helpers round-trip a document through both directions" {
  local document
  document=$(dybatpho::json_object text "$(printf 'quote " and\nnewline')")
  dybatpho::json_valid "${document}"
  assert_equal "$(dybatpho::json_get "${document}" '.text')" "$(printf 'quote " and\nnewline')"
}

# ---------------------------------------------------------------------------
# Editing documents
# ---------------------------------------------------------------------------

# @description Print a PATH holding the real `jq` and the tools the editing
#   helpers reach for, but no `yq`, to prove nothing JSON needs it.
# @stdout PATH value
__json_path_jq_only() {
  local bin="${BATS_TEST_TMPDIR}/jq-only-bin" tool
  mkdir -p "${bin}"
  for tool in bash cat chmod date env jq mktemp mv rm sed tr; do
    ln -sf "$(command -v "${tool}")" "${bin}/${tool}"
  done
  printf '%s\n' "${bin}"
}

# @description Run a command once with `yq` on PATH and once with only `jq`,
#   and fail unless both print the same thing.
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

@test "the editing helpers fail clearly without their command" {
  local empty_path="${BATS_TEST_TMPDIR}/empty-bin" saved_path="${PATH}"
  mkdir -p "${empty_path}"
  PATH="${empty_path}"
  run -127 dybatpho::json_set data.json a 1
  PATH="${saved_path}"
  assert_output --partial "dybatpho::json_set: jq is not installed"

  PATH="$(__json_path_jq_only)"
  run -127 dybatpho::yaml_set data.yaml a 1
  PATH="${saved_path}"
  assert_output --partial "dybatpho::yaml_set: yq is not installed"
}

@test "dybatpho::yaml_set edits a YAML document and keeps its comments" {
  local file="${BATS_TEST_TMPDIR}/values.yaml"
  printf 'name: app # the service\nimage:\n  tag: "1.0"\n' > "${file}"
  dybatpho::yaml_set "${file}" image.tag 2.0 "${file}"
  dybatpho::yaml_set --json "${file}" replicas 3 "${file}"
  dybatpho::yaml_set "${file}" port 8080 "${file}"
  run_traced cat "${file}"
  assert_success
  assert_output - << 'EOF2'
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
  assert_output - << 'EOF2'
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
  assert_output - << 'EOF2'
a: 1 # kept
b:
  x: 1
  y: 2
EOF2
  run_traced --separate-stderr dybatpho::yaml_merge "${base}" "${list}"
  assert_failure
  assert_stderr --partial "both documents must be objects"
}
