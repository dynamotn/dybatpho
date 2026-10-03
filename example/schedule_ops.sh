#!/usr/bin/env bash
# @file schedule_ops.sh
# @brief Example deciding when work should run
# @description Demonstrates dybatpho::schedule_every, schedule_once_per,
#   schedule_reset, schedule_debounce, and schedule_cron_due
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules schedule lock

dybatpho::register_common_handlers

# @description Keep the markers in a directory of this example's own, so a run
#   never touches the state a real script keeps.
# @arg $1 string Name of the variable receiving the directory
# @set The named variable
function _make_state {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  local -n state_ref="${target}"
  dybatpho::create_temp state_ref "/" "schedule-demo"
}

# @description Run something on a cadence, bounded so the example ends.
# @noargs
function _demo_every {
  dybatpho::header "EVERY"
  # The first run is immediate; the cadence is measured from when each run was
  # due, so a slow run does not push the schedule later and later.
  dybatpho::schedule_every 1 --times 3 -- \
    bash -c 'printf "tick at %s\n" "$(date +%H:%M:%S)"'
}

# @description Limit a noisy warning to once a day, across invocations.
# @noargs
function _demo_once_per {
  dybatpho::header "ONCE PER PERIOD"
  # The marker is a file, so this holds when the script runs again tomorrow
  # morning -- and, more to the point, when it runs again in five minutes.
  dybatpho::schedule_once_per day token-expiry -- \
    dybatpho::warn "The deploy token expires in a week"

  if ! dybatpho::schedule_once_per day token-expiry -- \
    dybatpho::warn "The deploy token expires in a week"; then
    dybatpho::info "Second call did nothing: already warned today"
  fi

  # Forgetting the marker is how an operator says "warn me again".
  dybatpho::schedule_reset token-expiry
  dybatpho::schedule_once_per day token-expiry -- \
    dybatpho::info "Warned again after a reset"
}

# @description Collapse a burst of triggers into a single run.
# @noargs
function _demo_debounce {
  dybatpho::header "DEBOUNCE"
  # An editor writing a file produces several events in a row. Running on the
  # first one reads a half-written file, so the run belongs after the burst
  # settles -- which is why each trigger waits and only the last one acts.
  # Exit 9 says "a later trigger replaced this one", which is the normal
  # outcome for every event but the last. It is not an error, so the error
  # handler must not see it.
  local at
  for at in 1 2 3; do
    (dybatpho::schedule_debounce 2 rebuild -- printf 'rebuilt, triggered by event %s\n' "${at}" || true) &
    sleep 1
  done
  wait
  dybatpho::info "Three events, one rebuild"
}

# @description Ask whether a cron expression is due, without a crontab.
# @noargs
function _demo_cron {
  dybatpho::header "CRON"
  # A fixed moment keeps the example's output the same on every run.
  # 2026-10-02 14:30:00 UTC is a Friday.
  local moment
  moment="$(TZ=UTC dybatpho::date_parse "2026-10-02 14:30:00")"

  local expression
  for expression in "30 14 * * *" "*/15 * * * *" "0 3 * * *" "30 14 * * 5" "30 14 1 10 5"; do
    if dybatpho::schedule_cron_due "${expression}" "${moment}"; then
      printf 'due      %s\n' "${expression}"
    else
      printf 'not due  %s\n' "${expression}"
    fi
  done
  # The last one is the subtlety: the 1st does not match, but Friday does, and
  # cron runs when either day field matches.
  dybatpho::info "With both day fields set, either one matching is enough"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  local state
  _make_state state
  export DYBATPHO_SCHEDULE_DIR="${state}"

  _demo_every
  _demo_once_per
  _demo_debounce
  _demo_cron
  dybatpho::success "Schedule operations demo complete"
}

_main "$@"
