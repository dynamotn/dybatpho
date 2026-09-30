# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file diff.sh
# @brief Utilities for comparing text and structured documents
# @namespace dybatpho
# @description
#   Showing a user what changed is something scripts keep doing and keep doing
#   differently: one shells out to `diff` with its own flags, another to `jq`,
#   and a snapshot assertion dumps whatever `diff -u` printed. This module is
#   the one place that answers it.
#
#   The text diff is a unified diff colored by this module rather than by
#   `diff --color`, which only GNU has. The comparison itself uses `diff -u`,
#   which GNU, BSD and BusyBox all understand, so the output is the same
#   wherever the script runs.
#
#   The structured diffs answer a different question. A line diff of
#   reformatted JSON is noise; what a reader wants is which keys were added,
#   removed, or given a new value. Both documents are flattened to
#   `path<TAB>value` pairs and compared by path, so reordering a document
#   changes nothing and a moved key is not reported as a rewrite.
# @tip Every comparison takes a file path, `-` for stdin, or the text itself,
#   and only one side can be stdin
# @tip A side that names an existing file is read as that file. Text that could
#   itself be a path -- a command's output, say -- belongs in a file first, or
#   the wrong thing gets compared
# @tip `dybatpho::diff_text` needs no external command; the structured diffs
#   need `jq`, and `dybatpho::diff_yaml` needs `yq` to reach JSON first
# @env DYBATPHO_DIFF_COLOR string Force color on or off; the default follows `NO_COLOR` and whether stdout is a terminal
# @env DYBATPHO_DIFF_CONTEXT number Lines of context in a text diff, default is `3`
# @see
#   - `example/diff_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_DIFF_CONTEXT number Lines of context around each change, default is `3`
DYBATPHO_DIFF_CONTEXT="${DYBATPHO_DIFF_CONTEXT:-3}"
# @env DYBATPHO_DIFF_COLOR string `true` or `false` to decide coloring, empty to detect it
DYBATPHO_DIFF_COLOR="${DYBATPHO_DIFF_COLOR-}"

#######################################
# @description Return success when the output should carry ANSI color.
#   `DYBATPHO_DIFF_COLOR` decides when it is set, which is what lets a test
#   assert on colored output without a terminal; otherwise `NO_COLOR` and
#   whether stdout is a terminal do.
# @noargs
# @exitcode 0 Color should be emitted
# @exitcode 1 It should not
# @internal
#######################################
function __dybatpho_diff_wants_color {
  if [[ -n "${DYBATPHO_DIFF_COLOR}" ]]; then
    dybatpho::is true "${DYBATPHO_DIFF_COLOR}"
    return
  fi
  [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]
}

#######################################
# @description Resolve one side of a comparison to a file, into a named
#   variable. `-` is stdin, an existing file is itself, and anything else is
#   text, which is written to a temporary file so `diff` has two paths to
#   compare either way.
# @arg $1 string Name of the variable receiving the path
# @arg $2 string File path, `-`, or text
# @arg $3 string Label used in the diff header
# @set The named variable
# @internal
#######################################
function __dybatpho_diff_side_into {
  local -n __dybatpho_diff_side_ref="$1"
  local __dybatpho_diff_source="$2"

  if dybatpho::is file "${__dybatpho_diff_source}"; then
    __dybatpho_diff_side_ref="${__dybatpho_diff_source}"
    return 0
  fi

  # Not a `__dybatpho`-prefixed name: `dybatpho::create_temp` refuses one,
  # because a caller handing over a library-owned name would have its nameref
  # bound to the library's variable instead of its own.
  local dybatpho_diff_temp
  dybatpho::create_temp dybatpho_diff_temp ".txt" "diff-$3"
  if [[ "${__dybatpho_diff_source}" == "-" ]]; then
    cat > "${dybatpho_diff_temp}"
  else
    printf '%s\n' "${__dybatpho_diff_source}" > "${dybatpho_diff_temp}"
  fi
  __dybatpho_diff_side_ref="${dybatpho_diff_temp}"
}

#######################################
# @description Print a unified diff line with the color its prefix calls for.
# @arg $1 string One line of unified diff output
# @arg $2 string `1` to color, `0` to print plain
# @stdout The line
# @internal
#######################################
function __dybatpho_diff_paint {
  local line="$1"
  if (($2 == 0)); then
    printf '%s\n' "${line}"
    return 0
  fi

  case "${line}" in
    '+++'* | '---'*) printf '\033[1m%s\033[0m\n' "${line}" ;;
    '@@'*) printf '\033[36m%s\033[0m\n' "${line}" ;;
    '+'*) printf '\033[32m%s\033[0m\n' "${line}" ;;
    '-'*) printf '\033[31m%s\033[0m\n' "${line}" ;;
    *) printf '%s\n' "${line}" ;;
  esac
}

#######################################
# @description Compare two texts and print a colored unified diff.
#   The exit code is `diff`'s own, so the call reads as a question in a
#   conditional: zero when the two are identical, one when they are not.
# @arg $1 string File path, `-` for stdin, or text
# @arg $2 string File path, `-` for stdin, or text
# @arg $3 string Optional label for the first side, default is its path
# @arg $4 string Optional label for the second side, default is its path
# @stdout A unified diff, empty when the two are identical
# @exitcode 0 The two are identical
# @exitcode 1 They differ
# @example
#   dybatpho::diff_text /etc/nginx/nginx.conf "${rendered}" current proposed
#######################################
function dybatpho::diff_text {
  local first second
  dybatpho::expect_args first second -- "$@"
  local first_label="${3-}" second_label="${4-}"

  # Text that came in as a literal is compared through a temporary file, and
  # naming that file in the header would print a path that means nothing and
  # differs every run. `a` and `b` say what the side is instead.
  [[ -n "${first_label}" ]] || dybatpho::is file "${first}" || first_label="a"
  [[ -n "${second_label}" ]] || dybatpho::is file "${second}" || second_label="b"

  local first_file second_file
  __dybatpho_diff_side_into first_file "${first}" "a"
  __dybatpho_diff_side_into second_file "${second}" "b"

  local color=0
  __dybatpho_diff_wants_color && color=1

  local raw status=0
  # `-u` is the one unified-diff flag GNU, BSD and BusyBox agree on. `--label`
  # is not, so a caller that named its sides gets the rename applied here
  # rather than by the tool.
  raw="$(diff -U "${DYBATPHO_DIFF_CONTEXT}" -- "${first_file}" "${second_file}")" || status=$?
  ((status == 0)) && return 0

  local line
  while IFS= read -r line; do
    case "${line}" in
      '--- '*) [[ -z "${first_label}" ]] || line="--- ${first_label}" ;;
      '+++ '*) [[ -z "${second_label}" ]] || line="+++ ${second_label}" ;;
      *) ;; # kcov(skip) - a case arm has no command to fire on
    esac
    __dybatpho_diff_paint "${line}" "${color}"
  done <<< "${raw}"

  return 1
}

#######################################
# @description Summarize a text comparison as one line.
#   `~K` counts hunks, not changed lines: a unified diff records a rewritten
#   line as one removal and one addition, so calling that a change as well
#   would count it twice.
# @arg $1 string File path, `-` for stdin, or text
# @arg $2 string File path, `-` for stdin, or text
# @stdout `+N -M ~K`: lines added, lines removed, and hunks touched
# @exitcode 0 The two are identical
# @exitcode 1 They differ
# @example
#   dybatpho::diff_summary "${before}" "${after}" || true
#   # +12 -3 ~4
#######################################
function dybatpho::diff_summary {
  local first second
  dybatpho::expect_args first second -- "$@"

  local first_file second_file
  __dybatpho_diff_side_into first_file "${first}" "a"
  __dybatpho_diff_side_into second_file "${second}" "b"

  local raw status=0
  raw="$(diff -U0 -- "${first_file}" "${second_file}")" || status=$?

  local added=0 removed=0 hunks=0 line
  if ((status != 0)); then
    while IFS= read -r line; do
      case "${line}" in
        '+++'* | '---'*) ;; # kcov(skip) - a case arm has no command to fire on
        '@@'*) hunks=$((hunks + 1)) ;;
        '+'*) added=$((added + 1)) ;;
        '-'*) removed=$((removed + 1)) ;;
        *) ;; # kcov(skip) - a case arm has no command to fire on
      esac
    done <<< "${raw}"
  fi

  printf '+%s -%s ~%s\n' "${added}" "${removed}" "${hunks}"
  ((status == 0)) && return 0
  return 1
}

#######################################
# @description Flatten a JSON document to sorted `path<TAB>value` lines.
# @arg $1 string JSON file path
# @stdout One line per scalar, sorted by path
# @exitcode 0 The document was flattened
# @exitcode 1 The document is not valid JSON
# @internal
#######################################
function __dybatpho_diff_flatten {
  # A leaf is a scalar or an empty container. `scalars` alone would not do:
  # it drops a key whose value is `null`, and removing such a key would then
  # be reported as no change at all. An empty object or array is a leaf too,
  # so replacing one with a value is reported rather than passed over.
  #
  # Array indices join the path as plain numbers, so `.a[0].b` reads as
  # `a.0.b`: one syntax for both kinds of step, which keeps the comparison
  # below a plain string match.
  local filter='def leaf: if type == "object" or type == "array" then length == 0 else true end;'
  filter+=' . as $doc'
  filter+=' | [ if leaf then [] else empty end ] + [ paths(leaf) ]'
  filter+=' | .[] as $p'
  filter+=' | [ (if ($p | length) == 0 then "." else ($p | map(tostring) | join(".")) end),'
  filter+=' ($doc | getpath($p) | tojson) ]'
  filter+=' | @tsv'
  jq -r "${filter}" -- "$1" | LC_ALL=C sort
}

#######################################
# @description Compare two JSON documents by key rather than by line.
#   A reordered or reformatted document reports no change, because the
#   comparison is between the values at each path.
# @arg $1 string JSON file path, `-` for stdin, or JSON text
# @arg $2 string JSON file path, `-` for stdin, or JSON text
# @stdout One line per difference: `+ path = value`, `- path = value`, or `~ path: old -> new`
# @exitcode 0 The two documents hold the same values
# @exitcode 1 They differ
# @exitcode 127 `jq` is not installed
# @example
#   dybatpho::diff_json old-state.json new-state.json
#   # ~ replicas: 2 -> 3
#   # + labels.tier = "web"
#######################################
function dybatpho::diff_json {
  local first second
  dybatpho::expect_args first second -- "$@"

  dybatpho::is command jq > /dev/null \
    || dybatpho::die "${FUNCNAME[0]}: jq is required to compare documents by key" 127

  local first_file second_file
  __dybatpho_diff_side_into first_file "${first}" "a"
  __dybatpho_diff_side_into second_file "${second}" "b"

  local -A before=() after=()
  local path value
  while IFS=$'\t' read -r path value; do
    before["${path}"]="${value}"
  done < <(__dybatpho_diff_flatten "${first_file}")
  while IFS=$'\t' read -r path value; do
    after["${path}"]="${value}"
  done < <(__dybatpho_diff_flatten "${second_file}")

  local color=0
  __dybatpho_diff_wants_color && color=1

  local -a paths=()
  for path in "${!before[@]}" "${!after[@]}"; do
    paths+=("${path}")
  done

  local differed=0 seen
  local -A reported=()
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    seen="${reported[${path}]-}"
    [[ -z "${seen}" ]] || continue
    reported["${path}"]=1

    if [[ -z "${before[${path}]+set}" ]]; then
      __dybatpho_diff_report "${color}" added "${path}" "${after[${path}]}"
      differed=1
    elif [[ -z "${after[${path}]+set}" ]]; then
      __dybatpho_diff_report "${color}" removed "${path}" "${before[${path}]}"
      differed=1
    elif [[ "${before[${path}]}" != "${after[${path}]}" ]]; then
      __dybatpho_diff_report "${color}" changed "${path}" \
        "${before[${path}]}" "${after[${path}]}"
      differed=1
    fi
  done < <(((${#paths[@]})) && printf '%s\n' "${paths[@]}" | LC_ALL=C sort -u)

  ((differed == 0)) && return 0
  return 1
}

#######################################
# @description Print one structural difference.
# @arg $1 number `1` to color, `0` to print plain
# @arg $2 string Kind: `added`, `removed`, or `changed`
# @arg $3 string Path
# @arg $4 string Value, or the old value for a change
# @arg $5 string New value, for a change
# @stdout The formatted line
# @internal
#######################################
function __dybatpho_diff_report {
  local color="$1" kind="$2" path="$3" value="$4" replacement="${5-}"
  local body tint

  # The marker is an argument rather than part of the format: a format
  # beginning with `-` is read as an option, and `printf` then refuses it.
  case "${kind}" in
    added)
      printf -v body '%s %s = %s' '+' "${path}" "${value}"
      tint='32'
      ;;
    removed)
      printf -v body '%s %s = %s' '-' "${path}" "${value}"
      tint='31'
      ;;
    *)
      printf -v body '%s %s: %s -> %s' '~' "${path}" "${value}" "${replacement}"
      tint='33'
      ;;
  esac

  if ((color == 1)); then
    printf '\033[%sm%s\033[0m\n' "${tint}" "${body}"
    return 0
  fi
  printf '%s\n' "${body}"
}

#######################################
# @description Compare two YAML documents by key rather than by line.
#   Both are converted to JSON first, so anchors, quoting style and key order
#   are not reported as changes.
# @arg $1 string YAML file path, `-` for stdin, or YAML text
# @arg $2 string YAML file path, `-` for stdin, or YAML text
# @stdout One line per difference, in the form `dybatpho::diff_json` prints
# @exitcode 0 The two documents hold the same values
# @exitcode 1 They differ
# @exitcode 127 `jq` or `yq` is not installed
# @example
#   dybatpho::diff_yaml deploy-old.yaml deploy-new.yaml
#######################################
function dybatpho::diff_yaml {
  local first second
  dybatpho::expect_args first second -- "$@"

  local first_file second_file
  __dybatpho_diff_side_into first_file "${first}" "a"
  __dybatpho_diff_side_into second_file "${second}" "b"

  local first_json second_json
  dybatpho::create_temp first_json ".json" "diff-a"
  dybatpho::create_temp second_json ".json" "diff-b"
  dybatpho::yaml_to_json "${first_file}" "${first_json}"
  dybatpho::yaml_to_json "${second_file}" "${second_json}"

  dybatpho::diff_json "${first_json}" "${second_json}"
}
