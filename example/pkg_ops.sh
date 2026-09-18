#!/usr/bin/env bash
# @file pkg_ops.sh
# @brief Example showing package manager detection and guarded dependency installation.
#
# The example never changes the machine: every install runs in dry-run mode, so
# it prints the command it would have run instead of running it.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules pkg

# This example has to produce the same output on any machine, so it pretends to
# run on Debian instead of probing the real one. Drop these two lines in a real
# script and let `dybatpho::pkg_manager` detect the manager.
export DYBATPHO_PKG_MANAGER="apt"
export DYBATPHO_PKG_SUDO="true"

dybatpho::header "DETECTION"
dybatpho::print "supported: $(dybatpho::pkg_supported | tr '\n' ' ')"
if manager="$(dybatpho::pkg_manager)"; then
  dybatpho::print "this machine uses: ${manager}"
else
  dybatpho::warn "No supported package manager on this machine"
  exit 0
fi

dybatpho::header "PACKAGE NAMES PER DISTRIBUTION"
# The same tool is named differently everywhere, so state the exceptions once
# and let the module pick the right one.
dybatpho::print "fd is installed as: $(dybatpho::pkg_name fd apt:fd-find emerge:sys-apps/fd)"
dybatpho::print "install command: $(dybatpho::pkg_install_command ripgrep jq)"

dybatpho::header "DRY RUN"
# A dry run changes nothing, so it never asks for confirmation.
dybatpho::pkg_install --dry-run ripgrep
dybatpho::pkg_install --dry-run --update -- jq

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
