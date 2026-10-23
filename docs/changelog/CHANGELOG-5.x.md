# Changelog: 5.x releases

Releases 5.x of dybatpho, archived from [CHANGELOG.md](../../CHANGELOG.md) by
`scripts/changelog_archive.sh`. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.2.0] - 2026-10-02

### Added

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

[5.2.0]: https://github.com/dynamotn/dybatpho/compare/v5.1.0...v5.2.0
[5.1.0]: https://github.com/dynamotn/dybatpho/compare/v5.0.0...v5.1.0
[5.0.0]: https://github.com/dynamotn/dybatpho/compare/v4.0.0...v5.0.0
