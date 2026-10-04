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

@test "release.sh regenerates the docs from a checkout whose path has a space" {
  # The docs step handed `dybatpho::dry_run` the script path as one string,
  # which it evaluates; under a directory with a space in its name the path
  # split in two and the release stopped after stamping VERSION.
  local repo="${BATS_TEST_TMPDIR}/re lease"
  mkdir -p "${repo}/scripts" "${repo}/docs"
  cp -R "${DYBATPHO_DIR}/src" "${repo}/src"
  cp "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}/VERSION" "${DYBATPHO_DIR}/CHANGELOG.md" "${repo}/"
  cp "${RELEASE_SH}" "${repo}/scripts/release.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "regenerated\n" > "$(cd "$(dirname "$0")/.." && pwd)/docs/marker"' > "${repo}/scripts/docs.sh"
  chmod +x "${repo}/scripts/docs.sh"
  git -C "${repo}" init -q
  git -C "${repo}" remote add origin "git@github.com:example/release-space.git"
  git -C "${repo}" -c user.name=t -c user.email=t@example.test add -A
  git -C "${repo}" -c user.name=t -c user.email=t@example.test commit -q -m "feat: start"

  run --separate-stderr env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test \
    "${repo}/scripts/release.sh" --version 9.9.9 --no-push --no-publish --no-bundle --yes
  assert_success
  assert_equal "$(cat "${repo}/docs/marker")" "regenerated"
  assert_equal "$(git -C "${repo}" log -1 --format=%s)" "chore(release): v9.9.9"
}
