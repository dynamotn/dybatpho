setup() {
  load test_helper
}

@test "dybatpho::generate_from_spec simple" {
  # shellcheck disable=2317
  _spec() {
    dybatpho::opts::setup "" -
    echo "called" >&2
  }

  run --separate-stderr dybatpho::generate_from_spec _spec
  assert_success
  assert_stderr_line --index 0 "called"
  assert_stderr_line --index 1 "called"
}

@test "dybatpho::generate_from_spec send arguments to dybatpho::opts::parse" {
  # shellcheck disable=2317
  _spec() {
    dybatpho::opts::setup "" -
  }

  # shellcheck disable=2030
  export LOG_LEVEL=debug
  export DYBATPHO_CLI_DEBUG=true
  run --separate-stderr dybatpho::generate_from_spec _spec 1 2 "3\""
  assert_success
  assert_stderr --partial "dybatpho::opts::parse::_spec \"1\" \"2\" \"3\\\""
}

@test "dybatpho::generate_from_spec handling rest arguments" {
  # shellcheck disable=2317
  _spec() {
    dybatpho::opts::setup "" ARGS action:"echo \$ARGS"
  }

  run dybatpho::generate_from_spec _spec -a 1 -a 2 -a "3\"" -- -a
  assert_success
  assert_output "-a 1 -a 2 -a 3\" -- -a"
}

@test "dybatpho::generate_from_spec handling arguments with doesn't have sub commands" {
  # shellcheck disable=2317
  _spec() {
    dybatpho::opts::setup "" ARGS action:"echo -e \"\$ARGS\n\$FLAG_A\""
    dybatpho::opts::flag "" FLAG_A -a
  }

  run dybatpho::generate_from_spec _spec -a 1 -a 2 -a "3\"" -- -a
  assert_success
  assert_line --index 0 " 1 -a 2 -a 3\" -- -a"
  assert_line --index 1 "true"

  run dybatpho::generate_from_spec _spec -a -- -a
  assert_success
  assert_line --index 0 " -a"
  assert_line --index 1 "true"
}
