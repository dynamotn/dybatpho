# Feature Specification: Time-to-Live Cache on Disk

**Feature Branch**: `[cache-ttl]`
**Status**: Implemented
**Input**: Existing source analysis: `src/cache.sh`, `docs/cache.md`, `test/cache.bats`, and `example/cache_ops.sh`

## Problem Statement *(mandatory)*

A script that asks a slow question more than once writes the same four lines
every time: work out a file name, read how old that file is, compare the age
against a number of seconds, and remember to create the directory first.
`dybatpho::file_age_seconds` documents exactly that shape as its own usage
example, and `src/ai.sh` had written it out in full, which is how the library
came to carry a cache that nothing else could use.

That private copy also had two defects a shared one does not. It read the
modification time with `date -r FILE`, where BSD `date` expects a number of
seconds rather than a path, so the age was wrong or unreadable outside GNU
coreutils. And it wrote entries with a plain redirection, which truncates the
file before filling it, so a reader running at the same moment could see an
empty or half-written entry.

## Business Value *(mandatory)*

Repeated work against a slow or rate-limited source is the common cost in CI
and in operator scripts: the same API listing fetched once per job step, the
same resolution repeated per host. One call turns that into one request,
without the caller hand-rolling expiry logic that is easy to get subtly wrong
and that nothing tests.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ask a slow question once (Priority: P1)

As a script author, I want to run a command and reuse its output until it goes
stale, so that a listing I need in five places is fetched once.

**Independent Test**: Run a command through the cache twice and verify it was
executed once.

**Acceptance Scenarios**:

1. **Given** no entry exists, **When** the command is run through the cache,
   **Then** the command runs and its output is both printed and stored.
2. **Given** a fresh entry exists, **When** the same call is made, **Then** the
   stored output is printed and the command does not run.
3. **Given** a time to live of zero, **When** the call is made, **Then** the
   command runs again, so a script can offer a refresh without deleting files.

### User Story 2 - Do not remember a failure (Priority: P1)

As a script author, I want a failed command to be asked again next time, so
that one bad minute does not become a whole time to live of them.

**Independent Test**: Run a failing command through the cache and verify
nothing was stored and its exit status came back.

**Acceptance Scenarios**:

1. **Given** a command that exits non-zero, **When** it is run through the
   cache, **Then** its exit status is returned and no entry is written.
2. **Given** that same key, **When** the call is repeated, **Then** the command
   runs again.

### User Story 3 - Keep unrelated caches apart (Priority: P2)

As a script author, I want two parts of a script to use the same obvious key
without colliding, so that neither has to invent a prefix.

**Independent Test**: Store the same key in two namespaces and verify each
reads back its own value and clears independently.

### User Story 4 - Give a module its own cache directory (Priority: P2)

As a module author, I want to point the cache at a directory my own
configuration names, so that a documented setting such as
`DYBATPHO_AI_CACHE_DIR` keeps working.

**Independent Test**: Set the cache directory with an empty namespace and
verify entries land directly in it.

### User Story 5 - Answer at once from a recent answer while it refreshes (Priority: P2)

As a script author, I want an expired entry to be answered immediately while
the command runs again in the background, so that a prompt or status line never
waits on a slow source that answered a moment ago.

**Independent Test**: Backdate an entry past its time to live, run it through
the cache with a grace window, and verify the old answer comes back at once and
the entry is replaced once the refresh finishes.

**Acceptance Scenarios**:

1. **Given** an entry older than its time to live but within the grace window,
   **When** the command is run through the cache with `--stale`, **Then** the
   stored output is printed and the command runs once in the background to
   replace it.
2. **Given** an entry older than the time to live and the grace window
   together, **When** the call is made, **Then** it is a miss and the command
   runs in the foreground.
3. **Given** a refresh of that entry already running, **When** another call
   finds the entry stale, **Then** no second refresh starts.
4. **Given** a background refresh whose command fails, **When** it ends,
   **Then** the entry it was meant to replace is still there.
5. **Given** a refresh under way, **When** the script waits for the entry,
   **Then** the wait returns once the refresh is done, or fails when its time
   runs out first.

### User Story 6 - Keep a cache within bounds (Priority: P2)

As an operator, I want to drop old entries until a namespace fits a count, a
size, or an age, so that a cache keyed by URL does not grow without limit on a
long-lived host.

**Independent Test**: Write entries with known modification times and sizes,
prune with each limit, and verify the entries written longest ago are the ones
removed.

**Acceptance Scenarios**:

1. **Given** entries of different ages, **When** the namespace is pruned with
   `--older-than`, **Then** exactly the entries past that age are removed.
2. **Given** more entries than `--max-entries`, **When** the namespace is
   pruned, **Then** the least recently written are removed until it fits.
3. **Given** entries totalling more than `--max-size`, **When** the namespace
   is pruned, **Then** the least recently written are removed until the rest
   fit, and a size may carry a binary `K`, `M`, or `G` suffix.
4. **Given** `DRY_RUN`, **When** the namespace is pruned, **Then** each
   removal is reported and nothing is removed.

### User Story 7 - See what a cache holds (Priority: P3)

As an operator, I want a summary of a namespace, as text or JSON, so that I can
decide limits for pruning and feed a dashboard without walking the directory
myself.

**Independent Test**: Write entries of known sizes and ages, freeze the clock,
and verify the counts, bytes, freshness, and ages reported.

**Acceptance Scenarios**:

1. **Given** entries of known sizes and ages, **When** the namespace is
   described against a time to live, **Then** the entry count, total bytes,
   fresh and stale counts, and oldest and newest ages are reported.
2. **Given** `--json`, **When** the namespace is described, **Then** the same
   counts come back as one JSON object.
3. **Given** a namespace never written, **When** it is described, **Then**
   every count is zero and the call succeeds.

### Example Workflow

```sh
. dybatpho/init.sh --modules cache

releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"

status="$(dybatpho::cache_run status 300 --stale 86400 -- fetch_status)"
dybatpho::cache_wait status 30

dybatpho::cache_prune --older-than 604800 --max-size 50M
dybatpho::cache_stats 3600 --json

key="$(dybatpho::cache_key "${url}")"
if ! body="$(dybatpho::cache_get "${key}" 600)"; then
  body="$(dybatpho::curl_json "${url}" /dev/stdout)"
  printf '%s\n' "${body}" | dybatpho::cache_set "${key}"
fi
```

## Edge Cases

- A script serves stale entries or waits for a refresh without having loaded the `lock` module.
- A key that could leave the cache directory, such as `../escape` or `a/b`.
- A key that is an arbitrary value: a URL, a request body, a whole command line.
- An entry written moments ago against a time to live of zero.
- A namespace that has never been written being cleared.
- A file in the cache directory that this module did not write.
- `DRY_RUN` set, with no cache directory in existence yet.
- A command that prints to standard error as well as standard output.
- Several calls finding the same stale entry at once, from one shell or many.
- A background refresh that fails, or is interrupted while it runs.
- A refresh started from inside a command substitution, which the calling
  shell's own `wait` cannot see.
- A time to live or grace window that is not a number of seconds.
- Several entries written within the same second when pruning by count.
- A size limit with a suffix, in either case, or an unknown one such as `T`.
- Pruning a namespace that was never written, or is empty.
- Describing a namespace that was never written, or with the time to live after `--json`.
- An accessor is given a key that cannot be a file name from inside a condition.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST store entries under a configurable directory, grouped by a configurable namespace, and MUST place entries directly in the directory when the namespace is empty.
- **FR-002**: The module MUST expose the directory and the path of an entry, so a caller can report where its cache lives.
- **FR-003**: A key MUST be usable as a file name. The module MUST refuse a key that is not, rather than sanitising it into something the caller did not ask for, and MUST offer a hashing helper for values that are not already short names.
- **FR-004**: The hashing helper MUST accept several values and MUST NOT hash two values to the same key as their concatenation.
- **FR-005**: An entry MUST be fresh while its age is less than the time to live, so that a time to live of zero makes nothing fresh. The module MUST NOT offer a value meaning "never expires".
- **FR-006**: The module MUST take the time to live per call, falling back to a configured default.
- **FR-007**: Entries MUST be written atomically, so a reader sees either the previous entry or the complete new one.
- **FR-008**: Storing an entry MUST create the directory it needs, and MUST NOT let the output of doing so reach the stored content.
- **FR-009**: The module MUST memoize a command: printing a fresh entry when there is one, otherwise running the command, storing its standard output, and printing it.
- **FR-009a**: A command that exits non-zero MUST NOT be stored, and its exit status MUST be returned unchanged.
- **FR-009b**: The command's standard error MUST NOT be captured, so a warning it prints is seen on every call rather than once.
- **FR-010**: The module MUST remove a single entry, and MUST remove every entry of a namespace while leaving files it did not write alone.
- **FR-011**: Removing an entry or a namespace that is not there MUST succeed.
- **FR-012**: `DRY_RUN` MUST report a write, a removal, and a clear instead of performing them, and MUST work when the cache directory does not yet exist.
- **FR-013**: The `ai` module MUST use this module rather than its own copy, keeping `DYBATPHO_AI_CACHE_DIR`, `DYBATPHO_AI_CACHE_TTL`, and `DYBATPHO_AI_CACHE` working as documented.
- **FR-014**: A cache entry MUST be written `0600` inside a directory created
  `0700`. An entry holds whatever the caller found expensive to obtain -- an API
  response, a query result -- which is not public, and under the usual
  `umask 022` a new file would otherwise be readable by every account on the
  host.

- **FR-015**: `dybatpho::cache_run` MUST accept a grace window, as `--stale <seconds>`, `--stale=<seconds>`, or `DYBATPHO_CACHE_STALE`, defaulting to none. An entry older than the time to live but younger than the time to live and the window together MUST be printed at once while the command runs again in the background to replace it; an entry older than both MUST be a miss.
- **FR-016**: At most one background refresh of an entry MUST run at a time, guarded by a lock beside the entry that is taken before the refresh starts and released when it ends, including when it is interrupted. The lock MUST NOT be mistaken for an entry by clearing a namespace.
- **FR-017**: A background refresh that fails MUST leave the existing entry in place, and its output and diagnostics MUST NOT reach the caller or hold a command substitution open.
- **FR-018**: The module MUST offer a way to wait for the background refresh of an entry, with a time limit, returning `1` when a refresh is still running when the time runs out.
- **FR-019**: `dybatpho::cache_run` MUST stop the script when the time to live or the grace window is not a number of seconds, or when more than one time to live is given.
- **FR-020**: The module MUST prune the current namespace by any combination of `--older-than <seconds>`, `--max-entries <count>`, and `--max-size <size>`, each also accepted in `--option=value` form, removing entries past the age first and then the least recently written until the rest fit every limit.
- **FR-021**: Entries written within the same second MUST be pruned in the order of their keys, so the result never depends on the file system.
- **FR-022**: Pruning MUST consider only entries this module wrote in the current namespace, MUST succeed when the namespace does not exist, and MUST report each removal instead of performing it under `DRY_RUN`.
- **FR-023**: Pruning MUST stop the script when no limit is given, an option is unknown or lacks its value, or a limit is malformed; a size MUST be a number of bytes with an optional binary `K`, `M`, or `G` suffix.
- **FR-024**: The module MUST describe the current namespace with its entry count, total bytes, counts of fresh and stale entries against a given or default time to live, and the ages of its oldest and newest entries, as aligned text or, with `--json`, as one JSON object with `entries`, `bytes`, `fresh`, `stale`, `oldest_age`, and `newest_age`.
- **FR-025**: Describing a namespace MUST count only entries this module wrote, MUST report zero everywhere for a namespace never written, and MUST stop the script on a malformed time to live or an unknown option. It MUST NOT count hits and misses.
- **FR-026**: Loading the module MUST NOT load `lock`. A grace window, from `--stale` or `DYBATPHO_CACHE_STALE`, and `cache_wait` MUST stop the script, naming the `lock` module and how to load it, when that module is not loaded, before an entry is read; caching without a grace window MUST work without it.
- **FR-027**: Every accessor MUST resolve an entry's path in the caller's shell, so a key that cannot be a file name stops the script instead of reading as a missing entry.
- **FR-028**: The cache directory MUST fall back to the user cache when `DYBATPHO_CACHE_DIR` is empty, never resolve to the root of the filesystem.
- **FR-029**: Falling back from an empty `DYBATPHO_CACHE_DIR` MUST happen in the caller's shell, so that with neither `XDG_CACHE_HOME` nor `HOME` set the public function stops instead of writing from `/`.

### Key Entities *(include if feature involves data)*

- **Entry**: One stored answer, named by its key and aged by its modification time.
- **Namespace**: A subdirectory grouping entries that belong together.
- **Time to live**: The number of seconds an entry stays usable.
- **Grace window**: The seconds after the time to live during which an entry is still answered while it is refreshed.
- **Refresh lock**: The lock beside an entry held for as long as its background refresh runs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A repeated slow call is made once per time to live rather than once per use.
- **SC-002**: A caller offers a refresh without deleting anything, by asking with a time to live of zero.
- **SC-003**: A transient failure is retried on the next call rather than remembered.
- **SC-004**: A reader never sees a partially written entry.
- **SC-005**: The library carries one cache implementation rather than one per module.
- **SC-006**: A caller with a grace window never waits on the source while a recent answer exists, and the source is asked once per refresh however many callers find the entry stale.
- **SC-007**: A long-lived cache stays within a stated count, size, or age without a hand-written cleanup.
- **SC-008**: An operator reads a namespace's size and freshness in one call, in a form a script or dashboard can parse.

## Integration Tests *(mandatory)*

- **IT-001**: Verify the directory includes the namespace, and that an empty namespace puts entries directly in the cache directory.
- **IT-002**: Verify the entry path for a valid key, and that `../escape`, `a/b`, and an empty key are refused.
- **IT-003**: Verify the hashing helper produces a usable key, is stable, distinguishes two values from their concatenation, and refuses no arguments.
- **IT-004**: Store and read an entry back, with an explicit time to live and with the default, and verify a missing entry reports absent.
- **IT-005**: Verify nothing but the stored content ends up in an entry, including the path the directory helper prints.
- **IT-006**: Backdate an entry and verify it stops being fresh against a short time to live and stays readable against a long one.
- **IT-007**: Verify a time to live of zero makes a just-written entry stale, and that a non-numeric one stops the script.
- **IT-008**: Run a command through the cache twice and verify it executed once; verify the default time to live is a hit and a zero one re-runs.
- **IT-009**: Run a failing command and verify its status comes back, nothing is printed, and no entry is stored.
- **IT-010**: Verify a missing command after the separator, and a call with no separator, stop the script.
- **IT-011**: Verify removing one entry leaves the others, and that removing an absent one succeeds.
- **IT-012**: Verify clearing a namespace removes this module's entries, leaves a foreign file alone, and succeeds on a namespace never written.
- **IT-013**: Store the same key in two namespaces and verify each reads back its own value and that clearing one leaves the other.
- **IT-014**: Verify `DRY_RUN` stores nothing when no directory exists, and leaves an existing entry in place for a removal and a clear.
- **IT-015**: Verify the `ai` module still answers from its cache and still clears it, through its own documented environment variables.
- **IT-016**: Verify a stored entry is `0600` and its directory `0700`, under a
  permissive `umask`.
- **IT-017**: Backdate an entry, run it with `--stale`, and verify the old answer is printed, the command ran once, and the entry holds the new answer after waiting.
- **IT-018**: Verify an entry older than the time to live and the window is a miss, through `--stale=` and through `DYBATPHO_CACHE_STALE`.
- **IT-019**: Verify a failing background refresh leaves the old entry in place.
- **IT-020**: Hold the refresh lock, verify a stale call starts no refresh, that waiting gives up with `1` while the lock is held and succeeds once it is released, and that clearing the namespace still succeeds.
- **IT-021**: Verify a non-numeric time to live, grace window, or wait limit, a missing `--stale` value, and a second time to live stop the script.
- **IT-022**: With the clock frozen, verify `--older-than` removes only the entry past the age, that `--older-than=0` removes the rest, and that a foreign file is left alone.
- **IT-023**: Verify `--max-entries` removes the least recently written first, leaves a namespace already within the limit alone, and that zero empties it.
- **IT-024**: Verify `--max-size` with a `k` suffix, an exact byte limit, and a limit below one entry.
- **IT-025**: Verify entries of the same second are pruned by key when limits are combined.
- **IT-026**: Verify `DRY_RUN` reports the removal of the oldest entry only and removes nothing.
- **IT-027**: Verify pruning a namespace that does not exist, and one that is empty, succeeds.
- **IT-028**: Verify no limit, an unknown option, a missing value, and malformed age, count, and size limits stop the script.
- **IT-029**: With the clock frozen, verify the JSON and text reports of two entries against several times to live, with the option before and after the time to live, and that a foreign file is not counted.
- **IT-030**: Verify a namespace never written reports zero in both forms.
- **IT-031**: Verify a malformed time to live and an unknown option stop the script.
- **IT-032**: In a script that loaded `cache` alone, cache a command, have `--stale` and `cache_wait` stop and name the `lock` module, and run both once `lock` is loaded.
- **IT-033**: From a script file, have `cache_get` used as a condition stop the script on `../escape` before the branch for a miss runs.
- **IT-034**: Resolve the cache directory with `DYBATPHO_CACHE_DIR` emptied and a namespace set, and get a path under `XDG_CACHE_HOME`.
- **IT-035**: Store an entry with the cache directory emptied and no home, under `if !`, and stop naming `dybatpho::cache_set`.

## Acceptance Criteria *(mandatory)*

1. A slow command run through the cache executes once per time to live.
2. A failed command is never stored and its status reaches the caller.
3. Entries expire on their modification time, and a zero time to live forces a refresh.
4. Clearing a namespace touches only entries this module wrote.
5. `src/ai.sh` holds no cache implementation of its own.
6. With a grace window, an expired entry is answered at once and refreshed once in the background, and a failed refresh keeps it.
7. Pruning removes the entries written longest ago until the namespace fits its limits.
8. A namespace can be described in one call, as text or JSON.
