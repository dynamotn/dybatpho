#!/usr/bin/env bash
# @file tui_ops.sh
# @brief Example showing the interactive terminal widgets
# @description
#   Walks one small release workflow through `dybatpho::tui_supported`,
#   `dybatpho::tui_bar`, the `tui_spinner_*` and `tui_progress_*` helpers,
#   `dybatpho::tui_menu`, `dybatpho::tui_multi_menu`, and
#   `dybatpho::tui_confirm`.
#
#   The answers are fed in from here with redirects so the example runs
#   unattended. A redirected stdin is not a terminal, which is exactly what
#   selects the numbered fallback: run the same calls without the `< <(...)`
#   parts in a real terminal and the arrow-key menus are drawn instead.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules tui

dybatpho::register_common_handlers

function _main {
  dybatpho::header "TERMINAL DETECTION"
  if dybatpho::tui_supported; then
    dybatpho::info "A terminal is attached: the widgets draw in place"
  else
    dybatpho::info "No terminal: the widgets fall back to prompts and log lines"
  fi

  dybatpho::header "PROGRESS BARS AS TEXT"
  # The bar is just a string, so it composes with anything that takes one.
  local step
  for step in 0 2 5; do
    printf 'release %s\n' "$(dybatpho::tui_bar "${step}" 5 20)"
  done

  dybatpho::header "CHOOSING A TARGET"
  local environment=""
  dybatpho::tui_menu environment "Deploy to which environment?" \
    dev staging prod < <(printf '2\n') \
    || dybatpho::die "No environment chosen"
  dybatpho::info "Chose ${environment}, entry ${DYBATPHO_TUI_INDEX}"

  local -a components=()
  dybatpho::tui_multi_menu components "Which components?" \
    api worker scheduler < <(printf '1,3\n') \
    || dybatpho::die "No component chosen"
  dybatpho::info "Chose ${#components[@]} components: ${components[*]}"

  dybatpho::header "CONFIRMING"
  # Off a terminal this is `dybatpho::confirm`, which refuses to guess unless
  # the shell is declared interactive or `DYBATPHO_FORCE` answers for it.
  if DYBATPHO_INTERACTIVE=true dybatpho::tui_confirm \
    "Deploy ${components[*]} to ${environment}?" yes < <(printf '\n'); then
    dybatpho::info "Confirmed"
  else
    dybatpho::die "Cancelled"
  fi

  dybatpho::header "NARRATING WORK"
  # A spinner brackets a region: the message changes as the work moves on.
  dybatpho::tui_spinner_start "Resolving ${environment} release"
  local component
  for component in "${components[@]}"; do
    dybatpho::tui_spinner_message "Resolving ${component}"
  done
  dybatpho::tui_spinner_stop 0 "Resolved ${#components[@]} components"

  dybatpho::header "MEASURING WORK"
  # A progress bar is for work whose size is known up front.
  dybatpho::tui_progress_start "Uploading" "${#components[@]}"
  for component in "${components[@]}"; do
    dybatpho::tui_progress_step 1 "Uploading ${component}"
  done
  dybatpho::tui_progress_stop "Uploaded ${#components[@]} components"

  dybatpho::success "TUI operations demo complete"
}

_main "$@"
