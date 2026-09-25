# `AGENT.md` requires every example to be an executable workflow that runs
# non-interactively, without credentials, network access or machine-local
# assumptions, and that cleans up after itself. Nothing checked that, and one
# example had drifted into making real HTTP requests to example.com,
# api.github.com and httpbin.org — it only ever "passed" because no one ran it.
#
# One test per example keeps the report readable: a failure names the file
# rather than a single opaque "examples failed".

setup() {
  load test_helper
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

# @description Run one example and assert it succeeds and changes nothing in the
#   repository. Examples write to temporary directories by contract.
#
#   The working tree is compared before and after rather than required to be
#   clean: a contributor runs this suite on top of their own uncommitted work,
#   so "clean" would fail for reasons that have nothing to do with the example.
# @arg $1 string Example file name, relative to `example/`
run_example() {
  local name="$1" before after

  before="$(git -C "${REPO_ROOT}" status --porcelain)"

  # Not the `timeout` binary: a stock macOS has none, and the library's own
  # helper falls back to a Bash watchdog there.
  run --separate-stderr dybatpho::run_with_timeout 120 bash "${REPO_ROOT}/example/${name}"
  if [ "${status}" -ne 0 ]; then
    printf 'example/%s exited %s\n--- stdout ---\n%s\n--- stderr ---\n%s\n' \
      "${name}" "${status}" "${output}" "${stderr}" >&2
    return 1
  fi

  after="$(git -C "${REPO_ROOT}" status --porcelain)"
  [ "${before}" = "${after}" ] || {
    printf 'example/%s changed the working tree:\n%s\n' \
      "${name}" "$(diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") || true)" >&2
    return 1
  }
}

@test "every example is discovered by this file" {
  # A new example must gain a test here, otherwise it is never run. The count is
  # deliberately mechanical: it fails loudly when someone adds example/foo.sh
  # and forgets the matching @test below.
  local missing="" name
  for source in "${REPO_ROOT}"/example/*.sh; do
    name="$(basename "${source}")"
    grep -qF "run_example \"${name}\"" "${BATS_TEST_FILENAME}" ||
      missing+="example/${name} has no test in test/examples.bats"$'\n'
  done
  [ -z "${missing}" ] || {
    printf 'Examples that are never executed:\n\n%s\n' "${missing}" >&2
    return 1
  }
}

@test "example/agent_ops.sh runs clean" { run_example "agent_ops.sh"; }
@test "example/ai_ops.sh runs clean" { run_example "ai_ops.sh"; }
@test "example/archive_ops.sh runs clean" { run_example "archive_ops.sh"; }
@test "example/array_ops.sh runs clean" { run_example "array_ops.sh"; }
@test "example/cache_ops.sh runs clean" { run_example "cache_ops.sh"; }
@test "example/cli_advanced.sh runs clean" { run_example "cli_advanced.sh"; }
@test "example/cli_basic.sh runs clean" { run_example "cli_basic.sh"; }
@test "example/cli_ux.sh runs clean" { run_example "cli_ux.sh"; }
@test "example/config_ops.sh runs clean" { run_example "config_ops.sh"; }
@test "example/date_ops.sh runs clean" { run_example "date_ops.sh"; }
@test "example/doctor_ops.sh runs clean" { run_example "doctor_ops.sh"; }
@test "example/file_ops.sh runs clean" { run_example "file_ops.sh"; }
@test "example/forge_ops.sh runs clean" { run_example "forge_ops.sh"; }
@test "example/git_ops.sh runs clean" { run_example "git_ops.sh"; }
@test "example/helpers_ops.sh runs clean" { run_example "helpers_ops.sh"; }
@test "example/i18n_ops.sh runs clean" { run_example "i18n_ops.sh"; }
@test "example/init_modules.sh runs clean" { run_example "init_modules.sh"; }
@test "example/json_ops.sh runs clean" { run_example "json_ops.sh"; }
@test "example/lock_ops.sh runs clean" { run_example "lock_ops.sh"; }
@test "example/logging_demo.sh runs clean" { run_example "logging_demo.sh"; }
@test "example/math_ops.sh runs clean" { run_example "math_ops.sh"; }
@test "example/metrics_ops.sh runs clean" { run_example "metrics_ops.sh"; }
@test "example/network_ops.sh runs clean" { run_example "network_ops.sh"; }
@test "example/notification_ops.sh runs clean" { run_example "notification_ops.sh"; }
@test "example/os_ops.sh runs clean" { run_example "os_ops.sh"; }
@test "example/parallel_ops.sh runs clean" { run_example "parallel_ops.sh"; }
@test "example/pkg_ops.sh runs clean" { run_example "pkg_ops.sh"; }
@test "example/process_ops.sh runs clean" { run_example "process_ops.sh"; }
@test "example/release_ops.sh runs clean" { run_example "release_ops.sh"; }
@test "example/safety_ops.sh runs clean" { run_example "safety_ops.sh"; }
@test "example/secret_ops.sh runs clean" { run_example "secret_ops.sh"; }
@test "example/semver_ops.sh runs clean" { run_example "semver_ops.sh"; }
@test "example/string_ops.sh runs clean" { run_example "string_ops.sh"; }
@test "example/table_ops.sh runs clean" { run_example "table_ops.sh"; }
@test "example/testing_ops.sh runs clean" { run_example "testing_ops.sh"; }
@test "example/text_ops.sh runs clean" { run_example "text_ops.sh"; }
