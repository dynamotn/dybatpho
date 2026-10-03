# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`screen` — the four [Catppuccin](https://catppuccin.com) flavours as
  themes.** `dybatpho::screen_theme` now takes `catppuccin-latte`,
  `catppuccin-frappe`, `catppuccin-macchiato` and `catppuccin-mocha`, drawn in
  24-bit colour from Catppuccin's own palette: mauve frames and selection,
  lavender titles, pink keys, and the flavour's green, yellow and red. The
  themes do not paint the screen behind the text, so use `catppuccin-latte` on
  a light terminal and one of the others on a dark one. Like `dusk`, each one
  falls back to `mono` when `dybatpho::color_supported` says colour is not
  wanted.

  ```sh
  dybatpho::screen_theme catppuccin-mocha
  ```

- **`json` — edit JSON and YAML documents by path.**
  `dybatpho::json_set` and `dybatpho::yaml_set` store a value at a path such as
  `spec.ports.0.name`, creating the objects and arrays on the way; the value is
  a string unless `--json` says to parse it, which is how a number, a boolean,
  `null` or a nested document is written. `dybatpho::json_del` and
  `dybatpho::yaml_del` remove a path and leave the document alone when it is not
  there, and `dybatpho::json_merge` and `dybatpho::yaml_merge` deep-merge an
  override onto a base object. The path and the value are never spliced into a
  filter, so a quotation mark or a `|` in either is stored as written. Each
  helper prints the result, or takes an output file — which may be the input —
  written atomically only once the edit has succeeded. A path through a scalar
  is refused the same way on `yq` and on the `jq` fallback, and YAML edits keep
  the document's comments.

  ```sh
  dybatpho::json_set package.json version 2.0.0 package.json
  dybatpho::json_set --json config.json server.ports '[80,443]' config.json
  dybatpho::yaml_del compose.yaml services.debug compose.yaml
  dybatpho::yaml_merge values.yaml values-prod.yaml > rendered.yaml
- **`date` — read durations, order dates, ISO weeks and timezone
  conversion.** `dybatpho::date_parse_duration` turns `90`, `90s`, `1h30m`,
  `1w 2d`, the `H:MM:SS` clock that `dybatpho::date_seconds_to_hms` writes, and
  ISO 8601 such as `PT1H30M` or `P1DT2H` into a number of seconds, returned
  through a variable so a refusal reaches the caller. Months and years are
  refused, as `dybatpho::date_add` refuses them, and so is a total too large
  for Bash to count. `dybatpho::date_is_before` and `dybatpho::date_is_after`
  order two dates strictly and stop the script on a date they cannot read.
  `dybatpho::date_iso_week` prints the ISO 8601 week with its week-year
  (`2021-01-01` is `2020-W53`), the same on GNU, BSD and BusyBox.
  `dybatpho::date_in_tz` prints a date as another timezone reads it, and
  refuses a zone missing from the zone database instead of answering in UTC.

  ```sh
  dybatpho::date_parse_duration timeout "${TIMEOUT:-5m}" || exit 1
  dybatpho::date_is_before "$(dybatpho::date_today)" 2026-12-31 && echo valid
  dybatpho::date_iso_week 2024-12-30          # 2025-W01
  dybatpho::date_in_tz "2024-02-29 12:00:00" Asia/Tokyo
- **`string` — regular expression captures and "did you mean" ranking.**
  `dybatpho::string_match` matches a string against an extended regular
  expression and writes the whole match and every capture group into an array
  you name, so a version or a `key=value` pair comes apart without touching
  `BASH_REMATCH`. It returns `1` on a miss and `2` for an invalid pattern, and
  empties the array either way.

  `dybatpho::string_distance` prints the Levenshtein edit distance between two
  strings, counted in characters, and `dybatpho::string_closest` ranks a list of
  candidates by it, returning every candidate tied at the smallest distance
  within the maximum you give. Any script can now answer a mistyped word the way
  the CLI parser answers a mistyped option. `dybatpho::cli_levenshtein` now
  delegates to `dybatpho::string_distance` and answers exactly as before.

  ```sh
  local -a parts=() guesses=()
  dybatpho::string_match parts "v1.24.3" '^v([0-9]+)\.([0-9]+)\.([0-9]+)$'
  dybatpho::string_closest guesses "staus" 2 status start stash   # status
- **`text` — boxes, centering, line numbers, and truncation for text blocks.**
  `dybatpho::text_box` frames a block in a border sized to its widest line,
  with an optional title set into the top edge and a `single`, `double`,
  `rounded`, `heavy` or `ascii` style. `dybatpho::text_center` centers each
  line within a width, the terminal's by default.
  `dybatpho::text_number_lines` numbers every line, right-aligned, from any
  start and with any separator, and `dybatpho::text_truncate_lines` keeps the
  first lines of a block and ends with `… N more lines` or a marker of your own
  where `{count}` stands for the lines left out. Boxing and centering measure
  what the terminal shows: ANSI colors count for nothing, and when the `screen`
  module is loaded a wide character counts for the two columns it occupies.
  Every helper reads stdin when given `-`.

  ```sh
  dybatpho::text_box "$(git diff --shortstat)" "Changes" rounded
  ./build.sh 2>&1 | dybatpho::text_truncate_lines - 20 "(+{count} lines in build.log)"
- **`git` — where a branch stands before you act on it.** Six read-only
  helpers answer what a commit, pull, push, or rebase script asks first:
  `dybatpho::git_upstream` names the branch's upstream (`origin/main`) and
  exits 1 when there is none, `dybatpho::git_ahead_behind` prints
  `<ahead> <behind>` against the upstream or any ref, `dybatpho::git_state`
  names an unfinished `merge`, `rebase`, `am`, `cherry-pick`, `revert`, or
  `bisect` (or `none`) and answers correctly inside a linked worktree,
  `dybatpho::git_is_shallow` spots a shallow CI clone,
  `dybatpho::git_stash_count` counts stash entries, and
  `dybatpho::git_worktree_list` prints each worktree's path and branch,
  tab-separated so paths with spaces read back whole.

  ```sh
  [[ "$(dybatpho::git_state)" == none ]] || dybatpho::die "Finish it first"
  read -r ahead behind <<< "$(dybatpho::git_ahead_behind)"
  ```
- **`testing` — freeze the clock, fake a terminal, and assert an exit status.**
  `dybatpho::mock_time` stops the clock that `date` reports at a Unix
  timestamp, for the test shell and every process it starts, so
  `dybatpho::date_now`, `dybatpho::file_age_seconds`, cache ages, schedules and
  rate-limit windows give exact answers; `dybatpho::mock_time_advance` moves it
  by any number of seconds, and `dybatpho::unmock_time` releases it. A `date`
  call that names its own moment (`-d`, `-r`, …) still goes to the real `date`,
  and millisecond timers keep measuring real time. `dybatpho::mock_tty` makes
  `dybatpho::is_tty` — and so `dybatpho::color_supported` and
  `dybatpho::is_interactive` — report a terminal or none on chosen streams,
  undone by `dybatpho::unmock_tty`. `dybatpho::assert_exit_code` runs a command
  and fails, showing its output, unless it exits with the stated status.
  `dybatpho::unmock_all` now also releases the clock and the terminal mock.

  ```sh
  dybatpho::mock_time 1767225600
  dybatpho::mock_time_advance 3600
  dybatpho::mock_tty off stdin
  dybatpho::assert_exit_code 1 -- dybatpho::confirm "Delete everything?"
  ```

- **`queue` — urgent jobs first, and jobs that wait until they are due.**
  `dybatpho::queue_push --priority <n>` puts a job ahead of every waiting job of
  a lower priority, while jobs of one priority still leave in the order they
  arrived. `--delay <duration>` (such as `90s`, `15m` or `PT1H`) and
  `--at <epoch>` keep a job in `pending`, counted and listed but neither claimed
  nor peeked, until it falls due. `dybatpho::queue_requeue` keeps a job's
  priority and takes the same `--delay` and `--at`, which is how a worker backs
  off from a failure, and `dybatpho::queue_peek` now answers the job a claim
  would take next. A queue that never uses these options is the same strict
  FIFO as before.

  ```sh
  dybatpho::queue_push --priority 10 deploys "rollback api"
  dybatpho::queue_push --delay 15m deploys "warm caches"
  dybatpho::queue_requeue --delay 30s deploys "${id}" 3
  ```

- **`queue` — a ready-made worker.** `dybatpho::queue_work <queue> <handler>`
  claims each job that is due, calls the handler with the payload as its last
  argument and the job's id in `DYBATPHO_QUEUE_JOB_ID`, completes the job when
  the handler succeeds, and requeues it when it fails, until `--retries` (default
  `3`) is spent and the job is dead-lettered with a warning. `--backoff` holds
  each retry back twice as long as the last, up to `--max-backoff`. The handler
  runs in a subshell, so one that exits fails only its own job. Without
  `--poll` the worker drains the queue and returns; with it, it waits for new
  work until `--idle` runs out, and `--max-jobs` stops it after a number of jobs.

  ```sh
  dybatpho::queue_work --retries 5 --backoff 10s deploys handle_deploy
  dybatpho::queue_work --poll 5s --idle 10m deploys ./handle.sh --verbose
  ```

- **`lock` — semaphores: let a few runs in at once.**
  `dybatpho::lock_semaphore_acquire <name> <slots> [timeout] [var]` takes one of
  a fixed number of slots, waiting up to the timeout for one to free up, and
  names the slot it took; `dybatpho::lock_semaphore_release` gives back that
  slot, or every slot the current process holds. Each slot is an ordinary
  lock, so one left by a crashed process is reclaimed the same way, and a
  refusal lists every holder, as `dybatpho::lock_semaphore_holders` does.
  `dybatpho::with_semaphore` runs a command holding a slot and gives it back
  afterwards, on failure and interruption too, exactly as `dybatpho::with_lock`
  does for a lock.

  ```sh
  dybatpho::with_semaphore downloads 4 60 -- curl -fsSLO "${url}"
  dybatpho::lock_semaphore_acquire builds 2 300 slot || exit 1
- **`parallel` — fail-fast now ends the jobs still running, and says why.**
  `dybatpho::parallel_map` and `dybatpho::parallel_run` take a `--fail-fast`
  option before the job count, the per-call form of
  `DYBATPHO_PARALLEL_FAILFAST=true`. Fail-fast used to stop only new jobs from
  starting and then waited for the ones already running, however long they
  took; the first failure now ends every running job together with the
  processes it started, including while the last jobs drain. Such a job reads
  `terminated` from `dybatpho::parallel_status` and, like a `skipped` one, is
  not counted by `dybatpho::parallel_failed`. A warning on standard error names
  the job that failed, its item or command, and its exit code.

  ```sh
  dybatpho::parallel_map --fail-fast 4 _deploy "${hosts[@]}" || exit 1
  ```

- **`parallel` — a time limit for each job.** `dybatpho::parallel_map` and
  `dybatpho::parallel_run` take `--timeout <duration>` (or
  `DYBATPHO_PARALLEL_TIMEOUT`), in any form `dybatpho::date_parse_duration`
  reads, such as `90`, `30s` or `1h30m`. A job that runs past it has its whole
  process group asked to stop, is killed `DYBATPHO_TIMEOUT_KILL_AFTER` seconds
  later if it is still there, and is recorded as exit `124`, the code `timeout`
  uses, with a warning naming it. A timeout is a failure like any other, so
  `--fail-fast` stops on it, and a generous limit costs nothing: the run ends as
  soon as its jobs do. The `parallel` module now loads `date`.

  ```sh
  dybatpho::parallel_map --timeout 30s 8 _check "${hosts[@]}"
  ```

- **`parallel` — progress while a long run works.** `--progress` (or
  `DYBATPHO_PARALLEL_PROGRESS=true`) on `dybatpho::parallel_map` and
  `dybatpho::parallel_run` reports finished jobs on standard error while the
  run is still going. When the `tui` module is loaded it drives
  `dybatpho::tui_progress_start` and its bar, which logs on a percentage grid
  when there is no terminal; without `tui`, each finished job prints a plain
  `Jobs: 3/10 finished` line. Standard output still carries only what the jobs
  wrote, so a run can be piped or redirected with progress on.

  ```sh
  dybatpho::parallel_map --progress 4 _convert ./images/*.png > converted.log
- **`csv` — TSV and a delimiter that cannot hang the parser.**
  `DYBATPHO_CSV_DELIMITER` now takes `tab` (or `\t`) for tab-separated files,
  and `dybatpho::csv_convert` rewrites a file with another delimiter, quoting
  each field for the delimiter it is written with — a comma inside a value
  needs no quotes in TSV, a tab inside one does. Every csv function now refuses
  a delimiter it cannot work with — empty, longer than one character, a quote,
  or a line break — where an empty one used to spin the parser forever.

  ```sh
  dybatpho::csv_convert billing.csv tab > billing.tsv
  DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_col billing.tsv owner
  ```

- **`csv` — keep just the columns a report needs.** `dybatpho::csv_select`
  prints CSV holding the columns you name, header included, in the order you
  name them. A column is chosen by its header or by its position from `1`; a
  header literally named like a number still wins, a column may repeat, and an
  unknown one stops the script naming the columns there are.

  ```sh
  dybatpho::csv_select billing.csv owner cost > owners.csv
  ```

- **`csv` — sort rows by a column.** `dybatpho::csv_sort` prints the header
  and the rows ordered by one column, `asc` or `desc`. It compares as numbers
  when every value in the column is one (so `9` comes before `10`, and `10`
  equals `010.0`) and byte by byte otherwise, or as `text` / `number` when you
  say so. The sort is stable, an empty value always sorts last, and a value
  that spans several lines stays whole.

  ```sh
  dybatpho::csv_sort billing.csv cost desc | head -n 6   # header and the top five
  ```

- **`csv` — join two files on a key.** `dybatpho::csv_join` combines two
  inputs on a key column, `inner` by default or `left` to keep every left row,
  with the right key named separately when the two files disagree. Every match
  becomes its own row, in the left file's order and then the right's, the
  right key is not repeated, and a blank key matches nothing.

  ```sh
  dybatpho::csv_join services.csv owners.csv team left
  ```

- **`table` — draw real CSV and JSON records.** `dybatpho::table_from_csv`
  renders CSV through the csv parser, so a quoted comma stays in its cell
  where `dybatpho::table_csv` would refuse the row, and follows
  `DYBATPHO_CSV_DELIMITER` for semicolon and tab files.
  `dybatpho::table_from_json` renders a JSON array of objects, the first
  object's keys as the header. Both draw `plain`, `box` or `markdown`; a line
  break inside a value is drawn as a space and Markdown escapes `|`. Both need
  the `csv` module, which `table` does not load for you, so a script that only
  draws plain tables does not pay for the parser; without it they stop and say
  `dybatpho::load csv`.

  ```sh
  dybatpho::csv_sort billing.csv cost desc | dybatpho::table_from_csv - box
  dybatpho::table_from_json pods.json markdown >> report.md
- **`diff` — compare two directory trees.** `dybatpho::diff_dir` walks two
  directories and prints one record per entry that changed, sorted by path:
  `+` for an entry only in the second tree, `-` for one only in the first, `~`
  for a file whose content or a link whose target differs, and `!` for an entry
  that changed kind (`! plugins: file -> directory`). Files are compared by
  content, so a copy with fresh timestamps is no change, and links are never
  followed. A name holding a newline or a backslash is escaped onto one line,
  and `--null` prints every record raw and NUL-terminated instead.
  `--summary` reduces the comparison to the `+A -R ~M` line
  `dybatpho::diff_summary` prints. The exit code is 0 when the trees match, 1
  when they differ, and 2 when a side is not a directory.

  ```sh
  dybatpho::diff_dir ./release-1.2 ./release-1.3
  dybatpho::diff_dir --summary /srv/www /mnt/restore/www   # +3 -1 ~2
  ```

- **`backup` — see what changed since a backup.** `dybatpho::backup_diff`
  compares two backups, or a backup with the live file or directory it was
  taken from, and reports through `dybatpho::diff_dir`: what the newer side
  added, removed, rewrote, or turned into another kind of entry, or a
  `+A -R ~M` line with `--summary`. Each backup is checked against its sidecar
  and for entries that escape before it is extracted into a scratch directory
  removed on exit, so nothing in the backup directory or the source is
  written, and a backup that fails either check stops the call with exit
  code 2. The source's own name is not compared, so a backup of `/etc/nginx`
  lines up with a copy restored anywhere else.

  ```sh
  dybatpho::backup_diff "$(dybatpho::backup_latest /var/backups nginx)" /etc/nginx
  dybatpho::backup_diff --summary "${older}" "${newer}"   # +1 -0 ~2
  ```

- **`backup` — incremental snapshots that share unchanged files.**
  `dybatpho::backup_create --incremental` writes a `<name>-<timestamp>.snapshot`
  directory instead of an archive: a plain copy of the source in which every
  file unchanged since the previous snapshot of the same name is a hard link
  to it, so a nightly history of a large tree costs one copy plus what
  changed. It uses `rsync --link-dest` when installed and walks the source in
  Bash otherwise, with the same result. `dybatpho::backup_list`,
  `dybatpho::backup_latest`, `dybatpho::backup_verify`,
  `dybatpho::backup_restore`, `dybatpho::backup_diff` and
  `dybatpho::backup_prune` take snapshots as they take archives: the sidecar
  fingerprints the whole tree, a restore copies plain files back, and pruning
  one snapshot never breaks another that shares its files. Special files are
  skipped, and a snapshot is meant to be read and restored, never edited in
  place, since its files are shared.

  ```sh
  dybatpho::backup_create --incremental /srv/www /var/backups www
  dybatpho::backup_prune --keep-count 30 --name www --force /var/backups
- **`cache` — answer from a recent entry while it refreshes.**
  `dybatpho::cache_run` takes `--stale <seconds>` (or `DYBATPHO_CACHE_STALE`):
  an entry past its time to live but within that grace window is printed at
  once while the command runs again in the background to replace it, so a
  prompt or status line never waits on a slow source that answered recently.
  One refresh of an entry runs at a time however many callers find it stale,
  and a refresh that fails keeps the entry it was meant to replace.
  `dybatpho::cache_wait` waits for a refresh to finish, for a script that is
  about to exit or wants the new answer. The `cache` module now loads `lock`.

  ```sh
  status="$(dybatpho::cache_run status 300 --stale 86400 -- fetch_status)"
  dybatpho::cache_wait status 30
  ```

- **`cache` — keep a namespace within bounds.** `dybatpho::cache_prune`
  removes entries older than `--older-than <seconds>`, then the least recently
  written ones until the namespace holds no more than `--max-entries <count>`
  and `--max-size <size>` (bytes, or a binary `K`, `M` or `G` suffix). Like
  `dybatpho::cache_clear` it touches only entries the module wrote, and under
  `DRY_RUN` it reports each removal instead.

  ```sh
  dybatpho::cache_prune --older-than 604800 --max-size 50M
  ```

- **`cache` — see what a namespace holds.** `dybatpho::cache_stats` reports
  the entry count, total bytes, how many entries are fresh and stale against a
  time to live, and the ages of the oldest and newest, as aligned text or, with
  `--json`, as one object a dashboard can read.

  ```sh
  dybatpho::cache_stats 3600 --json   # {"entries":3,"bytes":1800,"fresh":1,...}
- **`math` — median, percentiles, standard deviation and square roots.**
  `dybatpho::math_median` prints the middle value of a list, or the exact mean
  of the two middle ones. `dybatpho::math_percentile` prints any percentile
  from `0` to `100`, interpolated linearly between the two nearest ranks — the
  `PERCENTILE.INC` definition, R type 7, NumPy's default — so `50` is the
  median and the answer is exact. `dybatpho::math_stddev` prints the population
  standard deviation, or the sample one with `--sample`, rounding only the final
  root to `DYBATPHO_MATH_SCALE`. `dybatpho::math_sqrt` takes a square root digit
  by digit, rounded half away from zero at the width you ask for. Like the
  other aggregates, the list comes from the arguments or from standard input,
  and nothing outside Bash is needed.

  ```sh
  dybatpho::math_percentile 99 < latencies_ms.txt
  dybatpho::math_stddev --sample 2 4 4 4 5 5 7 9   # 2.1380899353
  dybatpho::math_sqrt 2 5                          # 1.41421
  ```

- **`metrics` — summaries with exact quantiles.**
  `dybatpho::metrics_summary_ms` records a duration in a Prometheus summary:
  every observation is kept for the life of the shell, and
  `dybatpho::metrics_render` exports the quantiles listed in
  `DYBATPHO_METRICS_QUANTILES` — `0.5,0.9,0.99` by default — each interpolated
  exactly between the nearest ranks, in seconds, followed by `_sum` and
  `_count`. Where a histogram leaves the dashboard to estimate the 99th
  percentile from buckets, a summary states it. `dybatpho::metrics_get sum` and
  `count` read a summary's totals back, and one metric name cannot be recorded
  as both a histogram and a summary. Summaries need the `math` module, which
  `metrics` does not load for you; without it the call stops and says
  `dybatpho::load math`.

  ```sh
  dybatpho::metrics_summary_ms fetch_duration_seconds 143 site=docs
  # fetch_duration_seconds{site="docs",quantile="0.99"} 0.143
  ```

- **`metrics` — push to a Prometheus Pushgateway.**
  `dybatpho::metrics_push` sends the rendered metrics to a Pushgateway, so a
  cron job or CI step that exits before any scrape still reaches the dashboard.
  The job name and any `key=value` grouping labels become the URL
  (`/metrics/job/<job>/<key>/<value>`), with a value that is empty or contains
  a `/` sent base64url-encoded as the Pushgateway expects and every other value
  percent-encoded. It replaces the whole group with `PUT`, or only the pushed
  metrics with `--add` (`POST`), goes through `dybatpho::curl_do` with its
  retries and `DRY_RUN`, returns its exit code, and logs the gateway's own error
  text when the push is refused. With nothing recorded it sends nothing and
  says so. A push needs the `network` module, which `metrics` does not load
  for you, so counting and timing never require `curl`; without it the push
  stops and says `dybatpho::load network`.

  ```sh
  dybatpho::metrics_push https://pushgateway.example.com nightly-backup host="$(hostname)"
- **`notification` — desktop notifications.** `dybatpho::notify_desktop`
  shows a title, an optional body and a `low`, `normal` or `critical` urgency
  through `notify-send` on Linux and the BSDs, or `osascript` on macOS. The
  text reaches either one as separate arguments, so quotes, a title starting
  with `-`, or AppleScript syntax are shown as written rather than run. With
  no backend installed it fails with exit code `127`, and `DRY_RUN` prints the
  command instead of showing anything. `dybatpho::doctor` lists the two
  backends as optional dependencies of the module.

  ```sh
  ./backup.sh && dybatpho::notify_desktop "Backup finished" "42 files, 3.1 GiB"
  ```

- **`notification` — ntfy.** `dybatpho::notify_ntfy` publishes a message to
  the topic in `DYBATPHO_NTFY_TOPIC`, on ntfy.sh or the server in
  `DYBATPHO_NTFY_URL`, with an optional title, a priority given as `1`-`5` or
  as `min` through `urgent`, and comma-separated tags. `DYBATPHO_NTFY_TOKEN`
  unlocks a protected topic and is sent outside curl's command line, so other
  users of the host cannot read it from the process list. A topic ntfy would
  refuse, a server URL without a scheme, an unknown priority, or tags holding
  a line break stop the call before any request is made.

  ```sh
  export DYBATPHO_NTFY_TOPIC=backups-7f3a
  dybatpho::notify_ntfy "Disk /var at 97%" "Disk almost full" urgent warning
  ```

- **`notification` — Gotify.** `dybatpho::notify_gotify` pushes a message,
  with an optional title and a priority from `0` to `10`, to the server in
  `DYBATPHO_GOTIFY_URL` as the application whose token is in
  `DYBATPHO_GOTIFY_TOKEN`. The token travels in the `X-Gotify-Key` header
  outside curl's command line, so it cannot be read from the process list.

  ```sh
  dybatpho::notify_gotify "Disk /var at 97%" "Disk almost full" 8
  ```

- **`notification` — email through the local MTA.** `dybatpho::notify_email`
  sends a plain-text message to comma-separated recipients through whatever
  `sendmail` the host has — Postfix, Exim, OpenSMTPD, msmtp — looking in
  `/usr/sbin` and `/usr/lib` too, or using `DYBATPHO_SENDMAIL`. The sender is
  an argument or `DYBATPHO_EMAIL_FROM`. Recipients go to `sendmail` as
  arguments rather than being read from the headers, and a line break in a
  recipient, the sender or the subject is refused, so text from a variable
  cannot add a header or a recipient. A subject in any language is encoded for
  the header, the body is sent as UTF-8, and a line holding a single `.` does
  not cut the message short. With no `sendmail` it fails with exit code `127`;
  `DRY_RUN` prints the command and sends nothing.

  ```sh
  dybatpho::notify_email ops@example.com "Backup failed" "$(tail -n 20 backup.log)"
  ```

- **`notification` — a delivery policy for the HTTP notifiers.**
  `DYBATPHO_NOTIFY_MAX_RETRIES` sets the retry budget of notification requests
  alone, so an alert from a cron job can give up quickly without shortening
  the script's other requests. `DYBATPHO_NOTIFY_CIRCUIT=true` puts each
  provider behind `dybatpho::circuit_breaker`: once it has failed
  `DYBATPHO_CIRCUIT_THRESHOLD` times in a row, further calls return `9` at once
  until `DYBATPHO_CIRCUIT_COOLDOWN` passes, and the other providers keep
  working. Circuits are named after the provider, or the host for
  `dybatpho::notify_webhook`, never the full URL, so a webhook secret does not
  reach the log. Both are off by default, and nothing changes until they are
  set.

  ```sh
  export DYBATPHO_NOTIFY_MAX_RETRIES=1 DYBATPHO_NOTIFY_CIRCUIT=true
  dybatpho::notify_slack "Job finished" || [[ $? -eq 9 ]]
  ```

### Changed

- **BREAKING: `network` no longer loads `json`.** Loading `network` -- directly
  or through `notification`, `forge`, `ai` or `testing` -- used to bring the
  `json` module along. Only `dybatpho::curl_graphql` needs it, and it now stops
  with `dybatpho::curl_graphql needs the json module, load it with: dybatpho::load
  json` when it is missing; every other request helper works without it. A
  script that calls `dybatpho::curl_graphql`, or any `dybatpho::json_*` helper,
  having asked only for `network` must now ask for `json` too:

  ```sh
  # before
  . dybatpho/init.sh --modules network
  # after
  . dybatpho/init.sh --modules network json   # or: dybatpho::load json
  ```

- **BREAKING: `diff` no longer loads `json`.** Only `dybatpho::diff_yaml`
  needs it, to convert YAML before comparing, and it now stops with
  `dybatpho::diff_yaml needs the json module, load it with: dybatpho::load json`
  when it is missing; `dybatpho::diff_text`, `diff_summary`, `diff_json` and
  `diff_dir` work without it. Loading `backup` no longer brings `json` either.
  A script that calls `dybatpho::diff_yaml`, or any `dybatpho::json_*` helper,
  having asked only for `diff` or `backup` must now ask for `json` too:

  ```sh
  . dybatpho/init.sh --modules diff json   # or: dybatpho::load json
  ```

- **BREAKING: `csv` no longer loads `json`.** Only `dybatpho::csv_to_json`
  needs it, to encode each value, and it now stops with
  `dybatpho::csv_to_json needs the json module, load it with: dybatpho::load
  json` when it is missing; every other `csv` function, including
  `dybatpho::csv_from_json`, works without it. `csv` still loads `math`. A
  script that calls `dybatpho::csv_to_json`, or any `dybatpho::json_*` helper,
  having asked only for `csv` must now ask for `json` too:

  ```sh
  . dybatpho/init.sh --modules csv json   # or: dybatpho::load json
  ```

- **BREAKING: `testing` loads only `text`, not `json`, `diff` or `network`.**
  The JSON and YAML assertions -- `dybatpho::assert_json_valid`,
  `assert_json_query`, `assert_json_has`, `assert_yaml_valid`,
  `assert_yaml_query` and `assert_yaml_has` -- need `json`; without it each one
  fails as an assertion with `<function> needs the json module, load it with:
  dybatpho::load json`, and returns rather than ending the test. Snapshots
  still record and compare without `diff`; a mismatch still fails, and says it
  needs `diff` to show the difference instead of drawing it. Nothing in
  `testing` used `network`. A suite that uses those assertions, wants snapshot
  mismatches drawn, or calls a `json`, `diff` or `network` helper having asked
  only for `testing` must now ask for those modules too:

  ```sh
  . dybatpho/init.sh --modules testing json diff   # or: dybatpho::load json diff
- **BREAKING: `text` no longer loads `table`.** Only `dybatpho::text_columns`
  draws through the table renderer, so loading `text` -- or `testing`, which
  loads it -- no longer brings `table` along. `dybatpho::text_columns` now
  stops with `dybatpho::text_columns needs the table module, load it with:
  dybatpho::load table` when it is missing, instead of a message naming
  `dybatpho::table_align`. A script that calls `text_columns`, or any
  `table_*` function, after loading only `text` has to ask for `table`:

  ```sh
  . dybatpho/init.sh --modules text          # before
  . dybatpho/init.sh --modules text table    # after
  ```

### Fixed

- **`testing` — a mock now wins over a command the shell already ran.**
  `dybatpho::mock_command` and `dybatpho::mock_command_script` used to be
  bypassed for a command that had already run in the same shell, because Bash
  remembered its real path; `dybatpho::unmock_command` likewise left the shell
  pointing at the removed mock. Both now take effect immediately.

- **`cache` — a time to live that is not a number now stops `dybatpho::cache_run`.**
  It used to be rejected inside a command substitution, so the error was
  printed and the command ran anyway, uncached.

- **`backup` — backups taken in the same second are listed in the order they
  were taken.** `dybatpho::backup_list`, `dybatpho::backup_latest` and
  `dybatpho::backup_prune` ordered names the way the shell's collation did, so
  under the C locale `snap-<stamp>-1` counted as older than `snap-<stamp>`, and
  under every locale `-10` counted as older than `-2`. `backup_latest` could
  name the wrong backup and `--keep-count` could prune the newest one. The
  same-second suffix is now compared as a number, whatever the locale.

- **`lock` — reclaiming a stale lock no longer steals one that just changed
  hands.** When a holder released its lock while another process was checking
  it, the empty name read as a dead holder, and the lock the next process
  claimed a moment later was moved aside and deleted. Both processes then held
  the same lock, and a semaphore could let more holders in than it has slots.
  The check now judges the holder it actually read, and leaves a lock alone
  once its holder has changed.

- **`csv` — stray text after a closing quote is no longer read twice.** A
  malformed field such as `"a"x` at the end of a record came back as `ax` and
  then again as an extra field `x`, so the row was one column wider than its
  header. Every reader now keeps `ax` as the one field it is.

- **`csv` — `dybatpho::csv_from_json` accepts an empty array.** With `jq` as
  the backend, `[]` was refused as "not an array of objects", while `yq`
  converted it to nothing. Both now write nothing and succeed.

- **`json` — `dybatpho::json_valid` accepts `null` and `false`.** With only
  `jq` installed it ran `jq -e`, which judges the value rather than the text,
  so the valid documents `null` and `false` were refused; with `yq` they were
  accepted, and so was blank text. Both backends now accept every JSON value
  and refuse blank text.

### Security

- **`network` — URLs no longer reach the log in full.** `dybatpho::curl_do`
  logged `Error when access <url>` and `No more retries left to run curl <url>`
  with the whole URL, and the download, pagination and GraphQL helpers did the
  same in their progress, debug and error lines. A Slack, Discord, Teams or
  Google Chat webhook URL is the secret itself, so a failed notification wrote
  it to stderr and to `LOG_FILE`. Those lines now show only the scheme, host
  and port, as `https://hooks.slack.com/[redacted]`.

- **`notification` — `dybatpho::notify_webhook` no longer logs its URL.** Its
  debug line, `Sending webhook notification to <url>`, wrote the whole webhook
  URL whenever `LOG_LEVEL` was `debug`; it now shows the host only.
- **`helpers` — `dybatpho::require` no longer passes a path that is not
  there.** A command given as a path, such as `/usr/sbin/sendmail`, counted as
  installed whether or not the file existed, because the shell's `hash` takes
  any name holding a `/` on trust. A path now has to be an executable file.

- **`testing` — code after `dybatpho::mock_http` shows up in coverage again.**
  The mock passed its `curl` script through a traced argument, and kcov stops
  recording a process once the trace holds a value with both a line break and
  a single quote, so under kcov every line a test ran after mocking HTTP was
  reported as never run. The script is now written without entering the
  trace.

## [5.2.0] - 2026-10-02

### Added

- **`privilege` — ask for sudo once, and hold it for the whole run.** `pkg`
  could put `sudo` in front of one command; a script running twenty of them
  over several minutes needs the prompt up front, the ticket kept alive, and
  no child able to stop and ask again halfway through.

  `dybatpho::privilege_needed`, `dybatpho::privilege_command`,
  `dybatpho::privilege_acquire`, `dybatpho::privilege_release` and
  `dybatpho::privilege_run`.

  ```sh
  . dybatpho/init.sh --modules privilege

  dybatpho::privilege_acquire --shield || dybatpho::die "Cannot elevate"
  dybatpho::privilege_run -- apt-get install -y the-tools
  dybatpho::privilege_release
  ```

  `--shield` puts a non-interactive escalation command first on `PATH`, so a
  child cannot hang the run with a prompt nothing can display. The background
  refresher watches its parent rather than waiting to be signalled, so a
  script that is killed outright does not leave it behind. With no cached
  ticket and no terminal the call fails instead of blocking, which is what a
  run from cron needs. `DYBATPHO_PRIVILEGE_SUSPEND_HOOK` is how a full-screen
  caller gives the terminal back around the prompt.

- **`array` — order a dependency graph instead of resolving one by hand.**
  `dybatpho::array_toposort` reads an associative array of edges and returns
  an order where a dependency comes before what needs it;
  `dybatpho::array_closure` answers what a set of roots pulls in.

  ```sh
  declare -A deps=([cli]="config validate" [config]="validate")
  dybatpho::array_toposort deps order   # validate config cli
  dybatpho::array_closure deps needed cli
  ```

  The order is the same on every run, because the walk starts from the keys
  sorted rather than in the order Bash hashes them into. An entry named only
  as a dependency is in the result, since a leaf still has to come first. A
  cycle is reported through the exit code with an order still returned: some
  graphs have one on purpose, and `init.sh`'s own `text`/`table` pair is one.

- **`dybatpho::color_supported` — one answer for whether output should carry
  colour.** `NO_COLOR` wins over everything, `FORCE_COLOR` overrides the
  stream, `TERM=dumb` rules colour out, and otherwise the named stream has to
  be a terminal. It answers per stream, because a module writing diagnostics
  to stderr and data to stdout needs a different answer for each. A stream it
  does not know is reported as the caller's mistake, whatever the environment
  would otherwise have answered.


- **`schedule` — when a command should run, rather than whether to retry it.**
  The three shapes a script keeps rewriting as a `sleep` loop, plus a cron
  predicate for scripts an external scheduler already runs.

  `dybatpho::schedule_every`, `dybatpho::schedule_debounce`,
  `dybatpho::schedule_once_per`, `dybatpho::schedule_reset` and
  `dybatpho::schedule_cron_due`. `DYBATPHO_SCHEDULE_DIR` sets where the
  markers live.

  ```sh
  . dybatpho/init.sh --modules schedule

  dybatpho::schedule_once_per day token-expiry -- dybatpho::warn "The token expires soon"
  dybatpho::schedule_debounce 2 rebuild -- make
  dybatpho::schedule_cron_due "*/15 * * * *" && collect_metrics
  dybatpho::schedule_every 60 -- check_health
  ```

  `schedule_once_per` keeps its marker on disk, so "once a day" holds across
  separate invocations rather than only within one run. `schedule_debounce`
  acts after a burst settles, not at its start, which is what an editor'"'"'s
  write-then-rename needs. `schedule_every` measures from when each run was
  due, so the cadence does not drift, and drops the ticks a slow run missed
  instead of queueing catch-ups. `schedule_cron_due` follows cron'"'"'s own rule
  that a restricted day of month and day of week match on either, not both.

- **`screen` — themes and styled rows, so a full-screen application looks
  finished without choosing a colour for every widget.**
  `dybatpho::screen_theme` sets every style of the module from a palette:
  `default`, `dusk` (256 colours) or `mono`, and `NO_COLOR` turns `dusk` into
  `mono`. `dybatpho::screen_spans` draws pieces of a row in their own styles
  over an optional background, `dybatpho::screen_ansi` draws program output
  with the colours it was written in, and `dybatpho::screen_keybar` draws a bar
  of key hints. A block takes `focus:true` to mark the panel that has the keys,
  and tabs take `divider_style:`.

  New style variables: `DYBATPHO_SCREEN_STYLE_FOCUS`,
  `DYBATPHO_SCREEN_STYLE_TAB_ACTIVE`, `DYBATPHO_SCREEN_STYLE_KEYBAR`,
  `DYBATPHO_SCREEN_STYLE_KEY`, `DYBATPHO_SCREEN_STYLE_ACCENT`,
  `DYBATPHO_SCREEN_STYLE_DIM`, `DYBATPHO_SCREEN_STYLE_OK`,
  `DYBATPHO_SCREEN_STYLE_WARN` and `DYBATPHO_SCREEN_STYLE_ERROR`.

  ```sh
  dybatpho::screen_theme dusk
  dybatpho::screen_block "${rect}" title:"Tools" focus:true
  dybatpho::screen_spans "${row}" "${x}" "${width}" "" "✔ " "${DYBATPHO_SCREEN_STYLE_OK}" "ripgrep" "1"
  dybatpho::screen_keybar "${footer}" "space" "pick" "q" "quit"
  ```
- **`dybatpho::screen_pending` — keep a screen in step with a held key.** It
  reports whether a key or a resize is already waiting, without reading it. An
  input loop that handles every waiting event before drawing the next frame no
  longer falls behind a key held down, and stops moving as soon as the key is
  released instead of seconds later. `example/screen_top.sh` drains its input
  this way.

### Changed

- **Colour is now decided in one place, and the decision takes the stream into
  account.** `logging`, `tui`, `diff` and `screen` each answered this
  differently: `logging` and `tui` looked only at `NO_COLOR`, `screen` only
  downgraded its `dusk` theme, and `diff` alone checked whether the output was
  a terminal. None of them honoured `FORCE_COLOR`. All four now defer to
  `dybatpho::color_supported`, keeping their own overrides — `DYBATPHO_DIFF_COLOR`
  and `DYBATPHO_TUI` are unchanged.

  What a consumer will notice:

  - A log line redirected to a file or a pipe no longer carries escape
    sequences. Previously it did, while a diff written beside it did not.
  - `FORCE_COLOR` now works everywhere, so a script piped into `less -R` or a
    CI log viewer can keep its colour.
  - `TERM=dumb` now turns colour off.
  - `dybatpho::screen_theme default` is downgraded to `mono` when colour is
    not wanted, as `dusk` already was. It used to keep its own three colours
    under `NO_COLOR`.

  Set `FORCE_COLOR=1` to restore colour where output is not a terminal.

- **The generated reference in `docs/` covers the public API only.** Every
  internal `__dybatpho_*` helper is now tagged `@internal`, so the module
  pages list only the `dybatpho::` functions a script can rely on, and no
  longer bury them under hundreds of private helpers.

### Fixed

- **`logging` — a log line no longer kills a script that unset `NO_COLOR`.**
  The renderer read `${NO_COLOR}` bare, so after `unset NO_COLOR` every log
  call under `set -u` stopped the script with `NO_COLOR: unbound variable`.
  An unset `NO_COLOR` now means colour, the same as an empty one.
- **`screen` — stderr no longer disappears after `dybatpho::screen_end`.**
  Closing the terminal ran `exec {fd}>&- 2> /dev/null`, and an `exec` without a
  command keeps its redirections, so every message the script wrote after
  giving the terminal back -- including its errors -- went to `/dev/null`.
- **`screen` — the divider between tabs and the active tab no longer ignore
  the configured styles.** The divider was always dim and the active tab
  always reversed; they now follow `DYBATPHO_SCREEN_STYLE_DIM` and
  `DYBATPHO_SCREEN_STYLE_TAB_ACTIVE`.
- **`screen` — a held arrow key no longer outruns a bordered screen.** Text painted inside
  a panel -- after its right border is already on the row -- rebuilt the
  row's whole list of style runs on every span, with several loops over it.
  It is now one pass, and a panel painted left to right only reads the runs to
  the right of the last span. A two-panel screen of 200x50 draws a frame about
  a quarter faster, and the scrollbar about two and a half times faster.

## [5.1.0] - 2026-09-30

### Added

- **`queue` — a job queue on disk that outlives the script.** `parallel`
  needs its jobs up front and loses them if the run dies; this is the other
  half. A producer can add work while workers are draining, and a crashed run
  resumes.

  A job is claimed, not consumed: `dybatpho::queue_pop` moves it to `claimed`
  and it stays there until the worker says what happened, so a worker that
  dies leaves its job where it can be found.

  `dybatpho::queue_push`, `dybatpho::queue_pop`, `dybatpho::queue_peek`,
  `dybatpho::queue_len`, `dybatpho::queue_list`, `dybatpho::queue_read`,
  `dybatpho::queue_complete`, `dybatpho::queue_requeue` and
  `dybatpho::queue_dead_letter`. `DYBATPHO_QUEUE_DIR` sets where a bare queue
  name lives, `DYBATPHO_QUEUE_TIMEOUT` how long an operation waits for the
  lock.

  ```sh
  . dybatpho/init.sh --modules queue

  dybatpho::queue_push deploys "restart api"

  while dybatpho::queue_pop deploys id payload; do
    if handle "${payload}"; then
      dybatpho::queue_complete deploys "${id}"
    else
      dybatpho::queue_requeue deploys "${id}" 3
    fi
  done
  ```

  Claiming takes the queue's lock, so concurrent workers never run the same
  job twice. Ordering is strict FIFO: the sequence in a job's id is handed out
  under that lock rather than read from a clock that cannot separate two
  pushes in the same second. A job requeued past its budget is dead-lettered
  with its payload rather than dropped.

- **`diff` — show what changed, the same way everywhere.** A colored unified
  diff for text, and a structural comparison for JSON and YAML that answers
  which keys moved rather than which lines did, so reordering or reformatting
  a document reports nothing.

  `dybatpho::diff_text`, `dybatpho::diff_summary`, `dybatpho::diff_json` and
  `dybatpho::diff_yaml`. `DYBATPHO_DIFF_COLOR` decides coloring and
  `DYBATPHO_DIFF_CONTEXT` how much context a diff carries.

  ```sh
  . dybatpho/init.sh --modules diff

  if ! dybatpho::diff_text /etc/app.conf "${rendered}" current proposed; then
    dybatpho::info "Change: $(dybatpho::diff_summary /etc/app.conf "${rendered}" || true)"
  fi
  dybatpho::diff_json state-before.json state-after.json
  ```

  The coloring is done by the module rather than by `diff --color`, which only
  GNU has, so the output is the same on GNU, BSD and BusyBox. Exit codes are
  `diff`'s own, so a call reads as a question in a conditional. `diff_text`
  needs no external command; comparing by key needs `jq`, and `diff_yaml`
  additionally `yq`.

- **`backup` — snapshot something, keep the last N, drop the rest.** The
  retention loop that log rotation, pre-change config snapshots and local
  database dumps each rewrite, with the off-by-one settled once. A backup is
  written under a hidden temporary name and renamed into place, so an
  interrupted run leaves nothing a later restore would trust, and a checksum
  sidecar is written beside it.

  `dybatpho::backup_create`, `dybatpho::backup_list`,
  `dybatpho::backup_latest`, `dybatpho::backup_verify`,
  `dybatpho::backup_restore` and `dybatpho::backup_prune`. Set
  `DYBATPHO_BACKUP_EXTENSION` and `DYBATPHO_BACKUP_CHECKSUM_ALGORITHM` to
  change the archive format or the sidecar's algorithm.

  ```sh
  . dybatpho/init.sh --modules backup

  archive="$(dybatpho::backup_create /etc/nginx /var/backups nginx)"
  dybatpho::backup_prune --keep-count 7 --name nginx --force /var/backups
  dybatpho::backup_restore --force "$(dybatpho::backup_latest /var/backups nginx)" /etc
  ```

  Backups are named with a UTC timestamp, so sorting them by name is sorting
  them by age. A prune with no policy is refused rather than treated as "keep
  nothing", a backup survives when any given policy keeps it, and every
  deletion goes through `dybatpho::safe_rm`, so `DRY_RUN` and the confirmation
  behave as they do elsewhere.

- **`csv` — read the CSV that `awk -F,` gets wrong.** A field may contain the
  delimiter, a doubled quote, or a line break, and none of them end the field.
  Rows come back as an array of records; `dybatpho::csv_fields` splits one into
  its values.

  `dybatpho::csv_read`, `dybatpho::csv_fields`, `dybatpho::csv_write`,
  `dybatpho::csv_header`, `dybatpho::csv_col`, `dybatpho::csv_filter`,
  `dybatpho::csv_to_json` and `dybatpho::csv_from_json`. Set
  `DYBATPHO_CSV_DELIMITER` for the files that use `;` or a tab.

  ```sh
  . dybatpho/init.sh --modules csv

  dybatpho::csv_filter billing.csv "cost" gt 100 > expensive.csv
  dybatpho::csv_read billing.csv rows
  dybatpho::csv_fields "${rows[1]}" first
  dybatpho::csv_to_json billing.csv | jq '[.[] | .cost |= tonumber]'
  ```

  Reading and writing need no external command; only the JSON conversion asks
  for `jq` or `yq`. Values convert as text, because CSV carries no types and
  guessing them is how an identifier with leading zeros becomes a number. A row
  with more fields than its header stops the script rather than losing one.

- **`markdown` — build a report, a pull request body or release notes from
  escaped pieces instead of a heredoc.** Every builder escapes the text it is
  given, so a commit subject containing `*`, a filename containing `[` or a cell
  containing `|` renders as the text it was. `dybatpho::md_raw` marks a fragment
  that is already Markdown so the surrounding escape leaves it alone.

  `dybatpho::md_heading`, `dybatpho::md_list`, `dybatpho::md_task_list`,
  `dybatpho::md_link`, `dybatpho::md_badge`, `dybatpho::md_code_block`,
  `dybatpho::md_table`, `dybatpho::md_collapsible`, `dybatpho::md_mention`,
  `dybatpho::md_emoji`, `dybatpho::md_raw` and `dybatpho::md_escape`.

  ```sh
  . dybatpho/init.sh --modules markdown

  dybatpho::md_heading 2 "What changed"
  dybatpho::md_list "$(git log --format=%s "${previous}..HEAD")"
  dybatpho::md_task_list $'x|Tag the commit\n|Announce the release'
  dybatpho::md_collapsible "Full build log" "$(dybatpho::md_code_block '' "${log}")"
  ```

  The code block fence grows past any fence inside its body, a link's URL is
  percent-encoded, and `dybatpho::md_table` renders through `table`.

### Changed

- **`dybatpho::assert_snapshot` renders a mismatch through the `diff`
  module** instead of dumping a raw `diff -u`, so a failing snapshot reads
  like every other comparison the library prints and carries color where the
  terminal takes it. The assertion's contract is unchanged.

- **`dybatpho::table_csv` now names the parser to use** when it refuses a
  quoted field, instead of only saying that it will not split one. The refusal
  and `DYBATPHO_TABLE_CSV_STRICT=false` are unchanged; the message points at
  `dybatpho::csv_read` and `dybatpho::csv_write`.

## [5.0.0] - 2026-09-30

### Added

- **`screen` — full-screen terminal applications: a layout solver, a widget
  set, and an event loop.** `tui` draws beside a script's output; this takes
  the whole terminal, which is what a process browser, a log viewer or a picker
  with a preview pane needs. It is the `ratatui` shape in Bash.

  ```sh
  . dybatpho/init.sh --modules screen

  dybatpho::screen_begin || dybatpho::die "No terminal"
  while true; do
    dybatpho::screen_clear
    dybatpho::screen_layout rows vertical "${DYBATPHO_SCREEN_RECT}" length:1 fill:1
    dybatpho::screen_tabs "${rows[0]}" tabs active:"${tab}"
    dybatpho::screen_block "${rows[1]}" title:"Pods" border:rounded
    dybatpho::screen_list "${DYBATPHO_SCREEN_INNER}" pods selected:"${cursor}"
    dybatpho::screen_flush

    dybatpho::screen_event key
    case "${key}" in
      char:q | escape) break ;;
      down) cursor=$((cursor + 1)) ;;
      resize) dybatpho::screen_size || true ;;
    esac
  done
  dybatpho::screen_end
  ```

  `dybatpho::screen_layout` splits a rectangle with the constraints `length:`,
  `percent:`, `ratio:`, `min:`, `max:` and `fill:`, always tiling it exactly.
  The widgets are `dybatpho::screen_block`, `screen_text`, `screen_list`,
  `screen_table`, `screen_gauge`, `screen_tabs`, `screen_scrollbar`,
  `screen_sparkline`, `screen_barchart`, `screen_chart` — a Braille line chart
  at two points across and four down per character — and `screen_popup`, which
  erases what it covers. `dybatpho::screen_event` reports keys, arrows,
  navigation keys, mouse buttons with a zero-based position, resizes and end of
  input as names, so an input loop never parses an escape sequence.

  `dybatpho::screen_begin` switches to the alternate screen, enters raw mode
  and hides the cursor, and registers the restore on `EXIT`, `INT` and `TERM`,
  so an application that crashes still gives the terminal back. It draws on
  `/dev/tty` rather than stdout, so an application can still print a result
  that a caller captures.

  Widths come from embedded Unicode tables rather than from another program, so
  CJK text and emoji stay on the column grid with no `python3` and no `wcwidth`
  binary, in a UTF-8 locale or the C one.

  The frame buffer holds rows rather than cells. `ratatui`'s per-cell model
  measures at about 50 microseconds a cell in Bash — half a second for one
  frame of a 200x50 terminal, and it is the per-cell loop that costs, so a
  smarter diff does not rescue it. Rows, styles kept as runs, and a per-row
  skip when nothing changed bring a realistic 80x24 frame to about 18
  milliseconds and a 200x50 one to about 38, which is fast enough to repaint on
  every keystroke.

  Requires `stty`, now declared for the module in `dybatpho::doctor`.

  `example/screen_top.sh` is a working process viewer built on it — a sortable,
  filterable, scrollable table of every process, with CPU and memory gauges,
  history sparklines, a detail panel and a confirmation dialog before a signal
  is sent. Run it with `bash example/screen_top.sh`; with no terminal it
  renders one frame and exits, which is what `--once` forces.

- **`validate` — one validator for the whole library.** Every module that took
  a value from outside wrote its own check: `config` matched an integer with
  one regular expression and a URL with another, `cli` matched a shell variable
  name with a third, and a script that wanted an email address, a port or an
  existing directory wrote a fourth. The expressions drifted, the messages
  drifted with them, and the set of checks stopped at whatever those two
  modules happened to need.

  ```sh
  . dybatpho/init.sh --modules validate

  dybatpho::validate_is email "${contact}" || dybatpho::die "Not an address"
  dybatpho::validate_or_die "--release" "${version}" type:semver

  if ! dybatpho::validate_value "${port}" type:int min:1 max:65535; then
    dybatpho::error "$(dybatpho::validate_errors)" # every violation, not the first
  fi

  function _is_service { [[ "$1" =~ ^[a-z]+-(api|worker)$ ]]; }
  dybatpho::validate_register service _is_service "a service name"
  ```

  `dybatpho::validate_is` answers for a named type; `dybatpho::validate_types`
  lists them. The built-ins cover `string`, `nonempty`, `int`, `uint`,
  `number`, `bool`, `port`, `email`, `url`, `hostname`, `ipv4`, `ipv6`, `ip`,
  `cidr`, `mac`, `semver`, `uuid`, `hex`, `alpha`, `alnum`, `slug`,
  `identifier`, `date`, `time`, `duration`, and the path types `path`, `file`,
  `dir`, `symlink`, `readable`, `writable`, `executable`, `abspath` and
  `parent_dir`. `dybatpho::validate_value` applies `type:`, `pattern:`,
  `choices:`, `min:`, `max:`, `minlen:` and `maxlen:` together and records
  every violation, which `dybatpho::validate_errors` prints and
  `dybatpho::validate_or_die` turns into a fatal `Invalid <label>: <reason>`.
  `dybatpho::validate_matches` applies a regular expression and turns a
  malformed one into the library's own error rather than a silent non-match.
  `dybatpho::validate_register` adds a type of your own, with `numeric` to make
  its bounds count the value rather than the characters, and
  `dybatpho::validate_reset` puts the registry back.

  The awkward cases are handled rather than avoided: a number with leading
  zeros, a fraction or an exponent compares correctly although shell arithmetic
  reads none of them, a date is checked against the length of its month, an
  IPv4 octet with a leading zero is refused because `inet_aton` reads it as
  octal, and `abspath` answers about a file that does not exist yet. `ipv4`,
  `ipv6` and `semver` are pinned by tests against `dybatpho::is_ipv4`,
  `dybatpho::is_ipv6` and `dybatpho::semver_valid` so the two cannot drift.

- **`config` — a schema key can declare any validated type.** `string`, `int`,
  `bool`, `url` and `enum` were the whole vocabulary. A key may now declare
  anything `dybatpho::validate_types` prints, including a type registered by
  the script, and a rejected value is described the same way it would be
  anywhere else in the library.

  ```sh
  dybatpho::config_schema ADMIN_EMAIL email required:true
  dybatpho::config_schema LISTEN_PORT port default:8080 min:1024 max:65535
  dybatpho::config_schema WORKDIR dir required:true
  # Invalid configuration `ADMIN_EMAIL`: expected an email address, got `ops@`
  ```

  `min:` and `max:` bound the value for every numeric type rather than only for
  `int`, and the character count for everything else, as before.

- **`cli` — `type:<name>` constrains an option to a validated type.** Checking
  a value meant either a `pattern:` glob or a `validate:` function of your own.

  ```sh
  dybatpho::opts::param "Port" PORT --port type:port
  dybatpho::opts::param "Contact" EMAIL --contact type:email
  # --port 65536  ->  Expected a port number: 65536
  ```

  A spec naming a type nobody registered fails while the parser is generated
  rather than when a user first types a value. The declared type is annotated
  in `--help` and the man page as `[type: ...]` and carried into the generated
  JSON schema as `valueType`.
- **`tui` — spinners, progress bars, arrow-key menus and confirmations that
  also work with no terminal.** `cli` covered everything up to the moment a
  script starts talking to a person, and stopped there. Asking a question meant
  hand-rolling ANSI escapes and raw key reading, plus a second code path for
  the unattended case — which is where hand-rolled widgets fail: a menu hangs
  in CI, a `\r` progress bar fills a log with part-drawn lines, and a widget
  that prints to stdout corrupts the value the script was computing.

  ```sh
  . dybatpho/init.sh --modules tui

  dybatpho::tui_menu environment "Deploy where?" dev staging prod \
    || dybatpho::die "No environment chosen"
  dybatpho::tui_multi_menu components "Which components?" api worker scheduler
  dybatpho::tui_confirm "Deploy ${components[*]} to ${environment}?" \
    || dybatpho::die "Cancelled"

  dybatpho::tui_spinner_start "Resolving the release"
  dybatpho::tui_spinner_message "Resolving api"
  dybatpho::tui_spinner_stop "$?" "Resolved"

  dybatpho::tui_progress_start "Uploading" "${#components[@]}"
  for component in "${components[@]}"; do
    _upload "${component}"
    dybatpho::tui_progress_step 1 "Uploading ${component}"
  done
  dybatpho::tui_progress_stop "Uploaded ${#components[@]} components"
  ```

  Every widget has two renderings and the module picks between them, so the
  same calls work in both places. On a terminal `dybatpho::tui_menu` and
  `dybatpho::tui_multi_menu` draw a pointer, move on the arrow keys or `j`/`k`,
  toggle on `space`, scroll once the list is longer than the window, and cancel
  on `esc`; `dybatpho::tui_confirm` draws both answers with the default
  highlighted. With the streams captured — CI, a pipe, a `$( )` — the menus
  become numbered prompts read through `dybatpho::prompt`, and
  `dybatpho::tui_confirm` is `dybatpho::confirm`, keeping its `DYBATPHO_FORCE`
  override and its refusal to guess in an unattended shell.
  `dybatpho::tui_supported` reports which rendering is in force, and
  `DYBATPHO_TUI` overrides the detection in both directions.

  Everything the module draws goes to stderr, including its closing banners, so
  a value on stdout stays usable in a command substitution; the menus return
  their answer through a named variable for the same reason, and a multi-select
  returns an array so entries containing spaces survive. A menu that can
  neither ask nor read `DYBATPHO_TUI_DEFAULT` fails rather than choosing an
  entry silently.

  `dybatpho::spinner` still wraps one command;
  `dybatpho::tui_spinner_start`/`_message`/`_stop` bracket a region instead,
  which is what a loop or a pipeline needs, and stopping returns the status it
  was given so one call both reports and propagates an outcome. Progress is
  driven with `dybatpho::tui_progress_start`, `_update`, `_step` and `_stop`;
  off a terminal it logs on a percentage grid rather than once per update, so a
  thousand-item loop leaves a bounded log. `dybatpho::tui_bar` renders a bar as
  plain text on its own, for a script that already tracks its own progress.

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

- **The generated documentation moved from `doc/` to `docs/`.** Every link into
  it changes: `doc/logging.md` is now `docs/logging.md`, and the
  specifications sit under `docs/spec/`. It is also the layout `sh-docs`
  defaults to, so `scripts/docs.sh` no longer has to describe this repository
  to it.

- **The documentation generator is now the standalone `sh-docs` project.**
  `scripts/genshdoc.awk` was a copy of it maintained inside this repository, so
  every fix had to be made twice. It is gone; `scripts/sh-docs` is a submodule
  of [sh-docs](https://gitlab.com/dynamo-tools/sh-docs) and `scripts/docs.sh`
  drives it.

  Clone with `--recurse-submodules`, or run
  `git submodule update --init scripts/sh-docs` before `scripts/docs.sh`; it
  says so itself when the submodule is missing.

  Every file under `docs/` is regenerated: the stray double blank lines between
  overview paragraphs are gone, an indented `@description` continuation is
  dedented, and `@set` renders its type column like `@arg` and `@env` do.

- **`scripts/lint.sh` checks the code against the Bash coding style guide, not
  only against ShellCheck.** The `shell` stage now runs
  [`dyshellint`](https://github.com/dynamotn/dyshellint), which reports the
  guide's own rules (`BSG###`), ShellCheck (`SC####`) and shfmt (`FMT001`) as a
  single list, reading the same `.shellcheckrc` as before. The rules the guide
  states — namespaced functions, `dybatpho::expect_args`, shdoc headers, line
  length — were prose a reviewer had to remember; they are now checked.

  ```sh
  scripts/lint.sh --stage shell # dyshellint and `bash -n`
  ```

  `dyshellint` is required for that stage, and the CI lint job installs it —
  along with the ShellCheck and shfmt it drives — at their latest release, so
  a new rule reaches the job as soon as it ships. The repository does not satisfy the
  full rule set yet, so the stage reports a backlog that is being worked down;
  `bash -n`, the changelog, documentation and bundle stages are unaffected.

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

- **`dybatpho::array_sort` no longer slows to a crawl on a real list.** It was
  an insertion sort, which pays a comparison per pair: 2000 elements — a
  directory listing, an installed-package list, a tag list — took 39 seconds,
  and every element added cost more than the last. It is a bottom-up merge sort
  now, so the same 2000 elements sort in about 1 second and 5000 in about 3,
  where the old one would have spent minutes.

  The comparison is unchanged and still lives in one place, so locale
  collation, `--numeric` and `--reverse` decide the order exactly as before. An
  element containing a newline still survives, since nothing is piped through
  `sort(1)`. The new sort is also stable: values that compare equal keep the
  order they arrived in, which is what lets a caller sort by one field without
  scrambling the rest.

- **`dybatpho::json_string` quotes in the shell instead of forking a JSON
  tool.** Escaping a string is the one JSON operation that needs no parser, yet
  every call started `yq` or `jq` and waited ~12ms for it — enough to dominate
  any loop building a request body or a structured log line. Quoting is now
  done in Bash, which is roughly 80× faster and makes this the one JSON helper
  that works on a host with neither tool installed.

  The output is byte-for-byte what `jq -Rs .` produced, control characters and
  `DEL` included. UTF-8 is passed through rather than escaped, so the result
  stays readable; the walk is by character and the control-character test is by
  code point, so a multi-byte character is never cut in half or mistaken for
  one.

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

- **`dybatpho::file_hash` returned a corrupt digest for some file names.** Given
  a path holding a newline or a backslash, `sha256sum` and friends quote the
  name: the whole line is prefixed with `\`, so taking the first field handed
  back `\<digest>` and every comparison against it — `dybatpho::verify_checksum`
  included — failed on a file that was perfectly fine. The file now goes in on
  standard input, which has no name to quote and is the one spelling the GNU
  tools, `shasum`, `md5` and `openssl` all accept.

- **`LOG_FORMAT=json` produced lines no JSON parser would read.** Only
  backslash, quote, newline, carriage return and tab were escaped, and JSON
  forbids every other raw control character inside a string. A message carrying
  an ANSI colour sequence — which is what logging the output of any coloured
  command gives you — made the whole event invalid, and a log shipper drops an
  invalid line without saying so. `\b` and `\f` are now spelled out and
  anything else below `0x20`, plus `DEL`, goes out as `\u00XX`. UTF-8 is
  untouched.

- **A notification carrying a control character was refused by the webhook.**
  `notification` had its own copy of the same five-character escaper, so a
  Slack, Telegram, Teams, Google Chat or Discord message quoting the output of
  a failed command built a payload the API rejected — the message simply never
  arrived. It now uses the `logging` escaper, which is core and always loaded,
  rather than a second copy that can drift.

- **`dybatpho::string_slugify` threw away every accented letter.** Anything
  outside `a-z0-9` counted as a separator, so `Thế Giới` slugged to `th-gi-i`
  and `Crème brûlée` to `cr-me-br-l-e` — slugs that name nothing, and that
  collide between titles which have nothing in common. A letter carrying a
  diacritic now becomes the ASCII letter underneath it (`the-gioi`,
  `creme-brulee`), `ß`, `æ` and `œ` expand to the two letters they stand for,
  and a combining mark in decomposed text comes off without splitting the word
  in two.

### Security

- **A CLI built on `dybatpho::opts` ran whatever an argument value asked it
  to.** `dybatpho::generate_from_spec` wrote the script's arguments into the
  generated parser file as shell source and then sourced that file, quoting
  only `"`. Inside double quotes `$`, a backtick and a backslash are still
  live, so `--name '$(id)'` ran `id` before the parser had even looked at the
  value, `--name '$HOME'` came out expanded, and a value ending in a backslash
  escaped the closing quote and left the file unparseable — the CLI then died
  with a bash syntax error. A positional argument went the same way.

  Any script whose arguments are not entirely under the author's control was
  therefore a way to run commands: a branch name, a ticket title or a file name
  coming from CI was enough. The generated file now only defines parsers, and
  `dybatpho::generate_from_spec` calls the one it needs with the real argument
  vector, so nothing a caller typed is ever read as shell source.

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

- **A stale lock could be handed to two processes at once.** Reclaiming one was
  a check followed by a delete. Two runs that both found the dead holder both
  decided to reclaim: the first removed the lock and took it, and the second
  then removed *that* — a live lock — and took it as well. Both believed they
  held it, which is the one thing a lock exists to prevent, and it happened
  exactly when a lock is reclaimed, after a crash.

  Reclaiming is a rename now. `rename()` fails when the source is gone, so of
  two processes racing to move the same lock aside exactly one succeeds and the
  loser touches nothing. The identity recorded in the lock is re-read from the
  moved-aside copy and compared with the one that was judged stale; they differ
  only when the lock changed hands in between, and that lock is put back rather
  than deleted.

- **`dybatpho::create_temp` left a symlink attack open where `mktemp` is
  missing.** On that fallback path the name was the prefix and the pid — fully
  predictable — and the file was made with `touch`, which follows a symbolic
  link someone else planted at that name and writes through to its target. The
  name now carries 32 random bits, the file is opened under `set -C` so an
  existing name (a link included) is refused rather than followed, and both the
  file and the directory form are created under `umask 077`.

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

- **`scripts/docs.sh --check`.** Generates into a temporary directory and
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

- **`scripts/docs.sh` read its arguments as a string, and the documentation
  guard quietly stopped guarding.** `dybatpho::opts::setup` collects positional
  arguments into a Bash array, which the positional-argument rework made
  explicit. This script was not updated with it and still expanded the array as
  a scalar, which is wrong in both directions: with arguments, `"${DOC_ARGS}"`
  is element zero, so `scripts/docs.sh src/a.sh src/b.sh` documented only
  `src/a.sh`; with none, an empty array is unset, so `errexit` ended the source
  listing inside the process substitution that feeds the loop.

  The second case is the damaging one. The loop simply read nothing, so
  `scripts/docs.sh --check` compared no documents and reported that everything
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

[Unreleased]: https://github.com/dynamotn/dybatpho/compare/v5.2.0...HEAD
[5.2.0]: https://github.com/dynamotn/dybatpho/compare/v5.1.0...v5.2.0
[5.1.0]: https://github.com/dynamotn/dybatpho/compare/v5.0.0...v5.1.0
[5.0.0]: https://github.com/dynamotn/dybatpho/compare/v4.0.0...v5.0.0
[4.0.0]: https://github.com/dynamotn/dybatpho/compare/v3.0.0...v4.0.0
[3.0.0]: https://github.com/dynamotn/dybatpho/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/dynamotn/dybatpho/releases/tag/v2.0.0
