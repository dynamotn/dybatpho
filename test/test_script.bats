setup() {
  load test_helper
  TEST_SH="${DYBATPHO_DIR}/scripts/test.sh"
}

@test "scripts/test.sh stops its workers and their Bats on Ctrl-C" {
  # Workers started with `&` in a non-interactive shell ignore SIGINT: after
  # Ctrl-C they kept running the remaining files into a run directory nobody
  # would clean up.
  # The runner of this very test may have left SIGINT ignored, and a shell
  # cannot trap a signal it started with ignored.
  env --default-signal=INT true 2> /dev/null || skip "env cannot reset SIGINT here"
  local suite="${BATS_TEST_TMPDIR}/suite" marks="${BATS_TEST_TMPDIR}/marks"
  local tmp="${BATS_TEST_TMPDIR}/tmp" i pid shards
  mkdir -p "${suite}" "${marks}" "${tmp}"
  for i in 1 2 3 4; do
    printf '@test "slow %s" {\n  sleep 2\n  touch "%s/%s"\n}\n' "${i}" "${marks}" "${i}" \
      > "${suite}/slow${i}.bats"
  done
  # Both kinds of workers: plain Bash ones, and with GNU parallel when present.
  for shards in true false; do
    # Its own process group, like a foreground job, so the group gets the
    # interrupt the way a terminal delivers Ctrl-C.
    set -m
    DYBATPHO_TEST_SHARDS="${shards}" TMPDIR="${tmp}" \
      env --default-signal=INT bash "${TEST_SH}" --jobs 2 "${suite}" > /dev/null 2>&1 &
    pid=$!
    set +m
    sleep 1
    kill -INT -- "-${pid}"
    status=0
    wait "${pid}" || status=$?
    assert_equal "${status}" 130
    sleep 3
    run ls -A "${marks}"
    assert_output ""
    run ls -A "${tmp}"
    assert_output ""
  done
}
