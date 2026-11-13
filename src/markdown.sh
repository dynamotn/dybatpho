# shellcheck shell=bash
# @file markdown.sh
# @brief Utilities for building structured Markdown content
# @namespace dybatpho
# @description
#   This module contains builders for the pieces a generated document is made
#   of: headings, lists, task lists, links, badges, fenced code blocks, tables,
#   and collapsible sections. It exists because a script that assembles a
#   report, a pull request description, or a release note otherwise
#   concatenates Markdown by hand, and an interpolated value containing `*`,
#   `_`, `[` or `|` then renders as formatting rather than as the text it was.
#
#   **Every builder escapes the text it is given.** A value read from a commit
#   message, a filename, or a command's output is therefore safe to pass
#   straight in. To embed Markdown that is already formatted -- a link built by
#   another call, a bold run of your own -- wrap it in `dybatpho::md_raw`,
#   which marks the fragment so the surrounding escape leaves it alone. The
#   exceptions are documented per function: a fenced code block's body is
#   literal by definition, and a collapsible section's body is the Markdown the
#   caller already built.
#
#   Output goes to stdout one block at a time, so blocks compose through
#   command substitution and ordinary concatenation rather than through a
#   document object.
# @tip `dybatpho::md_table` renders through `table.sh`, so that module must be
#   loaded for it; `markdown` does not load it, and every other builder needs
#   only the core modules
# @see
#   - `example/markdown_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# Sentinels marking a region that `dybatpho::md_raw` produced and the escape
# must copy through untouched. They are control characters rather than a textual
# marker such as `<!--raw-->` on purpose: any textual marker is something a
# caller's data could also contain, at which point the data decides whether it
# is escaped. `\001` and `\002` cannot appear in Markdown that renders.
# Control characters can still arrive in data, though -- a filename, a commit
# message -- so the opening mark also carries a value drawn when the module
# loads, which data cannot guess, and the escape drops a stray `\001` or `\002`.
# A fragment marked in one process is therefore raw only in that process and
# its subshells, and is drawn once, so loading the module again keeps it.
[[ -n "${__dybatpho_md_raw_open-}" ]] || printf -v __dybatpho_md_raw_open '\001%04x%04x%04x%04x\001' \
  "${SRANDOM:-${RANDOM}}" "${RANDOM}" "${RANDOM}" "${RANDOM}"
__dybatpho_md_raw_close=$'\002'

#######################################
# @description Join an array of lines into one newline-separated string in a
#   named variable. The `IFS` the join needs is local to this helper, so no
#   caller has to set and restore it around the expansion.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Name of the array of lines
# @set The named variable
# @internal
#######################################
function __dybatpho_md_join_into {
  local -n __dybatpho_md_join_ref="$1"
  local -n __dybatpho_md_join_lines="$2"
  local IFS=$'\n'
  __dybatpho_md_join_ref="${__dybatpho_md_join_lines[*]}"
}

#######################################
# @description Escape only the characters that carry meaning anywhere in a
#   line, writing the result into a named variable. A table cell takes this
#   alone, since nothing in a cell starts a block.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to escape
# @set The named variable
# @internal
#######################################
function __dybatpho_md_escape_inline {
  local -n __dybatpho_md_inline_ref="$1"
  local __dybatpho_md_inline="${2-}"

  # A mark that did not come from `dybatpho::md_raw` is data, and dropped.
  __dybatpho_md_inline="${__dybatpho_md_inline//[$'\001\002']/}"
  # The backslash goes first: escaping it after any other character would also
  # escape the backslashes this loop just introduced.
  __dybatpho_md_inline="${__dybatpho_md_inline//\\/\\\\}"
  local __dybatpho_md_char
  for __dybatpho_md_char in '`' '*' '_' '[' ']' '<' '>' '|' '~' '&'; do
    __dybatpho_md_inline="${__dybatpho_md_inline//"${__dybatpho_md_char}"/\\"${__dybatpho_md_char}"}"
  done
  __dybatpho_md_inline_ref="${__dybatpho_md_inline}"
}

#######################################
# @description Escape the characters that carry inline meaning in Markdown,
#   writing the result into a named variable. Raw regions are not handled here:
#   `__dybatpho_md_escape_into` splits them off first.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to escape
# @set The named variable
# @internal
#######################################
function __dybatpho_md_escape_plain {
  local -n __dybatpho_md_plain_ref="$1"
  local __dybatpho_md_value
  __dybatpho_md_escape_inline __dybatpho_md_value "${2-}"

  # `#`, `-`, `+`, `=` and an ordered-list marker only start a block when they
  # start a line, so they are escaped by position instead of everywhere: a
  # date or a hyphenated word would otherwise come out full of backslashes.
  local -a __dybatpho_md_lines=()
  mapfile -t __dybatpho_md_lines <<< "${__dybatpho_md_value}"
  local __dybatpho_md_index
  for __dybatpho_md_index in "${!__dybatpho_md_lines[@]}"; do
    # A backslash escapes punctuation only, so an ordered-list marker is escaped
    # on its `.` or `)`: `\1.` would render the backslash and still read `1.`.
    if [[ "${__dybatpho_md_lines[${__dybatpho_md_index}]}" =~ ^([[:space:]]*)([#=+-])(.*)$ ]]; then
      __dybatpho_md_lines[__dybatpho_md_index]="${BASH_REMATCH[1]}\\${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    elif [[ "${__dybatpho_md_lines[${__dybatpho_md_index}]}" =~ ^([[:space:]]*[0-9]+)([.\)])(.*)$ ]]; then
      __dybatpho_md_lines[__dybatpho_md_index]="${BASH_REMATCH[1]}\\${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    fi
  done

  local IFS=$'\n'
  __dybatpho_md_plain_ref="${__dybatpho_md_lines[*]-}"
}

#######################################
# @description Escape text for an HTML element, writing the result into a
#   named variable: inside raw HTML a Markdown backslash escape is not read, so
#   `\<img>` would still be an element. A line break becomes a space, since a
#   blank line would end the HTML block early.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to escape
# @set The named variable
# @internal
#######################################
function __dybatpho_md_escape_html_plain {
  local -n __dybatpho_md_html_ref="$1"
  local __dybatpho_md_html="${2-}"
  __dybatpho_md_html="${__dybatpho_md_html//[$'\001\002']/}"
  __dybatpho_md_html="${__dybatpho_md_html//&/"&amp;"}"
  __dybatpho_md_html="${__dybatpho_md_html//</"&lt;"}"
  __dybatpho_md_html="${__dybatpho_md_html//>/"&gt;"}"
  __dybatpho_md_html_ref="${__dybatpho_md_html//$'\n'/ }"
}

#######################################
# @description Escape text for inline use, copying through any region that
#   `dybatpho::md_raw` marked.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to escape
# @arg $3 string [default: __dybatpho_md_escape_plain] Function escaping the text outside raw regions
# @set The named variable
# @internal
#######################################
function __dybatpho_md_escape_into {
  local -n __dybatpho_md_escaped_ref="$1"
  local __dybatpho_md_rest="${2-}"
  local __dybatpho_md_plain="${3:-__dybatpho_md_escape_plain}"
  local __dybatpho_md_result="" __dybatpho_md_segment="" __dybatpho_md_piece=""

  while [[ "${__dybatpho_md_rest}" == *"${__dybatpho_md_raw_open}"* ]]; do
    __dybatpho_md_segment="${__dybatpho_md_rest%%"${__dybatpho_md_raw_open}"*}"
    __dybatpho_md_rest="${__dybatpho_md_rest#*"${__dybatpho_md_raw_open}"}"
    "${__dybatpho_md_plain}" __dybatpho_md_piece "${__dybatpho_md_segment}"
    __dybatpho_md_result+="${__dybatpho_md_piece}"

    if [[ "${__dybatpho_md_rest}" == *"${__dybatpho_md_raw_close}"* ]]; then
      __dybatpho_md_result+="${__dybatpho_md_rest%%"${__dybatpho_md_raw_close}"*}"
      __dybatpho_md_rest="${__dybatpho_md_rest#*"${__dybatpho_md_raw_close}"}"
    else
      # An opening sentinel with no closing one means the raw fragment was cut,
      # by a truncation or a substring. Copying the remainder through keeps the
      # caller's Markdown intact rather than escaping half of it.
      __dybatpho_md_result+="${__dybatpho_md_rest}"
      __dybatpho_md_rest=""
    fi
  done

  "${__dybatpho_md_plain}" __dybatpho_md_piece "${__dybatpho_md_rest}"
  __dybatpho_md_escaped_ref="${__dybatpho_md_result}${__dybatpho_md_piece}"
}

#######################################
# @description Make a URL safe to place inside `(...)`, writing it into a named
#   variable. Percent-encoding is used rather than the angle-bracket form
#   because a URL that already contains `<` or `>` breaks that form in turn.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string URL
# @set The named variable
# @internal
#######################################
function __dybatpho_md_encode_url_into {
  local -n __dybatpho_md_url_ref="$1"
  local __dybatpho_md_url="${2-}"

  __dybatpho_md_url="${__dybatpho_md_url//\%/%25}"
  __dybatpho_md_url="${__dybatpho_md_url// /%20}"
  __dybatpho_md_url="${__dybatpho_md_url//"("/%28}"
  __dybatpho_md_url="${__dybatpho_md_url//")"/%29}"
  __dybatpho_md_url="${__dybatpho_md_url//</%3C}"
  __dybatpho_md_url="${__dybatpho_md_url//>/%3E}"
  __dybatpho_md_url="${__dybatpho_md_url//\\/%5C}"
  # A line break ends the link, and the other control characters are not
  # valid in a URL either, so each one is percent-encoded too.
  local __dybatpho_md_code __dybatpho_md_hex __dybatpho_md_ctl
  for __dybatpho_md_code in {1..31} 127; do
    printf -v __dybatpho_md_hex '%02X' "${__dybatpho_md_code}"
    printf -v __dybatpho_md_ctl '%b' "\\x${__dybatpho_md_hex}"
    __dybatpho_md_url="${__dybatpho_md_url//"${__dybatpho_md_ctl}"/"%${__dybatpho_md_hex}"}"
  done
  __dybatpho_md_url_ref="${__dybatpho_md_url}"
}

#######################################
# @description Mark text as Markdown that is already formatted, so a builder
#   embeds it instead of escaping it.
#   The marked text carries two control characters that every builder removes
#   as it renders. Print it only through a builder: on its own it still holds
#   them.
# @arg $1 string Markdown fragment, or `-` for stdin
# @stdout The fragment, marked as raw
# @example
#   dybatpho::md_list "$(dybatpho::md_raw "$(dybatpho::md_link 'docs' 'https://example.com')")"
#   # - [docs](https://example.com)
#######################################
function dybatpho::md_raw {
  local input
  dybatpho::expect_args input -- "$@"
  local -a lines=()

  local text
  __dybatpho_string_read_lines_into lines "${input}"
  __dybatpho_md_join_into text lines
  printf '%s%s%s\n' "${__dybatpho_md_raw_open}" "${text}" "${__dybatpho_md_raw_close}"
}

#######################################
# @description Escape the Markdown-significant characters in a text block.
#   The builders in this module already escape what they are given, so this is
#   for Markdown a caller assembles itself. Passing its output to a builder
#   escapes the text twice.
# @arg $1 string Text to escape, or `-` for stdin
# @stdout Escaped text
# @example
#   dybatpho::md_escape 'release v2 [beta]'
#   # release v2 \[beta\]
#######################################
function dybatpho::md_escape {
  local input
  dybatpho::expect_args input -- "$@"
  local -a lines=()
  local escaped text

  __dybatpho_string_read_lines_into lines "${input}"
  __dybatpho_md_join_into text lines
  __dybatpho_md_escape_into escaped "${text}"
  printf '%s\n' "${escaped}"
}

#######################################
# @description Render an ATX heading.
# @arg $1 number Heading level, 1 to 6
# @arg $2 string Heading text
# @stdout The heading line
# @exitcode 0 The heading is rendered
# @example
#   dybatpho::md_heading 2 "Release notes"
#   # ## Release notes
#######################################
function dybatpho::md_heading {
  local level text
  dybatpho::expect_args level text -- "$@"
  [[ "${level}" =~ ^[1-6]$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Heading level must be 1 to 6, got: ${level}"

  local escaped hashes
  __dybatpho_md_escape_into escaped "${text}"
  # A run of `#` after a blank at the end would be read as the closing
  # sequence and dropped, so its last `#` is escaped.
  if [[ "${escaped}" =~ ^(.*[[:space:]])?(#+)([[:space:]]*)$ ]]; then
    escaped="${BASH_REMATCH[1]}${BASH_REMATCH[2]%#}\\#${BASH_REMATCH[3]}"
  fi
  printf -v hashes '%*s' "${level}" ''
  printf '%s %s\n' "${hashes// /#}" "${escaped}"
}

#######################################
# @description Render a bullet or ordered list, one item per input line.
#   A marker of `1.` or `1)` numbers the items from that value; any other
#   marker is used literally on every item. Blank input lines stay blank, so a
#   list can be split into visual groups.
# @arg $1 string List items, one per line, or `-` for stdin
# @arg $2 string [default: -] Marker
# @stdout The rendered list
# @example
#   dybatpho::md_list $'first\nsecond' "1."
#   # 1. first
#   # 2. second
#######################################
function dybatpho::md_list {
  local input
  dybatpho::expect_args input -- "$@"
  local marker="${2:--}"
  local -a lines=()
  local line escaped number="" suffix=""

  if [[ "${marker}" =~ ^([0-9]+)([.\)])$ ]]; then
    number=$((10#${BASH_REMATCH[1]}))
    suffix="${BASH_REMATCH[2]}"
  fi

  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      printf '\n'
      continue
    fi
    __dybatpho_md_escape_into escaped "${line}"
    if [[ -n "${number}" ]]; then
      printf '%s%s %s\n' "${number}" "${suffix}" "${escaped}"
      number=$((number + 1))
    else
      printf '%s %s\n' "${marker}" "${escaped}"
    fi
  done
}

#######################################
# @description Render a GitHub-flavored task list, one item per input line.
#   Each line is `<state><delimiter><text>`; a line with no delimiter is an
#   unchecked item whose text is the whole line. The state is checked for
#   `x`, `X`, and anything `dybatpho::is true` accepts.
# @arg $1 string Task lines, or `-` for stdin
# @arg $2 string [default: |] Delimiter between state and text
# @stdout The rendered task list
# @example
#   dybatpho::md_task_list $'x|Write the spec\n|Ship it'
#   # - [x] Write the spec
#   # - [ ] Ship it
#######################################
function dybatpho::md_task_list {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"
  local -a lines=()
  local line state text escaped box

  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      printf '\n'
      continue
    fi

    if [[ -n "${delimiter}" && "${line}" == *"${delimiter}"* ]]; then
      state="${line%%"${delimiter}"*}"
      text="${line#*"${delimiter}"}"
    else
      state=""
      text="${line}"
    fi

    box=" "
    if [[ "${state}" == "x" || "${state}" == "X" ]] || dybatpho::is true "${state}"; then
      box="x"
    fi

    __dybatpho_md_escape_into escaped "${text}"
    printf -- '- [%s] %s\n' "${box}" "${escaped}"
  done
}

#######################################
# @description Render an inline link.
# @arg $1 string Link text
# @arg $2 string URL
# @arg $3 string? Title shown on hover
# @stdout The rendered link
# @example
#   dybatpho::md_link "the docs" "https://example.com/a b"
#   # [the docs](https://example.com/a%20b)
#######################################
function dybatpho::md_link {
  local text url
  dybatpho::expect_args text url -- "$@"
  local title="${3-}"
  local escaped encoded escaped_title

  __dybatpho_md_escape_into escaped "${text}"
  __dybatpho_md_encode_url_into encoded "${url}"

  if [[ -n "${title}" ]]; then
    escaped_title="${title//\\/\\\\}"
    escaped_title="${escaped_title//\"/\\\"}"
    printf '[%s](%s "%s")\n' "${escaped}" "${encoded}" "${escaped_title}"
    return 0
  fi
  printf '[%s](%s)\n' "${escaped}" "${encoded}"
}

#######################################
# @description Render a shields.io badge as an image, optionally wrapped in a
#   link. The label and value are encoded the way shields.io requires: `-`
#   doubles, `_` doubles, and a space becomes `_`. Every other character that
#   is not safe in a URL path, the color's included, is percent-encoded.
# @arg $1 string Badge label, the left half
# @arg $2 string Badge value, the right half
# @arg $3 string [default: blue] Color
# @arg $4 string? URL the badge links to
# @stdout The rendered badge
# @example
#   dybatpho::md_badge "build" "passing" "green"
#   # ![build: passing](https://img.shields.io/badge/build-passing-green)
#######################################
function dybatpho::md_badge {
  local label value
  dybatpho::expect_args label value -- "$@"
  local color="${3:-blue}"
  local link="${4-}"
  local label_part value_part color_part alt badge encoded

  __dybatpho_md_badge_segment_into label_part "${label}"
  __dybatpho_md_badge_segment_into value_part "${value}"
  __dybatpho_md_percent_encode_into color_part "${color}"
  __dybatpho_md_escape_into alt "${label}: ${value}"
  badge="![${alt}](https://img.shields.io/badge/${label_part}-${value_part}-${color_part})"

  if [[ -n "${link}" ]]; then
    __dybatpho_md_encode_url_into encoded "${link}"
    printf '[%s](%s)\n' "${badge}" "${encoded}"
    return 0
  fi
  printf '%s\n' "${badge}"
}

#######################################
# @description Encode one half of a shields.io badge path into a named
#   variable.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Segment text
# @set The named variable
# @internal
#######################################
function __dybatpho_md_badge_segment_into {
  local -n __dybatpho_md_segment_ref="$1"
  local __dybatpho_md_segment="${2-}"

  __dybatpho_md_segment="${__dybatpho_md_segment//_/__}"
  __dybatpho_md_segment="${__dybatpho_md_segment//-/--}"
  __dybatpho_md_segment="${__dybatpho_md_segment// /_}"
  __dybatpho_md_percent_encode_into __dybatpho_md_segment_ref "${__dybatpho_md_segment}"
}

#######################################
# @description Percent-encode every byte of a URL path segment outside the
#   unreserved set, into a named variable.
#   `/` would add a segment, `?` and `#` would end the path, `%` would start an
#   escape, and `(` or `)` would end the Markdown that holds the URL.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Segment text
# @set The named variable
# @internal
#######################################
function __dybatpho_md_percent_encode_into {
  local -n __dybatpho_md_percent_ref="$1"
  local LC_ALL=C
  local __dybatpho_md_percent_in="${2-}" __dybatpho_md_percent_out="" __dybatpho_md_percent_char
  local -i __dybatpho_md_percent_i __dybatpho_md_percent_n="${#__dybatpho_md_percent_in}"
  for ((__dybatpho_md_percent_i = 0; __dybatpho_md_percent_i < __dybatpho_md_percent_n; __dybatpho_md_percent_i++)); do
    __dybatpho_md_percent_char="${__dybatpho_md_percent_in:__dybatpho_md_percent_i:1}"
    case "${__dybatpho_md_percent_char}" in
      [a-zA-Z0-9._~-]) __dybatpho_md_percent_out+="${__dybatpho_md_percent_char}" ;;
      *)
        printf -v __dybatpho_md_percent_char '%%%02X' "'${__dybatpho_md_percent_char}"
        __dybatpho_md_percent_out+="${__dybatpho_md_percent_char}"
        ;;
    esac
  done
  __dybatpho_md_percent_ref="${__dybatpho_md_percent_out}"
}

#######################################
# @description Render a fenced code block.
#   The body is literal by definition, so it is not escaped. The fence grows
#   past the longest run of backticks the body contains, which is what keeps a
#   block that itself shows fenced Markdown from ending early.
# @arg $1 string Language for the info string, empty for none
# @arg $2 string Code, or `-` for stdin
# @stdout The rendered code block
# @example
#   dybatpho::md_code_block bash 'ls -la'
#   # ```bash
#   # ls -la
#   # ```
#######################################
function dybatpho::md_code_block {
  local language body
  dybatpho::expect_args language body -- "$@"
  [[ "${language}" != *'`'* ]] \
    || dybatpho::die "${FUNCNAME[0]}: Language must not contain a backtick, got: ${language}"

  local -a lines=()
  __dybatpho_string_read_lines_into lines "${body}"

  local text
  __dybatpho_md_join_into text lines

  # The fence has to be longer than every backtick run inside it. Everything
  # but a backtick turns into a space, which leaves the runs as words to
  # measure in one pass. Walking the body a character at a time cost quadratic
  # time, since Bash finds `${text:index:1}` by counting from the start, and so
  # did growing the fence until the body no longer held it: 40000 backticks
  # took 14 seconds.
  local -a runs=()
  local run longest=2 fence
  IFS=" " read -r -a runs <<< "${text//[!\`]/ }"
  for run in ${runs[@]+"${runs[@]}"}; do
    ((${#run} <= longest)) || longest=${#run}
  done
  __dybatpho_log_repeat_into fence '`' "$((longest + 1))"

  printf '%s%s\n' "${fence}" "${language}"
  printf '%s\n' ${lines[@]+"${lines[@]}"}
  printf '%s\n' "${fence}"
}

#######################################
# @description Render a Markdown table through `table.sh`.
#   Every cell is escaped like any other builder's text, after the row is split
#   on the delimiter, so a value holding `|`, `*` or `[` stays one plain cell.
#   Wrap a cell that is already Markdown, such as a link, in `dybatpho::md_raw`.
# @arg $1 string Rows, one per line, cells split on the delimiter, or `-` for stdin
# @arg $2 string [default: |] Delimiter
# @stdout The rendered table
# @exitcode 0 The table is rendered
# @exitcode 1 Stop the script when the `table` module cannot be loaded on demand
# @example
#   . dybatpho/init.sh --modules markdown table
#   dybatpho::md_table $'Name,Role\nAlice,Dev *lead*' ","
#######################################
function dybatpho::md_table {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"

  # The guard names an internal helper on purpose: `dybatpho::` functions are
  # exported and a child shell inherits them without the internals they call,
  # so testing the public name would pass in a child that never loaded `table`
  # and then fail on the first internal call.
  __dybatpho_helpers_need_module table __dybatpho_table_measure_widths "${FUNCNAME[0]}"

  # The escaped cells are joined on the unit separator, which no escaped cell
  # holds, since an escape can add a backslash that a delimiter contains.
  local -a rows=() cells=() escaped_rows=()
  local row index escaped unit=$'\037' IFS
  __dybatpho_string_read_lines_into rows "${input}"
  for row in ${rows[@]+"${rows[@]}"}; do
    __dybatpho_table_split_row "${row}" "${delimiter}" cells
    for index in "${!cells[@]}"; do
      __dybatpho_md_escape_into escaped "${cells[${index}]//"${unit}"/}" __dybatpho_md_escape_inline
      cells[index]="${escaped}"
    done
    IFS="${unit}"
    escaped_rows+=("${cells[*]-}")
    unset IFS
  done
  __dybatpho_table_markdown_rows escaped_rows "${unit}"
}

#######################################
# @description Render a collapsible `<details>` section.
#   The summary is escaped as HTML, since it sits inside an HTML element where
#   Markdown escapes are not read, and a line break in it becomes a space;
#   the body is the Markdown the caller already built, so it is emitted as
#   given. The blank lines around the body are what let a renderer treat it as
#   Markdown rather than as raw HTML.
# @arg $1 string Summary line shown when collapsed
# @arg $2 string Body, or `-` for stdin
# @stdout The rendered section
# @example
#   dybatpho::md_collapsible "Full log" "$(dybatpho::md_code_block '' "${log}")"
#######################################
function dybatpho::md_collapsible {
  local summary body
  dybatpho::expect_args summary body -- "$@"
  local -a lines=()
  local escaped

  __dybatpho_md_escape_into escaped "${summary}" __dybatpho_md_escape_html_plain
  __dybatpho_string_read_lines_into lines "${body}"

  printf '<details>\n'
  printf '<summary>%s</summary>\n\n' "${escaped}"
  printf '%s\n' ${lines[@]+"${lines[@]}"}
  printf '\n</details>\n'
}

#######################################
# @description Render a mention of a user or group.
#   A leading `@` in the name is accepted and not doubled.
# @arg $1 string Account name, with or without a leading `@`
# @stdout The rendered mention
# @example
#   dybatpho::md_mention dynamotn
#   # @dynamotn
#######################################
function dybatpho::md_mention {
  local name
  dybatpho::expect_args name -- "$@"
  name="${name#@}"
  [[ "${name}" =~ ^[A-Za-z0-9._/-]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid account name: ${name}"
  printf '@%s\n' "${name}"
}

#######################################
# @description Render an emoji shortcode.
#   Surrounding colons are accepted and not doubled.
# @arg $1 string Shortcode name, with or without surrounding colons
# @stdout The rendered shortcode
# @example
#   dybatpho::md_emoji rocket
#   # :rocket:
#######################################
function dybatpho::md_emoji {
  local name
  dybatpho::expect_args name -- "$@"
  name="${name#:}"
  name="${name%:}"
  [[ "${name}" =~ ^[A-Za-z0-9_+-]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid emoji shortcode: ${name}"
  printf ':%s:\n' "${name}"
}
