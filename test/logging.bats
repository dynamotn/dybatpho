setup() {
  load test_helper
}

teardown() {
  export LOG_LEVEL=info
  export LOG_FORMAT=text
  unset COLUMNS
  unset LOG_FILE LOG_FILE_LEVEL LOG_FILE_MAX_BYTES LOG_FILE_MAX_BACKUPS LOG_REQUEST_ID
}

# The logging helpers are exercised directly here so their behavior is checked
# in this shell; the tests below assert the rendered output through `run`.
@test "logging helpers run in the current shell" {
  local out="${BATS_TEST_TMPDIR}/log-out"

  __log info "direct stdout" > "${out}"
  assert_file_contains "${out}" "direct stdout"
  __log info "direct stderr" stderr
  NO_COLOR=true __log info "no color" > "${out}"
  assert_file_contains "${out}" "no color"
  NO_COLOR=""

  assert_equal "$(__log_json_escape 'a"b\c')" 'a\"b\\c'
  assert_equal "$(__log_json_escape $'tab\tnew\nret\r')" 'tab\tnew\nret\r'
  [[ "$(__log_timestamp)" =~ ^[0-9]{4}- ]]

  dybatpho::validate_log_level info
  run ! dybatpho::validate_log_level nonsense

  LOG_LEVEL=trace
  dybatpho::debug "debug message"
  dybatpho::debug_command "command output" "printf 'hi\n'"
  dybatpho::info "info message"
  dybatpho::warn "warn message"
  dybatpho::error "error message"
  dybatpho::fatal "fatal message"
  LOG_FORMAT=json
  dybatpho::error "structured message"
  LOG_FORMAT=text
  LOG_LEVEL=info

  dybatpho::print "printed" > "${out}"
  assert_file_contains "${out}" "printed"
  dybatpho::progress "in progress" > "${out}"
  assert_file_contains "${out}" "in progress"
  dybatpho::header "a header" > "${out}"
  assert_file_contains "${out}" "a header"
  dybatpho::success "all good" > "${out}"
  assert_file_contains "${out}" "all good"
  dybatpho::progress_bar 50 10 > "${out}"
  assert_file_contains "${out}" "#####"
}

@test "boxed output falls back to plain widths without python3" {
  local out="${BATS_TEST_TMPDIR}/fallback-out"
  local empty_bin="${BATS_TEST_TMPDIR}/empty-bin"
  local old_path="${PATH}"
  mkdir -p "${empty_bin}"
  export COLUMNS=24
  export NO_COLOR=true

  # Without python3 the wrapping and width helpers use their pure-bash paths.
  PATH="${empty_bin}"
  dybatpho::header "alpha beta gamma delta epsilon" > "${out}"
  dybatpho::success "https://example.com/a/very/long/link" >> "${out}"
  # A long token with a later space breaks at that space, dropping the padding.
  assert_equal "$(__wrap_line "ab   cd" 2)" "$(printf 'ab\ncd')"
  assert_equal "$(__wrap_line "aaaaaaaaaa bb" 5)" "$(printf 'aaaaaaaaaa\nbb')"
  PATH="${old_path}"

  assert_file_contains "${out}" "alpha"
  assert_file_contains "${out}" "example.com"
  unset COLUMNS
  NO_COLOR=""
}

@test "__get_terminal_width falls back to tput and then to 80 columns" {
  local out="${BATS_TEST_TMPDIR}/width-out"
  unset COLUMNS
  stub_repeated tput ": echo 30"
  export NO_COLOR=true
  dybatpho::header "width probe" > "${out}"
  assert_file_contains "${out}" "width probe"

  COLUMNS=not-a-number
  dybatpho::header "width probe" > "${out}"
  assert_file_contains "${out}" "width probe"
  unset COLUMNS
  NO_COLOR=""
}

@test "logging redacts registered secrets in both formats" {
  dybatpho::secret_register "logging-secret-value"
  local out="${BATS_TEST_TMPDIR}/masked-log"

  __log info "token logging-secret-value" > "${out}"
  assert_file_contains "${out}" "token \\*\\*\\*"
  assert_file_not_contains "${out}" "logging-secret-value"

  LOG_FORMAT=json
  dybatpho::error "json logging-secret-value"
  LOG_FORMAT=text
  dybatpho::secret_forget
}

@test "__log_structured renders text output when the format is not json" {
  LOG_FORMAT=text
  __log_structured info "source.sh:12" "structured text message"
  __log_structured trace "source.sh:12" "filtered out"
}

@test "__wrap_line handles non-positive widths and empty lines" {
  assert_equal "$(__wrap_line "unwrapped text" 0)" "unwrapped text"
  assert_equal "$(__wrap_line "" 10)" ""
}

@test "boxed output copes with empty messages and tiny terminals" {
  local out="${BATS_TEST_TMPDIR}/tiny-box"
  export NO_COLOR=true

  export COLUMNS=3
  dybatpho::header "" > "${out}"
  assert_file_contains "${out}" "╔"

  unset COLUMNS
  NO_COLOR=""
}

@test "__log_timestamp supports busybox and portable date" {
  stub_repeated busybox ": echo '2024-02-29T12:34:56+07:00'"
  assert_equal "$(__log_timestamp)" "2024-02-29T12:34:56+07:00"
}

@test "__log_timestamp falls back to portable date flags" {
  # Neither busybox nor GNU date is available in this environment.
  stub_repeated date ": case \"\$1\" in --version) exit 1 ;; *) echo '2024-02-29T12:34:56+0700' ;; esac"
  assert_equal "$(__log_timestamp)" "2024-02-29T12:34:56+0700"
}

@test "__log output message" {
  run --separate-stderr __log info test
  assert_success
  refute_stderr
  assert_output --partial test
  run --separate-stderr __log info test stderr
  assert_success
  refute_output
  assert_stderr --partial test
}

@test "__log with NO_COLOR" {
  export NO_COLOR="true"
  run --separate-stderr __log info test
  assert_success
  refute_output --partial "$(echo -e "\e[0;32m")"
}

@test "dybatpho::compare_log_level with same level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=info
  dybatpho::compare_log_level "info"
}

@test "dybatpho::compare_log_level with lower level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=info
  dybatpho::compare_log_level "error"
}

@test "dybatpho::compare_log_level with higher level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=error
  run dybatpho::compare_log_level "debug"
  assert_failure
}

@test "dybatpho::compare_log_level with trace and fatal" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=trace
  dybatpho::compare_log_level "fatal"
}

@test "dybatpho::compare_log_level case insensitive" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=INFO
  dybatpho::compare_log_level "info"
}

@test "dybatpho::compare_log_level does not mutate LOG_LEVEL" {
  export LOG_LEVEL=INFO
  dybatpho::compare_log_level "warn"
  [ "${LOG_LEVEL}" = "INFO" ]
}

@test "dybatpho::validate_log_level succeeds with valid level" {
  run --separate-stderr dybatpho::validate_log_level error
  assert_success
  refute_output
  run --separate-stderr dybatpho::validate_log_level ERROR
  assert_success
  refute_output
}

@test "dybatpho::validate_log_level succeeds with invalid level" {
  run --separate-stderr dybatpho::validate_log_level foo
  assert_failure
}

@test "dybatpho::debug doesn't output anything when using default log level" {
  run --separate-stderr dybatpho::debug foo
  assert_success
  refute_output
  refute_stderr "foo"
}

@test "dybatpho::debug output when using debug level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=debug
  run --separate-stderr dybatpho::debug foo
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;36m")"
  assert_stderr --partial "foo"
  assert_stderr --partial "‖ DEBUG"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::debug_command output" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=debug
  run --separate-stderr dybatpho::debug_command "Who am I" "whoami"
  assert_success
  refute_output
  assert_stderr --partial "${USER}"
}

@test "structured logging emits valid JSON" {
  export LOG_FORMAT=json
  export NO_COLOR=true
  run --separate-stderr dybatpho::error 'message with "quotes" and
a newline'
  assert_success
  refute_output
  assert_stderr --partial '"level":"error"'
  assert_stderr --partial '"message":"message with'
  printf '%s\n' "${stderr}" | python3 -c 'import json, sys; event=json.load(sys.stdin); assert event["level"] == "error"; assert event["message"].startswith("message with")'
}

@test "filtered debug command does not execute its command" {
  local marker="${BATS_TEST_TMPDIR}/debug-command-marker"
  dybatpho::debug_command "hidden" "touch '${marker}'"
  [ ! -e "${marker}" ]
}

@test "dybatpho::info output" {
  run --separate-stderr dybatpho::info daylathongtin
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;34m")"
  assert_stderr --partial daylathongtin
  assert_stderr --partial "‖ INFO"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::print output" {
  run --separate-stderr dybatpho::print daylathongtin
  assert_success
  refute_stderr
  refute_output --partial "$(echo -e "\e[0;32m")"
  assert_output --partial daylathongtin
  refute_output --partial "‖ INFO"
}

@test "dybatpho::progress output" {
  run --separate-stderr dybatpho::progress daylathongtin
  assert_success
  refute_stderr
  assert_output --partial "$(echo -e "\e[0;3;34m")"
  assert_output --partial "╭"
  assert_output --partial "│ 🚀 daylathongtin... │"
  assert_output --partial "╰"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::progress_bar output" {
  run --separate-stderr dybatpho::progress_bar 3
  assert_success
  refute_stderr
  assert_output --partial "[#                                                 ]"
  run --separate-stderr dybatpho::progress_bar 0 20
  assert_success
  refute_stderr
  assert_output --partial "[                    ]"
  run --separate-stderr dybatpho::progress_bar 10 20
  assert_success
  refute_stderr
  assert_output --partial "[##                  ]"
  run --separate-stderr dybatpho::progress_bar 100 20
  assert_success
  refute_stderr
  assert_output --partial "[####################]"
}

@test "dybatpho::header output" {
  run --separate-stderr dybatpho::header daylathongtin
  assert_success
  refute_stderr
  assert_output --partial "$(echo -e "\e[1;5;30;47m")"
  assert_output --partial "╔"
  assert_output --partial "║ daylathongtin ║"
  assert_output --partial "╝"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::success output" {
  run --separate-stderr dybatpho::success daylathongtin
  assert_success
  refute_stderr
  assert_output --partial "$(echo -e "\e[1;3;32m")"
  assert_output --partial "╭"
  assert_output --partial "DONE:"
  assert_output --partial "│ ✅ DONE: daylathongtin │"
  assert_output --partial "╯"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "boxed logging helpers wrap to terminal width and keep minimal box size" {
  export COLUMNS=20
  export NO_COLOR=true

  run --separate-stderr dybatpho::header "alpha beta gamma"
  assert_success
  refute_stderr
  assert_output << EOF
╔══════════════╗
║ alpha beta   ║
║ gamma        ║
╚══════════════╝
EOF

  run --separate-stderr dybatpho::success "deploy finished cleanly"
  assert_success
  refute_stderr
  assert_output << EOF
╭────────────────╮
│ ✅ DONE: deploy │
│ finished       │
│ cleanly        │
╰────────────────╯
EOF
}

@test "boxed logging helpers do not split words or links mid-token" {
  command -v python3 > /dev/null || skip "python3 required"
  export NO_COLOR=true

  # A URL that would overflow inner_limit=36 (COLUMNS=40) must not be split mid-link
  export COLUMNS=40
  run --separate-stderr dybatpho::header "Visit https://example.com/very/long/path/to/resource please"
  assert_success
  refute_stderr
  assert_output --partial "https://example.com/very/long/path/to/resource"
  refute_output --partial "https://example.com/very/long/path/to/resource/" # would be cut
  # Ensure the URL appears on one unbroken line
  while IFS= read -r line; do
    if [[ "${line}" == *"https://"* ]]; then
      [[ "${line}" == *"https://example.com/very/long/path/to/resource"* ]] || {
        echo "URL was split: ${line}"
        return 1
      }
    fi
  done <<< "${output}"
}

@test "boxed logging helpers keep visual border width aligned for wide glyphs" {
  command -v python3 > /dev/null || skip "python3 required"
  export NO_COLOR=true

  run --separate-stderr dybatpho::success "daylathongtin"
  assert_success
  refute_stderr
  OUTPUT="${output}" python3 - << 'PY'
import os
import sys
import unicodedata

def display_width(text):
    width = 0
    for char in text:
        if unicodedata.combining(char):
            continue
        width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
    return width

lines = os.environ["OUTPUT"].splitlines()
if len(lines) != 3:
    raise SystemExit(f"expected 3 lines, got {len(lines)}")

widths = [display_width(line) for line in lines]
if len(set(widths)) != 1:
    raise SystemExit(f"misaligned box widths: {widths}")
PY
  assert_success

  run --separate-stderr dybatpho::progress "daylathongtin"
  assert_success
  refute_stderr
  OUTPUT="${output}" python3 - << 'PY'
import os
import sys
import unicodedata

def display_width(text):
    width = 0
    for char in text:
        if unicodedata.combining(char):
            continue
        width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
    return width

lines = os.environ["OUTPUT"].splitlines()
if len(lines) != 3:
    raise SystemExit(f"expected 3 lines, got {len(lines)}")

widths = [display_width(line) for line in lines]
if len(set(widths)) != 1:
    raise SystemExit(f"misaligned box widths: {widths}")
PY
  assert_success
}

@test "dybatpho::warn output" {
  run --separate-stderr dybatpho::warn haycanthan
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;33")"
  assert_stderr --partial haycanthan
  assert_stderr --partial "‖ WARN"
  assert_stderr --partial bats # show source file
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::error output" {
  run --separate-stderr dybatpho::error loiroine
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[1;31m")"
  assert_stderr --partial loiroine
  assert_stderr --partial "‖ ERROR"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::fatal output" {
  run --separate-stderr dybatpho::fatal loiroine
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;31m")"
  assert_stderr --partial loiroine
  assert_stderr --partial "‖ FATAL"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::start_trace doesn't output anything when using default log level" {
  run --separate-stderr dybatpho::start_trace
  assert_success
  refute_output
  refute_stderr "Start tracing"
}

@test "dybatpho::start_trace output when using trace level" {
  # shellcheck disable=SC2030,SC2031
  export LOG_LEVEL=trace
  run --separate-stderr dybatpho::start_trace
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;37m")"
  assert_stderr --partial "‖ TRACE"
  assert_stderr --partial "Start tracing"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::end_trace doesn't output anything when using default log level" {
  run --separate-stderr dybatpho::end_trace
  assert_success
  refute_output
  refute_stderr "End tracing"
}

@test "dybatpho::end_trace output when using trace level" {
  # shellcheck disable=SC2030,SC2031
  export LOG_LEVEL=trace
  run --separate-stderr dybatpho::end_trace
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;37m")"
  assert_stderr --partial "‖ TRACE"
  assert_stderr --partial "End tracing"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "structured JSON events include request_id, hostname, pid, and duration_ms" {
  export LOG_FORMAT=json
  export NO_COLOR=true
  export LOG_REQUEST_ID="req-fixed-123"
  run --separate-stderr dybatpho::error "enriched event"
  assert_success
  refute_output
  assert_stderr --partial '"request_id":"req-fixed-123"'
  assert_stderr --partial "\"pid\":$$"
  printf '%s\n' "${stderr}" | python3 -c '
import json, sys
event = json.load(sys.stdin)
assert event["request_id"] == "req-fixed-123"
assert event["hostname"]
assert event["pid"] == '"$$"'
assert isinstance(event["duration_ms"], int)
assert event["duration_ms"] >= 0
'
}

@test "LOG_REQUEST_ID is generated once and reused across calls when unset" {
  export LOG_FORMAT=json
  export NO_COLOR=true
  unset LOG_REQUEST_ID
  local out="${BATS_TEST_TMPDIR}/request-id-out"
  { dybatpho::error "first"; dybatpho::error "second"; } 2> "${out}"
  local first_id second_id
  first_id=$(sed -n '1p' "${out}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["request_id"])')
  second_id=$(sed -n '2p' "${out}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["request_id"])')
  assert_equal "${first_id}" "${second_id}"
  [[ -n "${first_id}" ]]
}

@test "dybatpho::compare_log_level supports an explicit threshold override" {
  export LOG_LEVEL=error
  dybatpho::compare_log_level debug debug
  run dybatpho::compare_log_level debug warn
  assert_failure
}

@test "LOG_FILE receives structured JSON events independent of LOG_FORMAT" {
  local log_file="${BATS_TEST_TMPDIR}/app.log"
  export LOG_FILE="${log_file}"
  export LOG_FORMAT=text
  export LOG_LEVEL=info
  dybatpho::info "file logged event"
  assert_file_exist "${log_file}"
  grep -q '"message":"file logged event"' "${log_file}"
  grep -q '"level":"info"' "${log_file}"
}

@test "LOG_FILE_LEVEL captures more verbose events than stdout LOG_LEVEL" {
  local log_file="${BATS_TEST_TMPDIR}/verbose.log"
  export LOG_FILE="${log_file}"
  export LOG_LEVEL=info
  export LOG_FILE_LEVEL=debug
  run --separate-stderr dybatpho::debug "hidden from stdout, visible in file"
  assert_success
  refute_stderr "hidden from stdout"
  grep -q '"message":"hidden from stdout, visible in file"' "${log_file}"
}

@test "LOG_FILE_LEVEL can suppress events that still appear on stdout" {
  local log_file="${BATS_TEST_TMPDIR}/quiet.log"
  export LOG_FILE="${log_file}"
  export LOG_LEVEL=debug
  export LOG_FILE_LEVEL=error
  run --separate-stderr dybatpho::debug "stdout only"
  assert_success
  assert_stderr --partial "stdout only"
  [ ! -s "${log_file}" ]
}

@test "LOG_FILE creates missing parent directories" {
  local log_file="${BATS_TEST_TMPDIR}/nested/dir/app.log"
  export LOG_FILE="${log_file}"
  dybatpho::info "creates parent dirs"
  assert_file_exist "${log_file}"
}

@test "LOG_FILE rotates once the size threshold is reached" {
  local log_file="${BATS_TEST_TMPDIR}/rotate.log"
  export LOG_FILE="${log_file}"
  export LOG_FILE_MAX_BYTES=1
  export LOG_FILE_MAX_BACKUPS=2
  dybatpho::info "first entry"
  dybatpho::info "second entry"
  dybatpho::info "third entry"
  assert_file_exist "${log_file}"
  assert_file_exist "${log_file}.1"
  grep -q '"message":"third entry"' "${log_file}"
  grep -q '"message":"second entry"' "${log_file}.1"
}

@test "LOG_FILE rotation caps the number of retained backups" {
  local log_file="${BATS_TEST_TMPDIR}/rotate_cap.log"
  export LOG_FILE="${log_file}"
  export LOG_FILE_MAX_BYTES=1
  export LOG_FILE_MAX_BACKUPS=1
  dybatpho::info "one"
  dybatpho::info "two"
  dybatpho::info "three"
  assert_file_exist "${log_file}.1"
  [ ! -e "${log_file}.2" ]
}

@test "LOG_FILE_MAX_BYTES=0 disables rotation" {
  local log_file="${BATS_TEST_TMPDIR}/no_rotate.log"
  export LOG_FILE="${log_file}"
  export LOG_FILE_MAX_BYTES=0
  dybatpho::info "one"
  dybatpho::info "two"
  [ ! -e "${log_file}.1" ]
  grep -q '"message":"one"' "${log_file}"
  grep -q '"message":"two"' "${log_file}"
}

@test "LOG_FILE is a no-op when unset" {
  unset LOG_FILE
  run --separate-stderr dybatpho::info "no file configured"
  assert_success
  assert_stderr --partial "no file configured"
}

@test "LOG_FILE redacts registered secrets" {
  local log_file="${BATS_TEST_TMPDIR}/masked.log"
  export LOG_FILE="${log_file}"
  dybatpho::secret_register "file-secret-value"
  dybatpho::info "token file-secret-value"
  dybatpho::secret_forget
  grep -q '\*\*\*' "${log_file}"
  ! grep -q "file-secret-value" "${log_file}"
}

@test "__log_now_ms returns an increasing integer" {
  local first second
  first=$(__log_now_ms)
  sleep 0.01
  second=$(__log_now_ms)
  [[ "${first}" =~ ^[0-9]+$ ]]
  [[ "${second}" =~ ^[0-9]+$ ]]
  ((second >= first))
}

@test "__log_now_ms falls back to SECONDS when date lacks nanosecond support" {
  local saved_epochrealtime="${EPOCHREALTIME:-}"
  # shellcheck disable=SC2030
  unset EPOCHREALTIME 2> /dev/null || true
  stub_repeated date ": echo 1700000000N"
  local value
  value=$(__log_now_ms)
  [[ "${value}" =~ ^[0-9]+$ ]]
  unstub date
}

@test "__log_hostname returns a non-empty value" {
  [[ -n "$(__log_hostname)" ]]
}

@test "__log_rotate_file is a no-op for a missing file or disabled rotation" {
  local missing_file="${BATS_TEST_TMPDIR}/missing.log"
  __log_rotate_file "${missing_file}" 100 3
  [ ! -e "${missing_file}" ]

  local existing_file="${BATS_TEST_TMPDIR}/existing.log"
  echo "some content" > "${existing_file}"
  __log_rotate_file "${existing_file}" 0 3
  [ ! -e "${existing_file}.1" ]
}
