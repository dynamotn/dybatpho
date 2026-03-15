#!/usr/bin/env bash
# @file cli_basic.sh
# @brief A minimal CLI example using the dybatpho opts system
# @description Shows the simplest usage of dybatpho::opts::* to build a CLI
#              with flags, a required param, an optional param, and help output.
#
# Usage examples:
#   bash example/cli_basic.sh --help
#   bash example/cli_basic.sh --name Alice
#   bash example/cli_basic.sh --name Alice --greeting "Hey"
#   bash example/cli_basic.sh --name Alice --shout
#   bash example/cli_basic.sh --name Alice --count 3
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

VERSION="v1.0.0"

# ---------------------------------------------------------------------------
# Implementation
# ---------------------------------------------------------------------------

function _run {
  local _msg="${GREETING:-Hello}, ${NAME}!"

  if [[ -n "${SHOUT:-}" ]]; then
    _msg=$(dybatpho::upper "${_msg}")
  fi

  local _i
  for ((_i = 1; _i <= ${COUNT:-1}; _i++)); do
    dybatpho::print "${_msg}"
  done

  dybatpho::success "Done!" && exit 0
}

# ---------------------------------------------------------------------------
# Spec
# ---------------------------------------------------------------------------

function _spec {
  dybatpho::opts::setup "A minimal greeter CLI" ARGS action:"_run"

  dybatpho::opts::param "Your name" NAME -n --name required:true
  dybatpho::opts::param "Custom greeting word" GREETING -g --greeting init:="Hello"
  dybatpho::opts::param "How many times to greet" COUNT -c --count init:="1"
  dybatpho::opts::flag "Print the message in UPPERCASE" SHOUT -s --shout

  dybatpho::opts::disp "Show version" --version action:"echo ${VERSION}"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}

if (($# == 0)); then
  set -- --help
fi

dybatpho::generate_from_spec _spec "$@"
