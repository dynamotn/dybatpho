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
#
#   The tree diff walks two directories and reports each entry that was added,
#   removed, rewritten, or changed kind, comparing files by content and links
#   by target, so a copy with fresh timestamps is no change and a link is never
#   followed into whatever it points at.
# @tip Every text and document comparison takes a file path, `-` for stdin, or the text itself,
#   and only one side can be stdin
# @tip A side that names an existing file is read as that file. Text that could
#   itself be a path -- a command's output, say -- belongs in a file first, or
#   the wrong thing gets compared
# @tip `dybatpho::diff_dir` takes two directories and needs only `find`, `cmp`
#   and `sort`
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
  dybatpho::color_supported stdout
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
# @exitcode 2 Either document is not valid JSON
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
  __dybatpho_diff_expect_json "${FUNCNAME[0]}" "${first_file}" first
  __dybatpho_diff_expect_json "${FUNCNAME[0]}" "${second_file}" second

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
# @description Stop unless a file holds at least one JSON value.
#   The comparison reads each side through a process substitution, whose exit
#   status is lost, so a document that does not parse used to flatten to
#   nothing -- and two broken documents then compared as identical. An empty
#   file is refused too: it holds no value to compare.
# @arg $1 string Name of the public function, for the message
# @arg $2 string File to check
# @arg $3 string Which side it is: `first` or `second`
# @exitcode 2 The file is not valid JSON
# @internal
#######################################
function __dybatpho_diff_expect_json {
  jq -e 'true' -- "$2" > /dev/null 2>&1 \
    || dybatpho::die "$1: Not valid JSON: the $3 document" 2
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
# @exitcode 2 Either document is not valid YAML
# @exitcode 127 `jq` or `yq` is not installed
# @example
#   dybatpho::diff_yaml deploy-old.yaml deploy-new.yaml
# @note Needs the `json` module: `dybatpho::load json`, or `--modules diff json`
#######################################
function dybatpho::diff_yaml {
  local first second
  dybatpho::expect_args first second -- "$@"
  __dybatpho_diff_need_json

  local first_file second_file
  __dybatpho_diff_side_into first_file "${first}" "a"
  __dybatpho_diff_side_into second_file "${second}" "b"

  local first_json second_json
  dybatpho::create_temp first_json ".json" "diff-a"
  dybatpho::create_temp second_json ".json" "diff-b"
  # The conversion's status is checked rather than left to `set -e`: a caller
  # testing the result in a condition has errexit suspended, and a document
  # that did not convert would then compare as an empty one.
  dybatpho::yaml_to_json "${first_file}" "${first_json}" 2> /dev/null \
    || dybatpho::die "${FUNCNAME[0]}: Not valid YAML: the first document" 2
  dybatpho::yaml_to_json "${second_file}" "${second_json}" 2> /dev/null \
    || dybatpho::die "${FUNCNAME[0]}: Not valid YAML: the second document" 2

  dybatpho::diff_json "${first_json}" "${second_json}"
}

#######################################
# @description Stop unless the `json` module is loaded.
#   Converting YAML to JSON is the `json` module's work. Text, JSON and
#   directory comparisons need nothing from it -- `diff_json` reads its input
#   with `jq` directly -- and `backup` and `testing` compare through this
#   module, so registering `json` as a dependency would load it into every
#   script that only diffs text; the YAML comparison asks for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `json`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `json` module is not loaded
# @internal
#######################################
function __dybatpho_diff_need_json {
  __dybatpho_helpers_need_module json __dybatpho_json_cmd_into "${FUNCNAME[1]}"
}

#######################################
# @description Collect a directory tree into a named associative array that
#   maps each entry's path, relative to the root, to its kind: `file`,
#   `directory`, `symlink`, or `other`.
#   The walk runs from inside the root, so a root that is itself a symbolic
#   link to a directory is walked as that directory, and `find` prints the
#   same `./`-relative paths on GNU, BSD and BusyBox. Entries are read
#   NUL-separated, which keeps a name holding a newline in one piece.
# @arg $1 string Name of the associative array to fill
# @arg $2 string Directory to walk
# @set The named array
# @internal
#######################################
function __dybatpho_diff_tree_into {
  local -n __dybatpho_diff_tree_ref="$1"
  local __dybatpho_diff_root="$2" __dybatpho_diff_entry __dybatpho_diff_full

  while IFS= read -r -d '' __dybatpho_diff_entry; do
    __dybatpho_diff_entry="${__dybatpho_diff_entry#./}"
    __dybatpho_diff_full="${__dybatpho_diff_root}/${__dybatpho_diff_entry}"
    if [[ -L "${__dybatpho_diff_full}" ]]; then
      __dybatpho_diff_tree_ref["${__dybatpho_diff_entry}"]="symlink"
    elif [[ -d "${__dybatpho_diff_full}" ]]; then
      __dybatpho_diff_tree_ref["${__dybatpho_diff_entry}"]="directory"
    elif [[ -f "${__dybatpho_diff_full}" ]]; then
      __dybatpho_diff_tree_ref["${__dybatpho_diff_entry}"]="file"
    else
      __dybatpho_diff_tree_ref["${__dybatpho_diff_entry}"]="other"
    fi
  # kcov never records the redirection line of a loop; the body above it runs.
  done < <(cd -- "${__dybatpho_diff_root}" && find . -mindepth 1 -print0) # kcov(skip)
}

#######################################
# @description Render a path on one line, escaping what would break the line.
#   A backslash, newline, tab, or carriage return is written as its C escape,
#   so every record stays on one line and a reader can still tell `a\nb` the
#   name from `a` and `b` the two names.
# @arg $1 string Path
# @stdout The escaped path, without a trailing newline
# @internal
#######################################
function __dybatpho_diff_escape_path {
  local path="$1"
  path="${path//\\/\\\\}"
  path="${path//$'\n'/\\n}"
  path="${path//$'\t'/\\t}"
  path="${path//$'\r'/\\r}"
  printf '%s' "${path}"
}

#######################################
# @description Print one directory difference.
# @arg $1 string Output mode: `color`, `plain`, or `null`
# @arg $2 string Marker: `+`, `-`, `~`, or `!`
# @arg $3 string Path, relative to the roots
# @arg $4 string Optional detail printed after the path, such as the two kinds
# @stdout The formatted record
# @internal
#######################################
function __dybatpho_diff_dir_report {
  local mode="$1" marker="$2" path="$3" detail="${4-}"

  if [[ "${mode}" == null ]]; then
    printf '%s %s\0' "${marker}" "${path}"
    return 0
  fi

  local body tint escaped
  escaped="$(__dybatpho_diff_escape_path "${path}")"
  printf -v body '%s %s%s' "${marker}" "${escaped}" "${detail}"
  if [[ "${mode}" == plain ]]; then
    printf '%s\n' "${body}"
    return 0
  fi

  case "${marker}" in
    '+') tint='32' ;;
    '-') tint='31' ;;
    '~') tint='33' ;;
    *) tint='35' ;;
  esac
  printf '\033[%sm%s\033[0m\n' "${tint}" "${body}"
}

#######################################
# @description Compare two directory trees entry by entry.
#   Every path under either root is reported once, sorted bytewise so the
#   output is the same on every machine:
#
#   - `+ path` exists only in the second tree;
#   - `- path` exists only in the first;
#   - `~ path` is a file whose content differs, or a symbolic link whose target
#     differs;
#   - `! path: file -> directory` changed kind between the two trees.
#
#   A directory's path carries a trailing `/` when it is added or removed, and
#   the entries inside it are reported too, so a removed directory reads as
#   the whole of what went with it. Files are compared by content with `cmp`,
#   so a copy with a new modification time is no change; permissions and
#   ownership are not compared. Symbolic links are compared by target and never
#   followed, so a link into a large tree does not drag that tree in.
#
#   A path holding a backslash, newline, tab, or carriage return is written
#   with C escapes so each record stays on one line; `--null` prints each
#   record raw and NUL-terminated instead, for a reader that needs the exact
#   name.
# @arg $1 string Options, then the first directory
# @arg $2 string Second directory
# @opt --summary, -s Print one `+A -R ~M` line instead, the `diff_summary` shape; a change of kind counts in `~`
# @opt --null, -z Terminate each record with NUL instead of a newline, uncolored and unescaped
# @stdout One record per difference, or the summary line
# @exitcode 0 The two trees hold the same entries with the same content
# @exitcode 1 They differ
# @exitcode 2 Either side is not a directory
# @example
#   dybatpho::diff_dir ./release-1.2 ./release-1.3
#   # + bin/new-tool
#   # - share/old.conf
#   # ~ etc/app.conf
#   # ! lib/plugins: file -> directory
#   dybatpho::diff_dir --summary ./release-1.2 ./release-1.3   # +1 -1 ~2
#######################################
function dybatpho::diff_dir {
  local summary=0 mode=plain
  while (($#)); do
    case "$1" in
      --summary | -s) summary=1 ;;
      --null | -z) mode=null ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
    shift
  done

  local first second
  dybatpho::expect_args first second -- "$@"
  # `diff` itself answers 2 for trouble, which keeps "could not compare" apart
  # from the 1 that means "they differ".
  dybatpho::is dir "${first}" \
    || dybatpho::die "${FUNCNAME[0]}: Not a directory: ${first}" 2
  dybatpho::is dir "${second}" \
    || dybatpho::die "${FUNCNAME[0]}: Not a directory: ${second}" 2

  if [[ "${mode}" == plain ]] && __dybatpho_diff_wants_color; then
    mode=color
  fi

  local -A before=() after=()
  __dybatpho_diff_tree_into before "${first}"
  __dybatpho_diff_tree_into after "${second}"

  local -a paths=()
  local path
  for path in "${!before[@]}" "${!after[@]}"; do
    paths+=("${path}")
  done

  local added=0 removed=0 changed=0 old new
  while IFS= read -r -d '' path; do
    old="${before[${path}]-}"
    new="${after[${path}]-}"

    if [[ -z "${old}" ]]; then
      added=$((added + 1))
      ((summary)) && continue
      [[ "${new}" != directory ]] || path+="/"
      __dybatpho_diff_dir_report "${mode}" '+' "${path}"
    elif [[ -z "${new}" ]]; then
      removed=$((removed + 1))
      ((summary)) && continue
      [[ "${old}" != directory ]] || path+="/"
      __dybatpho_diff_dir_report "${mode}" '-' "${path}"
    elif [[ "${old}" != "${new}" ]]; then
      changed=$((changed + 1))
      ((summary)) && continue
      __dybatpho_diff_dir_report "${mode}" '!' "${path}" ": ${old} -> ${new}"
    elif [[ "${old}" == file ]]; then
      cmp -s -- "${first}/${path}" "${second}/${path}" && continue
      changed=$((changed + 1))
      ((summary)) && continue
      __dybatpho_diff_dir_report "${mode}" '~' "${path}"
    elif [[ "${old}" == symlink ]]; then
      old="$(readlink -- "${first}/${path}")" || true
      new="$(readlink -- "${second}/${path}")" || true
      [[ "${old}" != "${new}" ]] || continue
      changed=$((changed + 1))
      ((summary)) && continue
      __dybatpho_diff_dir_report "${mode}" '~' "${path}"
    fi
  # kcov never records the redirection line of a loop; the body above it runs.
  done < <(((${#paths[@]})) && printf '%s\0' "${paths[@]}" | LC_ALL=C sort -z -u) # kcov(skip)

  ((summary)) && printf '+%s -%s ~%s\n' "${added}" "${removed}" "${changed}"
  ((added + removed + changed == 0)) && return 0
  return 1
}
