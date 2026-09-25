setup() {
  load test_helper
}

@test "config_load loads dotenv files and later files override earlier values" {
  local base="${BATS_TEST_TMPDIR}/base.env"
  local local_config="${BATS_TEST_TMPDIR}/local.env"
  printf 'HOST=example.test\nPORT=80\n' > "${base}"
  printf 'PORT=443\nMESSAGE="hello world"\n' > "${local_config}"

  dybatpho::config_load "${base}" "${local_config}"
  assert_equal "$(dybatpho::config_get HOST)" "example.test"
  assert_equal "$(dybatpho::config_get PORT)" "443"
  assert_equal "$(dybatpho::config_get MESSAGE)" "hello world"
}

@test "config_env applies prefixed environment variables" {
  export APP_HOST="env.test"
  dybatpho::config_env APP_
  assert_equal "$(dybatpho::config_get HOST)" "env.test"
  unset APP_HOST
}

@test "config_get supports defaults and config_export exports values" {
  assert_equal "$(dybatpho::config_get MISSING fallback)" "fallback"

  __dybatpho_config_set EXPORTED "value"
  dybatpho::config_export
  assert_equal "${EXPORTED}" "value"
}

@test "config_load rejects unsupported files and missing files" {
  run dybatpho::config_load "${BATS_TEST_TMPDIR}/missing.conf"
  assert_failure
  assert_output --partial "Configuration file not found"

  local config="${BATS_TEST_TMPDIR}/config.txt"
  : > "${config}"
  run dybatpho::config_load "${config}"
  assert_failure
  assert_output --partial "Unsupported configuration format"
}

@test "config_load parses dotenv comments, quoting, and escaped values" {
  local config="${BATS_TEST_TMPDIR}/quoted.dotenv"
  printf '%s\n' \
    '# comment' \
    'PLAIN=value # inline comment' \
    'DOUBLE="line\nvalue"' \
    "SINGLE='literal # value'" \
    'SPACED = trimmed' > "${config}"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${config}"
  assert_equal "$(dybatpho::config_get PLAIN)" "value"
  assert_equal "$(dybatpho::config_get DOUBLE)" $'line\nvalue'
  assert_equal "$(dybatpho::config_get SINGLE)" 'literal # value'
  assert_equal "$(dybatpho::config_get SPACED)" "trimmed"
}

@test "config_load supports JSON and YAML files with precedence" {
  local json_file="${BATS_TEST_TMPDIR}/settings.json"
  local yaml_file="${BATS_TEST_TMPDIR}/settings.yaml"
  printf '{}' > "${json_file}"
  printf '{}' > "${yaml_file}"
  stub jq ": printf 'PORT\\t8080\\nSHARED\\tfrom-json\\n'"
  # `yq` is asked for the root tag before the entries, so a sequence or a
  # scalar is rejected instead of being loaded under positional keys.
  stub yq ": printf '!!map\\n'" ": printf 'SHARED\\tfrom-yaml\\nHOST\\tlocalhost\\n'"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${json_file}" "${yaml_file}"
  assert_equal "$(dybatpho::config_get PORT)" "8080"
  assert_equal "$(dybatpho::config_get SHARED)" "from-yaml"
  assert_equal "$(dybatpho::config_get HOST)" "localhost"
  unstub jq
  unstub yq
}

@test "config_load reports invalid dotenv and structured configuration" {
  local dotenv="${BATS_TEST_TMPDIR}/invalid.env"
  local json_file="${BATS_TEST_TMPDIR}/invalid.json"
  local yaml_file="${BATS_TEST_TMPDIR}/invalid.yaml"
  printf 'not an assignment\n' > "${dotenv}"
  run dybatpho::config_load "${dotenv}"
  assert_failure
  assert_output --partial "Invalid dotenv entry"

  printf '{}' > "${json_file}"
  stub jq ": exit 1"
  run dybatpho::config_load "${json_file}"
  assert_failure
  assert_output --partial "Invalid JSON configuration"
  unstub jq

  printf '{}' > "${yaml_file}"
  stub yq ": exit 1"
  run dybatpho::config_load "${yaml_file}"
  assert_failure
  assert_output --partial "Invalid YAML configuration"
  unstub yq
}

@test "config_get and config_require validate keys and missing values" {
  DYBATPHO_CONFIG=()
  run ! dybatpho::config_get MISSING
  __dybatpho_config_set PRESENT "yes"
  dybatpho::config_require PRESENT

  run --separate-stderr dybatpho::config_get "bad key"
  assert_failure
  assert_stderr --partial "Invalid configuration key"

  run dybatpho::config_require
  assert_failure

  run --separate-stderr dybatpho::config_require MISSING
  assert_failure
  assert_stderr --partial "Required configuration is missing"
}

@test "config_env applies only matching prefixed variables" {
  export DYBATPHO_CONFIG_ENV_TEST="loaded"
  export UNRELATED_CONFIG_ENV_TEST="ignored"
  DYBATPHO_CONFIG=()
  dybatpho::config_env DYBATPHO_CONFIG_
  assert_equal "$(dybatpho::config_get ENV_TEST)" "loaded"
  run dybatpho::config_get UNRELATED_CONFIG_ENV_TEST
  assert_failure
  unset DYBATPHO_CONFIG_ENV_TEST UNRELATED_CONFIG_ENV_TEST
}

@test "config_env also loads variables without a prefix" {
  export DYBATPHO_CONFIG_UNPREFIXED="loaded"
  DYBATPHO_CONFIG=()
  set +u
  dybatpho::config_env
  set -u
  assert_equal "$(dybatpho::config_get DYBATPHO_CONFIG_UNPREFIXED)" "loaded"
  unset DYBATPHO_CONFIG_UNPREFIXED
}

@test "config_load rejects invalid keys returned by structured backends" {
  local json_file="${BATS_TEST_TMPDIR}/bad-key.json"
  printf '{}' > "${json_file}"
  stub jq ": printf '1BAD\\tvalue\\n'"
  run dybatpho::config_load "${json_file}"
  assert_failure
  assert_output --partial "Invalid configuration key"
  unstub jq
}

@test "config_export rejects invalid prefixes and non-shell keys" {
  DYBATPHO_CONFIG=()
  run --separate-stderr dybatpho::config_export "bad-prefix-"
  assert_failure
  assert_stderr --partial "Invalid configuration variable prefix"

  __dybatpho_config_set "with.dot" "value"
  run --separate-stderr dybatpho::config_export
  assert_failure
  assert_stderr --partial "Cannot export configuration key as variable"
}

@test "config_validate applies defaults and validates types, ranges, URLs, and enums" {
  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema HOST url required:true
  dybatpho::config_schema PORT int default:8080 min:1 max:65535
  dybatpho::config_schema MODE enum choices:dev,prod
  dybatpho::config_schema DEBUG bool
  __dybatpho_config_set HOST "https://example.test"
  __dybatpho_config_set MODE prod
  __dybatpho_config_set DEBUG true
  # An optional key without a default is skipped instead of failing.
  dybatpho::config_schema REGION string
  dybatpho::config_validate
  assert_equal "$(dybatpho::config_get PORT)" "8080"
  run ! dybatpho::config_get REGION
}

@test "config_validate rejects missing required and invalid values" {
  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema REQUIRED string required:true
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "required value is missing"

  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema PORT int min:1 max:10
  __dybatpho_config_set PORT 99
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "must be at most 10"

  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema MODE enum choices:dev,prod
  __dybatpho_config_set MODE test
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "expected one of"
}

@test "config_schema rejects invalid types and rules" {
  run --separate-stderr dybatpho::config_schema VALUE float
  assert_failure
  assert_stderr --partial "Unsupported configuration type"
  run --separate-stderr dybatpho::config_schema VALUE string unknown:value
  assert_failure
  assert_stderr --partial "Unsupported configuration schema rule"
}

@test "config_schema accepts long type aliases and replaces earlier declarations" {
  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema PORT integer min:1 max:65535
  dybatpho::config_schema DEBUG boolean default:no
  # Re-declaring a key replaces its rules instead of merging them.
  dybatpho::config_schema PORT integer default:9000
  __dybatpho_config_set PORT 70000
  dybatpho::config_validate
  assert_equal "$(dybatpho::config_get DEBUG)" "no"
  assert_equal "${#DYBATPHO_CONFIG_SCHEMA_KEYS[@]}" "2"
}

@test "config_validate applies string length ranges and reports every failing key" {
  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema NAME string min:3 max:5
  dybatpho::config_schema PORT int
  dybatpho::config_schema ENDPOINT url required:true
  __dybatpho_config_set NAME "ab"
  __dybatpho_config_set PORT "eight"

  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "\`NAME\`: must be at least 3 characters"
  assert_stderr --partial "\`PORT\`: expected an integer"
  assert_stderr --partial "\`ENDPOINT\`: required value is missing"
}

@test "config_validate prefers a declared default over a required failure" {
  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema REGION string required:true default:us-east-1
  dybatpho::config_validate
  assert_equal "$(dybatpho::config_get REGION)" "us-east-1"
  assert_equal "${#DYBATPHO_CONFIG_ERRORS[@]}" "0"
}

@test "config_validate accepts every supported boolean and rejects other values" {
  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema FLAG bool
  local value
  for value in true False YES no ON off 1 0; do
    __dybatpho_config_set FLAG "${value}"
    dybatpho::config_validate
  done

  __dybatpho_config_set FLAG maybe
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "expected a boolean"
}

@test "config_schema rejects malformed rule values and enums without choices" {
  dybatpho::config_schema_reset
  run --separate-stderr dybatpho::config_schema PORT int min:many
  assert_failure
  assert_stderr --partial "Invalid \`min\` rule for PORT"

  run --separate-stderr dybatpho::config_schema FLAG bool required:sometimes
  assert_failure
  assert_stderr --partial "Invalid \`required\` rule for FLAG"

  run --separate-stderr dybatpho::config_schema MODE enum
  assert_failure
  assert_stderr --partial "requires \`choices\`"

  run --separate-stderr dybatpho::config_schema MODE enum choices:
  assert_failure
  assert_stderr --partial "Empty \`choices\` rule for MODE"

  run --separate-stderr dybatpho::config_schema "bad key" string
  assert_failure
  assert_stderr --partial "Invalid configuration key"

  run --separate-stderr dybatpho::config_schema VALUE string nocolon
  assert_failure
  assert_stderr --partial "Invalid configuration schema rule"
}

@test "config_doc renders markdown, text, and JSON references in declaration order" {
  dybatpho::config_schema_reset
  dybatpho::config_schema HOST url required:true description:"API base URL"
  dybatpho::config_schema PORT int default:8080 min:1 max:65535
  dybatpho::config_schema MODE enum choices:dev,prod default:dev

  run dybatpho::config_doc
  assert_success
  assert_line --index 0 "# Configuration"
  assert_line --partial "| \`HOST\` | url | true | - | - | API base URL |"
  assert_line --partial "| \`PORT\` | int | false | \`8080\` | 1..65535 | - |"
  assert_line --partial "| \`MODE\` | enum | false | \`dev\` | one of: dev, prod | - |"

  run dybatpho::config_doc text "App settings"
  assert_success
  assert_line --index 0 "App settings"
  assert_line --partial "  type: url"
  assert_line --partial "  constraints: 1..65535"
  assert_line --partial "  description: API base URL"

  run dybatpho::config_doc json
  assert_success
  assert_output --partial '{"key":"HOST","type":"url","required":true,"default":null,"constraints":null,"description":"API base URL"}'
  assert_output --partial '{"key":"PORT","type":"int","required":false,"default":"8080","constraints":"1..65535","description":null}'
}

@test "config_doc reports unsupported formats and renders an empty schema" {
  dybatpho::config_schema_reset
  run --separate-stderr dybatpho::config_doc xml
  assert_failure
  assert_stderr --partial "Unsupported configuration documentation format"

  run dybatpho::config_doc json
  assert_success
  assert_output "[]"
}

# The structured helpers below drive the real `jq` and `yq` rather than a stub.
# A stub answers whatever the test wants, which is exactly how the loader
# shipped a `jq`-only `if ... then ... else ... end` expression that no `yq`
# release has ever been able to parse.
require_tool() {
  command -v "$1" > /dev/null 2>&1 || skip "$1 is not installed"
}

@test "config_set stores values and rejects invalid keys" {
  DYBATPHO_CONFIG=()
  dybatpho::config_set PORT 9090
  assert_equal "$(dybatpho::config_get PORT)" "9090"
  dybatpho::config_set PORT 9443
  assert_equal "$(dybatpho::config_get PORT)" "9443"

  run --separate-stderr dybatpho::config_set "bad key" value
  assert_failure
  assert_stderr --partial "Invalid configuration key"

  run --separate-stderr dybatpho::config_set ONLY_A_KEY
  assert_failure
}

@test "config_load --optional skips absent files and keeps the merge order" {
  local base="${BATS_TEST_TMPDIR}/base.env"
  local overlay="${BATS_TEST_TMPDIR}/overlay.env"
  printf 'HOST=example.test\nPORT=80\n' > "${base}"
  printf 'PORT=443\n' > "${overlay}"

  DYBATPHO_CONFIG=()
  dybatpho::config_load --optional "${base}" \
    "${BATS_TEST_TMPDIR}/absent.env" "${overlay}"
  assert_equal "$(dybatpho::config_get HOST)" "example.test"
  assert_equal "$(dybatpho::config_get PORT)" "443"

  # Without the flag the same missing file is still an error.
  run --separate-stderr dybatpho::config_load "${BATS_TEST_TMPDIR}/absent.env"
  assert_failure
  assert_stderr --partial "Configuration file not found"

  run --separate-stderr dybatpho::config_load --optional
  assert_failure
  assert_stderr --partial "Expected at least one configuration file"

  # `--` ends the flags, so a file may be named like one.
  run --separate-stderr dybatpho::config_load -- "${BATS_TEST_TMPDIR}/absent.env"
  assert_failure
  assert_stderr --partial "Configuration file not found"
}

@test "config_profile overlays the profile file beside the base file" {
  local base="${BATS_TEST_TMPDIR}/config.env"
  printf 'HOST=localhost\nPORT=8080\nMODE=dev\n' > "${base}"
  printf 'PORT=443\nMODE=prod\n' > "${BATS_TEST_TMPDIR}/config.prod.env"

  DYBATPHO_CONFIG=()
  dybatpho::config_profile "${base}" prod
  assert_equal "$(dybatpho::config_get HOST)" "localhost"
  assert_equal "$(dybatpho::config_get PORT)" "443"
  assert_equal "$(dybatpho::config_get MODE)" "prod"

  # A profile with no file of its own leaves the base values in place.
  DYBATPHO_CONFIG=()
  dybatpho::config_profile "${base}" staging
  assert_equal "$(dybatpho::config_get PORT)" "8080"

  DYBATPHO_CONFIG=()
  DYBATPHO_CONFIG_PROFILE=prod dybatpho::config_profile "${base}"
  assert_equal "$(dybatpho::config_get MODE)" "prod"
}

@test "config_profile rejects a missing profile, a bad name, and an extensionless file" {
  local base="${BATS_TEST_TMPDIR}/config.env"
  printf 'HOST=localhost\n' > "${base}"

  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/profile.sh"
  printf '%s\n' ". '${DYBATPHO_DIR}/init.sh' --modules config" \
    "dybatpho::config_profile '${base}'" > "${script}"
  run --separate-stderr env -u DYBATPHO_CONFIG_PROFILE bash "${script}"
  assert_failure
  assert_stderr --partial "Expected a profile name or DYBATPHO_CONFIG_PROFILE"

  run --separate-stderr dybatpho::config_profile "${base}" "../escape"
  assert_failure
  assert_stderr --partial "Invalid configuration profile"

  printf 'HOST=localhost\n' > "${BATS_TEST_TMPDIR}/plainfile"
  run --separate-stderr dybatpho::config_profile "${BATS_TEST_TMPDIR}/plainfile" prod
  assert_failure
  assert_stderr --partial "Configuration file has no extension"
}

@test "config_save rewrites a dotenv file in place and keeps everything else" {
  local file="${BATS_TEST_TMPDIR}/app.env"
  printf '%s\n' \
    '# leading comment' \
    'HOST=localhost' \
    '' \
    '# the port' \
    'PORT=8080' \
    'KEEP=untouched' \
    'PORT=8081' > "${file}"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${file}"
  dybatpho::config_set PORT 9090
  dybatpho::config_set NOTE 'has spaces # and a hash'
  dybatpho::config_set EMPTY ''
  dybatpho::config_save "${file}" PORT NOTE EMPTY

  # The whole file is compared rather than single lines, because the comments,
  # the blank line, and the order are the point here. `run` drops blank lines
  # from `lines`, so an index-based assertion would not see that one at all.
  #
  # Both assignments of the repeated key are rewritten: the loader keeps the
  # last one, so leaving a stale copy behind would undo the save.
  local expected="${BATS_TEST_TMPDIR}/expected.env"
  printf '%s\n' \
    '# leading comment' \
    'HOST=localhost' \
    '' \
    '# the port' \
    'PORT=9090' \
    'KEEP=untouched' \
    'PORT=9090' \
    'NOTE="has spaces # and a hash"' \
    'EMPTY=""' > "${expected}"
  run diff -u "${expected}" "${file}"
  assert_success

  # What was written is what comes back.
  DYBATPHO_CONFIG=()
  dybatpho::config_load "${file}"
  assert_equal "$(dybatpho::config_get PORT)" "9090"
  assert_equal "$(dybatpho::config_get NOTE)" 'has spaces # and a hash'
  assert_equal "$(dybatpho::config_get EMPTY)" ''
  assert_equal "$(dybatpho::config_get KEEP)" "untouched"
}

@test "config_save round-trips values that need escaping and creates a missing file" {
  local file="${BATS_TEST_TMPDIR}/created.env"
  DYBATPHO_CONFIG=()
  dybatpho::config_set MULTILINE $'first\tsecond\nthird'
  dybatpho::config_set WINDOWS 'C:\path\to\thing'
  dybatpho::config_set QUOTED 'say "hi"'
  dybatpho::config_save "${file}" MULTILINE WINDOWS QUOTED

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${file}"
  assert_equal "$(dybatpho::config_get MULTILINE)" $'first\tsecond\nthird'
  assert_equal "$(dybatpho::config_get WINDOWS)" 'C:\path\to\thing'
  assert_equal "$(dybatpho::config_get QUOTED)" 'say "hi"'
}

@test "config_save defaults to every loaded key and honors DRY_RUN" {
  local file="${BATS_TEST_TMPDIR}/all.env"
  DYBATPHO_CONFIG=()
  dybatpho::config_set BRAVO two
  dybatpho::config_set ALPHA one
  dybatpho::config_save "${file}"
  run cat "${file}"
  assert_line --index 0 'ALPHA=one'
  assert_line --index 1 'BRAVO=two'

  dybatpho::config_set ALPHA changed
  DRY_RUN=true dybatpho::config_save "${file}" ALPHA
  run cat "${file}"
  assert_line --index 0 'ALPHA=one'
}

@test "config_save rejects unknown keys, unsupported formats, and non-dotenv names" {
  DYBATPHO_CONFIG=()
  run --separate-stderr dybatpho::config_save "${BATS_TEST_TMPDIR}/empty.env"
  assert_failure
  assert_stderr --partial "Expected at least one configuration key"

  run --separate-stderr dybatpho::config_save "${BATS_TEST_TMPDIR}/a.env" ABSENT
  assert_failure
  assert_stderr --partial "Cannot save a configuration key that is not set"

  run --separate-stderr dybatpho::config_save "${BATS_TEST_TMPDIR}/a.env" "bad key"
  assert_failure
  assert_stderr --partial "Invalid configuration key"

  dybatpho::config_set VALUE set
  run --separate-stderr dybatpho::config_save "${BATS_TEST_TMPDIR}/a.txt" VALUE
  assert_failure
  assert_stderr --partial "Unsupported configuration format"

  # A dotted key is valid configuration but cannot be spelled as a shell name.
  dybatpho::config_set "with.dot" set
  run --separate-stderr dybatpho::config_save "${BATS_TEST_TMPDIR}/a.env" "with.dot"
  assert_failure
  assert_stderr --partial "Cannot save configuration key to a dotenv file"
}

@test "config_load reads TOML and rejects a non-mapping root" {
  require_tool yq
  local file="${BATS_TEST_TMPDIR}/app.toml"
  printf '# a comment\nhost = "localhost"\nport = 8080\n' > "${file}"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${file}"
  assert_equal "$(dybatpho::config_get host)" "localhost"
  assert_equal "$(dybatpho::config_get port)" "8080"

  local sequence="${BATS_TEST_TMPDIR}/sequence.yaml"
  printf -- '- one\n- two\n' > "${sequence}"
  run --separate-stderr dybatpho::config_load "${sequence}"
  assert_failure
  assert_stderr --partial "Invalid YAML configuration"

  local malformed="${BATS_TEST_TMPDIR}/malformed.yaml"
  printf 'key: [\n' > "${malformed}"
  run --separate-stderr dybatpho::config_load "${malformed}"
  assert_failure
  assert_stderr --partial "Invalid YAML configuration"
}

@test "config_load reads a real YAML mapping" {
  require_tool yq
  local file="${BATS_TEST_TMPDIR}/settings.yaml"
  printf '# comment\nhost: localhost\nport: 8080\n' > "${file}"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${file}"
  assert_equal "$(dybatpho::config_get host)" "localhost"
  assert_equal "$(dybatpho::config_get port)" "8080"
}

@test "config_save keeps YAML comments and writes schema types as scalars" {
  require_tool yq
  local file="${BATS_TEST_TMPDIR}/config.yaml"
  printf '%s\n' '# service settings' 'host: localhost' 'port: 8080' \
    'debug: false' > "${file}"

  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_load "${file}"
  dybatpho::config_schema port int
  dybatpho::config_schema debug bool
  dybatpho::config_set port 9090
  dybatpho::config_set debug 1
  dybatpho::config_set note 'a: literal string'
  dybatpho::config_save "${file}" port debug note

  run cat "${file}"
  assert_line --index 0 '# service settings'
  assert_line 'host: localhost'
  # The schema is what makes these scalars rather than quoted strings.
  assert_line 'port: 9090'
  assert_line 'debug: true'
  assert_line "note: 'a: literal string'"
}

@test "config_save rewrites JSON and TOML without disturbing other keys" {
  require_tool jq
  require_tool yq
  local json_file="${BATS_TEST_TMPDIR}/settings.json"
  printf '{"host":"localhost","port":8080}\n' > "${json_file}"

  DYBATPHO_CONFIG=()
  dybatpho::config_schema_reset
  dybatpho::config_schema port int
  dybatpho::config_set port 9090
  dybatpho::config_set mode prod
  dybatpho::config_save "${json_file}" port mode
  assert_equal "$(jq -r '.host' "${json_file}")" "localhost"
  assert_equal "$(jq -r '.port' "${json_file}")" "9090"
  assert_equal "$(jq -r '.port | type' "${json_file}")" "number"
  assert_equal "$(jq -r '.mode' "${json_file}")" "prod"

  local toml_file="${BATS_TEST_TMPDIR}/settings.toml"
  printf '# a comment\nhost = "localhost"\nport = 8080\n' > "${toml_file}"
  dybatpho::config_save "${toml_file}" port mode
  run cat "${toml_file}"
  assert_line 'host = "localhost"'
  assert_line 'port = 9090'
  assert_line 'mode = "prod"'

  # A file that is not there yet is created in the requested format.
  local created="${BATS_TEST_TMPDIR}/created.json"
  dybatpho::config_save "${created}" mode
  assert_equal "$(jq -r '.mode' "${created}")" "prod"
}
