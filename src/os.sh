#!/usr/bin/env bash
# @file os.sh
# @brief Utilities for working with OS/distro package manager or getting information of OS/distro
# @description This module contains functions to get information of OS/distro or work with package manager
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Get $GOOS compilation environment
# @stdout Return $GOOS value https://go.dev/doc/install/source#environment
#######################################
function dybatpho::goos {
  local os="$(dybatpho::lower "$(uname -s)")"
  local goos
  case "${os}" in
    cygwin_nt*) goos="windows" ;;
    linux)
      local variant="$(dybatpho::lower "$(uname -o)")"
      case "${variant}" in
        android) goos="android" ;;
        *) goos="linux" ;;
      esac
      ;;
    mingw*) goos="windows" ;;
    msys_nt*) goos="windows" ;;
    *) goos="${os}" ;;
  esac
  printf '%s' "${goos}"
}

#######################################
# @description Get $GOARCH compilation environment
# @stdout Return $GOOS value https://go.dev/doc/install/source#environment
#######################################
function dybatpho::goarch {
  local arch="$(uname -m)"
  case "${arch}" in
    aarch64) goarch="arm64" ;;
    armv*) goarch="arm" ;;
    i386) goarch="386" ;;
    i686) goarch="386" ;;
    i86pc) goarch="amd64" ;;
    x86) goarch="386" ;;
    x86_64) goarch="amd64" ;;
    *) goarch="${arch}" ;;
  esac
  printf '%s' "${goarch}"
}
