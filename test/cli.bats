setup() {
  load test_helper
  unset CLI_NAME API_TOKEN
}

# =============================================================================
# dybatpho::generate_from_spec
# =============================================================================

@test "dybatpho::generate_from_spec simple" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    echo "called" >&2
  }

  run --separate-stderr dybatpho::generate_from_spec _spec
  assert_success
  assert_stderr_line --index 0 "called"
  assert_stderr_line --index 1 "called"
}

@test "commands get automatic help when no help option is declared" {
  _spec_auto_help() { dybatpho::opts::setup "Automatic help command" -; }
  # Display actions exit the shell, so these need the isolating form of `run`.
  run dybatpho::generate_from_spec _spec_auto_help --help
  assert_success
  assert_line --index 0 --partial "Usage:"
  assert_output --partial "Automatic help command"
  run dybatpho::generate_from_spec _spec_auto_help -h
  assert_success
  assert_line --index 0 --partial "Usage:"
}

@test "explicit help option overrides automatic help" {
  _spec_custom_help() {
    dybatpho::opts::setup "Custom help command" -
    dybatpho::opts::disp "Custom help" --help action:"echo custom-help"
  }
  assert_equal "$(dybatpho::generate_from_spec _spec_custom_help --help)" "custom-help"
}

@test "dybatpho::prompt uses entered value and default" {
  local entered
  entered="$(printf 'Alice\n' | dybatpho::prompt 'Name')"
  assert_equal "Alice" "${entered}"
  entered="$(printf '\n' | dybatpho::prompt 'Name' 'Guest')"
  assert_equal "Guest" "${entered}"
}

@test "dybatpho::select supports numeric multiple selections" {
  local selected
  selected="$(printf '1,3\n' | dybatpho::select 'Choose colors' 'red,green,blue' true)"
  assert_equal "red blue" "${selected}"
}

@test "dybatpho::select supports numeric ranges for multiple selections" {
  local selected
  selected="$(printf '1-3\n' | dybatpho::select 'Choose colors' 'red,green,blue,yellow' true)"
  assert_equal "red green blue" "${selected}"
}

@test "dybatpho::select rejects descending or out-of-range selections" {
  local selected
  selected="$(printf '4-2\n1-2\n' | dybatpho::select 'Choose colors' 'red,green,blue' true)"
  assert_equal "red green" "${selected}"
}

@test "options use environment values and explicit arguments take precedence" {
  _spec_env_option() {
    dybatpho::opts::setup "" - action:'printf "%s" "$NAME"'
    dybatpho::opts::param "Name" NAME --name env:CLI_NAME
  }

  export CLI_NAME=from-env
  assert_equal "$(dybatpho::generate_from_spec _spec_env_option)" "from-env"

  assert_equal "$(dybatpho::generate_from_spec _spec_env_option --name from-cli)" "from-cli"
}

@test "options validate choices and collect multiple values" {
  _spec_choices() {
    dybatpho::opts::setup "" - action:'printf "%s" "$COLORS"'
    dybatpho::opts::param "Color" COLORS --color choices:red,blue multiple:true
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_choices --color red --color blue)" "red blue"

  run --separate-stderr dybatpho::generate_from_spec _spec_choices --color green
  assert_failure
  assert_stderr --partial "Validation error"
}

@test "completion generation supports Bash Zsh and Fish" {
  _spec_completion() {
    dybatpho::opts::setup "Completion demo" -
    dybatpho::opts::flag "Verbose" VERBOSE --verbose alias:-v
    dybatpho::opts::cmd deploy _spec_completion_deploy
  }
  _spec_completion_deploy() { dybatpho::opts::setup "Deploy command" -; }

  run_traced dybatpho::generate_completion _spec_completion bash demo
  assert_success
  assert_output --partial "complete -F"
  assert_output --partial "--verbose"
  assert_output --partial "deploy"

  run_traced dybatpho::generate_completion _spec_completion zsh demo
  assert_success
  assert_output --partial "compdef"
  assert_output --partial "--verbose"

  run_traced dybatpho::generate_completion _spec_completion fish demo
  assert_success
  assert_output --partial "complete -c demo -l verbose"
  assert_output --partial "complete -c demo -f -a deploy"
}

@test "schema and man generation preserve CLI metadata" {
  _spec_artifacts() {
    dybatpho::opts::setup "Artifact demo" -
    dybatpho::opts::param "API token" TOKEN --token env:API_TOKEN required:true choices:a,b prompt:"Choose token"
    dybatpho::opts::cmd deploy _spec_artifacts_deploy
  }
  _spec_artifacts_deploy() { dybatpho::opts::setup "Deploy command" -; }

  run_traced dybatpho::generate_schema _spec_artifacts demo
  assert_success
  SCHEMA="${output}" python3 -c 'import json, os; data=json.loads(os.environ["SCHEMA"]); option=data["options"][0]; assert data["description"] == "Artifact demo"; assert option["env"] == "API_TOKEN"; assert option["required"] is True; assert option["choices"] == "a,b"; assert data["commands"][0]["name"] == "deploy"'

  run_traced dybatpho::generate_man _spec_artifacts demo
  assert_success
  assert_output --partial ".TH"
  assert_output --partial "Artifact demo"
  assert_output --partial "--token <TOKEN>"
  assert_output --partial "[env: API_TOKEN]"
  assert_output --partial "deploy"
}

@test "subcommand artifacts include child options and aliases" {
  _spec_artifact_child() {
    dybatpho::opts::setup "Child command" -
    dybatpho::opts::flag "Child flag" CHILD_FLAG --child-flag
  }
  _spec_artifact_root() {
    dybatpho::opts::setup "Root command" -
    dybatpho::opts::cmd child _spec_artifact_child aliases:c
  }

  run_traced dybatpho::generate_completion _spec_artifact_root bash tool
  assert_success
  assert_output --partial "--child-flag"
  assert_output --partial "child"
  assert_output --partial "c"

  run_traced dybatpho::generate_schema _spec_artifact_root tool
  assert_success
  SCHEMA="${output}" python3 -c 'import json, os; child=json.loads(os.environ["SCHEMA"])["commands"][0]; assert child["aliases"] == ["c"]; assert child["options"][0]["switches"] == ["--child-flag"]'

  run_traced dybatpho::generate_man _spec_artifact_root tool
  assert_success
  [ "$(printf "%s\n" "${output}" | grep -c '^\.TH')" -eq 1 ]
  assert_output --partial "--child-flag"
  assert_output --partial "Child command"
}

@test "dybatpho::generate_from_spec send arguments to dybatpho::opts::parse" {
  # shellcheck disable=2329
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
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" ARGS action:"echo \$ARGS"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -a 1 -a 2 -a "3\"" -- -a)" "-a 1 -a 2 -a 3\" -- -a"
}

@test "dybatpho::generate_from_spec handling arguments with doesn't have sub commands" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" ARGS action:"echo -e \"\$ARGS\n\$FLAG_A\""
    dybatpho::opts::flag "" FLAG_A -a
  }

  run_traced dybatpho::generate_from_spec _spec -a 1 -a 2 -a "3\"" -- -a
  assert_success
  assert_line --index 0 " 1 -a 2 -a 3\" -- -a"
  assert_line --index 1 "true"

  run_traced dybatpho::generate_from_spec _spec -a -- -a
  assert_success
  assert_line --index 0 " -a"
  assert_line --index 1 "true"
}

# =============================================================================
# dybatpho::opts::flag
# =============================================================================

@test "dybatpho::opts::flag basic long switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$VERBOSE"
    dybatpho::opts::flag "Verbose" VERBOSE --verbose
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --verbose)" "true"

  dybatpho::generate_from_spec _spec
}

@test "dybatpho::opts::flag basic short switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$DEBUGF"
    dybatpho::opts::flag "Debug" DEBUGF -d
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -d)" "true"
}

@test "dybatpho::opts::flag multiple switches" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$MFLAG"
    dybatpho::opts::flag "Multi" MFLAG -m --multi --multiple
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -m)" "true"

  assert_equal "$(dybatpho::generate_from_spec _spec --multi)" "true"

  assert_equal "$(dybatpho::generate_from_spec _spec --multiple)" "true"
}

@test "dybatpho::opts::flag custom on/off values" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$FEAT"
    dybatpho::opts::flag "Feature" FEAT --feature on:yes off:no init:="no"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --feature)" "yes"

  assert_equal "$(dybatpho::generate_from_spec _spec)" "no"
}

@test "dybatpho::opts::flag init:@on" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$FFLAG"
    dybatpho::opts::flag "Flag" FFLAG --flag init:@on
  }

  assert_equal "$(dybatpho::generate_from_spec _spec)" "true"
}

@test "dybatpho::opts::flag init:@off" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$OFFLAG"
    dybatpho::opts::flag "Flag" OFFLAG --flag on:yes off:no init:@off
  }

  assert_equal "$(dybatpho::generate_from_spec _spec)" "no"
}

@test "dybatpho::opts::flag init:@keep preserves existing value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$KFLAG"
    dybatpho::opts::flag "Flag" KFLAG --flag init:@keep
  }

  export KFLAG=existing
  assert_equal "$(dybatpho::generate_from_spec _spec)" "existing"
}

@test "dybatpho::opts::flag init:@unset unsets variable" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \${UFLAG:-UNSET}"
    dybatpho::opts::flag "Flag" UFLAG --flag init:@unset
  }

  export UFLAG=something
  assert_equal "$(dybatpho::generate_from_spec _spec)" "UNSET"
}

@test "dybatpho::opts::flag --{no-} expand" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$NOFEAT"
    dybatpho::opts::flag "Feature" NOFEAT --{no-}feature
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --feature)" "true"

  assert_equal "$(dybatpho::generate_from_spec _spec --no-feature)" ""
}

@test "dybatpho::opts::flag --with{out}- expand" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$WFEAT"
    dybatpho::opts::flag "Feature" WFEAT --with{out}-wfeat
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --with-wfeat)" "true"

  assert_equal "$(dybatpho::generate_from_spec _spec --without-wfeat)" ""
}

@test "dybatpho::opts::flag export:false" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PRIVFLAG"
    dybatpho::opts::flag "Private" PRIVFLAG --flag export:false
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --flag)" "true"
}

# =============================================================================
# dybatpho::opts::param
# =============================================================================

@test "dybatpho::opts::param basic long switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PNAME"
    dybatpho::opts::param "Name" PNAME --name
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --name hello)" "hello"
}

@test "dybatpho::opts::param basic short switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PVAL"
    dybatpho::opts::param "Value" PVAL -v
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -v world)" "world"
}

@test "dybatpho::opts::param short switch with attached value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PVALATTACHED"
    dybatpho::opts::param "Value" PVALATTACHED -v
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -vworld)" "world"
}

@test "dybatpho::opts::param multiple switches" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PMSW"
    dybatpho::opts::param "Multi" PMSW -p --param --parameter
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -p val1)" "val1"

  assert_equal "$(dybatpho::generate_from_spec _spec --param val2)" "val2"

  assert_equal "$(dybatpho::generate_from_spec _spec --parameter val3)" "val3"
}

@test "dybatpho::opts::param init:=" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PDEF"
    dybatpho::opts::param "Default" PDEF --default init:="default-value"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec)" "default-value"

  assert_equal "$(dybatpho::generate_from_spec _spec --default override)" "override"
}

@test "dybatpho::opts::param optional:true with = value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$POPT"
    dybatpho::opts::param "Optional" POPT --opt optional:true
  }

  # With = syntax, value is passed directly
  assert_equal "$(dybatpho::generate_from_spec _spec --opt=value)" "value"
}

@test "dybatpho::opts::param optional:true without value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$POPT2"
    dybatpho::opts::param "Optional" POPT2 --opt2 optional:true
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --opt2)" "true"

  assert_equal "$(dybatpho::generate_from_spec _spec)" ""
}

@test "dybatpho::opts::param optional:true with separated value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" PREST action:"printf '%s|%s\n' \"\$POPT3\" \"\$PREST\""
    dybatpho::opts::param "Optional" POPT3 --opt3 optional:true
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --opt3 value)" "value|"
}

@test "dybatpho::opts::param validate passes for valid input" {
  _validate_positive() { [[ "$1" -gt 0 ]] 2> /dev/null; }
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PCOUNT"
    dybatpho::opts::param "Count" PCOUNT --count validate:"_validate_positive \$OPTARG"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --count 5)" "5"
}

@test "dybatpho::opts::param validate fails for invalid input" {
  _validate_positive2() { [[ "$1" -gt 0 ]] 2> /dev/null; }
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PCOUNT2"
    dybatpho::opts::param "Count" PCOUNT2 --count2 validate:"_validate_positive2 \$OPTARG"
  }

  run --separate-stderr dybatpho::generate_from_spec _spec --count2 -1
  assert_failure
  assert_stderr --partial "Validation error"
}

@test "dybatpho::opts::param init not leaked from previous flag" {
  # Regression: __init from flag's off:value must not leak into setup's __define_var
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" PREST action:"echo \$PREST"
    dybatpho::opts::flag "Dry" PDRY --dry-run on:true off:false init:="false"
  }

  run_traced dybatpho::generate_from_spec _spec hello
  assert_success
  refute_output --partial "false"
  assert_output --partial "hello"
}

@test "dybatpho::opts::param required:true fails when option is missing" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$REQNAME"
    dybatpho::opts::param "Name" REQNAME -n --name required:true
  }

  run --separate-stderr dybatpho::generate_from_spec _spec
  assert_failure
  assert_stderr --partial "Missing required option: --name"
}

@test "dybatpho::opts::param required:true succeeds when option is present" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$REQNAME2"
    dybatpho::opts::param "Name" REQNAME2 -n --name required:true
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --name dynamo)" "dynamo"
}

@test "dybatpho::opts::setup rejects invalid rest variable name" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" bad-name action:"echo nope"
  }

  run --separate-stderr dybatpho::generate_from_spec _spec
  assert_failure
  assert_stderr --partial "Invalid shell variable name: bad-name"
}

@test "dybatpho::opts::setup args:none rejects positional args" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - args:none action:"echo ok"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec)" "ok"

  run --separate-stderr dybatpho::generate_from_spec _spec extra
  assert_failure
  assert_stderr --partial "Expected no arguments, got 1"
}

@test "dybatpho::opts::setup args:exact:N validates positional args" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" REST args:exact:2 action:"printf '[%s]\n' \"\$REST\""
  }

  assert_equal "$(dybatpho::generate_from_spec _spec one two)" "[ one two]"

  run --separate-stderr dybatpho::generate_from_spec _spec one
  assert_failure
  assert_stderr --partial "Expected exactly 2 arguments, got 1"
}

@test "dybatpho::opts::setup args:min/max validate positional args" {
  # shellcheck disable=2329
  _spec_min() {
    dybatpho::opts::setup "" REST args:min:1 action:"printf '[%s]\n' \"\$REST\""
  }
  # shellcheck disable=2329
  _spec_max() {
    dybatpho::opts::setup "" REST args:max:1 action:"printf '[%s]\n' \"\$REST\""
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_min one)" "[ one]"

  run --separate-stderr dybatpho::generate_from_spec _spec_min
  assert_failure
  assert_stderr --partial "Expected at least 1 argument, got 0"

  assert_equal "$(dybatpho::generate_from_spec _spec_max one)" "[ one]"

  run --separate-stderr dybatpho::generate_from_spec _spec_max one two
  assert_failure
  assert_stderr --partial "Expected at most 1 argument, got 2"
}

@test "dybatpho::opts::setup args:range validates subcommand positional args" {
  # shellcheck disable=2329
  _spec_leaf() {
    dybatpho::opts::setup "" LEAF_ARGS args:range:1:2 action:"printf '[%s]\n' \"\$LEAF_ARGS\""
  }
  # shellcheck disable=2329
  _spec_root() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd leaf _spec_leaf
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_root leaf one two)" "[ one two]"

  run --separate-stderr dybatpho::generate_from_spec _spec_root leaf
  assert_failure
  assert_stderr --partial "Expected between 1 and 2 arguments, got 0"

  run --separate-stderr dybatpho::generate_from_spec _spec_root leaf one two three
  assert_failure
  assert_stderr --partial "Expected between 1 and 2 arguments, got 3"
}

@test "dybatpho::opts::flag omits variable assignment with dash" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" REST action:"echo ${REST:-EMPTY}"
    dybatpho::opts::flag "Verbose" - --verbose
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --verbose)" "EMPTY"
}

@test "dybatpho::opts::flag alias metadata adds alternate switches" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$VERBOSE_ALIAS"
    dybatpho::opts::flag "Verbose" VERBOSE_ALIAS --verbose alias:-v aliases:--chatty
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -v)" "true"

  assert_equal "$(dybatpho::generate_from_spec _spec --chatty)" "true"
}

# =============================================================================
# dybatpho::opts::disp
# =============================================================================

@test "dybatpho::opts::disp runs action and exits" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::disp "Show version" --version action:"echo v1.0"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec --version)" "v1.0"
}

@test "dybatpho::opts::disp short switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::disp "Show help" -h action:"echo help-text"
  }

  assert_equal "$(dybatpho::generate_from_spec _spec -h)" "help-text"
}

@test "dybatpho::opts::disp exits before action runs" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo main"
    dybatpho::opts::disp "Version" --version action:"echo v2.0"
  }

  # The display action exits the shell, so `run` must isolate it.
  run dybatpho::generate_from_spec _spec --version
  assert_output "v2.0"
  refute_output --partial "main"
}

# =============================================================================
# dybatpho::opts::cmd – subcommand dispatch
# =============================================================================

@test "dybatpho::opts::cmd dispatches to subcommand" {
  # shellcheck disable=2329
  _spec_child() {
    dybatpho::opts::setup "Child" CHILD_ARGS action:"echo \$CHILD_ARGS"
  }
  # shellcheck disable=2329
  _spec_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd child _spec_child
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_parent child hello)" "hello"
}

@test "dybatpho::opts::cmd passes flags to subcommand" {
  # shellcheck disable=2329
  _spec_flag_child() {
    dybatpho::opts::setup "" - action:"echo \$CFLAG"
    dybatpho::opts::flag "Flag" CFLAG --cflag
  }
  # shellcheck disable=2329
  _spec_flag_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd child _spec_flag_child
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_flag_parent child --cflag)" "true"
}

@test "dybatpho::opts::cmd nested subcommand dispatch" {
  # shellcheck disable=2329
  _spec_leaf() {
    dybatpho::opts::setup "Leaf" LEAF_ARGS action:"echo leaf:\$LEAF_ARGS"
  }
  # shellcheck disable=2329
  _spec_mid() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd leaf _spec_leaf
  }
  # shellcheck disable=2329
  _spec_root() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd mid _spec_mid
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_root mid leaf world)" "leaf: world"
}

@test "dybatpho::opts::cmd global options before subcommand" {
  # shellcheck disable=2329
  _spec_gc_child() {
    dybatpho::opts::setup "" - action:"echo \$GFLAG:\$CFLAG2"
    dybatpho::opts::flag "Child flag" CFLAG2 --cflag2
  }
  # shellcheck disable=2329
  _spec_gc_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Global flag" GFLAG --gflag
    dybatpho::opts::cmd child _spec_gc_child
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_gc_parent --gflag child --cflag2)" "true:true"
}

@test "dybatpho::opts::flag persistent:true works after subcommand dispatch" {
  # shellcheck disable=2329
  _spec_persist_child() {
    dybatpho::opts::setup "" - action:"echo \$PERSIST_FLAG"
  }
  # shellcheck disable=2329
  _spec_persist_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Persistent flag" PERSIST_FLAG --persist persistent:true
    dybatpho::opts::cmd child _spec_persist_child
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_persist_parent child --persist)" "true"
}

@test "dybatpho::opts::setup prerun/postrun wrap action" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - prerun:"echo pre" action:"echo main" postrun:"echo post"
  }

  run_traced dybatpho::generate_from_spec _spec
  assert_success
  assert_line --index 0 "pre"
  assert_line --index 1 "main"
  assert_line --index 2 "post"
}

@test "dybatpho::opts::setup prerun/postrun are scoped to active subcommand" {
  # shellcheck disable=2329
  _spec_hook_child() {
    dybatpho::opts::setup "" - prerun:"echo child-pre" action:"echo child-main" postrun:"echo child-post"
  }
  # shellcheck disable=2329
  _spec_hook_parent() {
    dybatpho::opts::setup "" - prerun:"echo parent-pre" action:"echo parent-main" postrun:"echo parent-post"
    dybatpho::opts::cmd child _spec_hook_child
  }

  run_traced dybatpho::generate_from_spec _spec_hook_parent
  assert_success
  assert_line --index 0 "parent-pre"
  assert_line --index 1 "parent-main"
  assert_line --index 2 "parent-post"

  run_traced dybatpho::generate_from_spec _spec_hook_parent child
  assert_success
  assert_line --index 0 "child-pre"
  assert_line --index 1 "child-main"
  assert_line --index 2 "child-post"
}

@test "dybatpho::opts::cmd multiple subcommands dispatch correctly" {
  # shellcheck disable=2329
  _spec_cmd_a() {
    dybatpho::opts::setup "" - action:"echo cmd-a"
  }
  # shellcheck disable=2329
  _spec_cmd_b() {
    dybatpho::opts::setup "" - action:"echo cmd-b"
  }
  # shellcheck disable=2329
  _spec_multi_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd cmda _spec_cmd_a
    dybatpho::opts::cmd cmdb _spec_cmd_b
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_multi_parent cmda)" "cmd-a"

  assert_equal "$(dybatpho::generate_from_spec _spec_multi_parent cmdb)" "cmd-b"
}

@test "dybatpho::opts::cmd alias metadata dispatches to subcommand" {
  # shellcheck disable=2329
  _spec_alias_child() {
    dybatpho::opts::setup "" CHILD_ARGS action:"echo alias:\$CHILD_ARGS"
  }
  # shellcheck disable=2329
  _spec_alias_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd config _spec_alias_child alias:cfg aliases:conf,settings
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_alias_parent cfg hello)" "alias: hello"

  assert_equal "$(dybatpho::generate_from_spec _spec_alias_parent settings world)" "alias: world"
}

# =============================================================================
# Error handling
# =============================================================================

@test "error: unrecognized option via combined short flag" {
  # Combined short flag (-b--foo) triggers the "unknown" path when the
  # remainder after expansion starts with "--"
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "" BFLAG -b
  }

  run --separate-stderr dybatpho::generate_from_spec _spec -b--unknown
  assert_failure
  assert_stderr --partial "Unrecognized option"
}

@test "error: option requires an argument" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::param "" REQVAL --reqval
  }

  run --separate-stderr dybatpho::generate_from_spec _spec --reqval
  assert_failure
  assert_stderr --partial "Requires an argument"
}

@test "error: option does not allow an argument" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "" NOFLAG --noflag
  }

  run --separate-stderr dybatpho::generate_from_spec _spec --noflag=value
  assert_failure
  assert_stderr --partial "Does not allow an argument"
}

@test "error: invalid subcommand" {
  # shellcheck disable=2329
  _spec_dummy_err() {
    dybatpho::opts::setup "" -
  }
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd sub _spec_dummy_err
  }

  run --separate-stderr dybatpho::generate_from_spec _spec notacmd
  assert_failure
  assert_stderr --partial "Invalid command"
}

@test "error: validation failure" {
  # Use a validator that won't have $1 unbound: pass a non-empty invalid value
  _validate_alpha() { [[ "${1:-}" =~ ^[a-z]+$ ]]; }
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::param "" VALIDATED --validated validate:"_validate_alpha \$OPTARG"
  }

  run --separate-stderr dybatpho::generate_from_spec _spec --validated "123"
  assert_failure
  assert_stderr --partial "Validation error"
}

@test "deprecated flag warns but still works" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$OLD_FLAG"
    dybatpho::opts::flag "Old flag" OLD_FLAG --old deprecated:"Use --new instead"
  }

  run --separate-stderr dybatpho::generate_from_spec _spec --old
  assert_success
  assert_output "true"
  assert_stderr --partial "Deprecated option: --old. Use --new instead"
}

@test "deprecated command warns but still dispatches" {
  # shellcheck disable=2329
  _spec_old_cmd() {
    dybatpho::opts::setup "" - action:"echo old-cmd"
  }
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd old _spec_old_cmd deprecated:"Use 'new' instead"
  }

  run --separate-stderr dybatpho::generate_from_spec _spec old
  assert_success
  assert_output "old-cmd"
  assert_stderr --partial "Deprecated command: old. Use 'new' instead"
}

# =============================================================================
# dybatpho::generate_help
# =============================================================================

@test "dybatpho::generate_help shows usage line" {
  # shellcheck disable=2329
  _spec_hu() {
    dybatpho::opts::setup "My tool" -
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hu
  assert_success
  assert_line --index 0 --partial "Usage:"
  assert_line --index 0 --partial "[options...]"
}

@test "dybatpho::generate_help shows description" {
  # shellcheck disable=2329
  _spec_hd() {
    dybatpho::opts::setup "My tool description" -
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hd
  assert_output --partial "My tool description"
}

@test "dybatpho::generate_help shows Options section with flag and param" {
  # shellcheck disable=2329
  _spec_ho() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Enable verbose" HVERBOSE --verbose
    dybatpho::opts::param "Set name" HNAME --name
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_ho
  assert_output --partial "Options:"
  assert_output --partial "--verbose"
  assert_output --partial "Enable verbose"
  assert_output --partial "--name"
  assert_output --partial "Set name"
}

@test "dybatpho::generate_help hides hidden flags" {
  # shellcheck disable=2329
  _spec_hidden_flag() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Visible flag" HVISIBLE --visible
    dybatpho::opts::flag "Hidden flag" HHIDDEN --hidden hidden:true
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hidden_flag
  assert_success
  assert_output --partial "--visible"
  refute_output --partial "--hidden"
}

@test "dybatpho::generate_help param shows <VAR> in label" {
  # shellcheck disable=2329
  _spec_hpv() {
    dybatpho::opts::setup "" -
    dybatpho::opts::param "Value" HPVAL --param-val
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hpv
  assert_output --partial "<HPVAL>"
}

@test "dybatpho::generate_help marks required:true params automatically" {
  # shellcheck disable=2329
  _spec_hreq() {
    dybatpho::opts::setup "" -
    dybatpho::opts::param "Set name" HREQ --name required:true
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hreq
  assert_output --partial "--name"
  assert_output --partial "Set name (required)"
}

@test "dybatpho::generate_help disp shows without <VAR>" {
  # shellcheck disable=2329
  _spec_hdisp() {
    dybatpho::opts::setup "" -
    dybatpho::opts::disp "Show version" --version action:"echo v1"
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hdisp
  assert_output --partial "--version"
  assert_output --partial "Show version"
  refute_output --partial "<"
}

@test "dybatpho::generate_help shows Commands section with subcommand descriptions" {
  # shellcheck disable=2329
  _spec_hc_sub1() {
    dybatpho::opts::setup "First sub command" -
  }
  # shellcheck disable=2329
  _spec_hc_sub2() {
    dybatpho::opts::setup "Second sub command" -
  }
  # shellcheck disable=2329
  _spec_hc() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd sub1 _spec_hc_sub1
    dybatpho::opts::cmd sub2 _spec_hc_sub2
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hc
  assert_output --partial "Commands:"
  assert_output --partial "sub1"
  assert_output --partial "First sub command"
  assert_output --partial "sub2"
  assert_output --partial "Second sub command"
}

@test "dybatpho::generate_help hides hidden commands" {
  # shellcheck disable=2329
  _spec_hc_hidden_sub() {
    dybatpho::opts::setup "Hidden sub" -
  }
  # shellcheck disable=2329
  _spec_hc_hidden_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd visible _spec_hc_hidden_sub
    dybatpho::opts::cmd secret _spec_hc_hidden_sub hidden:true
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hc_hidden_parent
  assert_success
  assert_output --partial "visible"
  refute_output --partial "secret"
}

@test "dybatpho::generate_help annotates deprecated items" {
  # shellcheck disable=2329
  _spec_hdeprecated_sub() {
    dybatpho::opts::setup "Deprecated sub" -
  }
  # shellcheck disable=2329
  _spec_hdeprecated() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Legacy flag" HLEGACY --legacy deprecated:"Use --modern instead"
    dybatpho::opts::cmd old _spec_hdeprecated_sub deprecated:"Use 'new' instead"
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hdeprecated
  assert_success
  assert_output --partial "deprecated: Use --modern instead"
  assert_output --partial "deprecated: Use 'new' instead"
}

@test "dybatpho::generate_help includes persistent parent options in child help" {
  # shellcheck disable=2329
  _spec_hpersist_child() {
    dybatpho::opts::setup "Child help" -
    dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_hpersist_child"
  }
  # shellcheck disable=2329
  _spec_hpersist_parent() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Persistent flag" HPERSIST --persist persistent:true
    dybatpho::opts::cmd child _spec_hpersist_child
  }

  # The help action exits the shell, so `run` must isolate it.
  run dybatpho::generate_from_spec _spec_hpersist_parent child --help
  assert_success
  assert_output --partial "--persist"
  assert_output --partial "Persistent flag"
}

@test "dybatpho::generate_help shows command aliases" {
  # shellcheck disable=2329
  _spec_hc_alias_sub() {
    dybatpho::opts::setup "Config command" -
  }
  # shellcheck disable=2329
  _spec_hc_alias() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd config _spec_hc_alias_sub alias:cfg aliases:conf
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hc_alias
  assert_success
  assert_output --partial "config, cfg, conf"
}

@test "dybatpho::generate_help shows switch aliases from metadata" {
  # shellcheck disable=2329
  _spec_halias() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Verbose output" HALIAS --verbose alias:-v aliases:--chatty
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_halias
  assert_success
  assert_output --partial "--verbose"
  assert_output --partial "-v"
  assert_output --partial "--chatty"
}

@test "dybatpho::generate_help no Commands section when no subcommands" {
  # shellcheck disable=2329
  _spec_hnc() {
    dybatpho::opts::setup "No subcommands" -
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hnc
  refute_output --partial "Commands:"
}

@test "dybatpho::generate_help subcommand path shown in usage from __current_cmd_path" {
  # shellcheck disable=2329
  _spec_hsp() {
    dybatpho::opts::setup "Sub description" -
  }

  __current_cmd_path="weather"
  run_traced dybatpho::generate_help _spec_hsp
  assert_line --index 0 --partial "weather"
}

@test "dybatpho::generate_help nested subcommand path in usage" {
  # shellcheck disable=2329
  _spec_hnsp() {
    dybatpho::opts::setup "Nested sub" -
  }

  __current_cmd_path="ip internet"
  run_traced dybatpho::generate_help _spec_hnsp
  assert_line --index 0 --partial "ip internet"
}

@test "dybatpho::generate_help hidden option is excluded" {
  # shellcheck disable=2329
  _spec_hh() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Visible" HVIS --visible
    dybatpho::opts::flag "Hidden" HHID --hidden hidden:true
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hh
  assert_output --partial "--visible"
  refute_output --partial "--hidden"
}

@test "dybatpho::generate_help label: overrides switch display" {
  # shellcheck disable=2329
  _spec_hlbl() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Custom" HLBL --custom label:"[--custom]"
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hlbl
  assert_output --partial "[--custom]"
}

@test "dybatpho::generate_help --{no-} expands both variants" {
  # shellcheck disable=2329
  _spec_hno() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Toggle" HTOGGLE --{no-}toggle
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hno
  assert_output --partial "--toggle"
  assert_output --partial "--no-toggle"
}

@test "dybatpho::generate_help --with{out}- expands both variants" {
  # shellcheck disable=2329
  _spec_hwith() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "With" HWITH --with{out}-feature
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_hwith
  assert_output --partial "--with-feature"
  assert_output --partial "--without-feature"
}

@test "dybatpho::generate_help subcommand path tracked via generate_from_spec dispatch" {
  # shellcheck disable=2329
  _spec_dp_sub() {
    dybatpho::opts::setup "Dispatched sub" -
    dybatpho::opts::disp "Help" --help action:"dybatpho::generate_help _spec_dp_sub"
  }
  # shellcheck disable=2329
  _spec_dp_root() {
    dybatpho::opts::setup "" -
    dybatpho::opts::cmd mysub _spec_dp_sub
  }

  # The dispatched action exits, so it needs the isolating form of `run`.
  run dybatpho::generate_from_spec _spec_dp_root mysub --help
  assert_success
  assert_line --index 0 --partial "mysub"
}

@test "switch metadata expands bracketed aliases in help and schema" {
  # shellcheck disable=2329
  _spec_alias_forms() {
    dybatpho::opts::setup "Alias forms" -
    dybatpho::opts::flag "Colored output" COLORED --color alias:--{no-}colour
    dybatpho::opts::flag "Cache toggle" CACHE --cache alias:--with{out}-cache
    dybatpho::opts::flag "Quiet mode" QUIET --quiet alias:-q
    dybatpho::opts::flag "Tracing" TRACING --trace aliases:--{no-}tracing,--with{out}-timing,-t
  }

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_alias_forms
  assert_success
  assert_output --partial "--colour"
  assert_output --partial "--no-colour"
  assert_output --partial "--with-cache"
  assert_output --partial "--without-cache"
  assert_output --partial "-q"
  assert_output --partial "--no-tracing"
  assert_output --partial "--without-timing"
  assert_output --partial "-t"
}

@test "bracketed aliases parse into the same destination variable" {
  # shellcheck disable=2329
  _spec_alias_parse() {
    dybatpho::opts::setup "" - action:'printf "%s|%s" "${COLORED:-}" "${CACHE:-}"'
    dybatpho::opts::flag "Colored output" COLORED --color alias:--{no-}colour
    dybatpho::opts::flag "Cache toggle" CACHE --cache alias:--with{out}-cache
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_alias_parse --colour --with-cache)" "true|true"
  # The negative variants are accepted as switches and leave the flag unset.
  assert_equal "$(dybatpho::generate_from_spec _spec_alias_parse --no-colour --without-cache)" "|"
}

@test "generated parsers prompt for missing values" {
  # shellcheck disable=2329
  _spec_prompts() {
    dybatpho::opts::setup "" - action:'printf "%s|%s" "${NAME}" "${COLOR}"'
    dybatpho::opts::param "Name" NAME --name prompt:"Your name"
    dybatpho::opts::param "Color" COLOR --color choices:red,green prompt:"Pick a color"
  }

  local result
  result="$(printf 'Alice\n2\n' | dybatpho::generate_from_spec _spec_prompts 2> /dev/null)"
  assert_equal "${result}" "Alice|green"
}

@test "persistent params and display options are inherited by subcommands" {
  # shellcheck disable=2329
  _spec_persistent_sub() {
    dybatpho::opts::setup "Child" - action:'printf "%s" "${TOKEN}"'
  }
  # shellcheck disable=2329
  _spec_persistent_root() {
    dybatpho::opts::setup "Root" -
    dybatpho::opts::param "Token" TOKEN --token persistent:true
    dybatpho::opts::disp "Version" --version persistent:true action:'printf "1.0.0"'
    dybatpho::opts::cmd child _spec_persistent_sub
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_persistent_root child --token abc)" "abc"
  assert_equal "$(dybatpho::generate_from_spec _spec_persistent_root child --version)" "1.0.0"
}

@test "init:action: runs a shell action while initializing an option" {
  # shellcheck disable=2329
  _spec_init_action() {
    dybatpho::opts::setup "" - action:'printf "%s" "${STAMP}"'
    dybatpho::opts::param "Stamp" STAMP --stamp init:action:'STAMP=generated'
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_init_action)" "generated"
}

@test "generated artifacts expand bracketed aliases for every shell" {
  # shellcheck disable=2329
  _spec_alias_artifacts() {
    dybatpho::opts::setup "Alias artifacts" -
    dybatpho::opts::flag "Colored output" COLORED --color alias:--{no-}colour
    dybatpho::opts::flag "Cache toggle" CACHE --cache aliases:--with{out}-cache,-k
    dybatpho::opts::param "Name" NAME --name alias:-n
    dybatpho::opts::flag "Timing" TIMING --timing alias:--with{out}-timing
    dybatpho::opts::cmd deploy _spec_alias_artifacts_child
  }
  # shellcheck disable=2329
  _spec_alias_artifacts_child() {
    dybatpho::opts::setup "Child" -
  }

  run_traced dybatpho::generate_schema _spec_alias_artifacts tool
  assert_success
  assert_output --partial '"--no-colour"'
  assert_output --partial '"--without-cache"'
  assert_output --partial '"-k"'
  assert_output --partial '"--without-timing"'

  # Fish prints switch names without their leading dashes.
  local shell
  for shell in bash zsh fish; do
    run_traced dybatpho::generate_completion _spec_alias_artifacts "${shell}" tool
    assert_success
    assert_output --partial "no-colour"
    assert_output --partial "without-cache"
  done

  run_traced dybatpho::generate_man _spec_alias_artifacts tool
  assert_success
  assert_output --partial "--without-cache"
}

@test "short aliases stay usable while long aliases set the help label" {
  # shellcheck disable=2329
  _spec_alias_short() {
    dybatpho::opts::setup "" - action:'printf "%s|%s" "${QUIET:-}" "${NAME:-}"'
    dybatpho::opts::flag "Quiet" QUIET --quiet aliases:-q,--silent
    dybatpho::opts::param "Name" NAME --name aliases:-n
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_alias_short -q -n dybatpho)" "true|dybatpho"
  assert_equal "$(dybatpho::generate_from_spec _spec_alias_short --silent)" "true|"

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_alias_short
  assert_output --partial "-q"
  assert_output --partial "--silent"
  assert_output --partial "-n"
}

@test "dybatpho::select rejects ranges and multiple answers in single mode" {
  local selected
  # A range and a second answer are both refused before a plain name is accepted.
  selected="$(printf '1-2\n1,2\ngreen\n' | dybatpho::select 'Choose one color' 'red,green,blue' 2> /dev/null)"
  assert_equal "green" "${selected}"
}

@test "primary bracketed switches and short primaries flow through every artifact" {
  # shellcheck disable=2329
  _spec_primary_forms() {
    dybatpho::opts::setup "Primary forms" - action:'printf "%s|%s|%s" "${TOGGLE:-}" "${FEATURE:-}" "${QUIET:-}"'
    dybatpho::opts::flag "Toggle" TOGGLE --{no-}toggle
    dybatpho::opts::flag "Feature" FEATURE --with{out}-feature
    dybatpho::opts::flag "Quiet" QUIET -q alias:--quiet-mode
    dybatpho::opts::flag "Silent" SILENT -s aliases:-z,--silent-mode
    dybatpho::opts::flag "Extra" EXTRA --extra aliases:--{no-}extended,--with{out}-extras
    dybatpho::opts::disp "Version" --version action:'printf "2.0.0"'
  }

  assert_equal "$(dybatpho::generate_from_spec _spec_primary_forms --toggle --with-feature -q)" "true|true|true"
  assert_equal "$(dybatpho::generate_from_spec _spec_primary_forms --quiet-mode)" "||true"
  assert_equal "$(dybatpho::generate_from_spec _spec_primary_forms --version)" "2.0.0"

  __current_cmd_path=""
  run_traced dybatpho::generate_help _spec_primary_forms
  assert_success
  assert_output --partial "--no-toggle"
  assert_output --partial "--without-feature"
  assert_output --partial "-q"
  assert_output --partial "--quiet-mode"
  assert_output --partial "--no-extended"
  assert_output --partial "-z"
  assert_output --partial "--silent-mode"
  assert_output --partial "--version"

  run_traced dybatpho::generate_schema _spec_primary_forms tool
  assert_success
  assert_output --partial '"--no-toggle"'
  assert_output --partial '"--without-extras"'
  assert_output --partial '"--version"'
}
