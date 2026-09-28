setup() {
  load test_helper
}

teardown() {
  export LOG_LEVEL=info
  export LOG_FORMAT=text
  unset COLUMNS
  unset LOG_FILE LOG_FILE_LEVEL LOG_FILE_MAX_BYTES LOG_FILE_MAX_BACKUPS LOG_REQUEST_ID
  # Context fields and timers live in this shell, and Bats runs every test in
  # the same one: a field left registered would ride along on the next test's
  # log events.
  __dybatpho_log_context_values=()
  __dybatpho_log_context_keys=()
  __dybatpho_log_timer=()
  export DYBATPHO_SPINNER=auto
}

# The logging helpers are exercised directly here so their behavior is checked
# in this shell; the tests below assert the rendered output through `run`.
@test "logging helpers run in the current shell" {
  local out="${BATS_TEST_TMPDIR}/log-out"

  __dybatpho_log info "direct stdout" > "${out}"
  assert_file_contains "${out}" "direct stdout"
  __dybatpho_log info "direct stderr" stderr
  NO_COLOR=true __dybatpho_log info "no color" > "${out}"
  assert_file_contains "${out}" "no color"
  NO_COLOR=""

  # A log message is data: backslashes must survive it. `echo -e` used to turn
  # `C:\new\table` into a newline and a tab.
  NO_COLOR=true __dybatpho_log info 'path C:\new\table \d+' > "${out}"
  assert_equal "$(cat "${out}")" 'path C:\new\table \d+'
  __dybatpho_log info 'colored C:\new' > "${out}"
  assert_equal "$(dybatpho::text_strip_ansi "$(cat "${out}")")" 'colored C:\new'
  NO_COLOR=""

  assert_equal "$(__dybatpho_log_json_escape 'a"b\c')" 'a\"b\\c'
  assert_equal "$(__dybatpho_log_json_escape $'tab\tnew\nret\r')" 'tab\tnew\nret\r'
  assert_equal "$(__dybatpho_log_json_escape $'back\bfeed\f')" 'back\bfeed\f'
  # A control character with no short escape has to be spelled out, or the
  # event is not JSON at all.
  assert_equal "$(__dybatpho_log_json_escape $'esc\033[31m')" 'esc\u001b[31m'
  assert_equal "$(__dybatpho_log_json_escape $'a\001b\177c')" 'a\u0001b\u007fc'
  # UTF-8 is not a control character and must survive intact.
  assert_equal "$(__dybatpho_log_json_escape 'nhánh 日本')" 'nhánh 日本'
  [[ "$(__dybatpho_log_timestamp)" =~ ^[0-9]{4}- ]]

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
  assert_equal "$(__dybatpho_log_wrap_line "ab   cd" 2)" "$(printf 'ab\ncd')"
  assert_equal "$(__dybatpho_log_wrap_line "aaaaaaaaaa bb" 5)" "$(printf 'aaaaaaaaaa\nbb')"
  PATH="${old_path}"

  assert_file_contains "${out}" "alpha"
  assert_file_contains "${out}" "example.com"
  unset COLUMNS
  NO_COLOR=""
}

@test "__dybatpho_log_get_terminal_width falls back to tput and then to 80 columns" {
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

  __dybatpho_log info "token logging-secret-value" > "${out}"
  assert_file_contains "${out}" "token \\*\\*\\*"
  assert_file_not_contains "${out}" "logging-secret-value"

  LOG_FORMAT=json
  dybatpho::error "json logging-secret-value"
  LOG_FORMAT=text
  dybatpho::secret_forget
}

@test "__dybatpho_log_structured renders text output when the format is not json" {
  LOG_FORMAT=text
  __dybatpho_log_structured info "source.sh:12" "structured text message"
  __dybatpho_log_structured trace "source.sh:12" "filtered out"
}

@test "__dybatpho_log_wrap_line handles non-positive widths and empty lines" {
  assert_equal "$(__dybatpho_log_wrap_line "unwrapped text" 0)" "unwrapped text"
  assert_equal "$(__dybatpho_log_wrap_line "" 10)" ""
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

@test "__dybatpho_log_timestamp supports busybox and portable date" {
  stub_repeated busybox ": echo '2024-02-29T12:34:56+07:00'"
  assert_equal "$(__dybatpho_log_timestamp)" "2024-02-29T12:34:56+07:00"
}

@test "__dybatpho_log_timestamp falls back to portable date flags" {
  # This branch is only reachable where neither busybox nor GNU date exists.
  # On a BusyBox system the first branch is the right one and wins, so the
  # premise of this test cannot hold there — it used to read the real clock and
  # fail rather than say so.
  hash busybox 2> /dev/null && skip "busybox is installed, so this branch is unreachable"
  stub_repeated date ": case \"\$1\" in --version) exit 1 ;; *) echo '2024-02-29T12:34:56+0700' ;; esac"
  assert_equal "$(__dybatpho_log_timestamp)" "2024-02-29T12:34:56+0700"
}

@test "__dybatpho_log output message" {
  run --separate-stderr __dybatpho_log info test
  assert_success
  refute_stderr
  assert_output --partial test
  run --separate-stderr __dybatpho_log info test stderr
  assert_success
  refute_output
  assert_stderr --partial test
}

@test "__dybatpho_log with NO_COLOR" {
  export NO_COLOR="true"
  run --separate-stderr __dybatpho_log info test
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

@test "__dybatpho_log_now_ms returns an increasing integer" {
  local first second
  first=$(__dybatpho_log_now_ms)
  sleep 0.01
  second=$(__dybatpho_log_now_ms)
  [[ "${first}" =~ ^[0-9]+$ ]]
  [[ "${second}" =~ ^[0-9]+$ ]]
  ((second >= first))
}

@test "__dybatpho_log_now_ms falls back to SECONDS when date lacks nanosecond support" {
  stub_repeated date ": echo 1700000000N"
  local value
  # `EPOCHREALTIME` is unset inside the command substitution rather than in the
  # test body: it is a bash dynamic variable, an `unset` in the test process is
  # permanent, and Bats reads it for `--timing` right after the body returns —
  # which silently drops this test from the run.
  value=$(
    unset EPOCHREALTIME
    __dybatpho_log_now_ms
  )
  [[ "${value}" =~ ^[0-9]+$ ]]
  unstub date
}

@test "__dybatpho_log_hostname returns a non-empty value" {
  [[ -n "$(__dybatpho_log_hostname)" ]]
}

@test "__dybatpho_log_rotate_file is a no-op for a missing file or disabled rotation" {
  local missing_file="${BATS_TEST_TMPDIR}/missing.log"
  __dybatpho_log_rotate_file "${missing_file}" 100 3
  [ ! -e "${missing_file}" ]

  local existing_file="${BATS_TEST_TMPDIR}/existing.log"
  echo "some content" > "${existing_file}"
  __dybatpho_log_rotate_file "${existing_file}" 0 3
  [ ! -e "${existing_file}.1" ]
}

@test "__dybatpho_log_parse_size understands byte counts and unit suffixes" {
  assert_equal "$(__dybatpho_log_parse_size 1024)" "1024"
  assert_equal "$(__dybatpho_log_parse_size 0)" "0"
  assert_equal "$(__dybatpho_log_parse_size 512K)" "524288"
  assert_equal "$(__dybatpho_log_parse_size 10M)" "10485760"
  assert_equal "$(__dybatpho_log_parse_size 10MB)" "10485760"
  assert_equal "$(__dybatpho_log_parse_size 2GiB)" "2147483648"
  assert_equal "$(__dybatpho_log_parse_size 1t)" "1099511627776"
  run ! __dybatpho_log_parse_size "ten megabytes"
  run ! __dybatpho_log_parse_size "-1"
  run ! __dybatpho_log_parse_size "1.5M"
}

@test "dybatpho::log_to_file configures the file sink in one call" {
  local log_file="${BATS_TEST_TMPDIR}/configured/app.log"
  dybatpho::log_to_file "${log_file}" rotate:10M keep:3 level:debug

  assert_equal "${LOG_FILE}" "${log_file}"
  assert_equal "${LOG_FILE_MAX_BYTES}" "10485760"
  assert_equal "${LOG_FILE_MAX_BACKUPS}" "3"
  assert_equal "${LOG_FILE_LEVEL}" "debug"
  # The parent directory is created up front rather than on the first event,
  # so a misconfigured path fails where it is configured.
  assert_file_exist "${log_file}"

  export LOG_LEVEL=info
  dybatpho::debug "only the file sees this"
  grep -q '"message":"only the file sees this"' "${log_file}"
}

@test "dybatpho::log_to_file creates a new log file that only its owner can read" {
  local log_file="${BATS_TEST_TMPDIR}/private.log"
  dybatpho::log_to_file "${log_file}"
  assert_equal "$(stat -L -c '%a' "${log_file}" 2> /dev/null || stat -L -f '%Lp' "${log_file}")" "600"
}

@test "dybatpho::log_to_file leaves the mode of an existing log file alone" {
  local log_file="${BATS_TEST_TMPDIR}/existing-mode.log"
  : > "${log_file}"
  chmod 644 "${log_file}"
  dybatpho::log_to_file "${log_file}"
  assert_equal "$(stat -L -c '%a' "${log_file}" 2> /dev/null || stat -L -f '%Lp' "${log_file}")" "644"
}

@test "dybatpho::log_to_file off stops writing to a file" {
  local log_file="${BATS_TEST_TMPDIR}/stopped.log"
  dybatpho::log_to_file "${log_file}"
  dybatpho::info "before"
  dybatpho::log_to_file off
  assert_equal "${LOG_FILE}" ""
  dybatpho::info "after"

  grep -q '"message":"before"' "${log_file}"
  ! grep -q '"message":"after"' "${log_file}"
}

@test "dybatpho::log_to_file rejects a setting it cannot honor" {
  local log_file="${BATS_TEST_TMPDIR}/rejected.log"
  run dybatpho::log_to_file "${log_file}" rotate:huge
  assert_failure
  assert_output --partial "10M"

  run dybatpho::log_to_file "${log_file}" keep:many
  assert_failure
  assert_output --partial "whole number"

  run dybatpho::log_to_file "${log_file}" level:shouty
  assert_failure

  run dybatpho::log_to_file "${log_file}" rotating=10M
  assert_failure
  assert_output --partial "Unknown setting"

  run dybatpho::log_to_file
  assert_failure
}

@test "dybatpho::log_context adds fields to every structured event" {
  local log_file="${BATS_TEST_TMPDIR}/context.log"
  dybatpho::log_to_file "${log_file}"
  dybatpho::log_context add run_id=abc stage=build
  dybatpho::info "with context"

  grep -q '"run_id":"abc"' "${log_file}"
  grep -q '"stage":"build"' "${log_file}"
  # The built-in fields still come first, so an existing parser keeps working.
  grep -q '"message":"with context".*"run_id":"abc"' "${log_file}"
}

@test "dybatpho::log_context shows its fields on a text log line too" {
  export LOG_FORMAT=text
  dybatpho::log_context add run_id=abc
  run --separate-stderr dybatpho::warn "text carries context"
  assert_stderr --partial "text carries context run_id=abc"
}

@test "dybatpho::log_context lists, reads, updates, and drops fields" {
  dybatpho::log_context add run_id=abc stage=build
  assert_equal "$(dybatpho::log_context get stage)" "build"

  # An update keeps the field in the position it was first added.
  dybatpho::log_context add run_id=def
  run dybatpho::log_context list
  assert_success
  assert_line --index 0 "run_id=def"
  assert_line --index 1 "stage=build"

  dybatpho::log_context remove stage
  run ! dybatpho::log_context get stage
  run dybatpho::log_context list
  assert_output "run_id=def"

  dybatpho::log_context clear
  run dybatpho::log_context list
  assert_output ""
}

@test "dybatpho::log_context refuses a name that would corrupt an event" {
  run dybatpho::log_context add message=oops
  assert_failure
  assert_output --partial "already a field"

  run dybatpho::log_context add "not a name=value"
  assert_failure
  assert_output --partial "valid field name"

  run dybatpho::log_context add lonely
  assert_failure
  assert_output --partial "name=value"

  run dybatpho::log_context add
  assert_failure

  run dybatpho::log_context remove
  assert_failure

  run dybatpho::log_context frobnicate
  assert_failure
  assert_output --partial "Unknown action"
}

@test "dybatpho::log_context redacts a registered secret in a field value" {
  local log_file="${BATS_TEST_TMPDIR}/context-secret.log"
  dybatpho::log_to_file "${log_file}"
  dybatpho::log_context add token=context-secret-value
  dybatpho::secret_register "context-secret-value"
  dybatpho::info "context masking"
  dybatpho::secret_forget

  grep -q '"token":"\*\*\*"' "${log_file}"
  ! grep -q "context-secret-value" "${log_file}"
}

@test "dybatpho::log_context escapes a value that would break the JSON" {
  local log_file="${BATS_TEST_TMPDIR}/context-escape.log"
  dybatpho::log_to_file "${log_file}"
  dybatpho::log_context add note='he said "hi"'
  dybatpho::info "escaped context"
  grep -q '"note":"he said \\"hi\\""' "${log_file}"
}

@test "dybatpho::timer_start and dybatpho::timer_end report a duration" {
  local log_file="${BATS_TEST_TMPDIR}/timer.log"
  dybatpho::log_to_file "${log_file}"

  dybatpho::timer_start migration
  sleep 0.05
  run --separate-stderr dybatpho::timer_end migration
  assert_success
  assert_stderr --partial "migration took"

  # The subshell `run` created threw its own measurement away, so time the step
  # again here to assert on what the caller can read afterwards.
  dybatpho::timer_start migration
  dybatpho::timer_end migration
  [[ "${DYBATPHO_TIMER_LAST_MS}" =~ ^[0-9]+$ ]]
  grep -q '"timer":"migration"' "${log_file}"
  grep -q '"elapsed_ms":[0-9]' "${log_file}"
}

@test "dybatpho::timer_end logs at the level it is given" {
  export LOG_LEVEL=info
  dybatpho::timer_start quiet
  run --separate-stderr dybatpho::timer_end quiet debug
  assert_success
  refute_stderr --partial "quiet took"

  dybatpho::timer_start loud
  run --separate-stderr dybatpho::timer_end loud warn
  assert_stderr --partial "loud took"
}

@test "dybatpho::timer_end refuses a timer that was never started and a level that is not one" {
  run dybatpho::timer_end never_started
  assert_failure
  assert_output --partial "never started"

  dybatpho::timer_start started
  run ! dybatpho::timer_end started shouty
  # The failed call left the timer running, so the name is still usable.
  dybatpho::timer_end started
}

@test "dybatpho::spinner runs the command and passes its exit code through" {
  export DYBATPHO_SPINNER=never
  run dybatpho::spinner "Working" -- bash -c 'echo command output; exit 0'
  assert_success
  assert_output --partial "command output"

  run dybatpho::spinner "Failing" -- bash -c 'exit 7'
  assert_failure 7
}

@test "dybatpho::spinner logs the message once when there is nothing to animate" {
  export DYBATPHO_SPINNER=never
  run --separate-stderr dybatpho::spinner "Đang tải" -- true
  assert_success
  assert_stderr --partial "Đang tải"
}

@test "dybatpho::spinner animates and then erases its line" {
  export DYBATPHO_SPINNER=always
  export DYBATPHO_SPINNER_INTERVAL=0.02
  run --separate-stderr dybatpho::spinner "Downloading" -- sleep 0.2
  assert_success
  assert_stderr --partial "Downloading"
  # The animation ends with the line erased rather than with a stray frame.
  [[ "${stderr}" == *$'\r'*'[K' ]]
  unset DYBATPHO_SPINNER_INTERVAL
}

@test "dybatpho::spinner records the outcome as a structured event" {
  local log_file="${BATS_TEST_TMPDIR}/spinner.log"
  dybatpho::log_to_file "${log_file}" level:debug
  export DYBATPHO_SPINNER=never
  dybatpho::spinner "Measured step" -- true
  grep -q '"exit_code":0' "${log_file}"
  grep -q '"elapsed_ms":[0-9]' "${log_file}"
}

@test "dybatpho::spinner insists on the command separator" {
  export DYBATPHO_SPINNER=never
  run dybatpho::spinner "no separator" true
  assert_failure
  assert_output --partial "--"

  run dybatpho::spinner "nothing to run" --
  assert_failure
  assert_output --partial "Expected a command"

  run dybatpho::spinner
  assert_failure
}

@test "dybatpho::spinner redacts a registered secret in its message" {
  export DYBATPHO_SPINNER=never
  dybatpho::secret_register "spinner-secret-value"
  run --separate-stderr dybatpho::spinner "pushing spinner-secret-value" -- true
  dybatpho::secret_forget
  assert_success
  refute_stderr --partial "spinner-secret-value"
  assert_stderr --partial "***"
}

@test "a JSON log event stays parseable whatever the message carries" {
  # Only backslash, quote, newline, carriage return and tab were escaped, so a
  # message holding an ANSI colour sequence -- what you get logging the output
  # of any coloured command -- left a raw control character in the string and
  # made the whole line invalid JSON. A log shipper drops such a line silently.
  local out="${BATS_TEST_TMPDIR}/events.json"
  local message
  message="$(printf 'build \033[31mFAILED\033[0m\a on "main"\ttab')"

  LOG_FORMAT=json LOG_LEVEL=info dybatpho::info "${message}" 2> "${out}"
  run jq -e . "${out}"
  assert_success
  assert_equal "$(jq -r '.message' "${out}")" "${message}"
}
