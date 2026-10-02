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

@test "dybatpho::cache_run --stale serves an expired entry and refreshes it behind" {
  local counter="${BATS_TEST_TMPDIR}/runs"
  printf '0\n' > "${counter}"
  fetch() {
    printf '%s\n' "$(($(cat "${counter}") + 1))" > "${counter}"
    printf 'new\n'
  }
  printf 'old\n' | dybatpho::cache_set swr
  age_entry swr '2 hours ago'

  run_traced -0 dybatpho::cache_run swr 60 --stale 999999999 -- fetch
  assert_output "old"
  run_traced -0 dybatpho::cache_wait swr 10
  assert_equal "$(cat "${counter}")" "1"
  assert_equal "$(dybatpho::cache_get swr 60)" "new"
}

@test "dybatpho::cache_run treats an entry older than the stale window as a miss" {
  fetch() { printf 'new\n'; }
  printf 'old\n' | dybatpho::cache_set swr
  age_entry swr '2 hours ago'
  # The `=` form and the environment default are the same option.
  run_traced -0 dybatpho::cache_run swr 60 --stale=60 -- fetch
  assert_output "new"
  age_entry swr '2 hours ago'
  DYBATPHO_CACHE_STALE=60 run_traced -0 dybatpho::cache_run swr 60 -- fetch
  assert_output "new"
}

@test "dybatpho::cache_run --stale keeps the entry when the refresh fails" {
  boom() { return 3; }
  printf 'old\n' | dybatpho::cache_set swr
  age_entry swr '2 hours ago'
  run_traced -0 dybatpho::cache_run swr --stale 999999999 -- boom
  assert_output "old"
  run_traced -0 dybatpho::cache_wait swr 10
  assert_equal "$(dybatpho::cache_get swr 999999999)" "old"
}

@test "dybatpho::cache_run --stale starts no second refresh while one runs" {
  local counter="${BATS_TEST_TMPDIR}/runs"
  printf '0\n' > "${counter}"
  fetch() {
    printf '%s\n' "$(($(cat "${counter}") + 1))" > "${counter}"
    printf 'new\n'
  }
  printf 'old\n' | dybatpho::cache_set swr
  age_entry swr '2 hours ago'
  local lock
  lock="$(dybatpho::cache_path swr)"
  lock="${lock%.cache}.lock"
  # This shell holds the refresh lock, as a refresh already under way would.
  dybatpho::lock_acquire "${lock}"
  run_traced -0 dybatpho::cache_run swr 60 --stale 999999999 -- fetch
  assert_output "old"
  sleep 0.3
  assert_equal "$(cat "${counter}")" "0"
  # A refresh still under way makes the wait give up when its time runs out.
  DYBATPHO_LOCK_POLL_INTERVAL=0.1 run_traced -1 dybatpho::cache_wait swr 1
  dybatpho::lock_release "${lock}"
  run_traced -0 dybatpho::cache_wait swr 0
  # The lock is not an entry, so clearing the namespace never trips over it.
  run_traced -0 dybatpho::cache_clear
}

@test "dybatpho::cache_run refuses a time that is not a number of seconds" {
  run --separate-stderr ! dybatpho::cache_run k soon -- true
  assert_stderr --partial "is not a number of seconds"
  run --separate-stderr ! dybatpho::cache_run k 60 --stale never -- true
  assert_stderr --partial "for --stale"
  run --separate-stderr ! dybatpho::cache_run k 60 --stale
  assert_stderr --partial "Expected:"
  run --separate-stderr ! dybatpho::cache_run k 60 70 -- true
  assert_stderr --partial "Expected:"
  run --separate-stderr ! dybatpho::cache_wait k later
  assert_stderr --partial "is not a number of seconds"
}

# Write an entry with a given body and modification time, as `[[CC]YY]MMDDhhmm`.
entry_at() {
  printf '%s' "$2" | dybatpho::cache_set "$1"
  touch -t "$3" "$(dybatpho::cache_path "$1")"
}

remaining_entries() {
  local path names=()
  for path in "$(dybatpho::cache_dir)"/*.cache; do
    [[ -f "${path}" ]] || continue
    path="${path##*/}"
    names+=("${path%.cache}")
  done
  printf '%s\n' "${names[*]-}"
}

@test "dybatpho::cache_prune --older-than removes only entries past that age" {
  entry_at old x 200001010000
  entry_at recent x 200001010000
  local mtime
  mtime="$(dybatpho::file_mtime "$(dybatpho::cache_path recent)")"
  touch -t 200001010002 "$(dybatpho::cache_path recent)"
  # Two minutes separate the entries; with the clock frozen just after the
  # newer one, a limit of one minute removes exactly the older.
  dybatpho::mock_time "$((mtime + 150))"
  run_traced -0 dybatpho::cache_prune --older-than 60
  dybatpho::unmock_time
  assert_equal "$(remaining_entries)" "recent"
  local foreign="$(dybatpho::cache_dir)/not-ours.txt"
  printf 'keep\n' > "${foreign}"
  touch -t 200001010000 "${foreign}"
  run_traced -0 dybatpho::cache_prune --older-than=0
  assert_equal "$(remaining_entries)" ""
  assert_equal "$(cat "${foreign}")" "keep"
}

@test "dybatpho::cache_prune --max-entries removes the least recently written first" {
  entry_at c x 200301010000
  entry_at a x 200101010000
  entry_at b x 200201010000
  entry_at d x 200401010000
  run_traced -0 dybatpho::cache_prune --max-entries 2
  assert_equal "$(remaining_entries)" "c d"
  run_traced -0 dybatpho::cache_prune --max-entries=5
  assert_equal "$(remaining_entries)" "c d"
  run_traced -0 dybatpho::cache_prune --max-entries 0
  assert_equal "$(remaining_entries)" ""
}

@test "dybatpho::cache_prune --max-size keeps the newest entries that fit" {
  local body
  body="$(printf '%600s' '')"
  entry_at one "${body}" 200101010000
  entry_at two "${body}" 200201010000
  entry_at three "${body}" 200301010000
  run_traced -0 dybatpho::cache_prune --max-size 1k
  assert_equal "$(remaining_entries)" "three"
  run_traced -0 dybatpho::cache_prune --max-size=600
  assert_equal "$(remaining_entries)" "three"
  run_traced -0 dybatpho::cache_prune --max-size 599
  assert_equal "$(remaining_entries)" ""
}

@test "dybatpho::cache_prune orders entries of the same second by name" {
  entry_at beta x 200101010000
  entry_at alpha x 200101010000
  entry_at gamma x 200101010000
  run_traced -0 dybatpho::cache_prune --max-entries 1 --max-size 1G
  assert_equal "$(remaining_entries)" "gamma"
}

@test "dybatpho::cache_prune under DRY_RUN reports removals and removes nothing" {
  entry_at a x 200101010000
  entry_at b x 200201010000
  DRY_RUN=true run_traced -0 dybatpho::cache_prune --max-entries 1 --max-size 1M
  assert_output --partial "remove"
  assert_output --partial "$(dybatpho::cache_path a)"
  refute_output --partial "$(dybatpho::cache_path b)"
  assert_equal "$(remaining_entries)" "a b"
}

@test "dybatpho::cache_prune succeeds on a namespace that was never written" {
  DYBATPHO_CACHE_NAMESPACE="never-used"
  run_traced -0 dybatpho::cache_prune --max-entries 1
  mkdir -p "$(dybatpho::cache_dir)"
  run_traced -0 dybatpho::cache_prune --max-entries 1
}

@test "dybatpho::cache_prune refuses a missing or malformed limit" {
  run --separate-stderr ! dybatpho::cache_prune
  assert_stderr --partial "Expected --older-than"
  run --separate-stderr ! dybatpho::cache_prune --keep 3
  assert_stderr --partial "got '--keep'"
  run --separate-stderr ! dybatpho::cache_prune --max-entries
  assert_stderr --partial "needs a value"
  run --separate-stderr ! dybatpho::cache_prune --older-than soon
  assert_stderr --partial "is not a number of seconds"
  run --separate-stderr ! dybatpho::cache_prune --max-entries many
  assert_stderr --partial "is not a number of entries"
  run --separate-stderr ! dybatpho::cache_prune --max-size 10T
  assert_stderr --partial "is not a size"
}
