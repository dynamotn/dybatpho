setup() {
  load test_helper
  # Every test gets its own cache directory, so nothing reaches the real one.
  DYBATPHO_CACHE_DIR="${BATS_TEST_TMPDIR}/cache"
  DYBATPHO_CACHE_NAMESPACE="default"
  DYBATPHO_CACHE_TTL=3600
}

# Backdate an entry so that staleness is tested against a real modification
# time rather than by waiting for the clock.
age_entry() {
  local path
  path="$(dybatpho::cache_path "$1")"
  touch -d "$2" "${path}" 2> /dev/null || touch -t 200001010000 "${path}"
}

@test "dybatpho::cache_dir puts a namespace below the cache directory" {
  assert_equal "$(dybatpho::cache_dir)" "${DYBATPHO_CACHE_DIR}/default"
  DYBATPHO_CACHE_NAMESPACE="gh"
  assert_equal "$(dybatpho::cache_dir)" "${DYBATPHO_CACHE_DIR}/gh"
  # An empty namespace means the cache directory names the place outright,
  # which is how a module with its own configured directory uses this.
  DYBATPHO_CACHE_NAMESPACE=""
  assert_equal "$(dybatpho::cache_dir)" "${DYBATPHO_CACHE_DIR}"
}

@test "dybatpho::cache_path refuses a key that cannot be a file name" {
  assert_equal "$(dybatpho::cache_path releases)" "${DYBATPHO_CACHE_DIR}/default/releases.cache"
  # A key becomes a path, so a key that can leave the directory is refused
  # rather than sanitised into something the caller did not ask for.
  run --separate-stderr ! dybatpho::cache_path "../escape"
  assert_stderr --partial "cannot be a file name"
  run --separate-stderr ! dybatpho::cache_path "a/b"
  run --separate-stderr ! dybatpho::cache_path ""
}

@test "dybatpho::cache_key hashes any value into a usable key" {
  local key
  key="$(dybatpho::cache_key "https://example.com/x?y=1")"
  assert_equal "$(dybatpho::cache_path "${key}")" "${DYBATPHO_CACHE_DIR}/default/${key}.cache"
  assert_equal "$(dybatpho::cache_key a b)" "$(dybatpho::cache_key a b)"
  # Two values must not hash to the same key as their concatenation.
  refute [ "$(dybatpho::cache_key a b)" = "$(dybatpho::cache_key ab)" ]
  run --separate-stderr ! dybatpho::cache_key
}

@test "dybatpho::cache_set stores what it is given and cache_get reads it back" {
  printf 'hello\n' | dybatpho::cache_set greeting
  assert_equal "$(dybatpho::cache_get greeting 3600)" "hello"
  # The default time to live applies when a call does not name one.
  assert_equal "$(dybatpho::cache_get greeting)" "hello"
  run_traced -0 dybatpho::cache_has greeting 3600
  run_traced ! dybatpho::cache_get absent 3600
  run_traced ! dybatpho::cache_has absent 3600
}

@test "dybatpho::cache_set writes nothing extra into the entry" {
  # The directory is created on the way, and the helper that does it prints the
  # path; on the writing end of a pipe that path would land in the entry.
  printf 'body\n' | dybatpho::cache_set exact
  assert_equal "$(dybatpho::cache_get exact 3600)" "body"
}

@test "an entry stops being fresh once it is older than its time to live" {
  printf 'old\n' | dybatpho::cache_set aged
  age_entry aged '2 hours ago'
  run_traced ! dybatpho::cache_has aged 60
  run_traced -0 dybatpho::cache_has aged 999999999
}

@test "a time to live of zero makes nothing fresh" {
  # This is how a caller forces a refresh without deleting anything, so a
  # just-written entry must not count as fresh either.
  printf 'new\n' | dybatpho::cache_set fresh
  run ! dybatpho::cache_has fresh 0
  run ! dybatpho::cache_get fresh 0
  run --separate-stderr ! dybatpho::cache_has fresh notanumber
  assert_stderr --partial "is not a number of seconds"
}

@test "dybatpho::cache_run runs the command once and reuses its output" {
  local counter="${BATS_TEST_TMPDIR}/runs"
  printf '0\n' > "${counter}"
  slow() {
    printf '%s\n' "$(($(cat "${counter}") + 1))" > "${counter}"
    printf 'computed\n'
  }
  assert_equal "$(dybatpho::cache_run memo 3600 -- slow)" "computed"
  assert_equal "$(dybatpho::cache_run memo 3600 -- slow)" "computed"
  assert_equal "$(cat "${counter}")" "1"
  # Without a time to live the default decides, and it is still a hit.
  assert_equal "$(dybatpho::cache_run memo -- slow)" "computed"
  assert_equal "$(cat "${counter}")" "1"
  # A zero time to live runs it again.
  assert_equal "$(dybatpho::cache_run memo 0 -- slow)" "computed"
  assert_equal "$(cat "${counter}")" "2"
}

@test "dybatpho::cache_run never stores a command that failed" {
  # Remembering a failure turns one bad minute into a whole time to live of
  # them, and the caller cannot tell a remembered error from a fresh one.
  boom() {
    printf 'partial\n'
    return 7
  }
  local status=0 output
  output="$(dybatpho::cache_run failing 3600 -- boom)" || status=$?
  assert_equal "${status}" "7"
  assert_equal "${output}" ""
  run_traced ! dybatpho::cache_has failing 3600
}

@test "dybatpho::cache_run insists on a command after the separator" {
  run --separate-stderr ! dybatpho::cache_run nothing 3600 --
  assert_stderr --partial "Expected a command to run after --"
  run --separate-stderr ! dybatpho::cache_run nodashes 3600 printf
  assert_stderr --partial "Expected:"
}

@test "dybatpho::cache_forget removes one entry and leaves the rest" {
  printf 'x\n' | dybatpho::cache_set one
  printf 'y\n' | dybatpho::cache_set two
  dybatpho::cache_forget one
  run_traced ! dybatpho::cache_has one 3600
  run_traced -0 dybatpho::cache_has two 3600
  # Forgetting something that is not there is not an error.
  run_traced -0 dybatpho::cache_forget one
}

@test "dybatpho::cache_clear removes this module's entries and nothing else" {
  printf 'x\n' | dybatpho::cache_set one
  printf 'y\n' | dybatpho::cache_set two
  local foreign="$(dybatpho::cache_dir)/not-ours.txt"
  printf 'keep\n' > "${foreign}"
  dybatpho::cache_clear
  run_traced ! dybatpho::cache_has one 3600
  run_traced ! dybatpho::cache_has two 3600
  # The directory is named by an environment variable, so emptying whatever it
  # happens to contain is not something this offers to do.
  assert_equal "$(cat "${foreign}")" "keep"
  # Clearing a namespace that was never written is not an error.
  DYBATPHO_CACHE_NAMESPACE="never-used"
  run_traced -0 dybatpho::cache_clear
}

@test "namespaces keep entries of the same key apart" {
  printf 'in-a\n' | DYBATPHO_CACHE_NAMESPACE=a dybatpho::cache_set shared
  printf 'in-b\n' | DYBATPHO_CACHE_NAMESPACE=b dybatpho::cache_set shared
  assert_equal "$(DYBATPHO_CACHE_NAMESPACE=a dybatpho::cache_get shared 3600)" "in-a"
  assert_equal "$(DYBATPHO_CACHE_NAMESPACE=b dybatpho::cache_get shared 3600)" "in-b"
  DYBATPHO_CACHE_NAMESPACE=a dybatpho::cache_clear
  DYBATPHO_CACHE_NAMESPACE=a run ! dybatpho::cache_has shared 3600
  assert_equal "$(DYBATPHO_CACHE_NAMESPACE=b dybatpho::cache_get shared 3600)" "in-b"
}

@test "DRY_RUN reports a write and a removal instead of performing them" {
  printf 'z\n' | DRY_RUN=true dybatpho::cache_set dryrun
  run_traced ! dybatpho::cache_has dryrun 3600
  printf 'kept\n' | dybatpho::cache_set survivor
  DRY_RUN=true dybatpho::cache_forget survivor
  run_traced -0 dybatpho::cache_has survivor 3600
  DRY_RUN=true dybatpho::cache_clear
  run_traced -0 dybatpho::cache_has survivor 3600
}

@test "an entry is private to its owner even under a permissive umask" {
  local previous
  previous="$(umask)"
  umask 022
  printf 'expensive answer\n' | dybatpho::cache_set private
  umask "${previous}"

  # An entry holds whatever was expensive to obtain, which is not public.
  dybatpho::assert_file_mode "$(dybatpho::cache_path private)" 600
  dybatpho::assert_file_mode "$(dybatpho::cache_dir)" 700
}

@test "dybatpho::cache_forget under DRY_RUN reports the removal and keeps the entry" {
  printf 'still here\n' | dybatpho::cache_set keeper
  DRY_RUN=true run -0 dybatpho::cache_forget keeper
  assert_output --partial "remove"
  assert_output --partial "$(dybatpho::cache_path keeper)"
  run_traced -0 dybatpho::cache_has keeper 3600
}

@test "dybatpho::cache_clear under DRY_RUN reports the directory and empties nothing" {
  printf 'still here\n' | dybatpho::cache_set keeper
  DRY_RUN=true run -0 dybatpho::cache_clear
  assert_output --partial "clear"
  assert_output --partial "$(dybatpho::cache_dir)"
  run_traced -0 dybatpho::cache_has keeper 3600
}
