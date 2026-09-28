setup() {
  load test_helper
}

teardown() {
  # A test that registers a type of its own must not leak it into the next one.
  dybatpho::validate_reset
}

# ---------------------------------------------------------------------------
# dybatpho::validate_is
# ---------------------------------------------------------------------------

@test "dybatpho::validate_is accepts numbers of each numeric type" {
  dybatpho::validate_is int "42"
  dybatpho::validate_is int "-7"
  dybatpho::validate_is int "+7"
  dybatpho::validate_is uint "0"
  dybatpho::validate_is number "1.5"
  dybatpho::validate_is number "-0.25"
  dybatpho::validate_is number "1e3"
}

@test "dybatpho::validate_is rejects values that only look numeric" {
  run dybatpho::validate_is int "1.5"
  assert_failure

  run dybatpho::validate_is uint "-1"
  assert_failure

  run dybatpho::validate_is number "twelve"
  assert_failure

  run dybatpho::validate_is int ""
  assert_failure
}

@test "dybatpho::validate_is reads a boolean in either direction and any case" {
  dybatpho::validate_is bool "true"
  dybatpho::validate_is bool "FALSE"
  dybatpho::validate_is bool "yes"
  dybatpho::validate_is bool "off"
  dybatpho::validate_is bool "1"

  run dybatpho::validate_is bool "maybe"
  assert_failure
}

@test "dybatpho::validate_is bounds a port to the range a port can have" {
  dybatpho::validate_is port "1"
  dybatpho::validate_is port "8080"
  dybatpho::validate_is port "65535"

  # Port 0 asks the kernel to choose rather than naming a port.
  run dybatpho::validate_is port "0"
  assert_failure

  run dybatpho::validate_is port "65536"
  assert_failure

  # A long run of digits would overflow before it could be compared.
  run dybatpho::validate_is port "99999999999999999999"
  assert_failure
}

@test "dybatpho::validate_is accepts practical email addresses and rejects typos" {
  dybatpho::validate_is email "ops@example.com"
  dybatpho::validate_is email "first.last+tag@sub.example.co.uk"

  run dybatpho::validate_is email "ops@example"
  assert_failure

  run dybatpho::validate_is email "ops.example.com"
  assert_failure

  run dybatpho::validate_is email "@example.com"
  assert_failure

  run dybatpho::validate_is email "ops@-example.com"
  assert_failure
}

@test "dybatpho::validate_is requires a scheme and an authority in a URL" {
  dybatpho::validate_is url "https://example.com/health"
  dybatpho::validate_is url "postgres://user@db:5432/app"

  run dybatpho::validate_is url "example.com"
  assert_failure

  run dybatpho::validate_is url "mailto:ops@example.com"
  assert_failure

  run dybatpho::validate_is url "https://exa mple.com"
  assert_failure
}

@test "dybatpho::validate_is checks host names label by label" {
  dybatpho::validate_is hostname "example.com"
  dybatpho::validate_is hostname "db-01.internal"
  dybatpho::validate_is hostname "example.com."

  run dybatpho::validate_is hostname "-example.com"
  assert_failure

  run dybatpho::validate_is hostname "exa_mple.com"
  assert_failure

  local too_long
  too_long="$(dybatpho::string_repeat "a" 64)"
  run dybatpho::validate_is hostname "${too_long}.com"
  assert_failure
}

@test "dybatpho::validate_is accepts IP addresses of both versions" {
  dybatpho::validate_is ipv4 "192.0.2.10"
  dybatpho::validate_is ipv6 "::1"
  dybatpho::validate_is ipv6 "2001:db8::1"
  dybatpho::validate_is ipv6 "::ffff:192.0.2.1"
  dybatpho::validate_is ip "192.0.2.10"
  dybatpho::validate_is ip "2001:db8::1"

  run dybatpho::validate_is ipv4 "192.0.2.256"
  assert_failure

  # A leading zero is read as octal by much of the software downstream, so an
  # address that means two things is refused rather than guessed at.
  run dybatpho::validate_is ipv4 "127.0.0.010"
  assert_failure

  run dybatpho::validate_is ipv6 "2001:db8::1::2"
  assert_failure

  # A zone index names an interface rather than a part of the address.
  run dybatpho::validate_is ipv6 "fe80::1%eth0"
  assert_failure
}

@test "dybatpho::validate_is answers IP questions the same way the network module does" {
  # `network` owns the richer parser and `validate` owns the shared predicate.
  # They are two implementations of one rule, so they are pinned against each
  # other here: a fix to one that does not reach the other fails this test.
  local address expected actual
  for address in \
    "192.0.2.10" "192.0.2.256" "127.0.0.010" "0.0.0.0" "255.255.255.255" \
    "1.2.3" "1.2.3.4.5" "01.2.3.4" ""; do
    expected=no && dybatpho::is_ipv4 "${address}" && expected=yes
    actual=no && dybatpho::validate_is ipv4 "${address}" && actual=yes
    assert_equal "ipv4 ${address} ${actual}" "ipv4 ${address} ${expected}"
  done
  for address in \
    "::1" "2001:db8::1" "::ffff:192.0.2.1" "2001:db8::1::2" "fe80::1%eth0" \
    "::" "1:2:3:4:5:6:7:8" "1:2:3:4:5:6:7" "1:2:3:4:5:6:7:8:9" "abcd::12345" \
    "1:2:3:4:5:6:1.2.3.4" "::192.0.2.1" "1::" ""; do
    expected=no && dybatpho::is_ipv6 "${address}" && expected=yes
    actual=no && dybatpho::validate_is ipv6 "${address}" && actual=yes
    assert_equal "ipv6 ${address} ${actual}" "ipv6 ${address} ${expected}"
  done
}

@test "dybatpho::validate_is checks a CIDR prefix against the address version" {
  dybatpho::validate_is cidr "10.0.0.0/8"
  dybatpho::validate_is cidr "2001:db8::/32"

  run dybatpho::validate_is cidr "10.0.0.0/33"
  assert_failure

  run dybatpho::validate_is cidr "2001:db8::/129"
  assert_failure

  run dybatpho::validate_is cidr "10.0.0.0"
  assert_failure
}

@test "dybatpho::validate_is accepts a MAC address with one separator" {
  dybatpho::validate_is mac "00:1b:44:11:3a:b7"
  dybatpho::validate_is mac "00-1B-44-11-3A-B7"

  run dybatpho::validate_is mac "00:1b-44:11:3a:b7"
  assert_failure

  run dybatpho::validate_is mac "00:1b:44:11:3a"
  assert_failure
}

@test "dybatpho::validate_is answers semver the same way the semver module does" {
  local version expected actual
  for version in \
    "1.2.3" "v1.2.3" "1.2" "1.0.0-alpha.1" "1.0.0+build.42" \
    "1.0.0-beta.2+exp.sha.5114f85" "not-a-version" ""; do
    expected=no && dybatpho::semver_valid "${version}" && expected=yes
    actual=no && dybatpho::validate_is semver "${version}" && actual=yes
    assert_equal "${version} ${actual}" "${version} ${expected}"
  done
}

@test "dybatpho::validate_is recognizes identifiers, slugs and text shapes" {
  dybatpho::validate_is uuid "123e4567-e89b-12d3-a456-426614174000"
  dybatpho::validate_is hex "0xdeadBEEF"
  dybatpho::validate_is alpha "Deploy"
  dybatpho::validate_is alnum "deploy2"
  dybatpho::validate_is slug "deploy-to-prod"
  dybatpho::validate_is identifier "_MY_VAR2"
  dybatpho::validate_is nonempty " x "

  run dybatpho::validate_is uuid "123e4567-e89b-12d3-a456-42661417400"
  assert_failure

  run dybatpho::validate_is slug "Deploy-To-Prod"
  assert_failure

  run dybatpho::validate_is identifier "2fast"
  assert_failure

  run dybatpho::validate_is nonempty "   "
  assert_failure
}

@test "dybatpho::validate_is checks a date against the length of its month" {
  dybatpho::validate_is date "2024-02-29"
  dybatpho::validate_is date "2023-12-31"
  dybatpho::validate_is time "23:59"
  dybatpho::validate_is time "08:30:15"

  run dybatpho::validate_is date "2023-02-29"
  assert_failure

  run dybatpho::validate_is date "2023-13-01"
  assert_failure

  run dybatpho::validate_is date "2023-04-31"
  assert_failure

  run dybatpho::validate_is time "24:00"
  assert_failure
}

@test "dybatpho::validate_is reads a duration with or without units" {
  dybatpho::validate_is duration "30"
  dybatpho::validate_is duration "1h30m"
  dybatpho::validate_is duration "500ms"

  run dybatpho::validate_is duration "1hour"
  assert_failure
}

@test "dybatpho::validate_is asks the filesystem about the path types" {
  local file="${BATS_TEST_TMPDIR}/present.txt"
  printf 'body\n' > "${file}"
  ln -s "${file}" "${BATS_TEST_TMPDIR}/link"

  dybatpho::validate_is path "${file}"
  dybatpho::validate_is file "${file}"
  dybatpho::validate_is dir "${BATS_TEST_TMPDIR}"
  dybatpho::validate_is symlink "${BATS_TEST_TMPDIR}/link"
  dybatpho::validate_is readable "${file}"
  dybatpho::validate_is writable "${file}"
  dybatpho::validate_is abspath "/etc/hosts"
  # The file itself is about to be created; its directory has to be there.
  dybatpho::validate_is parent_dir "${BATS_TEST_TMPDIR}/not-created-yet.log"

  run dybatpho::validate_is file "${BATS_TEST_TMPDIR}/absent.txt"
  assert_failure

  run dybatpho::validate_is dir "${file}"
  assert_failure

  run dybatpho::validate_is abspath "relative/path"
  assert_failure

  run dybatpho::validate_is parent_dir "${BATS_TEST_TMPDIR}/absent-dir/file.log"
  assert_failure

  run dybatpho::validate_is executable "${file}"
  assert_failure
  chmod +x "${file}"
  dybatpho::validate_is executable "${file}"
}

@test "dybatpho::validate_is resolves the long form of a type name" {
  dybatpho::validate_is integer "42"
  dybatpho::validate_is boolean "yes"
  dybatpho::validate_is directory "${BATS_TEST_TMPDIR}"
  dybatpho::validate_is uri "https://example.com"
  dybatpho::validate_is INT "42"
}

@test "dybatpho::validate_is stops the script on a type nobody registered" {
  run --separate-stderr dybatpho::validate_is nosuchtype "value"
  assert_failure
  assert_stderr --partial "'nosuchtype' is not a known type"
}

# ---------------------------------------------------------------------------
# dybatpho::validate_matches
# ---------------------------------------------------------------------------

@test "dybatpho::validate_matches applies an extended regular expression" {
  dybatpho::validate_matches "v1.2.3" '^v[0-9]+\.[0-9]+\.[0-9]+$'

  run dybatpho::validate_matches "1.2.3" '^v[0-9]'
  assert_failure
}

@test "dybatpho::validate_matches turns a broken expression into a fatal error" {
  # Bash answers a malformed pattern with status 2 and a message of its own,
  # which at the call site reads as an ordinary "did not match".
  run --separate-stderr dybatpho::validate_matches "value" '['
  assert_failure
  assert_stderr --partial "is not a valid extended regular expression"
}

# ---------------------------------------------------------------------------
# dybatpho::validate_value and dybatpho::validate_errors
# ---------------------------------------------------------------------------

@test "dybatpho::validate_value accepts a value that satisfies every rule" {
  dybatpho::validate_value "8080" type:int min:1 max:65535
  assert_equal "$(dybatpho::validate_errors)" ""
}

@test "dybatpho::validate_value reports the type it expected" {
  run dybatpho::validate_value "http" type:int
  assert_failure

  dybatpho::validate_value "http" type:int || true
  assert_equal "$(dybatpho::validate_errors)" 'expected an integer, got `http`'
}

@test "dybatpho::validate_value bounds a numeric type by value and anything else by length" {
  dybatpho::validate_value "5" type:int min:1 max:10 || true
  assert_equal "$(dybatpho::validate_errors)" ""

  dybatpho::validate_value "50" type:int min:1 max:10 || true
  assert_equal "$(dybatpho::validate_errors)" "must be at most 10"

  dybatpho::validate_value "ab" type:string min:3 || true
  assert_equal "$(dybatpho::validate_errors)" "must be at least 3 characters"
}

@test "dybatpho::validate_value compares numbers the shell would get wrong" {
  # `((08 >= 1))` is a base-8 error and `((1.5 <= 2))` is a syntax error, and
  # both forms arrive from configuration files.
  dybatpho::validate_value "08" type:int min:1 max:10 || true
  assert_equal "$(dybatpho::validate_errors)" ""

  dybatpho::validate_value "1.5" type:number min:1 max:2 || true
  assert_equal "$(dybatpho::validate_errors)" ""

  dybatpho::validate_value "2.5" type:number max:2 || true
  assert_equal "$(dybatpho::validate_errors)" "must be at most 2"

  dybatpho::validate_value "-3" type:int min:-2 || true
  assert_equal "$(dybatpho::validate_errors)" "must be at least -2"
}

@test "dybatpho::validate_value applies minlen and maxlen whatever the type" {
  dybatpho::validate_value "8080" type:int minlen:2 maxlen:4 || true
  assert_equal "$(dybatpho::validate_errors)" ""

  dybatpho::validate_value "8" type:int minlen:2 || true
  assert_equal "$(dybatpho::validate_errors)" "must be at least 2 characters"
}

@test "dybatpho::validate_value restricts a value to a list of choices" {
  dybatpho::validate_value "prod" choices:dev,staging,prod || true
  assert_equal "$(dybatpho::validate_errors)" ""

  dybatpho::validate_value "qa" choices:dev,staging,prod || true
  assert_equal "$(dybatpho::validate_errors)" 'expected one of: dev,staging,prod, got `qa`'
}

@test "dybatpho::validate_value applies a regular expression rule" {
  dybatpho::validate_value "release/2.0" pattern:'^release/' || true
  assert_equal "$(dybatpho::validate_errors)" ""

  dybatpho::validate_value "main" pattern:'^release/' || true
  assert_equal "$(dybatpho::validate_errors)" 'expected a value matching `^release/`, got `main`'
}

@test "dybatpho::validate_value reports every violation rather than only the first" {
  dybatpho::validate_value "qa" choices:dev,prod pattern:'^p' maxlen:1 || true
  assert_equal "${#DYBATPHO_VALIDATE_ERRORS[@]}" 3
}

@test "dybatpho::validate_value stops measuring a value that is not of its type" {
  # `min:1` on something that is not a number has no answer worth reporting,
  # and a second message about it only buries the first.
  dybatpho::validate_value "http" type:int min:1 max:10 || true
  assert_equal "${#DYBATPHO_VALIDATE_ERRORS[@]}" 1
}

@test "dybatpho::validate_value stops the script on a malformed rule" {
  run --separate-stderr dybatpho::validate_value "x" nocolon
  assert_failure
  assert_stderr --partial "is not a \`name:value\` rule"

  run --separate-stderr dybatpho::validate_value "x" unknown:1
  assert_failure
  assert_stderr --partial "'unknown' is not a supported rule"

  run --separate-stderr dybatpho::validate_value "x" min:many
  assert_failure
  assert_stderr --partial "\`min\` needs a number"

  run --separate-stderr dybatpho::validate_value "x" choices:
  assert_failure
  assert_stderr --partial "needs at least one choice"

  run --separate-stderr dybatpho::validate_value "x" type:nosuchtype
  assert_failure
  assert_stderr --partial "'nosuchtype' is not a known type"
}

@test "dybatpho::validate_errors prints nothing after a value was accepted" {
  dybatpho::validate_value "42" type:int
  run dybatpho::validate_errors
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# dybatpho::validate_or_die
# ---------------------------------------------------------------------------

@test "dybatpho::validate_or_die returns quietly for a value it accepts" {
  run --separate-stderr dybatpho::validate_or_die "--port" "8080" type:port
  assert_success
  assert_output ""
}

@test "dybatpho::validate_or_die names the value and every reason it failed" {
  run --separate-stderr dybatpho::validate_or_die "--port" "http" type:int min:1
  assert_failure
  assert_stderr --partial 'Invalid --port: expected an integer, got `http`'

  run --separate-stderr dybatpho::validate_or_die "--env" "qa" choices:dev,prod maxlen:1
  assert_failure
  assert_stderr --partial "expected one of: dev,prod, got \`qa\`; must be at most 1 characters"
}

# ---------------------------------------------------------------------------
# dybatpho::validate_describe and dybatpho::validate_types
# ---------------------------------------------------------------------------

@test "dybatpho::validate_describe words a type the way a message needs it" {
  assert_equal "$(dybatpho::validate_describe int)" "an integer"
  assert_equal "$(dybatpho::validate_describe bool)" "a boolean"
  assert_equal "$(dybatpho::validate_describe url)" "a URL"
  assert_equal "$(dybatpho::validate_describe email)" "an email address"
  # An alias describes the type it resolves to.
  assert_equal "$(dybatpho::validate_describe integer)" "an integer"
}

@test "dybatpho::validate_describe stops the script on an unknown type" {
  run --separate-stderr dybatpho::validate_describe nosuchtype
  assert_failure
  assert_stderr --partial "'nosuchtype' is not a known type"
}

@test "dybatpho::validate_types lists the canonical names in order" {
  run dybatpho::validate_types
  assert_success
  assert_line "email"
  assert_line "int"
  assert_line "semver"
  # Aliases resolve to the names printed here rather than joining them.
  refute_line "integer"
  assert_equal "${lines[0]}" "abspath"
}

# ---------------------------------------------------------------------------
# dybatpho::validate_register and dybatpho::validate_reset
# ---------------------------------------------------------------------------

@test "dybatpho::validate_register adds a type usable everywhere a built-in is" {
  function _test_is_branch { [[ "$1" =~ ^(main|release/.+)$ ]]; }
  dybatpho::validate_register branch _test_is_branch "a release branch"

  dybatpho::validate_is branch "release/2.0"
  assert_equal "$(dybatpho::validate_describe branch)" "a release branch"

  run dybatpho::validate_is branch "topic/x"
  assert_failure

  dybatpho::validate_value "topic/x" type:branch || true
  assert_equal "$(dybatpho::validate_errors)" 'expected a release branch, got `topic/x`'
}

@test "dybatpho::validate_register can declare a type whose bounds are numeric" {
  function _test_is_weight { [[ "$1" =~ ^[0-9]+$ ]]; }
  dybatpho::validate_register weight _test_is_weight "a weight" numeric

  dybatpho::validate_value "500" type:weight max:100 || true
  assert_equal "$(dybatpho::validate_errors)" "must be at most 100"
}

@test "dybatpho::validate_register replaces a type that was already registered" {
  function _test_never { return 1; }
  dybatpho::validate_register int _test_never "an integer we refuse"

  run dybatpho::validate_is int "42"
  assert_failure
}

@test "dybatpho::validate_register refuses a malformed name or a missing predicate" {
  run --separate-stderr dybatpho::validate_register "Bad Name" printf "a thing"
  assert_failure
  assert_stderr --partial "is not a usable type name"

  run --separate-stderr dybatpho::validate_register thing _no_such_function "a thing"
  assert_failure
  assert_stderr --partial "is not a function"

  function _test_ok { return 0; }
  run --separate-stderr dybatpho::validate_register thing _test_ok ""
  assert_failure
  assert_stderr --partial "needs a description"
}

@test "dybatpho::validate_reset forgets custom types and restores the built-ins" {
  function _test_never { return 1; }
  dybatpho::validate_register branch _test_never "a release branch"
  dybatpho::validate_register int _test_never "an integer we refuse"

  dybatpho::validate_reset

  run dybatpho::validate_is branch "main"
  assert_failure
  assert_output --partial "not a known type"

  dybatpho::validate_is int "42"
  assert_equal "$(dybatpho::validate_describe int)" "an integer"
}
