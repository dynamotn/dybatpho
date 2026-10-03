setup() {
  load test_helper
  RELEASE_SH="${DYBATPHO_DIR}/scripts/release.sh"
}

# Run the release script as a user would, always as a rehearsal: a refusal is
# what these tests are about, and `--dry-run` keeps a regression from stamping,
# committing or pushing anything if the refusal ever stops happening.
release() {
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES -u GITHUB_TOKEN -u GITLAB_TOKEN \
    "${RELEASE_SH}" --dry-run "$@"
}

@test "release.sh refuses options that cannot all be honoured before doing anything" {
  # `--publish` is the default, and it needs the tag pushed. Finding that out
  # after the tree was stamped, committed and tagged left a half-made release.
  run --separate-stderr release --no-push
  assert_failure
  assert_stderr --partial "--publish needs the tag pushed"
  refute_stderr --partial "Releasing"

  run --separate-stderr release --sign --no-bundle
  assert_failure
  assert_stderr --partial "--sign needs the checksum file"

  run --separate-stderr release --draft --no-publish
  assert_failure
  assert_stderr --partial "--draft needs --publish"

  # Reaching this refusal also proves `--bump minor` parses: its choices were
  # once declared with `|`, which the spec reads as one choice, so every
  # `--bump` value was rejected.
  run --separate-stderr release --version 9.9.9 --bump minor
  assert_failure
  assert_stderr --partial "--version and --bump"
  refute_stderr --partial "Validation error"
}
