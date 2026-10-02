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

### Example Workflow

```sh
. dybatpho/init.sh --modules cache

releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"

status="$(dybatpho::cache_run status 300 --stale 86400 -- fetch_status)"
dybatpho::cache_wait status 30

key="$(dybatpho::cache_key "${url}")"
if ! body="$(dybatpho::cache_get "${key}" 600)"; then
  body="$(dybatpho::curl_json "${url}" /dev/stdout)"
  printf '%s\n' "${body}" | dybatpho::cache_set "${key}"
fi
```

## Edge Cases

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

## Acceptance Criteria *(mandatory)*

1. A slow command run through the cache executes once per time to live.
2. A failed command is never stored and its status reaches the caller.
3. Entries expire on their modification time, and a zero time to live forces a refresh.
4. Clearing a namespace touches only entries this module wrote.
5. `src/ai.sh` holds no cache implementation of its own.
6. With a grace window, an expired entry is answered at once and refreshed once in the background, and a failed refresh keeps it.
