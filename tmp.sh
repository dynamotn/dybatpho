#!/bin/sh

VERSION="0.1"
parser_definition() {
  setup REST help:usage -- "Usage: example.sh [options]... [arguments]..." ''
  msg -- 'Options:'
  flag FLAG -f --flag -- "takes no arguments"
  param PARAM -p --param -- "takes one argument"
  option OPTION -o --option on:"default" -- "takes one optional argument"
  disp :usage --help
  disp VERSION --version

  msg -- '' 'Commands:'
  cmd cmd1 -- "hahaha"
}

eval "$(getoptions parser_definition parse) exit 1"
# echo "FLAG: $FLAG, PARAM: $PARAM, OPTION: $OPTION"
# printf '%s\n' "$@" # rest arguments
echo "$(getoptions parser_definition parse)"
parse "$@"
