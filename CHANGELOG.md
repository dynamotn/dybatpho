# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`process` — a general time limit, named background jobs, and PID files.**
  The library could bound a curl request and nothing else, so every script that
  needed a command not to hang reached for the `timeout` binary — which a stock
  macOS does not ship, and which cannot run a shell function because it
  executes a program.

  ```sh
  dybatpho::run_with_timeout 30 ./deploy.sh # 124 when it overran
  dybatpho::run_with_timeout 5 my_function  # a function works too

  dybatpho::trap dybatpho::kill_children EXIT INT TERM
  dybatpho::background_run api ./serve.sh --port 8080
  dybatpho::background_run worker ./worker.sh
  dybatpho::wait_all \
    || dybatpho::die "worker exited $(dybatpho::background_status worker)"

  dybatpho::pid_file_is_running /var/run/app.pid && dybatpho::die "Already running"
  dybatpho::pid_file_write /var/run/app.pid
  dybatpho::trap 'dybatpho::pid_file_remove /var/run/app.pid' EXIT
  ```

  `dybatpho::run_with_timeout` uses the system `timeout` when it is there and
  usable, and a Bash watchdog when it is not, so the behaviour is the same on a
  machine with no coreutils. A shell function always takes the Bash path. The
  watchdog records that it fired in a marker file rather than reading the exit
  status, because a command killed by SIGTERM and a command that chose to exit
  143 look identical and only the first is a timeout. The limit is enforced
  with SIGTERM and then SIGKILL after `DYBATPHO_TIMEOUT_KILL_AFTER` seconds, so
  a job that cleans up on SIGTERM still gets to, and one that ignores it still
  goes.

  Timed and background commands run under job control, leading their own
  process group, so ending one ends what it started — otherwise a "killed"
  build leaves its compiler running. A job that does not lead its own group is
  never signalled as a group, because that group is the calling script's.

  `dybatpho::wait_all` records each job's exit code under its name instead of
  collapsing them: `wait` reports only one status, so a script that started
  three jobs could not say which of them failed. `dybatpho::background_run`
  refuses a name whose job is still running rather than forgetting the first
  one.

  `dybatpho::pid_file_write` stages the file and moves it into place, so a
  reader never sees the empty file that makes a supervisor believe a healthy
  service is dead. `dybatpho::pid_file_is_running` answers "nothing is running"
  for a missing, empty, malformed, or stale file alike, since that is the one
  thing callers act on, and `dybatpho::pid_file_remove` refuses to delete a PID
  file that records a different process — the guard that stops an exiting
  service from removing the PID file its replacement just wrote.
- **`config` — writing configuration back, profile overlays, and TOML.** The
  module could read a configuration and validate it, but not change one. A
  script that had to persist a setting was left rewriting the file by hand,
  and a hand-rolled rewrite loses exactly what makes the file worth keeping:
  the comments, the ordering, and the keys the script has no opinion about.

  ```sh
  dybatpho::config_set PORT 9090
  dybatpho::config_save ./config.yaml PORT
  ```

  `dybatpho::config_save` writes in the format the file already uses. A dotenv
  file is rewritten line by line, so comments, blank lines, assignment order,
  and unrelated keys survive, and keys the file never mentioned are appended.
  JSON, YAML, and TOML go through `jq` and `yq` as one assignment per key
  rather than a merged second document — a node imported from JSON carries its
  flow style with it and reflows everything around it, whereas assigning in
  place leaves a YAML file's comments and indentation where they were. The
  write is atomic and honors `DRY_RUN`, and values reach `jq` and `yq` through
  the environment rather than the command line, so a configured secret does
  not become world-readable in `/proc`.

  A value is written as a number or a boolean only when
  `dybatpho::config_schema` declared it as `int` or `bool`. Without a schema
  there is nothing to distinguish the string `01234` from the number `1234`,
  so the value is written as a string and the file stays honest about what it
  was told.

  ```sh
  dybatpho::config_profile ./config.yaml prod   # config.yaml, then config.prod.yaml
  dybatpho::config_load --optional /etc/app.env # absent is not an error
  ```

  `dybatpho::config_profile` is the overlay every deployment ends up writing:
  a shared base file, then the per-environment file beside it, which very
  often does not exist. The profile may also come from
  `DYBATPHO_CONFIG_PROFILE`. `--optional` is the same tolerance for any other
  list of files; without it a missing file is still an error, as before.

  `.toml` files now load too, through the same `yq` the YAML path uses, and
  `config_save` writes them back.

  `dybatpho::config_set` makes the in-memory setter public. It was already
  there as an internal helper, which meant the example had to reach into a
  `__dybatpho_` name to demonstrate a validation failure.
- **`logging` — a durable sink, fields that ride along, and the time a step
  took.** The file sink already existed, but reaching it meant exporting four
  variables in the right order and finding out from an empty file that the
  path was wrong. `dybatpho::log_to_file` is the front door to it:

  ```sh
  dybatpho::log_to_file /var/log/deploy.log rotate:10M keep:3 level:debug
  dybatpho::log_to_file off # back to stderr only
  ```

  It parses the rotation size the way an operator says it, checks every
  setting, and creates the directory and the file before it returns, so a path
  that will not work is reported where it is configured. A log file it creates
  is mode `600`, because a log holds whatever the script logged; one that
  already exists keeps the mode it has. Registered secrets were already masked
  on their way into the file, and still are — turning on a durable log has
  never been a way to leak a token into one.

  `dybatpho::log_context` attaches fields to every event that follows, instead
  of spelling them out in every message:

  ```sh
  dybatpho::log_context add run_id=abc stage=build
  dybatpho::error "compilation failed"
  # {"message":"compilation failed",…,"run_id":"abc","stage":"build"}
  ```

  The fields come after the built-in ones, in the order they were added, so an
  existing parser keeps working and two events from one run stay comparable.
  They follow the message on a text line too. Values are escaped and redacted
  exactly as messages are, and a name that an event already uses — `message`,
  `level`, `pid` — is refused rather than producing a duplicated field.
  `remove`, `clear`, `list` and `get` round it out.

  `dybatpho::timer_start` and `dybatpho::timer_end` answer where the twenty
  minutes went, without adding a metrics endpoint to find out:

  ```sh
  dybatpho::timer_start migration
  ./migrate.sh
  dybatpho::timer_end migration # "migration took 4182ms"
  ```

  The structured event carries `timer` and `elapsed_ms` as fields of their own,
  and `DYBATPHO_TIMER_LAST_MS` holds the number afterwards — published rather
  than printed, because `$(...)` would run the call in a subshell and throw the
  measurement away. `dybatpho::metrics_timer_start` still records the same
  measurement as a metric for a dashboard; this one puts it in the log.

  `dybatpho::spinner` says that a slow command is working rather than hung:

  ```sh
  dybatpho::spinner "Downloading dependencies" -- npm ci
  ```

  The command runs in the foreground of the calling shell, so it keeps stdin,
  its output goes where it would anyway, and its exit code comes back
  unchanged; only the animation runs in the background, and it is torn down and
  its line erased whether the command succeeded or failed. Without a terminal
  on stderr — in CI, or redirected — there is nothing to animate, so the
  message is logged once at `info` and the command runs as usual. Every run
  leaves a `debug` event behind with its elapsed time and exit code, and a
  secret in the message is redacted before it is drawn. `DYBATPHO_SPINNER`
  forces the animation on or off, and `DYBATPHO_SPINNER_INTERVAL` and
  `DYBATPHO_SPINNER_FRAMES` change how it looks.
- **`network` — the other half of calling a service politely, and the API
  client that always gets rewritten.** The module already had a circuit
  breaker, which stops calling a service that is failing. It had nothing that
  stops calling one that is working — faster than it agreed to be called. An
  API that answers `429` for the rest of the hour once a script has spent its
  budget is not made better by retrying; it is made better by not spending the
  budget in the first place.

  ```sh
  dybatpho::rate_limit api.example.com 10/60 -- dybatpho::curl_json "${url}" /tmp/out.json
  dybatpho::rate_limit_remaining api.example.com 10/60 # calls left this minute
  ```

  The window holds the timestamps of the calls inside it. While the budget has
  room the command runs at once; when it is full the limiter waits exactly
  until the oldest call leaves the window, and then runs. Nothing is dropped,
  so a loop over five hundred items still finishes — at the rate the spec
  allows. A script that would rather skip work than block sets
  `DYBATPHO_RATE_LIMIT_WAIT=false` and reads exit code `9`, the same code the
  circuit breaker uses for a call it did not attempt. The window is written the
  way a rate limit is spoken: `10/60`, `10/1m`, `5/500ms`.

  Around it are the three helpers an API client needs anyway, each with a
  failure mode that is silent when it is hand-written:

  ```sh
  dybatpho::curl_paginate "https://api.example.com/items?per_page=100"
  dybatpho::curl_auth_bearer "${url}" "${API_TOKEN}" /tmp/me.json
  dybatpho::curl_graphql "${endpoint}" "${query}" "${variables}" /tmp/answer.json
  ```

  `curl_paginate` follows the `Link` header's `next` relation and prints one
  body per page, so the loop that rebuilds `?page=N` by hand — and misses the
  last page — is not written again; it refuses to visit a URL twice, so a
  server that repeats itself ends the walk rather than the script. `curl_link`
  reads one relation out of that header, matching `rel` as a whole word, which
  is what an entry written `rel="next last"` needs. `curl_auth_bearer` sends
  the token through `DYBATPHO_CURL_SECRET_HEADERS`, so it never appears in
  `/proc/<pid>/cmdline` where `ps auxww` prints it, and it keeps any secret
  headers the caller had already set. `curl_graphql` builds the
  `query`/`variables` envelope, sends it on standard input, and turns the
  `errors` array of an otherwise successful `200 OK` into exit code `4` with
  the first message logged — the one GraphQL failure a status check cannot see.

  `network` now loads `json` with it, which is what builds that envelope and
  reads the error out of it.

- **`helpers` — asking the library about itself, from the running shell.** The
  library documents itself in `doc/`, which answers the question while you are
  reading it. It does not answer it while you are writing: at a prompt, or
  halfway through a script, the question is what a function is called, which
  module it is in, and what it takes — and the answer is in a browser tab.

  ```sh
  dybatpho::provides semver_valid     # semver
  dybatpho::provides --path cache_run # /path/to/src/cache.sh:245
  dybatpho::describe cache_run        # the comment block, rendered
  dybatpho::function_list cache       # everything that module exports
  ```

  These ask Bash rather than the filesystem. `declare -F` under `extdebug`
  reports the file and line a function was defined at, and the documentation
  comment is sitting just above that line in the source that was loaded — so
  the answer describes the code that will actually run, and it is there whether
  or not `doc/` was ever generated. `extdebug` is switched on for the one call
  and put back exactly as it was found, since it also changes how `DEBUG` and
  `RETURN` traps behave.

  The name may be given with or without the `dybatpho::` prefix, because the
  prefix is what you have already typed when you stop to ask. Nothing external
  is called, so these work on a host with nothing installed but Bash. They live
  in `helpers`, a core module, because a helper you have to remember to load is
  one you will not reach for at a prompt.

  Inside a bundle every module lives in one file, so no function can be
  attributed to one. `dybatpho::describe` and `--path` still work there;
  `dybatpho::provides` fails rather than naming the bundle file as the module,
  and `dybatpho::function_list <module>` stops with an explanation rather than
  returning an empty list that would read as "this module exports nothing".

- **`cache` — remembering a slow answer on disk until it goes stale.** A script
  that asks a slow question twice writes the same four lines every time: work
  out a file name, read how old the file is, compare that to a number of
  seconds, and remember to create the directory. `dybatpho::file_age_seconds`
  documents that shape as its own example, and `ai` had written it out in full,
  which is how the library came to carry a cache nothing else could use.

  The centre of the module is one call:

  ```sh
  releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"
  ```

  A failing command is never stored: remembering a failure turns one bad minute
  into an hour of them, and the caller cannot tell a remembered error from a
  fresh one. Its exit status comes back unchanged, and its standard error is
  not captured either way, so a warning it prints is seen every time.

  Also new: `dybatpho::cache_get`, `cache_set`, `cache_has`, `cache_forget`,
  `cache_clear`, `cache_key`, `cache_path`, and `cache_dir`. An entry is fresh
  while its age is *less than* the time to live, so `0` makes nothing fresh —
  which is how a script offers `--refresh` without deleting anything. There is
  no value meaning "never expires": an entry that never goes stale is a file.

  A key becomes a file name, so a key that could leave the directory is refused
  rather than quietly rewritten; `dybatpho::cache_key` hashes a URL or a
  request body into one that cannot. `cache_clear` removes only entries this
  module wrote, because the directory is named by an environment variable and
  emptying whatever a path happens to contain is not something a helper should
  offer to do.

### Changed

- **Drawing a table no longer costs a process per cell.** Every function in the
  library returns its answer on stdout, so every caller reads it with `$( )` —
  and `$( )` forks. The renderers were built entirely out of those: measuring a
  cell, padding it, aligning it, repeating a character for the padding, and
  splitting a row into cells each went through a subshell, several times per
  cell.

  The internal helpers now write into a caller-named variable instead:
  `__dybatpho_log_width_into`, `__dybatpho_log_repeat_into`,
  `__dybatpho_table_width_into`, `__dybatpho_table_pad_into` and
  `__dybatpho_table_format_cell_into`. Row splitting trims in place rather than
  calling `dybatpho::split` through a process substitution and `dybatpho::trim`
  through a subshell per field. The stdout forms are kept, so nothing outside
  the library changes.

  Measured as a ratio against the cost of one fork on the same host — wall clock
  is meaningless on a busy machine — a 20×4 `dybatpho::table_box` went from
  about 550 forks' worth of work to between 55 and 120, roughly five to ten
  times less. `test/security/bench_value_return.sh` reports that ratio and fails
  above a budget.

  The rendered output is unchanged, which the table, text and logging suites
  check.
- **`dybatpho::table_csv` refuses CSV it cannot read, instead of mangling it.**
  It splits on every comma, so a quoted field containing one became two columns
  and the row stopped matching its header — quietly. The table was simply wrong,
  and wrong in a way that looks like data.

  This was never a broken promise: the helper is scoped as a convenience over
  comma-delimited input, not as an RFC 4180 parser, and the documented use is
  `... | tr -s ' ' ',' | dybatpho::table_csv -`. It was the name promising more
  than the contract. Refusing is not a parser either; it turns silent corruption
  into an error that names the limitation, which is the part that hurt.

  A quote that is not at a field boundary — `5" pipe` — is data and is still
  rendered. `DYBATPHO_TABLE_CSV_STRICT=false` restores the old splitting for
  data known to carry no quoting.
- **A lock is a symbolic link on disk, not a directory.** `lock_info`,
  `lock_is_held` and `lock_field` are unchanged, and `lock_field` still reads the
  old form, but anything that inspected the lock directory by hand stops
  working. The command that took the lock now lives in a file beside it, because
  it can contain anything and does not belong in a link target.
- **`ai` now uses the `cache` module instead of its own copy.**
  `DYBATPHO_AI_CACHE`, `DYBATPHO_AI_CACHE_DIR` and `DYBATPHO_AI_CACHE_TTL` keep
  working exactly as documented, and the cache keys are unchanged.

  Two defects go with the copy. It read an entry's age with `date -r FILE`,
  where BSD `date` expects a number of seconds rather than a path, so ages were
  wrong or unreadable outside GNU coreutils; it now goes through
  `dybatpho::file_age_seconds`, which handles both. And it wrote entries with a
  plain redirection, which truncates the file before filling it, so a reader
  running at that moment could see an empty or half-written response; writes are
  now atomic.

  Entries written by older versions carry a `.json` suffix and are not read any
  more. `dybatpho::ai_cache_clear` removes them as well as the new ones, so
  upgrading does not leave them behind.

- **`array` — order, slices, and set operations.** The module could filter and
  map an array but not put one in order, and nothing anywhere in the library
  could sort a plain list: `dybatpho::semver_sort` was the only sort there was.

  `dybatpho::array_sort` fills that in, with `--numeric` for the case that
  makes a shell script want a sort at all — as text, `10` comes before `9` —
  and `--reverse`. It is an insertion sort rather than a pipe through `sort(1)`,
  which keeps an element containing a newline whole and needs nothing installed.
  Text follows the locale's collation, as `sort` does; the numeric form takes
  whole numbers and stops on anything else rather than quietly falling back to
  text order.

  `dybatpho::array_slice` keeps a run of an array, with a negative start
  counting back from the end. `dybatpho::array_union`,
  `dybatpho::array_intersect` and `dybatpho::array_difference` compare two
  arrays; each produces a set, in the order the first array had them.

- **`string` — naming conventions and quoting for generated shell code.**
  `dybatpho::string_to_snake`, `_to_kebab`, `_to_camel` and `_to_pascal`
  convert between the conventions a codebase mixes, reading the word
  boundaries whichever one the input arrived in, so `XMLHttpRequest`,
  `deploy_to_prod` and `Deploy To Prod` all split the same way. This is what
  `dybatpho::string_slugify` is not: slugify is for prose and has no idea where
  the words are, so it answers `xmlhttprequest`.

  `dybatpho::string_quote` prepares a value to be written into shell code that
  is evaluated later — a completion script, a remote command. `printf %q` was
  already being used for this in four modules with no helper to call.

- **`date` — the calendar and span arithmetic the module was missing.** It
  could add days and count days, and nothing else. New:
  `dybatpho::date_is_leap_year`, `dybatpho::date_days_in_month`,
  `dybatpho::date_month_start`, `dybatpho::date_month_end`,
  `dybatpho::date_add`, `dybatpho::date_diff`, and
  `dybatpho::date_seconds_to_hms`.

  Spans are measured in units that are a fixed number of seconds: seconds,
  minutes, hours, days, and weeks. Months and years are refused rather than
  approximated, because their length depends on where in the calendar they fall
  and GNU and BSD `date` shift by them differently — a helper that took them
  would answer differently per platform.

  `dybatpho::date_add_days` and `dybatpho::date_diff_days` now delegate to the
  general helpers instead of repeating them, and answer exactly as before.

- **`testing` — a time budget and a bulk snapshot refresh.** Two things a suite
  built on this module had to hand-roll.

  `dybatpho::assert_duration_under` states the budget a command has to stay
  inside, so a path that turns quadratic fails the suite instead of being
  reported by a user:

  ```sh
  dybatpho::assert_duration_under 200 -- ./mytool completions bash
  ```

  A budget measured on a loaded machine is a flaky test, so
  `DYBATPHO_TEST_DURATION_RUNS` repeats the command and judges the fastest run:
  the fastest run is the one that measured the code rather than the scheduler.
  A command that exits non-zero fails with its own output, because a crash is
  not a fast run. `dybatpho::benchmark` measures without asserting, reporting
  the fastest, median and slowest of N runs — the median, since one descheduled
  run drags a mean and leaves a median where it was.

  Snapshots already had `DYBATPHO_TEST_UPDATE_SNAPSHOTS`; they now also read the
  unprefixed `UPDATE_SNAPSHOTS`, which is what fits in front of a test runner
  when an intended output change has to be absorbed across the whole suite:

  ```sh
  UPDATE_SNAPSHOTS=1 bats test/
  ```

- **Boxed output and tables stopped spawning a `python3` per line.** Measuring
  the display width of a string — what aligns a table cell and sizes a box —
  ran a `python3` child *per measured string*. A twenty-row, four-column
  `dybatpho::table_box` paid eighty of them and took 3.5 seconds; fifty boxed
  `dybatpho::success` lines took 3.8.

  Width is now answered from a per-character cache that `python3` fills in one
  batched call for the characters it has not seen yet, and pure ASCII — nearly
  every log line and table cell — never consults it at all. `__dybatpho_log_box`
  and the table measuring pass warm that cache in the calling shell first,
  because the measuring itself happens inside `$(...)` and a subshell cannot
  hand back what it learned. Line wrapping is pure Bash for the same reason, and
  is measured in columns rather than characters, so a CJK or emoji line breaks
  where it actually reaches the edge.

  The rendered output is unchanged — the widths are still the ones
  `unicodedata` gives — and `python3` remains optional, with an unknown
  character counting as one column exactly as the old fallback did. The same
  table now takes 0.8 seconds and the same fifty boxes 1.7.

- **CI now runs the whole suite on macOS, and a new job runs it on BusyBox.**
  The portable job ran three of thirty-seven files, so everything that touches
  `stat`, `sed` or `find` went unchecked on a BSD userland. `AGENT.md` claims
  BusyBox portability in two places and nothing had ever run there: the Alpine
  image the repository ships installs GNU `coreutils`, so even building it
  would have tested GNU tools on musl rather than BusyBox.

  The BusyBox job installs no `coreutils` and fails if `date` turns out to be
  GNU, so it cannot quietly stop testing what it claims. It does install
  `tzdata`, which is not optional: without it every named timezone resolves to
  UTC and the date and i18n helpers return a wrong answer instead of failing.
  It also runs as an unprivileged user, because several tests assert that a
  write is refused and root is refused nothing.

- **`dybatpho::retry` now backs off the way the HTTP retries already did.**
  The library answered the same question two ways: `network.sh` grew its delay
  exponentially, capped it at `DYBATPHO_CURL_RETRY_MAX_DELAY` and could add
  jitter, while the generic helper — the one a script calls directly — grew
  `2, 4, 6, 8, …` linearly, with no upper bound and no jitter.

  It now takes `DYBATPHO_RETRY_BASE_DELAY` (2), `DYBATPHO_RETRY_MAX_DELAY` (30)
  and `DYBATPHO_RETRY_JITTER` (off), and the delays run `2, 4, 8, 16, 30, 30, …`.
  Jitter is worth turning on when several machines retry the same failing
  dependency: without it they all come back at the same instant, which is the
  load that kept it down. The first two delays are unchanged, so a script that
  retried twice waits exactly as long as before.

- **A snapshot switch set to `0` now means off.** Both snapshot switches read
  `1`, `true`, `yes` and `on` as on and everything else as off. Previously the
  value went through `dybatpho::is true`, which reads `0` as true because it
  speaks in exit codes — so `DYBATPHO_TEST_UPDATE_SNAPSHOTS=0` rewrote every
  baseline it touched, and a suite whose snapshots are all rewritten asserts
  nothing.

### Fixed

- **A bare date parsed on macOS kept the current time of day.** BSD `date -j -f`
  fills every field the format leaves out from the current time, so
  `dybatpho::date_month_start 2024-02-17 '%F %T'` answered `2024-02-01 08:46:02`
  rather than midnight, and `date_add_days` and every other helper built on the
  parser drifted the same way. A date without a time now parses as midnight on
  every `date` flavour.
- **`dybatpho::text_strip_ansi` stripped nothing on macOS.** Under a UTF-8
  locale BSD `sed` rejects the escape-sequence pattern as an invalid character
  range, so the helper printed empty lines — and `dybatpho::assert_snapshot`,
  which strips colours through it, recorded empty snapshots. The match now runs
  in the C locale, where the ranges are the byte ranges they were meant to be.
- **`dybatpho::ai_redact` let IP addresses and long numbers through on macOS.**
  Their patterns relied on `\b`, a GNU `sed` extension that BSD `sed` does not
  understand, so only email addresses were masked. The word boundaries are now
  spelled out, and back-to-back matches such as `1.2.3.4 5.6.7.8` are both
  masked.
- **`dybatpho::run_with_timeout` reported a timeout as 143 on BusyBox.** BusyBox
  `timeout` accepts `-k` but exits 143 rather than 124 when the limit elapses,
  so a caller checking for 124 took the timeout for a failure. Only a coreutils
  `timeout` (GNU or uutils) is used now; anything else goes through the Bash
  watchdog, which reports 124.
- **Boxed log messages came out too wide in the C locale.** Outside a UTF-8
  locale Bash indexes a string by byte, so a glyph such as `✅` was measured as
  three one-column characters and `dybatpho::success`, `dybatpho::progress` and
  the tables drew their border past the text. Multi-byte characters are now
  assembled from their bytes before they are measured.
- **An HTTP error lost its body and its status.** `dybatpho::curl_do` passed
  `-f` to `curl`, which discards the response body on a 4xx or 5xx — it does not
  even create the `-o` file. The part of the answer that says *why* a request was
  refused was gone before the library saw it, and every `forge_*` failure could
  report was `HTTP 422`. A bad field, an expired token, a rate limit and a
  repository that does not exist all looked the same.

  The same flag also cost the status: because `-f` makes `curl` exit non-zero for
  an HTTP error, the captured `%{http_code}` was thrown away and replaced with
  `000`, so `curl_do` returned 1 — its "unknown" branch — for a 422 rather than
  the documented 4.

  `-f` is gone. `curl` now exits non-zero only when no response arrived at all,
  which is what a transport failure is, and the status decides the result.

- **`forge_*` failures now quote the forge.** `dybatpho::forge_error` reads the
  message out of the response — `message`, `error` or GitHub's field-level
  `errors[]` — and every failure path reports it alongside the status. A body
  that is missing, empty or not JSON falls back to the status, and a non-JSON
  body is quoted in part rather than dropped.
- **Two processes could hold the same lock.** `dybatpho::lock_acquire` claimed
  the lock with `mkdir` and wrote the holder's pid afterwards. Between those two
  steps the lock existed with nobody in it, and a second process arriving in
  that window read the missing pid as "nobody holds this", removed the lock and
  took it. Both then proceeded believing they held it, and nothing ever told
  either of them otherwise. The window was entered by every single acquire, and
  contention — the only time a lock matters — is exactly when several processes
  are inside it at once.

  The claim is now a single `ln -s` whose target carries `pid:host:acquired_at`.
  `symlink()` is atomic and fails when the name already exists, so taking the
  lock and saying who took it are one operation and the gap does not exist.

  A lock written in the previous directory form is still read, so a lock taken
  by an older copy of the library is not mistaken for a free one.

- **An interrupted `dybatpho::with_lock` left its lock behind.** The release ran
  only on the path where the command returned normally. It now installs a
  release handler for `HUP`, `INT` and `TERM` while the command runs, and
  restores the previous handlers afterwards so repeated calls do not accumulate
  them. A shell that inherits a signal as ignored — which is how Bats runs, and
  how some callers run — still cannot install a handler for that signal; that is
  Bash, not something the module can change.
- **`config` could not read a YAML file at all.** The loader asked `yq` for
  `if type != "!!map" then error(...) else ... end`, which is `jq` syntax; no
  release of the Go `yq` has ever been able to parse it, so every
  `dybatpho::config_load` of a `.yaml` or `.yml` file died with
  `Invalid YAML configuration` regardless of the file's contents. The tests
  stubbed `yq`, and a stub answers whatever the test wants, so the expression
  was never once handed to the program that had to run it.

  The root check is now its own `yq` call that reads the document's tag, and
  the entry query is a plain `to_entries`. Reading the tag first also fixes a
  quieter case: `to_entries` on a sequence succeeds and yields the indices, so
  a YAML file whose root was a list would have loaded under the keys `0`, `1`,
  … instead of being rejected. The tests for both paths now drive the real
  `yq`, and skip when it is not installed rather than substituting a stub for
  it.

  `dybatpho::doctor` now reports `config`'s `yq` as `yq>=4`, the way it already
  did for `json`. Reading a document's tag and parsing TOML both need the Go
  `yq` v4, so a host carrying the Python `yq` or a pre-v4 build was told it had
  what it needed and then failed at the first call.

- **`ai` under `DRY_RUN` aborted on its first call on a fresh machine.** The
  counter file moved to a 0700 directory under the XDG state home, but that
  directory was created through `dybatpho::ensure_dir`, which only *prints* the
  `mkdir` in a dry run. The first `dybatpho::ai_ask` then failed writing its
  counters. The directory is bookkeeping, not an effect the caller asked for,
  so it is now created even in a dry run.

- **`dybatpho::agent_mcp` recorded the wrong command for the root tool with
  `yq` 4.52.** Its `x-dybatpho-command` came out as
  `["/usr/bin/mytool",["mytool"],"description"]` instead of
  `["/usr/bin/mytool"]`, because that `yq` applies `.path[1:]` to the enclosing
  object. The filter now reads `.path | .[1:]`, which both backends agree on.

- **`dybatpho::git_changed_files` ordered its output by the caller's locale.**
  Under a UTF-8 locale on macOS `notes.txt` came before `README.md`; under `C`
  it came after. It now sorts byte-wise, so the order is the same everywhere.

- **Passing the wrong variable name to an array helper did nothing, quietly.**
  A helper that writes into a variable the caller names binds it with
  `local -n`, and that has a failure mode with no error in it: when the name
  collides with one of the helper's own locals, the nameref resolves to *that*
  local, and every write lands where the caller will never look. Bash warns
  about the narrow case where the name collides with the nameref itself —
  `circular name reference`, after which the writes are dropped — and says
  nothing at all about the wider case. So this returned successfully and sorted
  nothing:

  ```sh
  __sort_values=(c a b)
  dybatpho::array_sort __sort_values # was: exit 0, still c a b
  ```

  The library now reserves a namespace. Every local in a function that takes a
  variable name is called `__dybatpho_...`, and the new `dybatpho::expect_ref`
  refuses a caller-supplied name in that namespace — and any name that is not a
  shell identifier — before anything is bound. A collision is now either
  impossible or a loud error naming the function and saying to rename the
  variable. It is applied across the `array` helpers, `dybatpho::create_temp`,
  the `secret` readers and writers, `dybatpho::ai_conversation_new`, and the
  `testing` fixtures, which replaces the identifier checks those already did.

- **`dybatpho::split` matched its delimiter as a glob pattern.** The function
  documents an *exact* delimiter, but it reached the separator through
  `${1//$2/…}` with `$2` unquoted, which is pattern position. A delimiter
  holding `*`, `?` or `[` was therefore matched as a wildcard and the result was
  silently wrong rather than an error:

  ```sh
  dybatpho::split "a*b*c" "*"   # was: one empty line.   now: a, b, c
  dybatpho::split "a[x]b" "[x]" # was: "a[" and "]b".    now: a, b
  ```

  Splitting now walks the string with `${rest%%"${delimiter}"*}`, so the
  delimiter is always literal. Two things follow from the rewrite. Empty fields
  survive, including the trailing ones the old `read`-based version dropped, so
  `n` delimiters give `n + 1` fields and `a,b,,` splits into four. And the
  function no longer leaks a global named `arr` into the caller's shell, which
  it did on every call.

- **Log messages no longer lose their backslashes.** `__dybatpho_log` rendered
  through `echo -e`, which interprets escapes, so any message carrying a
  backslash was quietly corrupted — a Windows path, a regular expression, a
  `sed` script. `dybatpho::info 'C:\new\table'` printed `C:` followed by a
  newline and a tab. Rendering goes through `printf '%s'` now, and
  `dybatpho::debug_command` carries a real newline instead of the `\n` it used
  to rely on `echo -e` expanding.

- **`dybatpho::array_unique` returned its result in Bash's hash order.** It
  collected values as the keys of an associative array, so deduplicating
  `1 2 3 4 5` gave back `5 4 3 2 1`, and the order changed with the contents.
  It keeps the first occurrence of each value in place now, which is what
  `dybatpho::array_union` already did.

- **A logging test read the real clock on a BusyBox host.** It asserted the
  fallback branch of `__dybatpho_log_timestamp` while stating that neither
  busybox nor GNU `date` was available — which is false on Alpine, where the
  busybox branch correctly wins and the stub was never consulted. It now skips
  where the branch it covers cannot run.

- **`date` was broken end to end on BusyBox.** The module asked `date --version`
  and treated everything that said no as BSD. BusyBox is neither: it has no
  `-j -f` for parsing, and `-r` means "read the time off this file" rather than
  "this is a timestamp", so `date_format` reported `can't stat '1709210096'`
  and every helper built on it failed. Detection is now three-way, by asking
  for the one flag only BusyBox accepts, and `dybatpho::date_add` — which
  `date_add_days` and the new unit helpers all go through — reuses
  `date_format` instead of spelling the platform difference a second time.

- **`archive` could not extract a zip with `--strip-components` outside GNU.**
  It listed entries with `find -printf '%P'`, which neither BusyBox nor BSD
  has. The prefix is stripped in the loop instead.

- **`dybatpho::verify_checksum` needed a tool macOS does not ship.** It called
  `sha256sum` by name and died when it was absent, while `file_hash` next door
  already knew to try `shasum`, `md5` and `openssl` in turn. It now goes
  through `file_hash`, which removes the duplicate as well as the gap.

- **A test fixture used `touch` flags no BusyBox has.** `test/file.bats` shifted
  a file into the future with GNU `-d '+1 hour'` or BSD `-A`; it now uses
  `-t CCYYMMDDhhmm`, which all three accept.

- **`example/math_ops.sh` was not executable.** Every other example is, and a
  commit had just set the bit across all of them, so this one drifted straight
  back — nothing runs an example by path, so nothing noticed.
  `test/conventions.bats` now checks the mode recorded in the index: everything
  under `example/` and `scripts/` is run and must be executable, everything
  under `src/` and `init.sh` is sourced and must not be.

### Security

- **Credentials no longer reach `curl` as command-line arguments.** A process's
  arguments are readable by every account on the host through
  `/proc/<pid>/cmdline` — that is what `ps auxww` prints — so
  `--header "Authorization: Bearer ..."` published the token for as long as the
  request ran. `forge` did that on every API call, and `ai` did it with the
  provider API key, on the buffered path and the streaming one.

  `dybatpho::curl_do` now takes that material out of band. Headers listed in
  `DYBATPHO_CURL_SECRET_HEADERS` go into a config file that `curl` reads with
  `--config`, created under `umask 077` and removed when the request is over; a
  body in `DYBATPHO_CURL_SECRET_DATA` goes to `curl` on standard input. Both are
  declared `local` by the caller, so they are visible to `curl_do` through
  Bash's dynamic scoping and gone again when it returns. Request bodies moved
  too: a prompt is not public either.

  `dybatpho::mock_http_payloads` is the matching test-side accessor, because a
  test still has to be able to say "the token was sent" about something that is
  deliberately no longer in `dybatpho::mock_calls curl`.

- **The `ai` counter file left a symlink attack open in `/tmp`.** It defaulted to
  `${TMPDIR:-/tmp}/dybatpho_ai_state_$$`. The name is entirely predictable — the
  only variable is the pid, which `ps` publishes and which comes from a small
  space — and the counters are written with a plain `>`, which follows a
  symbolic link. In a world-writable `/tmp` that is an arbitrary-file-overwrite
  primitive: another account pre-creates that name as a link to a file of yours,
  and the next run truncates it.

  The default moved to a `0700` directory under the XDG state home, where no
  other account can plant anything, and the module now refuses to read or write
  the counter file when it is a symbolic link, wherever it has been pointed.

- **Cache entries were world-readable.** `dybatpho::cache_set` wrote through
  `dybatpho::file_write_atomic` under the caller's umask, so on a normal
  `umask 022` host a new entry landed `0644` in a `0755` directory. An entry
  holds whatever the caller found expensive to obtain — an API response, a
  query result — which is not public, and the `ai` module caches provider
  responses there. Entries are now written `0600` inside a `0700` directory,
  the same treatment `dybatpho::secret_write_file` already gave a secret.

## [4.0.0] - 2026-09-23

### Added

- **`dybatpho::forge_release_create` can create a draft.** A fourth argument
  sets `draft` on GitHub. GitLab has no draft release, so asking for one there
  is an error rather than a release published by surprise.

- **`network` — the primitives a script needs before it makes a request.** The
  module could fetch a URL but not read one, and everything around that was
  left to the caller: picking a host out of configuration, deciding whether a
  string is an address, whether an address is inside an allowed network, and
  whether a service is listening yet. Each of those gets written inline as a
  regex that nearly works — the kind that accepts `192.0.2.256`, or reads
  `127.0.0.010` as a different host than the resolver does.

  `dybatpho::url_parse` splits a URL into `DYBATPHO_URL`, the way
  `dybatpho::curl_parse_response` leaves a response in `DYBATPHO_HTTP_*`, and
  `dybatpho::url_part` reads one component with an optional default:

  ```sh
  dybatpho::url_parse "postgres://app:secret@db.internal:5432/orders"
  host="${DYBATPHO_URL[host]}"
  port="$(dybatpho::url_part port 5432)"
  ```

  Every component is always present, so one the URL omits reads as empty rather
  than unset. The credentials are taken at the *last* `@`, since a password may
  contain one, and a bracketed IPv6 literal keeps its colons out of the port.
  Components come back as written: decoding percent-escapes here would erase the
  difference between a separator and a character that only looks like one.

  New with it: `dybatpho::is_ipv4`, `dybatpho::is_ipv6`,
  `dybatpho::ip_version`, `dybatpho::is_cidr`, `dybatpho::cidr_netmask`, and
  `dybatpho::cidr_contains`, which handles both versions and compares the prefix
  bit for bit, including one that ends inside an IPv6 group.

  Two refusals are deliberate. An IPv4 octet with a leading zero is rejected,
  because `inet_aton` reads `010` as octal, so the address names one host to the
  resolver and another to a reader. And an address is never inside a block of
  the other version, so `::ffff:10.0.0.1` cannot be used to walk past a check on
  `10.0.0.0/8`.

  `dybatpho::port_open` and `dybatpho::wait_port` answer whether a service is up
  yet, through Bash's own `/dev/tcp`, so nothing has to be installed. The wait
  gives no single attempt more time than its budget has left, so the call keeps
  to that budget rather than overrunning it by one connection attempt. `timeout`
  joins the module's optional dependencies: without it the probe still works and
  waits as long as the system's own TCP timeout.

- **Version constraints: a dependency check that asks how old the tool is.**
  Until now a dependency was either installed or not, which is the wrong
  question for a tool whose name is shared by an unrelated program. The YAML
  helpers call `yq eval`, the Go `yq`; the Python `yq` and the Go one before v4
  take a different expression syntax, so a presence check passed on a host where
  every YAML call then failed.

  `dybatpho::require` now takes a version range after the command name, written
  the way `dybatpho::semver_satisfies` already documents it:

  ```sh
  dybatpho::load semver
  dybatpho::require jq '>=1.6'
  dybatpho::require yq '^4' 3 # 3 is the exit code, as before
  ```

  A range is recognised only by its leading `>`, `<`, `=`, `^`, or `~`, so the
  older two-argument form still names an exit code and `require jq 3` keeps
  meaning what it always did. Ranges need the optional `semver` module, and
  `require` stops with a message naming it rather than letting a requirement
  pass unchecked — a check that is silently not enforced is worse than one
  nobody wrote.

  `dybatpho::doctor` reads the same syntax in its dependency maps. A dependency
  is now reported as `ok`, `missing`, `outdated`, or `unknown`, with the version
  it found, and the report fails on a required dependency that is outdated just
  as it does on one that is absent. It does not fail on `unknown`: a probe that
  could not read a version has not shown that anything is wrong. Only a
  dependency that names a range is ever executed, so the report stays a report.

  The first such constraint ships with it: `json` now requires `yq>=4`.

  New: `dybatpho::command_version`, which reports the version a command states
  about itself, and `dybatpho::semver_coerce`, which turns that answer into the
  complete SemVer the range matcher needs — `tar` says `1.35`, `unzip` says
  `6.00`, and `yq` buries `v4.53.3` in a sentence.

  `semver_coerce` keeps a trailing `-rc1` as a pre-release but drops a build
  marker such as the `-modified` a distribution appends to its patched `grep`.
  Read as a pre-release, that version ranks *below* the plain release, and
  `>=3.12` would have rejected the very grep that satisfies it.
- **`forge` module — the library can finally publish what it builds.**
  `git.sh` reads the repository on disk and `release.sh` builds, checksums and
  signs artifacts, and then nothing happened: every project using dybatpho wrote
  the same `curl` against the GitHub or GitLab API by hand. This module is that
  code, once.

  The forge is detected from the Git remote, so the same script runs against
  github.com, GitHub Enterprise, gitlab.com and a self-hosted GitLab.
  `dybatpho::forge_host`, `forge_kind`, `forge_repo` and `forge_api` answer where
  the repository lives; `DYBATPHO_FORGE`, `DYBATPHO_FORGE_API` and
  `DYBATPHO_FORGE_REPO` override any of it when a mirror or an unrevealing host
  name defeats detection.

  `dybatpho::forge_request` is the authenticated client underneath: a path is
  relative to the project, so callers write `issues` rather than repeating the
  API base, the encoded project path and the auth header on every call. The
  differences between the forges stay behind it — `repos/owner/name` against a
  URL-encoded project path, `Authorization: Bearer` against `PRIVATE-TOKEN`,
  `body` against `description`.

  For issues, `dybatpho::forge_issue_report` is the one worth knowing:
  it opens an issue the first time and comments on it every time after, and
  prints `{"action":"created"|"commented","number":...,"url":...}` so a pipeline
  can branch on which happened. A nightly job that reports a failure now leaves
  one issue behind instead of one per run. `forge_issue_find`, `forge_issue_create`,
  `forge_issue_comment` and `forge_issue_url` are the pieces it is built from.
  Title matching is exact, so `Build failing` never adopts `Build failing on macOS`.

  For releases, `dybatpho::forge_release_create`, `forge_release_find` and
  `forge_release_upload` finish what `release.sh` starts. The two forges differ
  most here and the module absorbs it: GitHub stores an asset itself, on a
  separate upload host, while GitLab stores nothing on a release — the file goes
  to the project's generic package registry and the release gains a link to it.
  The call a script makes is the same either way.

  Tokens come from `DYBATPHO_FORGE_TOKEN`, or `GITHUB_TOKEN`/`GH_TOKEN` and
  `GITLAB_TOKEN`/`CI_JOB_TOKEN` per forge, and are registered with `secret.sh`.
  That registration cannot survive `token="$(dybatpho::forge_token)"`, because a
  subshell takes its registrations with it when it exits; the documentation says
  so plainly rather than implying a guarantee Bash cannot give, and a script that
  holds the token should register it once in its own shell.

- **`os` — the host facts every module was detecting for itself.** The module
  now answers what a script actually needs to know about the machine it runs
  on, so that a worker pool, a log banner and a lock file stop each carrying
  their own probe. New: `dybatpho::hostname` and `dybatpho::user`,
  `dybatpho::is_root`, `dybatpho::cpu_count`, `dybatpho::terminal_width`,
  `dybatpho::terminal_height`, `dybatpho::is_tty`, `dybatpho::os_release`,
  `dybatpho::distro`, `dybatpho::distro_version`, `dybatpho::kernel_version`,
  `dybatpho::is_windows`, `dybatpho::is_container`, `dybatpho::is_wsl`, and
  `dybatpho::is_ci`.

  Each one reports a failure rather than inventing an answer: `cpu_count` fails
  when no probe is installed instead of guessing a number, and
  `distro_version` fails on a rolling release that publishes none, so the
  caller decides what to do about it. `DYBATPHO_HOSTNAME` overrides the
  detected host name and `DYBATPHO_OS_RELEASE` points the reader at another
  `os-release` file, which is what makes both testable.

  ```sh
  jobs="$(dybatpho::cpu_count || printf '4')"
  dybatpho::is_tty stdout && width="$(dybatpho::terminal_width)"
  case "$(dybatpho::distro)" in
    ubuntu | debian) dybatpho::info "Using apt on $(dybatpho::hostname)" ;;
  esac
  dybatpho::is_ci && export DYBATPHO_FORCE=true
- **`math` module — decimal arithmetic that is exact, and needs nothing but
  Bash.** `$(( ))` is integer-only and 64 bits wide, so any script that divides,
  averages, or adds two prices had to reach for `bc`, which a minimal container
  does not have, or for `awk`, which computes in binary floating point where
  `0.1 + 0.2` is not `0.3` and a money total drifts by a cent.

  The module does the arithmetic itself, on digit strings, the way it is done on
  paper: `dybatpho::math_add`, `dybatpho::math_sub`, `dybatpho::math_mul`,
  `dybatpho::math_div`, `dybatpho::math_mod` and `dybatpho::math_pow`. Values
  are exact decimals of any length, so `dybatpho::math_mul 99999999999
  99999999999` answers with all twenty-two digits instead of wrapping.

  Comparison reads the numbers rather than the strings, where `1.10` sorts below
  `1.9`: `dybatpho::math_compare` prints `-1`, `0` or `1`, and
  `dybatpho::math_gt`, `dybatpho::math_lt` and `dybatpho::math_eq` answer
  through the exit code.

  Rounding states its rule instead of inheriting one:
  `dybatpho::math_round` rounds halves away from zero at a width you choose,
  with `dybatpho::math_floor`, `dybatpho::math_ceil` and `dybatpho::math_trunc`
  beside it. `printf '%.2f'` rounds binary floats to even and follows
  `LC_NUMERIC`, so it answers `2.66` on one machine and `2,67` on another;
  `dybatpho::math_round 2.665 2` is `2.67` everywhere.

  Aggregates take their values from arguments or from a pipe:
  `dybatpho::math_sum`, `dybatpho::math_avg`, `dybatpho::math_min` and
  `dybatpho::math_max`. `dybatpho::math_clamp` holds a value inside bounds and
  `dybatpho::math_percent` turns a part and a whole into a share.

  For whole numbers there are `dybatpho::math_gcd`, `dybatpho::math_lcm`, and
  `dybatpho::math_random`, which draws uniformly from an inclusive range rather
  than with the bias `$((RANDOM % n))` carries. `dybatpho::math_is_number` and
  `dybatpho::math_is_integer` check input before any of it runs; everything else
  stops the script with the value and the function named.

  Division and averaging are the only operations that round, at
  `DYBATPHO_MATH_SCALE` fraction digits by default. Formatting for a reader —
  grouping, a fixed number of decimals, a locale's decimal mark — stays with
  `i18n`.

  ```sh
  . dybatpho/init.sh --modules math
  dybatpho::math_add 0.1 0.2  # 0.3
  dybatpho::math_div 2 3 5    # 0.66667
  dybatpho::math_avg 10 20 25 # 18.3333333333
  ```

- **`scripts/lint.sh` — the repository now checks its own shape.** One command
  runs ShellCheck and `bash -n` over every tracked script, validates
  `CHANGELOG.md` against the Keep a Changelog format it claims to follow,
  fails when the generated `doc/*.md` has drifted from its sources, and
  rebuilds the single-file bundle so the smoke test inside `scripts/bundle.sh`
  finally runs somewhere. `--stage` narrows it to one check and `--list` prints
  the scripts it found.

  Scripts are discovered through `git ls-files`, admitted by a `.sh` suffix or
  a Bash shebang, so nothing has to be registered by hand and the vendored Bats
  submodules under `test/lib/` are never scanned. `.bats` files are excluded
  from ShellCheck deliberately: `@test "name" {` is Bats syntax, not Bash.

  A `lint` job in CI runs it, together with a `gitleaks` scan of the history.
  `mise run lint` and a `pre-commit` hook run it locally.

- **`scripts/doc.sh --check`.** Generates into a temporary directory and
  compares instead of writing, so stale generated documentation fails a pull
  request. Previously the only signal was a dirty tree at commit time, which no
  reviewer ever saw.

- **`test/examples.bats` — the examples are executed, not just shipped.**
  `AGENT.md` has always required every example to run non-interactively,
  offline, and without touching the repository. Nothing enforced it. Each
  example now gets a test that runs it and compares the working tree before and
  after, and a first test fails when an example has no test at all, so a new
  example cannot be added and silently never run.

- **`i18n` module** — speak the reader's language, and write values the way they
  write them. `dybatpho::i18n_init` resolves the locale and loads its catalogs,
  `dybatpho::i18n_t` translates a key and fills in its `{name}` placeholders,
  `dybatpho::i18n_tc` does the same for a message qualified by a context, and
  `dybatpho::i18n_tn` picks the plural form a count actually takes in the target
  language, which is the part a hand-written `count == 1` check cannot get
  right: Russian and Polish disagree at twenty one, Arabic has six forms, and
  Vietnamese has one. `dybatpho::i18n_plural_form` exposes that rule on its own.
  A lookup walks a fallback chain — `zh_Hant_TW`, `zh_Hant`, `zh_TW`, `zh`, then
  the fallback locale — so a partly translated locale is backed by a more
  general one, and an untranslated key renders as the key rather than stopping
  the script unless `DYBATPHO_I18N_STRICT` says otherwise.

  Catalogs are read from a dependency-free `key = value` format and from GNU
  gettext `.po` files, found through `DYBATPHO_I18N_PATH` and the XDG and system
  directories in either the gettext or a flat layout. Fuzzy, obsolete, and
  untranslated `.po` entries are not treated as translations, and the
  `Plural-Forms` expression in a header is read for its form count but never
  evaluated, because a catalog is a file that arrives from a translation
  platform. `dybatpho::i18n_extract` writes a template covering every key a
  source tree refers to and names the call sites whose key it could not read,
  and `dybatpho::i18n_lint` reports what a translation is missing — including a
  `{placeholder}` that was renamed or dropped, which nothing else catches until
  the message is rendered.

  `dybatpho::i18n_number`, `i18n_number_plain`, `i18n_percent`,
  `i18n_currency`, and `i18n_bytes` format values for a locale, and
  `i18n_date`, `i18n_time`, `i18n_datetime`, `i18n_date_pattern`,
  `i18n_month_name`, `i18n_weekday_name`, `i18n_relative`, and `i18n_duration`
  do the same for time. Around twenty locales ship built in, and
  `dybatpho::i18n_register_number`, `i18n_register_currency`,
  `i18n_register_currency_layout`, `i18n_register_names`, `i18n_register_date`,
  and `i18n_register_rtl` add more from a caller's own script. Two details are
  deliberate: month names come from the module rather than from `LC_TIME`,
  because `date` answers in English when the requested locale was never
  generated on the machine, and fractional values are built from digit strings
  rather than through `printf '%f'`, which follows `LC_NUMERIC` and would print
  a different separator per machine — so the same script produces the same
  output in a container and on a workstation, and integers wider than a machine
  word are formatted exactly. `dybatpho::i18n_is_rtl`, `i18n_direction`,
  `i18n_bidi_mark`, `i18n_bidi_isolate`, and `i18n_bidi_strip` cover text that
  reads right to left.

  Setting `DYBATPHO_I18N_TRANSLATE_LIBRARY` also routes dybatpho's own output
  through the catalog, so that translating your strings does not leave half the
  screen in English. A diagnostic that carries no value is its own message id in
  the way gettext does — `"curl is not installed" = ...` translates every call
  site that emits it. Text that does carry one cannot work that way, because no
  catalog can list `Unrecognized option: --colr`, so those call sites name a
  stable key instead and `dybatpho::i18n_library_text` fills its placeholders:
  `cli.heading_usage`, `cli.heading_options`, `cli.heading_commands`,
  `cli.heading_arguments`, `cli.placeholder_options`, `cli.placeholder_command`,
  `cli.placeholder_args`, `cli.show_help`, `cli.more_info`, `cli.select`,
  `cli.select_multiple`, `cli.unrecognized_option`, `cli.invalid_command`,
  `cli.did_you_mean`, `cli.did_you_mean_one_of`, `cli.argument_required`,
  `cli.no_argument_allowed`, `cli.missing_required_option`,
  `cli.validation_error`, `cli.args_none`, `cli.args_range`,
  `cli.invalid_args_rule`, `cli.invalid_switch_alias`, `cli.invalid_var_name`,
  `cli.unsupported_shell`, `cli.deprecated_option`, `cli.deprecated_command`,
  and `logging.done`. `dybatpho::i18n_library_plural` covers the counted ones —
  `cli.args_exact`, `cli.args_min`, `cli.args_max` — so the target language
  picks between its plural forms rather than the English call site picking
  between `argument` and `arguments`. `dybatpho::success`, `dybatpho::progress` and
  `dybatpho::header` compose their text before boxing it, so they translate it
  themselves and the border is re-measured around the result.

  All of it is off by default: with `DYBATPHO_I18N_TRANSLATE_LIBRARY` unset,
  every message above is byte for byte what it was, and the hooks stay inert in
  a shell that never loaded the module.

  ```sh
  . dybatpho/init.sh --modules i18n
  DYBATPHO_I18N_PATH="${PWD}/locale" dybatpho::i18n_init vi_VN
  printf '%s\n' "$(dybatpho::i18n_tn deploy.files 1240)"
  printf '%s\n' "$(dybatpho::i18n_currency 1234.5 VND vi_VN)"
  dybatpho::i18n_lint --reference en vi_VN || exit 1
### Changed

- **`scripts/release.sh` publishes through `forge` instead of the `gh` CLI.**
  The release step works on GitHub, GitHub Enterprise and GitLab alike, and the
  script no longer needs `gh` installed — it needs a token, which it resolves
  and checks *before* any local step runs, so a missing one cannot be
  discovered after the tree is stamped, committed and tagged. Take one from an
  authenticated CLI with `GITHUB_TOKEN=$(gh auth token)` if that is easier than
  minting one.

  `--github` is now `--publish`, because the step is no longer GitHub-specific,
  and `__dybatpho_release_repo_url` is gone: `dybatpho::forge_host` and
  `forge_repo` already normalise every remote form, and that duplicated copy is
  where the broken changelog links came from.

- **`os` is a core module.** It is loaded with `string`, `logging`, `helpers`,
  `process`, `file` and `secret` rather than asked for by name, because the
  library itself now calls it unconditionally: `parallel` sizes its pool with
  `dybatpho::cpu_count`, `logging` measures its banners with
  `dybatpho::terminal_width` and stamps its JSON events with
  `dybatpho::hostname`, `lock` stamps the same name onto a lock directory,
  `pkg` decides on `sudo` with `dybatpho::is_root`, and `safety` asks
  `dybatpho::is_tty` whether it can prompt. Nothing breaks: `--modules os` is
  still accepted, and a script that never asked for the module now has it
  anyway. `dybatpho::module_list` and `dybatpho::doctor` report it among the
  core modules, and the `os` dependency edge is gone from `pkg` and `release`
  because core modules are implicit.

- **`dybatpho::lock_hostname` delegates to `dybatpho::hostname`.** It still
  prints the name a lock is stamped with, and now resolves it through the same
  chain as every other caller, which also adds the kernel's
  `/proc/sys/kernel/hostname` to the fallbacks it had.

- **Coverage runs use the whole runner.** `scripts/test.sh --coverage` spread
  the test files over chunks by slicing the count-ordered list, which put the
  heaviest files in one chunk: it held a third of the suite and decided the
  memory ceiling on its own, while the last chunk held a couple of small files
  and left most workers idle. Files are now dealt to the emptiest chunk in
  turn, which drops the biggest chunk from 417 tests to 179 without changing
  how many times kcov runs. kcov's peak turns out to track the tests in a chunk (~16 MiB each)
  rather than the worker count -- 2 and 4 workers over the same files peaked at
  2613 and 2615 MiB -- so CI now runs one worker per vCPU instead of two.

- **`.shellcheckrc` disables SC2004.** It contradicts the
  `require-variable-braces` rule the file enables: one asks for `${index}`
  everywhere, the other rejects it inside `$(( ))`. Braces everywhere is the
  more useful of the two.

- **BREAKING: `cli` gets its positional arguments right, and gains three
  options for shaping a command line.** The rest
  variable named by `dybatpho::opts::setup` used to be a string built by
  joining each argument with a space. That lost information no caller could
  recover: `tool "a b" c` and `tool "a b c"` produced the same value, every
  value carried a leading space, and a quote, glob character, or newline inside
  an argument could not survive at all. The count check was right while the
  values were wrong, so the failure was silent. It is now a Bash array:

  ```bash
  dybatpho::opts::setup "Copy files" FILES action:"_run"
  # _run reads "${FILES[@]}" and counts with "${#FILES[@]}"
  ```

  A POSIX shell would have to store positional *references* into the original
  `$@` and restore them with `eval "set -- $REST"`, because it has no arrays.
  dybatpho requires Bash 4.3, so it appends to a real array and skips the eval
  entirely.

  `dybatpho::opts::arg` follows from that. Declaring an argument used to shape
  only the usage line, the `Arguments` help section, and the derived `args:`
  rule, leaving its variable unset — `example/cli_ux.sh` declared `SERVICE` and
  then read `${DEPLOY_ARGS}`, which is exactly the confusion the declaration
  invites. Arguments now bind in declaration order, a `variadic:true` argument
  takes the remainder as an array, an omitted optional argument is the empty
  string, and `-` documents an argument without binding it:

  ```bash
  dybatpho::opts::arg "File to read" SOURCE
  dybatpho::opts::arg "Where to write it" TARGET required:false
  dybatpho::opts::arg "Anything else" EXTRA required:false variadic:true
  ```

  Three additions round it out:

  - `pattern:<glob>` restricts an option to a `case` glob without writing a
    validator function, reporting `Does not match the pattern (fast|slow):
    medium` under the key `cli.pattern_mismatch` and the error name
    `pattern:<glob>` for a custom `error:` handler. A pattern cannot be quoted
    on its way into the generated parser without `case` comparing it literally,
    so it is restricted to characters that cannot end a branch or start a
    substitution; anything else is rejected under `cli.invalid_pattern` when the
    parser is generated.
  - `dybatpho::opts::msg` puts free text in the help output, which is what a
    long option list needs to stay readable. It declares no switch, does not
    affect column alignment, and completion, schema, and man output ignore it.
  - `abbr:true` on `dybatpho::opts::setup` accepts any prefix that identifies a
    long switch uniquely, so `--vers` reaches `--version`. It is off by default,
    because enabling it means a newly added option can make a previously working
    abbreviation ambiguous. An exact match always wins, so declaring both
    `--log` and `--log-level` keeps `--log` usable; an ambiguous prefix fails
    under `cli.ambiguous_option` and reaches a custom `error:` handler as the
    error name `ambiguous` with the candidates in `$OPTARG`.

  Update any action that read the rest variable as a string: `${ARGS}` becomes
  `"${ARGS[@]}"` to iterate, or `"${ARGS[*]}"` for the old space-joined form
  minus the leading space. Bash cannot export an array, so `export:` no longer
  applies to it, and under `set -u` a scalar read of an empty rest array fails
  instead of yielding the empty string.

### Fixed

- **A failing test could vanish from the report instead of failing.**
  `dybatpho::cleanup_file_on_exit` took over the EXIT trap of the shell it ran
  in. Under Bats that trap is how a test result is reported, so any test that
  created a temporary file — directly, or through `parallel`, `forge`, `ai`,
  `file` and everything else that makes one — lost its failure: a passing test
  looked normal, because Bats re-arms its trap after the body, while a failing
  one disappeared and the run ended with `Executed N-1 instead of N tests`.
  Every intermittent "a worker died" this suite has shown traced back here, and
  the message sent every investigation after a crash that never happened.

  The trap is now left alone in the test shell, where Bats owns it and
  `dybatpho::create_temp` already writes into the directory Bats removes
  itself, and still installed in a subshell, where nothing of Bats' is at stake
  and the subshell's exit is the only chance to clean up what it registered.
  `test/process.bats` pins both halves.

- **`test/parallel.bats` asserted which of two concurrent jobs finished first.**
  The pool-width test expected `end a` on the third line of the trace, but with
  a width of two, `a` and `b` run at the same time and sleep for the same
  interval, so either can finish first — it failed about one run in ten. It now
  asserts the invariant it describes: the third line is an end, whichever job
  produced it.

- **`test/conventions.bats` made a committed document stale in place.** It
  appended a line to `doc/semver.md` to prove the documentation check inspects
  every source it is given, and restored it afterwards. The suite runs its
  files in parallel and `test/examples.bats` compares the working tree before
  and after every example, so whichever example overlapped that window failed.
  The check is now pointed at a copy in the test's own directory.

- **`dybatpho::is_ci` ignored `CI=false` on a runner that also names itself.**
  The variables were read as a flat list, so a false value only meant "skip to
  the next name". On GitHub Actions, which sets both `CI` and `GITHUB_ACTIONS`,
  `CI=false` fell through to `GITHUB_ACTIONS=true` and the script was still
  told it was on CI — leaving no way to turn the detection off, which is the
  one thing that variable is for.

  `CI` now decides whenever it holds a value, in either direction. The
  service-specific variables are consulted only when `CI` is unset or empty,
  which is the case they exist for: a service that names itself and never sets
  `CI`.

  The suite did not catch this because the existing test set `CI=false` and
  inherited everything else, so it only failed where a second marker happened
  to be present — a workstation passed, CI did not. The new test pins both
  variables instead of inheriting them.

- **`scripts/doc.sh` read its arguments as a string, and the documentation
  guard quietly stopped guarding.** `dybatpho::opts::setup` collects positional
  arguments into a Bash array, which the positional-argument rework made
  explicit. This script was not updated with it and still expanded the array as
  a scalar, which is wrong in both directions: with arguments, `"${DOC_ARGS}"`
  is element zero, so `scripts/doc.sh src/a.sh src/b.sh` documented only
  `src/a.sh`; with none, an empty array is unset, so `errexit` ended the source
  listing inside the process substitution that feeds the loop.

  The second case is the damaging one. The loop simply read nothing, so
  `scripts/doc.sh --check` compared no documents and reported that everything
  was up to date — which is what `scripts/lint.sh` and CI were relying on to
  catch documentation drift. It had been passing without checking anything.

  Both paths now read the array as an array, and generating or checking an
  empty set of sources fails loudly instead of reporting success, so this
  cannot go quiet again. `test/conventions.bats` covers both.

  No other script or example was affected: `scripts/test.sh` already read its
  array correctly, and every other caller declares a positional variable it
  never reads.

- **`scripts/release.sh` wrote broken changelog links.** Normalising an SSH
  remote prefixed `https://` and only then replaced the first `:` — which by
  that point belonged to the scheme, not to the `host:owner/repo` separator.
  Every link definition it generated came out as
  `https///github.com:owner/repo`, and v3.0.0 shipped with two of them. The
  substitution now runs before the scheme is added. `scripts/lint.sh` validates
  the shape of each link reference, so a dead link fails the build instead of
  being committed.

- **`example/network_ops.sh` made real HTTP requests.** It called
  `example.com`, `api.github.com` and `httpbin.org` on every run, against the
  rule in `AGENT.md` that an example must not need network access — so it
  failed on an offline machine and took a minute of retry backoff to do it. It
  now installs a `curl` stub on `PATH`; retry, header parsing, checksum
  verification and the circuit breaker are still the real code paths.

- **`mise run demo` pointed at a file that does not exist.** The task ran
  `doc/example.sh --help`; examples live in `example/`. It now runs
  `example/cli_basic.sh --help`.

- **A dead `case` branch in `cli.sh`.** `aliases:--help,-h` could never match,
  because `aliases:--help,*` and `aliases:*,-h` both precede it. Behaviour is
  unchanged; the branch is gone.

## [3.0.0] - 2026-09-22

### Added

- **`doctor` module — one report of what the environment is missing.**
  `dybatpho::doctor` prints the Bash version, the library version, the host
  platform, and every external command the loaded modules can call, each marked
  found or missing. A module only reaches for `yq`, `curl`, or `tar` when the
  caller reaches the function that needs it, so this turns a sequence of
  mid-script failures into one list to fix before the work starts. Missing
  **required** dependencies fail the report; missing **optional** ones are
  reported and succeed, because they only cost part of a module.

  `--modules "json,git"` checks a set the shell has not loaded yet, `--all`
  covers the registry, `--quiet` answers through the exit code alone for CI, and
  `--json` emits one object — built without `jq`, since a diagnostic that needs a
  tool the user may be missing is of no use.
  `dybatpho::doctor_requirements <module> [required|optional|all]` exposes the
  declarations, and `dybatpho::doctor_bash_supported` answers the version
  question on its own. A dependency written as `a|b` is satisfied by either, so
  `file` reports one row for `sha256sum|shasum|openssl`.

  ```sh
  . dybatpho/init.sh --modules doctor json archive
  dybatpho::doctor || dybatpho::die "Install the tools listed above first"
  ```

- **`dybatpho::version`** — the library now reports which copy is loaded, from
  `init.sh` alone and without loading a module. The version comes from the new
  `VERSION` file beside `init.sh`, with the commit the copy is at appended as
  SemVer build metadata — `2.0.0+af745ff`, and `+af745ff.dirty` when the working
  tree has uncommitted changes — so a report names the code that ran rather than
  the last release before it. Only the library's own checkout is consulted: a
  copy vendored inside another project reports its stamped version alone. A checkout with no `VERSION` file falls back to
  `git describe`, and a copy with neither answers `unknown` rather than empty. It
  drops a leading `v`, caches into `DYBATPHO_VERSION`, and honors that variable
  when it is already set.

- **`scripts/release.sh`** — cuts a release in one command. It refuses to start
  on a dirty tree or an existing tag, resolves the version from the commits
  through `dybatpho::release_next_version` (or from `--version` / `--bump`),
  stamps `VERSION`, promotes `## [Unreleased]` in `CHANGELOG.md` to
  `## [<version>] - <date>` with a fresh empty `Unreleased` above it, rewrites
  the comparison links, regenerates `doc/`, commits `chore(release): v<version>`
  and tags it annotated with the changelog entry, builds the all-modules bundle
  with a `SHA256SUMS` file beside it, pushes, and creates the GitHub release
  with that same entry as its notes. The notes are always the handwritten
  changelog, never a generated commit list, and an `Unreleased` section that
  marks a change **BREAKING** forces a major release even when no commit subject
  carried `!`. `--dry-run` performs every check and prints every command without
  writing anything, and `--no-push` / `--no-github` / `--no-bundle` / `--sign`
  cover the rest of the release policy.

  ```sh
  scripts/release.sh --dry-run
  scripts/release.sh --version 3.0.0 --sign
  ```

- **`scripts/bundle.sh`** — flattens a module selection into a single
  `dybatpho.bundle.sh` to vendor into another repository or bake into a
  container image. The selection is the same `--modules` used everywhere else
  and is resolved by running `init.sh` itself, so the bundled set cannot drift
  from what that selection loads. The generated file carries the bootstrap
  guards and the module sources verbatim, needs no `src/` directory beside it,
  reports the version it was generated from, and lists only what it carries as
  its registry. Inside a bundle, `dybatpho::load` succeeds for a carried module
  and fails for anything else with the command that regenerates the bundle with
  it. The generator refuses to overwrite an existing output without `--force` or
  `DYBATPHO_FORCE`, honors `DRY_RUN`, and verifies that what it wrote parses and
  can be sourced.

  ```sh
  scripts/bundle.sh --modules "logging git semver" --output dist/dybatpho.sh
- **Version ranges, ordering, and the last links of the release chain.**
  `dybatpho::semver_satisfies` answers whether a version fits a range written
  the way npm and Cargo write them: `^1.2` for anything compatible, `~1.2.3` for
  patch updates, plain comparisons such as `>=18`, partial versions and
  wildcards such as `1.2.x`, several comparators meaning all of them, and `||`
  meaning either. A pre-release only satisfies a range that names a pre-release
  of the same release, so `^1.0.0` does not quietly accept `2.0.0-alpha`.

  `dybatpho::semver_sort` and `dybatpho::semver_max` order versions by the
  specification rather than as strings, reading the list from arguments or
  standard input and preserving a leading `v`, so a list of tags stays usable.

  `dybatpho::git_is_ancestor` reports whether one commit is reachable from
  another, which is how a release script tells an already-released tag from one
  that is not on this branch.

  `dybatpho::release_commit_parse` breaks a commit into its type, scope,
  breaking flag, and description. `release_commit_type` reports a breaking
  change as its own kind, which loses the type; the parser reports both, and the
  bump and changelog helpers now derive their answers from it instead of each
  restating the convention.

  ```sh
  dybatpho::semver_satisfies "$(node --version | tr -d v)" ">=18" \
    || dybatpho::die "Node 18 or newer is required"
  ```

- **XDG directories and more filesystem helpers in the `file` module.**
  `dybatpho::xdg_config_dir`, `xdg_cache_dir`, `xdg_data_dir`, and
  `xdg_state_dir` return the directories the XDG Base Directory specification
  defines, optionally scoped to an application name. They honor the matching
  environment variable when it holds an absolute path and fall back to the
  specification's default otherwise — including when the variable holds a
  relative path, which the specification says to ignore. They build a path and
  create nothing, so they pair with `dybatpho::ensure_dir`, which prints the
  directory it made.

  Alongside them: `dybatpho::file_mtime` reports a modification time as a Unix
  timestamp, `dybatpho::dir_size` totals the regular files in a tree (excluding
  symlinks, so a target inside the tree cannot count twice),
  `dybatpho::file_is_binary` looks for a NUL byte in the first block so a text
  rewrite can be skipped rather than mangling the file, and
  `dybatpho::create_temp_dir` asks for a temporary directory by name instead of
  passing `/` as an extension to `dybatpho::create_temp`.

  ```sh
  state="$(dybatpho::ensure_dir "$(dybatpho::xdg_state_dir myapp)" 700)"
  printf '%s\n' "${run_id}" | dybatpho::file_write_atomic "${state}/last-run"
  ```
- **`cli` typo suggestions** — an unrecognized option or invalid command now
  names the closest thing the command accepts, compared by Levenshtein distance
  with leading dashes ignored, so `--colr` answers with
  `Did you mean '--color'?` and `depoy` with `Did you mean 'deploy'?`. Typing a
  prefix of a longer switch counts as an abbreviation and outranks every
  edit-distance match. `dybatpho::cli_levenshtein` and `dybatpho::cli_suggest`
  are exposed for CLIs that want to do their own matching.

  Making that work required the parser to notice a mistyped option at all:
  a command that declares at least one switch now rejects an unmatched `-x` or
  `--xy` instead of quietly collecting it as a positional argument. `--` is
  still how dashed values are passed through, and a command that declares no
  switches is a passthrough wrapper and keeps collecting them unchanged.

- **`cli` generated negation switches** — `negatable:true` on
  `dybatpho::opts::flag` generates a `--no-<name>` for every long switch and
  alias, instead of spelling the pair out as `--{no-}name`. Without an explicit
  `off:`, a negatable flag turns off to `false` rather than to the empty string,
  so `--no-color` lands on a value worth testing.

- **`cli` counting flags** — `count:true` records how often a flag appeared
  rather than a value, starting at `0`, so `-v`, `-vv`, and `-v -v` yield `1`,
  `2`, and `2`. `dybatpho::cli_verbosity_level` maps that count onto a log level
  and `dybatpho::cli_apply_verbosity` applies it to `LOG_LEVEL`, which is the
  `-vv`-raises-verbosity idiom in two lines of spec.

- **`cli` options bound to configuration keys** — `config:<key>` binds an option
  to a key loaded by `src/config.sh`, giving one precedence chain across the
  whole CLI: **flag > `env:` > `config:` > `init:`**. `cli` and `config` no
  longer have to be wired together by hand at every option; `cli` now depends on
  `config` so the binding works wherever `cli` is loaded. Configuration has to
  be loaded before `dybatpho::generate_from_spec`, because that is when an
  option's initial value is resolved; a missing key, or a CLI that never loaded
  configuration, falls through to `init:`.

- **`cli` documented positional arguments** — `dybatpho::opts::arg` declares a
  positional argument's name, description, and whether it is required or
  variadic. The values still land in the rest variable, but the usage line now
  shows real placeholders (`<SOURCE> [TARGET]...`), help gains an `Arguments`
  section, and the schema and man page describe them too. Declaring arguments
  also derives the `args:<rule>` count check, so the two cannot disagree; an
  explicit `args:` still wins.

- **`cli` completion cache** — `dybatpho::generate_completion` caches its output
  under `DYBATPHO_CLI_CACHE_DIR` (default
  `${XDG_CACHE_HOME:-$HOME/.cache}/dybatpho/cli`), so a shell startup that
  sources a generated completion does not walk the spec tree again. The key
  hashes the script declaring the spec, so editing it invalidates the entry on
  its own and there is nothing to clear by hand. `DYBATPHO_CLI_CACHE=false`
  regenerates every time.

- **`parallel` module** — run independent work a few jobs at a time.
  `dybatpho::parallel_map` runs one command over a list, passing each item as a
  single value so an item with spaces or shell syntax is not re-parsed;
  `dybatpho::parallel_run` runs different shell commands at once. Each job's
  output is captured while it runs and replayed afterwards in submission order,
  so a concurrent run reads like a serial one, and each job's exit code is kept
  separately and readable through `parallel_status`, `parallel_count`, and
  `parallel_failed`.

  `DYBATPHO_PARALLEL_JOBS` sets the default width, `0` means one job per
  processor, and `DYBATPHO_PARALLEL_FAILFAST` stops further jobs once one fails,
  reporting the ones that never started as skipped rather than failed. The pool
  gives each job its own process group, so an interrupted run ends the jobs
  together with anything they started.

  ```sh
  . dybatpho/init.sh --modules parallel
  dybatpho::parallel_map 8 check_host "${hosts[@]}" || true
  for ((i = 0; i < $(dybatpho::parallel_count); i++)); do
    [[ "$(dybatpho::parallel_status "${i}")" == 0 ]] || dybatpho::warn "${hosts[i]} is down"
  done
  ```

- **`release` module** — cut a release from the commits since the last tag.
  `dybatpho::release_next_version` derives the version from
  [Conventional Commits](https://www.conventionalcommits.org) (a breaking change
  moves the major, `feat` the minor, `fix` and `perf` the patch, anything else
  moves nothing and is reported as nothing to release);
  `release_changelog` writes the matching entry, grouped by what changed;
  `release_artifact_name` and `release_package` produce one artifact per platform
  under the `name_version_os_arch` layout Go release tooling established, a zip
  for Windows and a tarball elsewhere; `release_checksums` writes a `SHA256SUMS`
  file that `sha256sum -c` verifies; and `release_sign` signs it with `gpg`, or
  with any other tool through `DYBATPHO_RELEASE_SIGN_CMD`.

  The module produces files and never contacts a forge, so credentials for
  pushing a tag or creating a release stay with the caller.

  ```sh
  . dybatpho/init.sh --modules release
  version="$(dybatpho::release_next_version .)" || exit 0
  dybatpho::release_changelog . "$(dybatpho::git_latest_tag . 'v*')" HEAD "${version}"
  dybatpho::release_package ./dist/linux_amd64 ./release mytool "${version}" linux amd64
  dybatpho::release_sign "$(dybatpho::release_checksums ./release)"
  ```

- `dybatpho::git_latest_tag` returns the highest version tag in a repository,
  ordering tags as versions rather than as strings, so `v10.0.0` outranks
  `v9.0.0`.

- **`metrics` module** — measure a script and export the result to Prometheus.
  `dybatpho::metrics_time` wraps a command, records how long it took and whether
  it failed, and returns its exit code unchanged; `metrics_timer_start` and
  `metrics_timer_stop` cover a region rather than one command;
  `metrics_counter_inc`, `metrics_gauge_set`, and `metrics_observe_ms` record
  directly. `metrics_render` produces the Prometheus text exposition format and
  `metrics_write` saves it atomically, which is what the node exporter's textfile
  collector requires.

  Loading the module also turns on instrumentation the library was already in a
  position to record: retries and exhausted retries from `dybatpho::retry`,
  request duration and final status from `dybatpho::curl_do`, and logged messages
  by level. A script that does not load the module is unaffected.

  ```sh
  . dybatpho/init.sh --modules metrics
  dybatpho::metrics_time backup_duration_seconds target=db -- pg_dump -Fc mydb -f /backup/db.dump
  dybatpho::metrics_write /var/lib/node_exporter/textfile_collector/backup.prom
  ```
- **`ai` module.** Call a language model from a script the way you call any
  other command: prompt in, text on stdout, a documented exit code. One API
  covers four backends — the Claude Messages API, any OpenAI-compatible
  `/v1/chat/completions` endpoint, a local Ollama daemon, and an installed
  `claude`, `llm` or `ollama` client — so the choice of provider is
  configuration, not a rewrite.

  ```sh
  . dybatpho/init.sh --modules ai
  dybatpho::ai_ask "Summarize this deploy log in three bullets"
  ```

  Around the call it provides what a script actually needs: conversations kept
  in a file (`ai_conversation_new`, `ai_chat`), answers validated against a
  JSON schema (`ai_json`), token streaming (`ai_stream`), a tool-use loop that
  runs your shell functions (`ai_tool_register`, `ai_run`), response caching,
  and usage accounting. Secrets registered with `dybatpho::secret_register` are
  masked before any request is built, `dybatpho::ai_budget` caps how many calls
  a run may make, and `DRY_RUN` exercises the whole path without sending
  anything. Needs `yq` or `jq`, like the rest of the library.

- **`agent` module.** Make a script safe for an AI agent to drive.
  `agent_result` and `agent_error` print readable text for a person and JSON
  for an agent from the same call site; `agent_confirm` replaces an
  unanswerable prompt with an explicit `DYBATPHO_AGENT_ALLOW` allowlist and
  records every decision through `agent_audit`; `agent_context` tells a model
  what it is working with before it acts.

  ```sh
  . dybatpho/init.sh --modules agent
  dybatpho::agent_tools _spec_root mytool anthropic # Claude tool definitions
  dybatpho::agent_mcp _spec_root mytool             # MCP tools/list payload
  ```

  Tool definitions are generated from the same `cli.sh` option spec that drives
  the parser, in Anthropic, OpenAI, or MCP shape, so a schema cannot describe an
  option the CLI does not have. Needs `yq` or `jq`, like the rest of the library.

- **JSON documents you are still assembling.** `json.sh` gains five helpers for
  documents held in a shell variable rather than a file, so building JSON no
  longer means quoting by hand:

  ```sh
  dybatpho::json_object status ok message 'it "worked"' ports:json '[80,443]'
  # {"status":"ok","message":"it \"worked\"","ports":[80,443]}
  ```

  `json_string` encodes one value, `json_object` builds an object from name and
  value pairs (a name ending in `:json` nests an already-encoded document),
  `json_eval` and `json_get` run a filter against a document in a variable
  returning compact JSON or a bare scalar, and `json_valid` reports whether a
  string parses. All five prefer `yq` and fall back to `jq`, like the rest of
  the module, and the `ai` and `agent` modules are built on them.

- `example/ai_ops.sh` and `example/agent_ops.sh`, both runnable with no API key.

- **`pkg` module** — detect the machine's package manager and install
  dependencies through it. `dybatpho::pkg_manager` reports one of `apt`, `brew`,
  `apk`, `dnf`, `pacman`, or `emerge`, preferring the distribution manager over
  Homebrew on Linux, and `DYBATPHO_PKG_MANAGER` overrides the detection.
  `dybatpho::pkg_installed` and `dybatpho::pkg_missing` answer what is already
  there — on Homebrew they ask the formula scope and the cask scope, so an
  installed cask is not reinstalled on every run — `dybatpho::pkg_name` resolves `<manager>:<package>` overrides so one
  script names a dependency once, and `dybatpho::pkg_install_command` prints the
  exact command a run would execute.

  `dybatpho::pkg_install`, `dybatpho::pkg_update`, `dybatpho::pkg_ensure`, and
  `dybatpho::pkg_require` are the mutating half, and none of them changes the
  system quietly: each asks for confirmation unless `--force` or
  `DYBATPHO_FORCE` approves it, refuses rather than guessing in a
  non-interactive shell, and prints the command instead of running it under
  `--dry-run` or `DRY_RUN`. Elevation follows `DYBATPHO_PKG_SUDO` and is never
  added for Homebrew, and `DYBATPHO_PKG_ASSUME_YES=false` drops the managers'
  non-interactive flags.

  A flag the module does not model — `--cask` on Homebrew, `--no-cache` on
  Alpine, `--no-install-recommends` on Debian — goes through with `--arg`, once
  per flag, and lands after the manager's own flags and before the package
  names. `dybatpho::pkg_install`, `dybatpho::pkg_update`,
  `dybatpho::pkg_install_command`, `dybatpho::pkg_ensure`, and
  `dybatpho::pkg_require` all take it; the index refresh that `--update` runs
  never receives the install's extra arguments.

  ```sh
  . dybatpho/init.sh --modules pkg
  dybatpho::pkg_install --dry-run ripgrep # preview the command
  dybatpho::pkg_ensure --force --update curl jq
  dybatpho::pkg_require --force fd apt:fd-find emerge:sys-apps/fd
  dybatpho::pkg_install --force --arg --cask -- firefox
  dybatpho::pkg_ensure --force --arg --no-cache -- curl
  ```

### Changed

- **The repository contract is enforced by the test suite instead of a
  checklist.** `test/conventions.bats` fails the suite when a module ships
  without its `doc/`, `doc/spec/`, `test/` or `example/` counterpart, when it
  isn't registered in `init.sh`, when its spec is missing from
  `doc/spec/README.md`, when a public function is absent from its module
  documentation or never named in its test file, or when a function escapes the
  `dybatpho::` / `__dybatpho_` namespaces. The rules were already in `AGENT.md`;
  they were prose a contributor had to remember, and drift had already happened.
  Each check reports every violation at once rather than stopping at the first.

- **Private functions in `ai` and `agent` now carry the mandatory `__dybatpho_`
  prefix.** `src/ai.sh` and `src/agent.sh` defined 38 helpers as `__ai_*` and
  `__agent_*` — names bare enough to collide with a helper defined by the
  calling script, which is the reason the prefix is mandatory. They are private
  and were never exported, so no consumer can be affected.

- **`cli` help output now reads like a conventional command-line tool.** The
  usage line describes what the command actually accepts — `[OPTIONS]`, a
  `COMMAND` only when there are subcommands, and the declared positional
  arguments — instead of a fixed `[options...] [arguments...]`. Help gains an
  `Arguments` section, a `Commands` section ahead of `Options`, and a closing
  `Run '<prog> COMMAND --help' ...` line. Rows across all three sections align
  to one column computed from the longest label rather than a fixed width, and
  the `-h, --help` every command already accepted is finally listed.

  Each option now carries its details underneath it — `[env: NAME]`,
  `[config: key]`, `[choices: a, b]`, `[default: value]`, `[repeatable]`,
  `[repeat to increase]` — so where a value comes from is visible without
  reading the spec. A default built from a command substitution is left out,
  since printing the expression would mislead more than it helps.

- **BREAKING:** the minimum supported Bash is now 4.3, raised from 4.0.
  `init.sh` refuses to load on anything older instead of failing later with a
  confusing error.

  The library already depended on 4.3 without saying so: modules across it
  return values through nameref parameters (`local -n`, 43 uses at the time of
  the change), and the worker pool waits with `wait -n`. Both arrived in Bash
  4.3, so on 4.0 through 4.2 the library did not work — it just failed at the
  first call rather than at load time.

  Bash 4.3 was released in 2014 and every current distribution ships something
  newer. macOS still ships 3.2, which was already too old; `brew install bash`
  provides a current one.

- **The test runner is roughly three times faster and reports one summary
  instead of a TAP transcript.** `test/test_helper.bash` parks Bats' `DEBUG`
  trap while it sources the bats libraries and every dybatpho module: that trap
  fires once per executed command, and the setup a test does not care about was
  costing ~800ms per test instead of ~150ms. `scripts/test.sh` now lets Bats
  schedule at the test level so one heavy file no longer pins a single core, and
  prints a per-file table plus one set of totals, with the failure detail
  replayed once at the end. A full run went from ~6m to ~2m.
- **`scripts/test.sh` follows the library's own CLI conventions.** Options are
  declared through `dybatpho::opts::*` and parsed by
  `dybatpho::generate_from_spec`, so `--help` is generated, values are
  validated, and `--jobs`/`--chunk` read `DYBATPHO_TEST_JOBS`/
  `DYBATPHO_TEST_CHUNK` as their initial values.
- **Coverage is opt-in and chunked.** `scripts/test.sh` runs without kcov by
  default, which is what makes it usable in an edit/test loop; `--coverage`
  runs one kcov invocation per `--chunk` files and merges the parts into
  `coverage/bats`. kcov never releases the trace state it accumulates, so a
  single invocation over the whole suite grew until the OOM killer took the run
  down.

### Fixed

- **Six public functions had no direct test.** `dybatpho::ai_stream`,
  `dybatpho::opts::validate_choice`, `dybatpho::lock_field`,
  `dybatpho::lock_is_alive`, `dybatpho::lock_reclaim_stale` and
  `dybatpho::mock_calls` were only ever reached indirectly, so nothing pinned
  their contracts. Each now has a test naming it directly.

- **A dybatpho script run from a dybatpho shell no longer dies on its first log
  line.** The optional `metrics` hooks in `helpers`, `logging`, and `network`
  asked `declare -F dybatpho::metrics_counter_inc` whether to record. That name
  is exported, so a child shell inherited it without the internal helpers it
  calls, took the recording branch, and aborted with
  `__dybatpho_metrics_key: command not found` — which hit any script whose
  parent shell had loaded `metrics`, on its first `dybatpho::info` or first
  retry. The hooks now test an internal helper of the module, which cannot cross
  a process boundary, so they stay inert exactly when recording is impossible
  and still record in a child that loads `metrics` itself.
- **Temporary files no longer pile up in `/tmp` during a test run.** Bats
  re-arms its own `EXIT` trap after each test body, which discarded the cleanup
  trap `dybatpho::create_temp` had just registered, so virtually every temporary
  file a test created survived the run — the suite left roughly a thousand
  `/tmp/dybatpho_*` entries behind each time. With no explicit parent directory,
  temporary paths are now created under the Bats temporary directory when
  running as a test, which Bats removes itself and which is the right lifetime
  for a file a test created. A full suite run now leaves nothing behind.

- **`dybatpho::cleanup_file_on_exit` no longer grows the trap with every path.**
  Each registration used to append its own `rm` command, so a script creating
  many temporary files built a trap string that grew with each one. Paths are
  now collected in `DYBATPHO_CLEANUP_PATHS` and removed by a single trap
  installed on first use. A path registered by one shell is still never removed
  by another, so a subshell exiting leaves its parent's temporary files intact.

- **`dybatpho::create_temp` honours the requested parent directory when
  `mktemp` is missing.** The fallback path hardcoded `/tmp`, ignoring both the
  explicit fourth argument and `TMPDIR`.

- **`parallel`**: a job that called `exit` ended the worker before its exit code
  was written, so the pool reported the job as never having run and the run as
  successful even though the job had failed. Both `dybatpho::parallel_map` and
  `dybatpho::parallel_run` now evaluate the job one subshell deeper, so `exit`
  ends only the job.
- **`cli`**: a persistent option declared on a command was listed twice in that
  command's own help, once replayed as an inherited definition and once from
  its own spec.
- **`cli`**: the `@none` sentinel recorded for an alias-less command leaked into
  generated completion word lists and into the `aliases` array of the generated
  JSON schema.

- **File writers now work on macOS.** `chmod` and `sed` were given `--` to mark
  the end of the options, which the BSD versions on macOS read as a file name
  instead: `chmod: --: No such file or directory`. Every writer that carries a
  destination mode over — `file_write_atomic`, `file_replace`,
  `file_ensure_line`, `file_remove_line`, `ensure_dir` — failed there. The
  paths are now guarded by prefixing `./` when a name could be read as an
  option, which both platforms accept.
- CI installs a JSON backend. The `kcov` container had neither `yq` nor `jq`,
  so anything exercising `json.sh` for real died with `Neither yq nor jq is
  installed`; the existing JSON tests passed only because they stub the
  binaries.
- `scripts/test.sh` takes the worker count from `DYBATPHO_TEST_JOBS`, still one
  per core by default. A kcov-instrumented worker per core no longer fits in a
  CI runner now that the library has grown — the OOM killer was taking the run
  down mid-suite with exit 137 — so CI asks for two.
- **Two tests were silently not running.** `test/logging.bats` unset
  `EPOCHREALTIME` in the test body; it is a bash dynamic variable, so the unset
  is permanent, and Bats reads it for `--timing` right after the body returns —
  which dropped the test from the run with nothing but a warning line to say so.
  `test/metrics.bats` spawned a child shell with `bash -c`, whose empty
  `BASH_SOURCE` the kcov hook expands on every command until `set -u` fails the
  test, so it failed under coverage only. `scripts/test.sh` now fails a run when
  a file executes fewer tests than it declares, so a disappearing test cannot
  pass unnoticed again.

- `network` and `metrics` called `__log_now_ms`, which the internal-function
  rename had turned into `__dybatpho_log_now_ms`. Every timed `curl` call and
  every timer in the `metrics` module failed with `command not found` instead of
  recording a duration.

## [2.0.0] - 2026-09-17

### Added

- **Module loading on demand.** `init.sh` accepts a module set, either as a
  leading `--modules` argument or through the `DYBATPHO_MODULES` environment
  variable, and resolves the dependencies between modules for you. Use
  `--modules all` for the whole library.

  ```sh
  . dybatpho/init.sh --modules git semver
  DYBATPHO_MODULES="git semver" . dybatpho/init.sh
  ```

- `dybatpho::load` widens the module set after bootstrap, `dybatpho::module_loaded`
  answers whether a module is available, and `dybatpho::module_list` prints the
  `loaded`, `all`, `core`, or `optional` module names.
- **`lock` module** — serialize concurrent runs of a script without `flock`, which
  macOS does not ship. `dybatpho::with_lock` runs a command under a lock and
  releases it on every exit path; `lock_acquire`, `lock_release`, `lock_is_held`,
  `lock_info`, `lock_field`, `lock_path`, `lock_hostname`, `lock_is_alive`, and
  `lock_reclaim_stale` cover the rest. A lock records its holder, so a failed
  acquisition reports who owns it, and a lock left behind by a dead process is
  reclaimed rather than blocking forever. `DYBATPHO_LOCK_DIR` and
  `DYBATPHO_LOCK_POLL_INTERVAL` tune where locks live and how often waiting
  retries.
- **`safety` module** — guards for destructive operations, so a script asks
  before it removes or replaces something: `dybatpho::confirm`,
  `assert_safe_path`, `safe_rm`, `safe_overwrite`, `safe_copy`, `safe_move`,
  `safe_extract`, `safe_system`, and `is_interactive`. Every guarded operation
  validates the target path first, requires `--force` or a confirmation, refuses
  to touch a protected path such as `/` or `${HOME}`, and honors `DRY_RUN`.
  `is_interactive` lets a script tell an operator's terminal from CI, where a
  prompt would hang.
- **`testing` module** — 31 helpers for testing shell code: assertions for files,
  modes, symlinks, JSON, and YAML; snapshots, including CLI snapshots with
  scrubbing for values that change per run; mocks for commands, environment
  variables, and HTTP requests, each restoring the previous state; and fixtures
  that clean themselves up. Assertions report and return rather than terminate,
  so a test run reports every failure instead of stopping at the first.
- **Circuit breaker and more `curl` helpers in `network`** —
  `dybatpho::circuit_breaker` stops hammering an endpoint that keeps failing and
  lets a trial request through after a cooldown, with `circuit_state` and
  `circuit_reset` to inspect and clear it; `DYBATPHO_CIRCUIT_THRESHOLD` and
  `DYBATPHO_CIRCUIT_COOLDOWN` tune it. Added alongside: `curl_request`,
  `curl_parse_response`, `curl_response_header`, `curl_resume_download`,
  `curl_upload`, `curl_timeout`, and `verify_checksum`.
- **Structured logging to a file, with rotation** — `LOG_FILE` appends JSON log
  events independently of the console format, `LOG_FILE_LEVEL` sets its own
  threshold, and `LOG_FILE_MAX_BYTES` with `LOG_FILE_MAX_BACKUPS` rotate it.
  Every structured event carries `LOG_REQUEST_ID`, generated when unset, so the
  lines of one run can be correlated.
- **Configuration schema and documentation** — `dybatpho::config_doc` renders the
  declared schema as documentation, and `dybatpho::config_schema_reset` clears it
  between runs.
- **File content helpers in the `file` module** — the paths-and-temp-files module
  now also rewrites what a file holds. Every writer stages its output next to the
  destination and renames it into place, so a reader never sees a half-written
  file and an interrupted run leaves the original intact; the destination's mode
  is carried over, and its owner too when the process may set it. All of them
  honor `DRY_RUN`.

  | Function | Purpose |
  | --- | --- |
  | `dybatpho::file_write_atomic` | Write standard input over a file |
  | `dybatpho::file_replace` | Substitute a pattern in place, without the `sed -i` argument that differs on GNU and BSD |
  | `dybatpho::file_ensure_line` | Append a line unless the exact line is already there |
  | `dybatpho::file_remove_line` | Remove every occurrence of an exact line |
  | `dybatpho::file_hash` | Checksum a file as `md5`, `sha1`, `sha256`, or `sha512` |
  | `dybatpho::file_size` | Size in bytes |
  | `dybatpho::file_age_seconds` | Seconds since the last modification |
  | `dybatpho::file_backup` | Copy a file under a timestamped name and print the copy's path |
  | `dybatpho::find_up` | Search a directory and its ancestors for an entry, such as `.git` |
  | `dybatpho::ensure_dir` | Create a directory tree, apply a mode, and print the path |

  `file_ensure_line` and `file_remove_line` are idempotent, so a dotfiles script
  that runs twice leaves the same result as running it once. `file` is a core
  module, so these are available from a bare `. dybatpho/init.sh`.

  A destination that is a symlink is followed, so editing a dotfile symlinked
  into a repository rewrites the file in the repository and leaves the link in
  place. Set `DYBATPHO_FILE_FOLLOW_SYMLINKS=false` to replace the link instead.
  `file_size` and `file_age_seconds` likewise describe the file a symlink points
  at, not the link.

- `example/init_modules.sh`, showing how to request a module set and widen it at
  run time.
- `doc/init.md`, generated from `init.sh` like every module reference.

### Changed

- **BREAKING:** sourcing `init.sh` with no argument now loads only the core
  modules — `string`, `logging`, `helpers`, `process`, `file` and `secret`.
  Previously it loaded every module. A script that uses anything else has to ask
  for it:

  ```sh
  . dybatpho/init.sh               # before: everything; now: core only
  . dybatpho/init.sh --modules all # the previous behavior
  . dybatpho/init.sh --modules git # or name what the script actually uses
  ```

  Without the change, the script fails on the first call into an unloaded
  module. `dybatpho::module_list loaded` shows what a shell currently has.
- Project editor settings moved from `.neoconf.json` to `.vscode/settings.json`,
  which VS Code reads natively and
  [codesettings.nvim](https://github.com/mrjones2014/codesettings.nvim) feeds
  into Neovim's LSP configuration. The file pins the two bash-language-server
  settings without which no `dybatpho::` function resolves in an editor.

### Fixed

- Git helpers no longer inherit ambient Git environment variables such as
  `GIT_DIR` and `GIT_WORK_TREE`, which made them read whichever repository the
  caller's environment happened to point at rather than the one they were given.

### Security

- `dybatpho::archive_is_safe` and `dybatpho::archive_unsafe_entries` report
  archive entries that would escape the extraction directory, and
  `dybatpho::safe_extract` validates an archive before extracting it. This blocks
  path-traversal entries such as `../../etc/passwd` in an untrusted archive.

[Unreleased]: https://github.com/dynamotn/dybatpho/compare/v4.0.0...HEAD
[4.0.0]: https://github.com/dynamotn/dybatpho/compare/v3.0.0...v4.0.0
[3.0.0]: https://github.com/dynamotn/dybatpho/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/dynamotn/dybatpho/releases/tag/v2.0.0
