setup() {
  load test_helper
  LINT_SH="${DYBATPHO_DIR}/scripts/lint.sh"
}

@test "scripts/lint.sh fails when it cannot list the repository" {
  # The list came from `git ls-files` through a substitution whose failure
  # nobody checked: with no repository to read, the syntax stage parsed
  # nothing, the style stage found nothing to lint, and the run passed.
  GIT_DIR="${BATS_TEST_TMPDIR}/no-such-repository" \
    run --separate-stderr bash "${LINT_SH}" --stage shell
  assert_failure
  assert_stderr --partial "Cannot list the repository's files"
}

@test "scripts/lint.sh finds the same scripts whatever directory it runs from" {
  # A script known only by its shebang was looked for relative to the working
  # directory rather than the repository, so running from elsewhere lost it.
  local from_root from_elsewhere
  from_root="$(cd "${DYBATPHO_DIR}" && bash "${LINT_SH}" --list)"
  from_elsewhere="$(cd "${BATS_TEST_TMPDIR}" && bash "${LINT_SH}" --list)"
  [[ -n "${from_root}" ]]
  assert_equal "${from_elsewhere}" "${from_root}"
}
