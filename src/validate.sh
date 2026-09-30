# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file validate.sh
# @brief One validator for the whole library: named value types and declarative rules
# @namespace dybatpho
# @description
#   Before this module every caller wrote its own check. `config` matched an
#   integer with one regex and a URL with another, `cli` matched a shell
#   variable name with a third, and a script that wanted an email address or an
#   existing path had nowhere to get one. The regexes drifted, the messages
#   drifted with them, and a fix in one place never reached the other.
#
#   This module owns the checks instead. A *type* is a name — `int`, `email`,
#   `url`, `ipv4`, `semver`, `file` — bound to a predicate, and
#   `dybatpho::validate_is` is the only call needed to apply one:
#
#   ```sh
#   dybatpho::validate_is email "${address}" || dybatpho::die "Not an address"
#   ```
#
#   A *rule* is the declarative form of the same idea, used where a value
#   arrives with constraints attached rather than a single type:
#   `dybatpho::validate_value` takes `type:`, `pattern:`, `choices:`, `min:`,
#   `max:`, `minlen:` and `maxlen:` and reports **every** violation it finds
#   rather than only the first, which is what lets `config` list a whole broken
#   file at once.
#
#   Nothing here shells out or touches the network, so the module depends on
#   the core modules alone and stays cheap enough for `config` and `cli` to
#   load unconditionally. The path types are the one exception to "pure
#   computation": they ask the filesystem, because "does this exist" cannot be
#   answered any other way.
#
#   `dybatpho::validate_register` adds a type of your own, which then works
#   everywhere a built-in type does, including in a `config` schema and in a
#   `cli` `type:` attribute.
# @see
#   - `example/validate_ops.sh`
#   - `dybatpho::config_schema`
#   - `dybatpho::opts::param`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_VALIDATE_ERRORS array Reasons recorded by the last `dybatpho::validate_value` call
declare -ga DYBATPHO_VALIDATE_ERRORS=()
# Type name -> predicate function. Filled with the built-ins below and widened
# by `dybatpho::validate_register`.
declare -gA __DYBATPHO_VALIDATE_PREDICATES=()
# Type name -> the noun a message uses for it, such as `an email address`.
declare -gA __DYBATPHO_VALIDATE_DESCRIPTIONS=()
# Alias -> canonical type name, so `integer` and `int` cannot drift apart.
declare -gA __DYBATPHO_VALIDATE_ALIASES=()
# Canonical names whose `min:`/`max:` bound the value itself rather than its
# length. Everything else counts characters.
declare -gA __DYBATPHO_VALIDATE_NUMERIC=()

# The regular expressions are named constants rather than literals inside the
# predicates: several of them are long enough that a reader needs to see the
# name to know what is being matched, and a test can pin one directly.
__DYBATPHO_VALIDATE_RE_INT='^[+-]?[0-9]+$'
__DYBATPHO_VALIDATE_RE_UINT='^[0-9]+$'
__DYBATPHO_VALIDATE_RE_NUMBER='^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
# The practical address rather than the one RFC 5322 allows. A quoted local
# part and a bracketed address literal are legal and effectively never typed
# into a configuration file, and accepting them costs the rejection of the
# typos that are.
__DYBATPHO_VALIDATE_RE_EMAIL='^[A-Za-z0-9._%+-]+@[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
__DYBATPHO_VALIDATE_RE_EMAIL+='(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'
# A scheme, `://`, and something that is not whitespace. Deliberately the same
# expression `config` used before this module existed, so a schema that passed
# then still passes now.
__DYBATPHO_VALIDATE_RE_URL='^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$'
# Kept character for character in step with `DYBATPHO_SEMVER_REGEX`; the two are
# pinned against each other in `test/validate.bats` so neither can drift.
__DYBATPHO_VALIDATE_RE_SEMVER='^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-([a-zA-Z0-9._-]+))?(\+([a-zA-Z0-9._-]+))?$'
__DYBATPHO_VALIDATE_RE_UUID='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
__DYBATPHO_VALIDATE_RE_MAC='^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$'
__DYBATPHO_VALIDATE_RE_HEX='^(0[xX])?[0-9a-fA-F]+$'
__DYBATPHO_VALIDATE_RE_SLUG='^[a-z0-9]+(-[a-z0-9]+)*$'
__DYBATPHO_VALIDATE_RE_IDENTIFIER='^[a-zA-Z_][a-zA-Z0-9_]*$'
__DYBATPHO_VALIDATE_RE_HOSTNAME='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*\.?$'
__DYBATPHO_VALIDATE_RE_DATE='^([0-9]{4})-([0-9]{2})-([0-9]{2})$'
__DYBATPHO_VALIDATE_RE_TIME='^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
__DYBATPHO_VALIDATE_RE_DURATION='^([0-9]+(\.[0-9]+)?(ns|us|ms|s|m|h|d|w))+$'

#######################################
# @description Match a value against an extended regular expression, without
#   letting a malformed expression reach the caller as a shell diagnostic.
#   Bash answers a broken pattern with exit status 2 and a message of its own,
#   which reads as a validation failure at the call site; here it is turned into
#   the library's own fatal error instead.
# @example
#   dybatpho::validate_matches "v1.2.3" '^v[0-9]'      # succeeds
#
# @arg $1 string Value to match
# @arg $2 string Extended regular expression
# @exitcode 0 The value matches
# @exitcode 1 The value does not match
# @exitcode 1 Stop the script when the expression is not a valid ERE
#######################################
function dybatpho::validate_matches {
  local value pattern
  dybatpho::expect_args value pattern -- "$@"
  local status=0
  # The match is behind a function rather than written inline. `[[ =~ ]]`
  # answers 2 for a pattern that will not compile, and that third answer is the
  # whole point here -- but `$?` taken straight off a conditional is the one
  # ShellCheck will not vouch for, since a conditional is not a command. A
  # function call is, and the redirection still hides Bash's own complaint
  # about the broken pattern.
  __dybatpho_validate_match "${value}" "${pattern}" 2> /dev/null || status=$?
  ((status < 2)) || dybatpho::die \
    "${FUNCNAME[0]}: '${pattern}' is not a valid extended regular expression"
  return "${status}"
}

#######################################
# @description Match a value against an extended regular expression.
# @arg $1 string Value to test
# @arg $2 string Extended regular expression
# @exitcode 0 The value matches
# @exitcode 1 The value does not match
# @exitcode 2 The expression is not a valid ERE
# @internal
#######################################
function __dybatpho_validate_match {
  [[ "$1" =~ $2 ]]
}

#######################################
# @description Resolve a type name, or an alias of one, to its canonical name.
#   This never terminates the script: it is called from inside a command
#   substitution, where `dybatpho::die` would only end the subshell and leave
#   the caller reporting success on an empty value.
# @arg $1 string Declared type name
# @stdout The canonical type name, when it is known
# @exitcode 0 The type is known
# @exitcode 1 The type is not registered
# @internal
#######################################
function __dybatpho_validate_canonical {
  local name="${1,,}"
  name="${__DYBATPHO_VALIDATE_ALIASES[${name}]-${name}}"
  [[ -v "__DYBATPHO_VALIDATE_PREDICATES[${name}]" ]] || return 1
  printf '%s' "${name}"
}

#######################################
# @description Return success when a type's `min:` and `max:` bound the value
#   itself rather than the number of characters in it.
# @arg $1 string Type name or alias
# @exitcode 0 The type is numeric
# @exitcode 1 The type is not numeric, or is not registered
# @internal
#######################################
function __dybatpho_validate_numeric_type {
  local canonical
  canonical="$(__dybatpho_validate_canonical "${1-}")" || return 1
  [[ -v "__DYBATPHO_VALIDATE_NUMERIC[${canonical}]" ]]
}

#######################################
# @description Compare two numbers written as decimal text, without arithmetic
#   the shell would get wrong. `((08 > 1))` is an error, because a leading zero
#   asks for base 8, and `((1.5 > 1))` is an error too, because Bash has no
#   fractional arithmetic at all. Both forms reach here from a configuration
#   file, so both have to compare rather than abort.
#
#   Two plain integers are compared as integers, which is the case that matters
#   for a port, a timeout, or a count and is the one that must not lose
#   precision. Anything else — a fraction, an exponent — is scaled to a fixed
#   six decimal places first, under `LC_ALL=C` so the radix character is a dot
#   whatever the host's locale says.
# @arg $1 string Left value
# @arg $2 string Right value
# @arg $3 string Name of the variable receiving `-1`, `0`, or `1`
# @set The named variable
# @exitcode 0 The comparison was made
# @exitcode 1 A value is not a number
# @internal
#######################################
function __dybatpho_validate_number_cmp {
  local __cmp_left="$1" __cmp_right="$2"
  local -n __cmp_out="$3"
  local __cmp_l __cmp_r
  if [[ "${__cmp_left}" =~ ^[+-]?[0-9]+$ && "${__cmp_right}" =~ ^[+-]?[0-9]+$ ]]; then
    __dybatpho_validate_plain_int __cmp_l "${__cmp_left}"
    __dybatpho_validate_plain_int __cmp_r "${__cmp_right}"
  else
    __dybatpho_validate_scaled __cmp_l "${__cmp_left}" || return 1
    __dybatpho_validate_scaled __cmp_r "${__cmp_right}" || return 1
  fi
  if ((__cmp_l < __cmp_r)); then
    __cmp_out=-1
  elif ((__cmp_l > __cmp_r)); then
    __cmp_out=1
  else
    __cmp_out=0
  fi
}

#######################################
# @description Read a signed decimal integer written with any number of leading
#   zeros, as a number the shell's arithmetic accepts.
# @arg $1 string Name of the variable receiving the number
# @arg $2 string Integer text, such as `007` or `-42`
# @set The named variable
# @internal
#######################################
function __dybatpho_validate_plain_int {
  local -n __int_out="$1"
  local __int_text="$2" __int_sign=""
  case "${__int_text}" in
    -*)
      __int_sign="-"
      __int_text="${__int_text#-}"
      ;;
    +*) __int_text="${__int_text#+}" ;;
    *) ;;
  esac
  __int_out=$((10#${__int_text:-0}))
  [[ "${__int_sign}" == "-" ]] && __int_out=$((-__int_out))
  return 0
}

#######################################
# @description Read a decimal number, in any notation `printf` accepts, as an
#   integer scaled by one million, so two of them compare with shell arithmetic.
# @arg $1 string Name of the variable receiving the scaled integer
# @arg $2 string Number text, such as `1.5` or `1e3`
# @set The named variable
# @exitcode 1 The text is not a number `printf` can read
# @internal
#######################################
function __dybatpho_validate_scaled {
  local -n __scaled_out="$1"
  local __scaled_text="$2" __scaled_formatted __scaled_sign=""
  local LC_ALL=C
  printf -v __scaled_formatted '%.6f' "${__scaled_text}" 2> /dev/null || return 1
  if [[ "${__scaled_formatted}" == -* ]]; then
    __scaled_sign="-"
    __scaled_formatted="${__scaled_formatted#-}"
  fi
  # The parts are combined by arithmetic rather than by concatenation: a
  # fraction such as `.5` formats to `0.500000`, and the string `0500000` would
  # then be read as octal by the comparison that follows.
  __scaled_out=$((10#${__scaled_formatted%.*} * 1000000 + 10#${__scaled_formatted#*.}))
  [[ "${__scaled_sign}" == "-" ]] && __scaled_out=$((-__scaled_out))
  return 0
}

#######################################
# @description Return success when a value is of the named type.
#   A type is a name bound to a predicate: the built-ins listed by
#   `dybatpho::validate_types`, plus anything added with
#   `dybatpho::validate_register`.
# @example
#   dybatpho::validate_is int "42"                   # yes
#   dybatpho::validate_is email "ops@example.com"    # yes
#   dybatpho::validate_is dir "${HOME}"              # yes, it exists
#   dybatpho::validate_is ipv4 "192.0.2.256"         # no
#
# @arg $1 string Type name or alias
# @arg $2 string Value to test
# @exitcode 0 The value is of that type
# @exitcode 1 The value is not
# @exitcode 1 Stop the script when the type is not registered
# @see
#   - `dybatpho::validate_types`
#   - `dybatpho::validate_register`
#######################################
function dybatpho::validate_is {
  local type value canonical
  dybatpho::expect_args type value -- "$@"
  canonical="$(__dybatpho_validate_canonical "${type}")" \
    || dybatpho::die "${FUNCNAME[0]}: '${type}' is not a known type"
  "${__DYBATPHO_VALIDATE_PREDICATES[${canonical}]}" "${value}"
}

#######################################
# @description Print the noun a message uses for a type, such as `an email
#   address` for `email`. Error messages are built from this, so a caller that
#   reports its own failure words it the same way the library does.
# @example
#   dybatpho::validate_describe int      # an integer
#   dybatpho::validate_describe url      # a URL
#
# @arg $1 string Type name or alias
# @stdout The description
# @exitcode 0 The description is printed
# @exitcode 1 Stop the script when the type is not registered
#######################################
function dybatpho::validate_describe {
  local type canonical
  dybatpho::expect_args type -- "$@"
  canonical="$(__dybatpho_validate_canonical "${type}")" \
    || dybatpho::die "${FUNCNAME[0]}: '${type}' is not a known type"
  printf '%s\n' "${__DYBATPHO_VALIDATE_DESCRIPTIONS[${canonical}]}"
}

#######################################
# @description Print every registered type name, one per line, in alphabetical
#   order. Aliases are not listed: they resolve to the names printed here.
# @noargs
# @stdout Canonical type names
# @exitcode 0 Always
#######################################
function dybatpho::validate_types {
  # The names are collected before the pipeline, not inside it. A loop feeding
  # `sort` runs in a subshell, and ShellCheck then treats `name` as a variable
  # modified in a subshell -- for every function in this file, not just this
  # one, because the check reasons about the name rather than the scope.
  local -a names=()
  names=(${__DYBATPHO_VALIDATE_PREDICATES[@]+"${!__DYBATPHO_VALIDATE_PREDICATES[@]}"})
  ((${#names[@]})) || return 0
  printf '%s\n' "${names[@]}" | LC_ALL=C sort
}

#######################################
# @description Register a type, or replace one that is already registered.
#   The predicate is a function taking the value as its only argument and
#   returning success when the value is of the type; it must not print anything
#   and must not terminate the script.
# @example
#   function _is_branch { [[ "$1" =~ ^(main|release/.+)$ ]]; }
#   dybatpho::validate_register branch _is_branch "a release branch"
#   dybatpho::validate_is branch "release/2.0"     # yes
#
# @arg $1 string Type name, lowercase letters, digits and underscores
# @arg $2 string Predicate function name
# @arg $3 string Description used in messages, such as `a release branch`
# @arg $4 string Optional `numeric` to make `min:`/`max:` bound the value rather than its length
# @set __DYBATPHO_VALIDATE_PREDICATES
# @set __DYBATPHO_VALIDATE_DESCRIPTIONS
# @exitcode 0 The type is registered
# @exitcode 1 Stop the script when the name is malformed or the predicate is not a function
# @see
#   - `dybatpho::validate_reset`
#######################################
function dybatpho::validate_register {
  local name predicate description
  dybatpho::expect_args name predicate description -- "$@"
  [[ "${name}" =~ ^[a-z][a-z0-9_]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${name}' is not a usable type name"
  dybatpho::is function "${predicate}" \
    || dybatpho::die "${FUNCNAME[0]}: '${predicate}' is not a function"
  [[ -n "${description}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: type '${name}' needs a description"
  __DYBATPHO_VALIDATE_PREDICATES["${name}"]="${predicate}"
  __DYBATPHO_VALIDATE_DESCRIPTIONS["${name}"]="${description}"
  if [[ "${4-}" == "numeric" ]]; then
    __DYBATPHO_VALIDATE_NUMERIC["${name}"]=1
  else
    unset "__DYBATPHO_VALIDATE_NUMERIC[${name}]"
  fi
  return 0
}

#######################################
# @description Register an alias for a type that is already known.
# @arg $1 string Alias name
# @arg $2 string Canonical type name
# @set __DYBATPHO_VALIDATE_ALIASES
# @exitcode 1 Stop the script when the canonical type is not registered
# @internal
#######################################
function __dybatpho_validate_alias {
  local alias="$1" canonical="$2"
  [[ -v "__DYBATPHO_VALIDATE_PREDICATES[${canonical}]" ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${canonical}' is not a known type" # kcov(skip)
  __DYBATPHO_VALIDATE_ALIASES["${alias}"]="${canonical}"
}

#######################################
# @description Record one reason the value was rejected.
# @arg $1 string Reason, phrased to follow the name of what was validated
# @set DYBATPHO_VALIDATE_ERRORS Appends the reason
# @internal
#######################################
function __dybatpho_validate_error {
  DYBATPHO_VALIDATE_ERRORS+=("$1")
}

#######################################
# @description Validate one value against a list of declarative rules, and
#   record every violation rather than stopping at the first.
#
#   Supported rules:
#
#   | Rule | Meaning |
#   | --- | --- |
#   | `type:<name>` | The value must be of that type; defaults to `string` |
#   | `pattern:<ere>` | The value must match that extended regular expression |
#   | `choices:a,b` | The value must be one of the listed choices |
#   | `min:<n>` / `max:<n>` | Bounds; numeric for a numeric type, character count otherwise |
#   | `minlen:<n>` / `maxlen:<n>` | Bounds on the character count, whatever the type |
#
#   A value that is not of its declared type is not then measured against the
#   other rules: `min:1` on something that is not a number has no answer worth
#   reporting, and a second message about it only buries the first.
#
#   The reasons are phrased to follow the name of whatever was validated, so a
#   caller prints `Invalid configuration ${key}: ${reason}` without rewording
#   them. `dybatpho::validate_errors` prints them.
# @example
#   if ! dybatpho::validate_value "${port}" type:int min:1 max:65535; then
#     dybatpho::die "Invalid --port: $(dybatpho::validate_errors)"
#   fi
#
# @arg $1 string Value to validate
# @arg $@ string Rules, as `name:value`
# @set DYBATPHO_VALIDATE_ERRORS Reset, then one entry per violation
# @exitcode 0 The value satisfies every rule
# @exitcode 1 At least one rule was violated
# @exitcode 1 Stop the script when a rule name, a rule value, or a type is not supported
# @see
#   - `dybatpho::validate_errors`
#   - `dybatpho::validate_or_die`
#######################################
function dybatpho::validate_value {
  local value
  dybatpho::expect_args value -- "$@"
  shift
  DYBATPHO_VALIDATE_ERRORS=()

  local type="string" pattern="" choices="" min="" max="" minlen="" maxlen=""
  local rule name setting
  for rule in "$@"; do
    [[ "${rule}" == *:* ]] \
      || dybatpho::die "${FUNCNAME[0]}: '${rule}' is not a \`name:value\` rule"
    name="${rule%%:*}"
    setting="${rule#*:}"
    case "${name}" in
      type) type="${setting}" ;;
      pattern) pattern="${setting}" ;;
      choices)
        [[ -n "${setting}" ]] \
          || dybatpho::die "${FUNCNAME[0]}: \`choices\` needs at least one choice"
        choices="${setting}"
        ;;
      min | max | minlen | maxlen)
        [[ "${setting}" =~ ${__DYBATPHO_VALIDATE_RE_INT} ]] \
          || dybatpho::die "${FUNCNAME[0]}: \`${name}\` needs a number, got '${setting}'"
        printf -v "${name}" '%s' "${setting}"
        ;;
      *) dybatpho::die "${FUNCNAME[0]}: '${name}' is not a supported rule" ;;
    esac
  done

  local canonical
  canonical="$(__dybatpho_validate_canonical "${type}")" \
    || dybatpho::die "${FUNCNAME[0]}: '${type}' is not a known type"

  if ! "${__DYBATPHO_VALIDATE_PREDICATES[${canonical}]}" "${value}"; then
    __dybatpho_validate_error \
      "expected ${__DYBATPHO_VALIDATE_DESCRIPTIONS[${canonical}]}, got \`${value}\`"
    return 1
  fi

  if [[ -n "${choices}" ]]; then
    local -a items=()
    local choice matched=false
    IFS=',' read -r -a items <<< "${choices}"
    for choice in ${items[@]+"${items[@]}"}; do
      [[ "${value}" == "${choice}" ]] && {
        matched=true
        break
      }
    done
    [[ "${matched}" == true ]] \
      || __dybatpho_validate_error "expected one of: ${choices}, got \`${value}\`"
  fi

  if [[ -n "${pattern}" ]] && ! dybatpho::validate_matches "${value}" "${pattern}"; then
    __dybatpho_validate_error "expected a value matching \`${pattern}\`, got \`${value}\`"
  fi

  local measured subject order
  if [[ -n "${min}" || -n "${max}" ]]; then
    if __dybatpho_validate_numeric_type "${canonical}"; then
      measured="${value}"
      subject=""
    else
      measured="${#value}"
      subject=" characters"
    fi
    if [[ -n "${min}" ]]; then
      __dybatpho_validate_number_cmp "${measured}" "${min}" order
      ((order >= 0)) || __dybatpho_validate_error "must be at least ${min}${subject}"
    fi
    if [[ -n "${max}" ]]; then
      __dybatpho_validate_number_cmp "${measured}" "${max}" order
      ((order <= 0)) || __dybatpho_validate_error "must be at most ${max}${subject}"
    fi
  fi

  [[ -z "${minlen}" ]] || ((${#value} >= minlen)) \
    || __dybatpho_validate_error "must be at least ${minlen} characters"
  [[ -z "${maxlen}" ]] || ((${#value} <= maxlen)) \
    || __dybatpho_validate_error "must be at most ${maxlen} characters"

  ((${#DYBATPHO_VALIDATE_ERRORS[@]} == 0))
}

#######################################
# @description Print the reasons recorded by the last `dybatpho::validate_value`
#   call, one per line.
# @noargs
# @stdout One reason per line, nothing when the last call succeeded
# @exitcode 0 Always
# @see
#   - `dybatpho::validate_value`
#######################################
function dybatpho::validate_errors {
  ((${#DYBATPHO_VALIDATE_ERRORS[@]} > 0)) || return 0
  printf '%s\n' "${DYBATPHO_VALIDATE_ERRORS[@]}"
}

#######################################
# @description Validate a value and stop the script when it is rejected,
#   naming what was being validated and every reason it failed.
# @example
#   dybatpho::validate_or_die "--port" "${PORT}" type:int min:1 max:65535
#   # Invalid --port: expected an integer, got `http`
#
# @arg $1 string Name of what is being validated, used in the diagnostic
# @arg $2 string Value to validate
# @arg $@ string Rules, as accepted by `dybatpho::validate_value`
# @set DYBATPHO_VALIDATE_ERRORS Reset, then one entry per violation
# @exitcode 0 The value satisfies every rule
# @exitcode 1 Stop the script when the value is rejected
# @see
#   - `dybatpho::validate_value`
#######################################
function dybatpho::validate_or_die {
  local label value
  dybatpho::expect_args label value -- "$@"
  shift 2
  dybatpho::validate_value "${value}" "$@" && return 0
  local reasons
  # The reasons are joined here rather than through a command substitution on
  # `dybatpho::validate_errors`, so the array this function just filled is the
  # one reported: a subshell would be reading its own copy.
  printf -v reasons '%s; ' "${DYBATPHO_VALIDATE_ERRORS[@]}"
  dybatpho::die "Invalid ${label}: ${reasons%'; '}"
}

#######################################
# @description Forget every type added with `dybatpho::validate_register` and
#   restore the built-ins to their original predicates. A test or an example
#   that registers a type of its own calls this to leave the registry the way it
#   found it.
# @noargs
# @set __DYBATPHO_VALIDATE_PREDICATES Reset to the built-in types
# @set __DYBATPHO_VALIDATE_DESCRIPTIONS Reset to the built-in descriptions
# @set __DYBATPHO_VALIDATE_ALIASES Reset to the built-in aliases
# @exitcode 0 Always
#######################################
function dybatpho::validate_reset {
  __DYBATPHO_VALIDATE_PREDICATES=()
  __DYBATPHO_VALIDATE_DESCRIPTIONS=()
  __DYBATPHO_VALIDATE_ALIASES=()
  __DYBATPHO_VALIDATE_NUMERIC=()
  __dybatpho_validate_register_builtins
}

# ---------------------------------------------------------------------------
# Built-in predicates
# ---------------------------------------------------------------------------

#######################################
# @description Accept any value, including the empty string.
# @arg $1 string Value to test
# @exitcode 0 Always
# @internal
#######################################
function __dybatpho_validate_is_string {
  [[ -n "${1+x}" ]]
}

#######################################
# @description Return success when a value holds something other than whitespace.
# @arg $1 string Value to test
# @exitcode 0 The value is not blank
# @exitcode 1 The value is empty or only whitespace
# @internal
#######################################
function __dybatpho_validate_is_nonempty {
  [[ -n "${1//[[:space:]]/}" ]]
}

#######################################
# @description Return success when a value is an integer, with an optional sign.
# @arg $1 string Value to test
# @exitcode 0 The value is an integer
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_int {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_INT} ]]
}

#######################################
# @description Return success when a value is a non-negative integer with no sign.
# @arg $1 string Value to test
# @exitcode 0 The value is an unsigned integer
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_uint {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_UINT} ]]
}

#######################################
# @description Return success when a value is a decimal number, with an optional
#   sign, fraction, and exponent.
# @arg $1 string Value to test
# @exitcode 0 The value is a number
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_number {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_NUMBER} ]]
}

#######################################
# @description Return success when a value is one of the words the library reads
#   as a boolean, in either direction and in any case.
# @arg $1 string Value to test
# @exitcode 0 The value is a boolean
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_bool {
  dybatpho::is true "${1-}" || dybatpho::is false "${1-}"
}

#######################################
# @description Return success when a value is a TCP or UDP port number.
#   Port 0 is refused: it asks the kernel to choose rather than naming a port,
#   so a configuration that carries it has not been configured.
# @arg $1 string Value to test
# @exitcode 0 The value is a port number from 1 to 65535
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_port {
  __dybatpho_validate_is_uint "${1-}" || return 1
  # A long run of digits overflows before it can be compared, so the width is
  # checked before the value is.
  ((${#1} <= 5)) || return 1
  ((10#$1 >= 1 && 10#$1 <= 65535))
}

#######################################
# @description Return success when a value is an email address.
# @arg $1 string Value to test
# @exitcode 0 The value is an email address
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_email {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_EMAIL} ]]
}

#######################################
# @description Return success when a value is an absolute URL: a scheme, `://`,
#   and a remainder that holds no whitespace.
# @arg $1 string Value to test
# @exitcode 0 The value is a URL
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_url {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_URL} ]]
}

#######################################
# @description Return success when a value is a host name.
#   The whole name is limited to 253 characters and each label to 63, which is
#   what DNS accepts; a label may not start or end with a hyphen, and a single
#   trailing dot is allowed because it is how a fully qualified name is written.
# @arg $1 string Value to test
# @exitcode 0 The value is a host name
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_hostname {
  local name="${1-}"
  [[ -n "${name}" ]] || return 1
  ((${#name} <= 253)) || return 1
  [[ "${name}" =~ ${__DYBATPHO_VALIDATE_RE_HOSTNAME} ]] || return 1
  local -a labels=()
  local label
  IFS='.' read -r -a labels <<< "${name%.}"
  for label in ${labels[@]+"${labels[@]}"}; do
    ((${#label} >= 1 && ${#label} <= 63)) || return 1
  done
  return 0
}

#######################################
# @description Return success when a value is an IPv4 address.
#   A leading zero is refused rather than ignored, because `inet_aton` and the
#   software built on it read `010` as octal: an address that means two things
#   is not one this library will agree to. `dybatpho::is_ipv4` in the `network`
#   module answers the same question the same way, and the two are pinned
#   against each other in `test/validate.bats`.
# @arg $1 string Value to test
# @exitcode 0 The value is an IPv4 address
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_ipv4 {
  [[ "${1-}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local -a octets=("${BASH_REMATCH[@]:1:4}")
  local octet
  for octet in "${octets[@]}"; do
    [[ "${octet}" == "0" || "${octet}" != 0* ]] || return 1
    ((10#${octet} <= 255)) || return 1
  done
  return 0
}

#######################################
# @description Return success when a value is an IPv6 address.
#   `::` may appear once and stands for a run of zero groups; the last two
#   groups may instead be written as a dotted IPv4 address. A zone index such as
#   `%eth0` is refused: it names an interface rather than a part of the address.
# @arg $1 string Value to test
# @exitcode 0 The value is an IPv6 address
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_ipv6 {
  local address="${1-}"
  [[ -n "${address}" && "${address}" != *%* ]] || return 1
  # Only the characters an address is written with; everything else is rejected
  # before the shape is examined.
  [[ "${address}" =~ ^[0-9a-fA-F:.]+$ ]] || return 1
  # `::` is the one abbreviation, so a second one leaves the length ambiguous.
  local remainder="${address#*::}"
  [[ "${address}" == *::* && "${remainder}" == *::* ]] && return 1

  local head tail
  if [[ "${address}" == *::* ]]; then
    head="${address%%::*}"
    tail="${address#*::}"
  else
    head="${address}"
    tail=""
  fi

  local -a groups=()
  local trailing_v4=0 part
  # A dotted tail occupies the last two groups, so it is counted as two and
  # removed before the colon-separated groups are counted.
  local last="${tail:-${head}}"
  if [[ "${last}" == *.* ]]; then
    part="${last##*:}"
    __dybatpho_validate_is_ipv4 "${part}" || return 1
    trailing_v4=2
    if [[ -n "${tail}" ]]; then
      tail="${tail%"${part}"}"
      tail="${tail%:}"
    else
      head="${head%"${part}"}"
      head="${head%:}"
    fi
  fi

  local counted=0 section
  for section in "${head}" "${tail}"; do
    [[ -n "${section}" ]] || continue
    # A section may not begin or end with a stray colon once `::` is removed.
    [[ "${section}" == :* || "${section}" == *: ]] && return 1
    IFS=':' read -r -a groups <<< "${section}"
    for part in ${groups[@]+"${groups[@]}"}; do
      [[ "${part}" =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
      counted=$((counted + 1))
    done
  done
  counted=$((counted + trailing_v4))

  if [[ "${address}" == *::* ]]; then
    # `::` must stand for at least one group, otherwise it was written where a
    # plain colon belonged.
    ((counted <= 7))
  else
    ((counted == 8))
  fi
}

#######################################
# @description Return success when a value is an IP address of either version.
# @arg $1 string Value to test
# @exitcode 0 The value is an IPv4 or IPv6 address
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_ip {
  __dybatpho_validate_is_ipv4 "${1-}" || __dybatpho_validate_is_ipv6 "${1-}"
}

#######################################
# @description Return success when a value is a CIDR block: an IP address, a
#   slash, and a prefix length that fits the address's version.
# @arg $1 string Value to test
# @exitcode 0 The value is a CIDR block
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_cidr {
  local block="${1-}"
  [[ "${block}" == */* ]] || return 1
  local address="${block%/*}" prefix="${block##*/}"
  __dybatpho_validate_is_uint "${prefix}" || return 1
  # A prefix is at most three digits, so anything longer cannot be one and
  # would overflow the comparison below.
  ((${#prefix} <= 3)) || return 1
  if __dybatpho_validate_is_ipv4 "${address}"; then
    ((10#${prefix} <= 32))
  elif __dybatpho_validate_is_ipv6 "${address}"; then
    ((10#${prefix} <= 128))
  else
    return 1
  fi
}

#######################################
# @description Return success when a value is a MAC address written with colons
#   or hyphens.
# @arg $1 string Value to test
# @exitcode 0 The value is a MAC address
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_mac {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_MAC} ]] || return 1
  # One separator or the other, never both in the same address.
  [[ "$1" != *:*-* && "$1" != *-*:* ]]
}

#######################################
# @description Return success when a value is a semantic version, with or
#   without the leading `v` the library accepts everywhere else.
# @arg $1 string Value to test
# @exitcode 0 The value is a semantic version
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_semver {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_SEMVER} ]]
}

#######################################
# @description Return success when a value is a UUID in the canonical
#   eight-four-four-four-twelve hexadecimal form.
# @arg $1 string Value to test
# @exitcode 0 The value is a UUID
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_uuid {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_UUID} ]]
}

#######################################
# @description Return success when a value is hexadecimal, with an optional
#   `0x` prefix.
# @arg $1 string Value to test
# @exitcode 0 The value is hexadecimal
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_hex {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_HEX} ]]
}

#######################################
# @description Return success when a value is one or more ASCII letters.
# @arg $1 string Value to test
# @exitcode 0 The value is alphabetic
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_alpha {
  [[ "${1-}" =~ ^[A-Za-z]+$ ]]
}

#######################################
# @description Return success when a value is one or more ASCII letters or digits.
# @arg $1 string Value to test
# @exitcode 0 The value is alphanumeric
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_alnum {
  [[ "${1-}" =~ ^[A-Za-z0-9]+$ ]]
}

#######################################
# @description Return success when a value is a lowercase slug: words of letters
#   and digits joined by single hyphens.
# @arg $1 string Value to test
# @exitcode 0 The value is a slug
# @exitcode 1 The value is not
# @see
#   - `dybatpho::string_slugify`
# @internal
#######################################
function __dybatpho_validate_is_slug {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_SLUG} ]]
}

#######################################
# @description Return success when a value is usable as a shell variable name.
# @arg $1 string Value to test
# @exitcode 0 The value is a shell variable name
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_identifier {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_IDENTIFIER} ]]
}

#######################################
# @description Return success when a value is a calendar date written as
#   `YYYY-MM-DD`. The day is checked against the length of the month, February
#   included, so `2023-02-29` is refused rather than accepted as well-formed.
# @arg $1 string Value to test
# @exitcode 0 The value is a date
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_date {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_DATE} ]] || return 1
  local year=$((10#${BASH_REMATCH[1]}))
  local month=$((10#${BASH_REMATCH[2]}))
  local day=$((10#${BASH_REMATCH[3]}))
  ((month >= 1 && month <= 12)) || return 1
  ((day >= 1)) || return 1
  local -a lengths=(31 28 31 30 31 30 31 31 30 31 30 31)
  local limit="${lengths[month - 1]}"
  if ((month == 2)) && ((year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))); then
    limit=29
  fi
  ((day <= limit))
}

#######################################
# @description Return success when a value is a wall-clock time written as
#   `HH:MM` or `HH:MM:SS`.
# @arg $1 string Value to test
# @exitcode 0 The value is a time
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_time {
  [[ "${1-}" =~ ${__DYBATPHO_VALIDATE_RE_TIME} ]]
}

#######################################
# @description Return success when a value is a duration: either a bare number
#   of seconds, or one or more `<number><unit>` pairs using `ns`, `us`, `ms`,
#   `s`, `m`, `h`, `d`, or `w`, as in `1h30m`.
# @arg $1 string Value to test
# @exitcode 0 The value is a duration
# @exitcode 1 The value is not
# @internal
#######################################
function __dybatpho_validate_is_duration {
  local value="${1-}"
  __dybatpho_validate_is_number "${value}" && return 0
  [[ "${value}" =~ ${__DYBATPHO_VALIDATE_RE_DURATION} ]]
}

#######################################
# @description Return success when a value names a path that exists, of any kind.
# @arg $1 string Value to test
# @exitcode 0 The path exists
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_validate_is_path {
  [[ -n "${1-}" ]] && dybatpho::is exist "$1"
}

#######################################
# @description Return success when a value names an existing regular file.
# @arg $1 string Value to test
# @exitcode 0 The file exists
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_validate_is_file {
  [[ -n "${1-}" ]] && dybatpho::is file "$1"
}

#######################################
# @description Return success when a value names an existing directory.
# @arg $1 string Value to test
# @exitcode 0 The directory exists
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_validate_is_dir {
  [[ -n "${1-}" ]] && dybatpho::is dir "$1"
}

#######################################
# @description Return success when a value names an existing symbolic link.
# @arg $1 string Value to test
# @exitcode 0 The link exists
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_validate_is_symlink {
  [[ -n "${1-}" ]] && dybatpho::is link "$1"
}

#######################################
# @description Return success when a value names a path this process can read.
# @arg $1 string Value to test
# @exitcode 0 The path is readable
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_validate_is_readable {
  [[ -n "${1-}" ]] && dybatpho::is readable "$1"
}

#######################################
# @description Return success when a value names a path this process can write.
# @arg $1 string Value to test
# @exitcode 0 The path is writable
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_validate_is_writable {
  [[ -n "${1-}" ]] && dybatpho::is writeable "$1"
}

#######################################
# @description Return success when a value names a path this process can execute.
# @arg $1 string Value to test
# @exitcode 0 The path is executable
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_validate_is_executable {
  [[ -n "${1-}" ]] && dybatpho::is executable "$1"
}

#######################################
# @description Return success when a value is an absolute path. Unlike the other
#   path types this asks nothing of the filesystem: it is about the shape of the
#   path, so it answers for a file that has not been created yet.
# @arg $1 string Value to test
# @exitcode 0 The path is absolute
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_validate_is_abspath {
  [[ "${1-}" == /* ]]
}

#######################################
# @description Return success when a value names a path whose parent directory
#   exists. This is the check an output file wants: the file itself is about to
#   be created, but the directory it lands in has to be there already.
# @arg $1 string Value to test
# @exitcode 0 The parent directory exists
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_validate_is_parent_dir {
  local path="${1-}"
  [[ -n "${path}" ]] || return 1
  local parent
  parent="$(dybatpho::path_dirname "${path}")"
  dybatpho::is dir "${parent}"
}

#######################################
# @description Bind every built-in type to its predicate and description.
#   Called when the module is sourced, and again by `dybatpho::validate_reset`.
# @noargs
# @set __DYBATPHO_VALIDATE_PREDICATES
# @set __DYBATPHO_VALIDATE_DESCRIPTIONS
# @set __DYBATPHO_VALIDATE_ALIASES
# @internal
#######################################
function __dybatpho_validate_register_builtins {
  dybatpho::validate_register string __dybatpho_validate_is_string "a string"
  dybatpho::validate_register nonempty __dybatpho_validate_is_nonempty "a non-empty value"
  dybatpho::validate_register int __dybatpho_validate_is_int "an integer" numeric
  dybatpho::validate_register uint __dybatpho_validate_is_uint "a non-negative integer" numeric
  dybatpho::validate_register number __dybatpho_validate_is_number "a number" numeric
  dybatpho::validate_register bool __dybatpho_validate_is_bool "a boolean"
  dybatpho::validate_register port __dybatpho_validate_is_port "a port number" numeric
  dybatpho::validate_register email __dybatpho_validate_is_email "an email address"
  dybatpho::validate_register url __dybatpho_validate_is_url "a URL"
  dybatpho::validate_register hostname __dybatpho_validate_is_hostname "a host name"
  dybatpho::validate_register ipv4 __dybatpho_validate_is_ipv4 "an IPv4 address"
  dybatpho::validate_register ipv6 __dybatpho_validate_is_ipv6 "an IPv6 address"
  dybatpho::validate_register ip __dybatpho_validate_is_ip "an IP address"
  dybatpho::validate_register cidr __dybatpho_validate_is_cidr "a CIDR block"
  dybatpho::validate_register mac __dybatpho_validate_is_mac "a MAC address"
  dybatpho::validate_register semver __dybatpho_validate_is_semver "a semantic version"
  dybatpho::validate_register uuid __dybatpho_validate_is_uuid "a UUID"
  dybatpho::validate_register hex __dybatpho_validate_is_hex "a hexadecimal value"
  dybatpho::validate_register alpha __dybatpho_validate_is_alpha "letters only"
  dybatpho::validate_register alnum __dybatpho_validate_is_alnum "letters and digits only"
  dybatpho::validate_register slug __dybatpho_validate_is_slug "a slug"
  dybatpho::validate_register identifier __dybatpho_validate_is_identifier "a shell variable name"
  dybatpho::validate_register date __dybatpho_validate_is_date "a date as YYYY-MM-DD"
  dybatpho::validate_register time __dybatpho_validate_is_time "a time as HH:MM or HH:MM:SS"
  dybatpho::validate_register duration __dybatpho_validate_is_duration "a duration"
  dybatpho::validate_register path __dybatpho_validate_is_path "an existing path"
  dybatpho::validate_register file __dybatpho_validate_is_file "an existing file"
  dybatpho::validate_register dir __dybatpho_validate_is_dir "an existing directory"
  dybatpho::validate_register symlink __dybatpho_validate_is_symlink "an existing symbolic link"
  dybatpho::validate_register readable __dybatpho_validate_is_readable "a readable path"
  dybatpho::validate_register writable __dybatpho_validate_is_writable "a writable path"
  dybatpho::validate_register executable __dybatpho_validate_is_executable "an executable path"
  dybatpho::validate_register abspath __dybatpho_validate_is_abspath "an absolute path"
  dybatpho::validate_register parent_dir __dybatpho_validate_is_parent_dir "a path whose parent directory exists"

  __dybatpho_validate_alias integer int
  __dybatpho_validate_alias unsigned uint
  __dybatpho_validate_alias boolean bool
  __dybatpho_validate_alias uri url
  __dybatpho_validate_alias host hostname
  __dybatpho_validate_alias directory dir
  __dybatpho_validate_alias link symlink
  __dybatpho_validate_alias writeable writable
  __dybatpho_validate_alias varname identifier
  __dybatpho_validate_alias notempty nonempty
}

__dybatpho_validate_register_builtins
