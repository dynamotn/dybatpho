#!/usr/bin/env bash
# @file pkg_ops.sh
# @brief Example showing package manager detection and guarded dependency installation.
#
# The example never changes the machine: every install runs in dry-run mode, so
# it prints the command it would have run instead of running it.
# @description
#   Detects the package manager of the machine and builds the install command
#   for a dependency, without ever changing anything: the run is pinned to a
#   pretend Debian and every install is a dry run.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules pkg

dybatpho::register_common_handlers

# This example has to produce the same output on any machine, so it pretends to
# run on Debian instead of probing the real one. Drop these two lines in a real
# script and let `dybatpho::pkg_manager` detect the manager.
export DYBATPHO_PKG_MANAGER="apt"
export DYBATPHO_PKG_SUDO="true"

dybatpho::header "DETECTION"
pkg_supported_2=$(dybatpho::pkg_supported | tr '\n' ' ')
pkg_supported=${pkg_supported_2}
dybatpho::print "supported: ${pkg_supported}"
if manager="$(dybatpho::pkg_manager)"; then
  dybatpho::print "this machine uses: ${manager}"
else
  dybatpho::warn "No supported package manager on this machine"
  exit 0
fi

dybatpho::header "PACKAGE NAMES PER DISTRIBUTION"
# The same tool is named differently everywhere, so state the exceptions once
# and let the module pick the right one.
pkg_name=$(dybatpho::pkg_name fd apt:fd-find emerge:sys-apps/fd)
dybatpho::print "fd is installed as: ${pkg_name}"
pkg_install_command=$(dybatpho::pkg_install_command ripgrep jq)
dybatpho::print "install command: ${pkg_install_command}"

dybatpho::header "DRY RUN"
# A dry run changes nothing, so it never asks for confirmation.
dybatpho::pkg_install --dry-run ripgrep
dybatpho::pkg_install --dry-run --update -- jq

dybatpho::header "MANAGER FLAGS THIS MODULE DOES NOT MODEL"
# `--arg` hands a flag straight to the manager, once per flag, right before the
# package names: `--cask` on Homebrew, `--no-cache` on Alpine, and so on.
DYBATPHO_PKG_MANAGER=brew dybatpho::pkg_install --dry-run --arg --cask -- firefox
dybatpho::pkg_install --dry-run --arg --no-install-recommends -- ripgrep

dybatpho::header "CONFIRMATION"
# Without `--force`, an unattended run refuses rather than guessing.
if DYBATPHO_INTERACTIVE=false dybatpho::pkg_install ripgrep; then
  dybatpho::error "An unattended install should not have been approved"
else
  dybatpho::success "Refused to change the system without a confirmation"
fi

dybatpho::header "DEPENDENCY CHECKS"
# `pkg_require` is the usual entry point for a bootstrap script: it does nothing
# when the command is already there, and installs the right package when it is
# not.
dybatpho::pkg_require sh
dybatpho::success "sh is already available, nothing to install"
# A tool that is definitely not installed, so the example shows the install path
# on every machine.
dybatpho::pkg_require --dry-run dybatpho-demo-tool \
  apt:dybatpho-demo emerge:app-misc/dybatpho-demo

# In a real script, the unattended form of the same bootstrap is:
#
#   dybatpho::pkg_ensure --force --update curl jq
#   dybatpho::pkg_require --force fd apt:fd-find emerge:sys-apps/fd
#   dybatpho::pkg_ensure --force --arg --no-cache -- curl
