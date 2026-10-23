# Changelog: 4.x releases

Releases 4.x of dybatpho, archived from [CHANGELOG.md](../../CHANGELOG.md) by
`scripts/changelog_archive.sh`. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[4.0.0]: https://github.com/dynamotn/dybatpho/compare/v3.0.0...v4.0.0
