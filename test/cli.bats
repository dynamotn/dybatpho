setup() {
  load test_helper
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

  run dybatpho::generate_from_spec _spec -a 1 -a 2 -a "3\"" -- -a
  assert_success
  assert_output "-a 1 -a 2 -a 3\" -- -a"
}

@test "dybatpho::generate_from_spec handling arguments with doesn't have sub commands" {
  # shellcheck disable=2329
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

# =============================================================================
# dybatpho::opts::flag
# =============================================================================

@test "dybatpho::opts::flag basic long switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$VERBOSE"
    dybatpho::opts::flag "Verbose" VERBOSE --verbose
  }

  run dybatpho::generate_from_spec _spec --verbose
  assert_success && assert_output "true"

  run dybatpho::generate_from_spec _spec
  assert_success && assert_output ""
}

@test "dybatpho::opts::flag basic short switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$DEBUGF"
    dybatpho::opts::flag "Debug" DEBUGF -d
  }

  run dybatpho::generate_from_spec _spec -d
  assert_success && assert_output "true"
}

@test "dybatpho::opts::flag multiple switches" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$MFLAG"
    dybatpho::opts::flag "Multi" MFLAG -m --multi --multiple
  }

  run dybatpho::generate_from_spec _spec -m
  assert_output "true"

  run dybatpho::generate_from_spec _spec --multi
  assert_output "true"

  run dybatpho::generate_from_spec _spec --multiple
  assert_output "true"
}

@test "dybatpho::opts::flag custom on/off values" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$FEAT"
    dybatpho::opts::flag "Feature" FEAT --feature on:yes off:no init:="no"
  }

  run dybatpho::generate_from_spec _spec --feature
  assert_output "yes"

  run dybatpho::generate_from_spec _spec
  assert_output "no"
}

@test "dybatpho::opts::flag init:@on" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$FFLAG"
    dybatpho::opts::flag "Flag" FFLAG --flag init:@on
  }

  run dybatpho::generate_from_spec _spec
  assert_output "true"
}

@test "dybatpho::opts::flag init:@off" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$OFFLAG"
    dybatpho::opts::flag "Flag" OFFLAG --flag on:yes off:no init:@off
  }

  run dybatpho::generate_from_spec _spec
  assert_output "no"
}

@test "dybatpho::opts::flag init:@keep preserves existing value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$KFLAG"
    dybatpho::opts::flag "Flag" KFLAG --flag init:@keep
  }

  export KFLAG=existing
  run dybatpho::generate_from_spec _spec
  assert_output "existing"
}

@test "dybatpho::opts::flag init:@unset unsets variable" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \${UFLAG:-UNSET}"
    dybatpho::opts::flag "Flag" UFLAG --flag init:@unset
  }

  export UFLAG=something
  run dybatpho::generate_from_spec _spec
  assert_output "UNSET"
}

@test "dybatpho::opts::flag --{no-} expand" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$NOFEAT"
    dybatpho::opts::flag "Feature" NOFEAT --{no-}feature
  }

  run dybatpho::generate_from_spec _spec --feature
  assert_output "true"

  run dybatpho::generate_from_spec _spec --no-feature
  assert_output ""
}

@test "dybatpho::opts::flag --with{out}- expand" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$WFEAT"
    dybatpho::opts::flag "Feature" WFEAT --with{out}-wfeat
  }

  run dybatpho::generate_from_spec _spec --with-wfeat
  assert_output "true"

  run dybatpho::generate_from_spec _spec --without-wfeat
  assert_output ""
}

@test "dybatpho::opts::flag export:false" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PRIVFLAG"
    dybatpho::opts::flag "Private" PRIVFLAG --flag export:false
  }

  run dybatpho::generate_from_spec _spec --flag
  assert_success && assert_output "true"
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

  run dybatpho::generate_from_spec _spec --name hello
  assert_success && assert_output "hello"
}

@test "dybatpho::opts::param basic short switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PVAL"
    dybatpho::opts::param "Value" PVAL -v
  }

  run dybatpho::generate_from_spec _spec -v world
  assert_success && assert_output "world"
}

@test "dybatpho::opts::param short switch with attached value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PVALATTACHED"
    dybatpho::opts::param "Value" PVALATTACHED -v
  }

  run dybatpho::generate_from_spec _spec -vworld
  assert_success && assert_output "world"
}

@test "dybatpho::opts::param multiple switches" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PMSW"
    dybatpho::opts::param "Multi" PMSW -p --param --parameter
  }

  run dybatpho::generate_from_spec _spec -p val1
  assert_output "val1"

  run dybatpho::generate_from_spec _spec --param val2
  assert_output "val2"

  run dybatpho::generate_from_spec _spec --parameter val3
  assert_output "val3"
}

@test "dybatpho::opts::param init:=" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PDEF"
    dybatpho::opts::param "Default" PDEF --default init:="default-value"
  }

  run dybatpho::generate_from_spec _spec
  assert_output "default-value"

  run dybatpho::generate_from_spec _spec --default override
  assert_output "override"
}

@test "dybatpho::opts::param optional:true with = value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$POPT"
    dybatpho::opts::param "Optional" POPT --opt optional:true
  }

  # With = syntax, value is passed directly
  run dybatpho::generate_from_spec _spec --opt=value
  assert_output "value"
}

@test "dybatpho::opts::param optional:true without value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$POPT2"
    dybatpho::opts::param "Optional" POPT2 --opt2 optional:true
  }

  run dybatpho::generate_from_spec _spec --opt2
  assert_output "true"

  run dybatpho::generate_from_spec _spec
  assert_output ""
}

@test "dybatpho::opts::param optional:true with separated value" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" PREST action:"printf '%s|%s\n' \"\$POPT3\" \"\$PREST\""
    dybatpho::opts::param "Optional" POPT3 --opt3 optional:true
  }

  run dybatpho::generate_from_spec _spec --opt3 value
  assert_success && assert_output "value|"
}

@test "dybatpho::opts::param validate passes for valid input" {
  _validate_positive() { [[ "$1" -gt 0 ]] 2> /dev/null; }
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo \$PCOUNT"
    dybatpho::opts::param "Count" PCOUNT --count validate:"_validate_positive \$OPTARG"
  }

  run dybatpho::generate_from_spec _spec --count 5
  assert_success && assert_output "5"
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

  run dybatpho::generate_from_spec _spec hello
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

  run dybatpho::generate_from_spec _spec --name dynamo
  assert_success
  assert_output "dynamo"
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

@test "dybatpho::opts::flag omits variable assignment with dash" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" REST action:"echo ${REST:-EMPTY}"
    dybatpho::opts::flag "Verbose" - --verbose
  }

  run dybatpho::generate_from_spec _spec --verbose
  assert_success
  assert_output "EMPTY"
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

  run dybatpho::generate_from_spec _spec --version
  assert_success && assert_output "v1.0"
}

@test "dybatpho::opts::disp short switch" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" -
    dybatpho::opts::disp "Show help" -h action:"echo help-text"
  }

  run dybatpho::generate_from_spec _spec -h
  assert_success && assert_output "help-text"
}

@test "dybatpho::opts::disp exits before action runs" {
  # shellcheck disable=2329
  _spec() {
    dybatpho::opts::setup "" - action:"echo main"
    dybatpho::opts::disp "Version" --version action:"echo v2.0"
  }

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

  run dybatpho::generate_from_spec _spec_parent child hello
  assert_success && assert_output "hello"
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

  run dybatpho::generate_from_spec _spec_flag_parent child --cflag
  assert_success && assert_output "true"
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

  run dybatpho::generate_from_spec _spec_root mid leaf world
  assert_success && assert_output "leaf: world"
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

  run dybatpho::generate_from_spec _spec_gc_parent --gflag child --cflag2
  assert_success && assert_output "true:true"
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

  run dybatpho::generate_from_spec _spec_multi_parent cmda
  assert_output "cmd-a"

  run dybatpho::generate_from_spec _spec_multi_parent cmdb
  assert_output "cmd-b"
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

# =============================================================================
# dybatpho::generate_help
# =============================================================================

@test "dybatpho::generate_help shows usage line" {
  # shellcheck disable=2329
  _spec_hu() {
    dybatpho::opts::setup "My tool" -
  }

  __current_cmd_path=""
  run dybatpho::generate_help _spec_hu
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
  run dybatpho::generate_help _spec_hd
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
  run dybatpho::generate_help _spec_ho
  assert_output --partial "Options:"
  assert_output --partial "--verbose"
  assert_output --partial "Enable verbose"
  assert_output --partial "--name"
  assert_output --partial "Set name"
}

@test "dybatpho::generate_help param shows <VAR> in label" {
  # shellcheck disable=2329
  _spec_hpv() {
    dybatpho::opts::setup "" -
    dybatpho::opts::param "Value" HPVAL --param-val
  }

  __current_cmd_path=""
  run dybatpho::generate_help _spec_hpv
  assert_output --partial "<HPVAL>"
}

@test "dybatpho::generate_help marks required:true params automatically" {
  # shellcheck disable=2329
  _spec_hreq() {
    dybatpho::opts::setup "" -
    dybatpho::opts::param "Set name" HREQ --name required:true
  }

  __current_cmd_path=""
  run dybatpho::generate_help _spec_hreq
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
  run dybatpho::generate_help _spec_hdisp
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
  run dybatpho::generate_help _spec_hc
  assert_output --partial "Commands:"
  assert_output --partial "sub1"
  assert_output --partial "First sub command"
  assert_output --partial "sub2"
  assert_output --partial "Second sub command"
}

@test "dybatpho::generate_help no Commands section when no subcommands" {
  # shellcheck disable=2329
  _spec_hnc() {
    dybatpho::opts::setup "No subcommands" -
  }

  __current_cmd_path=""
  run dybatpho::generate_help _spec_hnc
  refute_output --partial "Commands:"
}

@test "dybatpho::generate_help subcommand path shown in usage from __current_cmd_path" {
  # shellcheck disable=2329
  _spec_hsp() {
    dybatpho::opts::setup "Sub description" -
  }

  __current_cmd_path="weather"
  run dybatpho::generate_help _spec_hsp
  assert_line --index 0 --partial "weather"
}

@test "dybatpho::generate_help nested subcommand path in usage" {
  # shellcheck disable=2329
  _spec_hnsp() {
    dybatpho::opts::setup "Nested sub" -
  }

  __current_cmd_path="ip internet"
  run dybatpho::generate_help _spec_hnsp
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
  run dybatpho::generate_help _spec_hh
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
  run dybatpho::generate_help _spec_hlbl
  assert_output --partial "[--custom]"
}

@test "dybatpho::generate_help --{no-} expands both variants" {
  # shellcheck disable=2329
  _spec_hno() {
    dybatpho::opts::setup "" -
    dybatpho::opts::flag "Toggle" HTOGGLE --{no-}toggle
  }

  __current_cmd_path=""
  run dybatpho::generate_help _spec_hno
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
  run dybatpho::generate_help _spec_hwith
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

  run dybatpho::generate_from_spec _spec_dp_root mysub --help
  assert_success
  assert_line --index 0 --partial "mysub"
}
