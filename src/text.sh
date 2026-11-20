# shellcheck shell=bash
# The library returns its values on stdout, so its own functions are called inside `$(...)` by design. Every call
# here that can stop the script was reviewed: it is fixed, or listed with its reason in test/die-in-substitution.allow,
# which test/conventions.bats enforces.
# dyshellint disable=BSG047 # reviewed in test/die-in-substitution.allow
# @file text.sh
# @brief Utilities for working with multi-line text blocks
# @namespace dybatpho
# @description
#   This module contains helpers for formatting larger text blocks: indenting
#   each line, removing shared indentation, stripping ANSI escape sequences,
#   turning lines into bullet lists, aligning simple delimited columns,
#   drawing a border around a block, centering lines, numbering them, and
#   cutting a long block short. It is useful when shell scripts need to prepare
#   readable console output, embed heredocs, or normalize text before writing
#   files.
#
#   The helpers that pad or center measure each line by what a terminal shows:
#   ANSI escape sequences count for nothing, and the library's built-in Unicode
#   tables give a CJK character or an emoji the two columns it occupies and a
#   combining mark none -- the same measure `table`, `screen` and the boxed log
#   helpers use.
# @see
#   - `example/text_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Prefix every line in a text block with the given indent string.
# @arg $1 string Input text or `-` for stdin
# @arg $2 string? Indent prefix, default is two spaces
# @stdout Indented text block
#######################################
function dybatpho::text_indent {
  local input
  dybatpho::expect_args input -- "$@"
  local prefix="${2:-  }"
  local -a lines=()
  local line

  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    printf '%s%s\n' "${prefix}" "${line}"
  done
}

#######################################
# @description Remove the shared leading indentation from a text block.
# @arg $1 string Input text or `-` for stdin
# @stdout Dedented text block
#######################################
function dybatpho::text_dedent {
  local input
  dybatpho::expect_args input -- "$@"
  local -a lines=()
  local line indent_length min_indent=-1

  __dybatpho_string_read_lines_into lines "${input}"

  for line in ${lines[@]+"${lines[@]}"}; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      continue
    fi

    # Blank lines are skipped above, so every remaining line has this shape.
    [[ "${line}" =~ ^([[:space:]]*)[^[:space:]] ]]
    indent_length=${#BASH_REMATCH[1]}

    if ((min_indent == -1 || indent_length < min_indent)); then
      min_indent=${indent_length}
    fi
  done

  if ((min_indent < 0)); then
    min_indent=0
  fi

  for line in ${lines[@]+"${lines[@]}"}; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      printf '\n'
    else
      printf '%s\n' "${line:min_indent}"
    fi
  done
}

#######################################
# @description Strip ANSI escape sequences from a text block.
# @arg $1 string Input text or `-` for stdin
# @stdout Text without ANSI color/control sequences
#######################################
function dybatpho::text_strip_ansi {
  local input
  dybatpho::expect_args input -- "$@"
  local -a lines=()
  local line

  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    __dybatpho_text_strip_ansi_into line "${line}"
    printf '%s\n' "${line}"
  done
}

#######################################
# @description Make text that is not trusted -- from another process, a file,
#   the network -- safe to print to a terminal. Escape sequences are removed
#   whole, then every character that can move the cursor, rewrite a line, or
#   change what the reader sees without being seen: C0 controls other than tab
#   (carriage return included), DEL, C1 controls, bidirectional controls,
#   zero-width characters, the byte-order mark and Unicode tag characters,
#   over and over until none is left, since removing one can join its
#   neighbours into another -- at most four rounds, after which input nested
#   that deep loses every byte from 0x80 up. Lines stay lines; printable text,
#   tabs and other Unicode are kept. A caller's `nocasematch` does not change it.
#
#   The caller's locale says what the terminal reads. Under UTF-8, bytes that
#   cannot be part of a character which is a control (a C1 byte at the start or
#   after ASCII, an overlong form) are removed too, and an 8-bit introducer such
#   as U+009B is read as the sequence it opens; a C1 byte after another
#   non-ASCII byte is left, which a UTF-8 terminal shows as U+FFFD. Under any other locale,
#   every byte 0x80-0x9F is removed, since an 8-bit terminal obeys it as a C1
#   control -- UTF-8 text then loses those bytes, so run under a UTF-8 locale to
#   keep it.
# @example
#   dybatpho::text_sanitize "$(< "${peer_log}")" 2000
#
# @arg $1 string Input text or `-` for stdin
# @arg $2 number? Largest number of characters to print, line breaks between lines included; characters as
#   the caller's locale counts them, so bytes under `C`
# @stdout The text without those characters
# @note Bash's pattern substitution makes the time grow faster than a line's length: a line of 12000
#   escape sequences takes about a second; split or bound very long input before sanitizing it
# @tip Use it on anything a peer, a file or a remote wrote before showing it; `text_strip_ansi` alone keeps a
#   bare carriage return or a right-to-left override that can disguise a line
#######################################
function dybatpho::text_sanitize {
  local input
  dybatpho::expect_args input -- "$@"
  local cap="${2-}"
  [[ -z "${cap}" || "${cap}" =~ ^[0-9]{1,9}$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: The largest size must be a number of characters, got '${cap}'"
  local -a lines=()
  local line left=-1 first=true
  [[ -z "${cap}" ]] || left=$((10#${cap}))
  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    __dybatpho_text_sanitize_into line "${line}"
    if ((left >= 0)); then
      # The newline before every line but the first counts as a character.
      [[ "${first}" == true ]] || left=$((left - 1))
      # Nothing left for this line: stop rather than print it empty.
      ((left > 0)) || break
      line="${line:0:left}"
      left=$((left - ${#line}))
    fi
    first=false
    printf '%s\n' "${line}"
  done
}

#######################################
# @description Remove, byte by byte, every character `dybatpho::text_sanitize`
#   drops. The patterns are UTF-8 byte sequences matched in the C locale, so
#   they work whatever locale the caller runs in.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string One line of text
# @set The named variable
# @internal
#######################################
function __dybatpho_text_sanitize_into {
  local -n __dybatpho_text_sanitize_ref="$1"
  local __dybatpho_text_sanitize_value="$2" __dybatpho_text_sanitize_utf8=false
  # Read in the caller's locale, before it is switched to C below.
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) __dybatpho_text_sanitize_utf8=true ;;
    *) ;;
  esac
  # The escape pass tells `ESC P` from `ESC p` with `case`, which a caller's
  # `nocasematch` would fold: switch it off here, and back on before returning.
  local __dybatpho_text_sanitize_nocase=false LC_ALL=C
  if shopt -q nocasematch; then
    __dybatpho_text_sanitize_nocase=true
    shopt -u nocasematch
  fi
  # A C0 control inside a sequence is obeyed and the sequence goes on, so they go
  # first; 8-bit introducers become their ESC forms, so their payload goes too.
  # Not tab, ESC, or BEL, which ends a string; the byte pass removes BEL later.
  local __dybatpho_text_sanitize_c0=$'[\x01-\x06\x08\x0b-\x1a\x1c-\x1f\x7f]'
  # dyshellint disable=BSG117 # the pattern is a bracket expression, so it must not be quoted
  # shellcheck disable=SC2295
  __dybatpho_text_sanitize_value="${__dybatpho_text_sanitize_value//${__dybatpho_text_sanitize_c0}/}"
  # Only under UTF-8: outside it, those bytes are often part of UTF-8 letters
  # (`ğ` ends in 0x9F) and would swallow the rest of the line; they are removed.
  local -a __dybatpho_text_sanitize_pairs=()
  [[ "${__dybatpho_text_sanitize_utf8}" == false ]] \
    || __dybatpho_text_sanitize_pairs=($'\x9b[' $'\x9d]' $'\x90P' $'\x98X' $'\x9e^' $'\x9f_')
  local __dybatpho_text_sanitize_pair __dybatpho_text_cf __dybatpho_text_ct
  for __dybatpho_text_sanitize_pair in ${__dybatpho_text_sanitize_pairs[@]+"${__dybatpho_text_sanitize_pairs[@]}"}; do
    __dybatpho_text_cf=$'\xc2'"${__dybatpho_text_sanitize_pair:0:1}"
    __dybatpho_text_ct=$'\e'"${__dybatpho_text_sanitize_pair:1}"
    __dybatpho_text_sanitize_value="${__dybatpho_text_sanitize_value//"${__dybatpho_text_cf}"/"${__dybatpho_text_ct}"}"
  done
  __dybatpho_text_sanitize_escapes_into __dybatpho_text_sanitize_value "${__dybatpho_text_sanitize_value}"
  __dybatpho_text_sanitize_bytes_into __dybatpho_text_sanitize_value "${__dybatpho_text_sanitize_value}" \
    "${__dybatpho_text_sanitize_utf8}"
  [[ "${__dybatpho_text_sanitize_nocase}" == false ]] || shopt -s nocasematch
  __dybatpho_text_sanitize_ref="${__dybatpho_text_sanitize_value}"
}

#######################################
# @description Remove the characters `dybatpho::text_sanitize` drops by their
#   bytes, in the C locale, going round while a removal joins its neighbours
#   into another one -- but at most four times: real text settles in two, and
#   each round costs a pass over the line, so input nested to need more is
#   hostile, and loses every byte from 0x80 up instead, which is linear and safe.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string One line of text, without escape sequences
# @arg $3 bool Whether the caller's locale is UTF-8
# @set The named variable
# @internal
#######################################
function __dybatpho_text_sanitize_bytes_into {
  local -n __dybatpho_text_bytes_ref="$1"
  local __dybatpho_text_bytes_value="$2" __dybatpho_text_bytes_utf8="$3"
  local __dybatpho_text_bytes_pattern __dybatpho_text_bytes_prev __dybatpho_text_bytes_round=0
  # C0 controls but tab, and DEL; C1 controls (U+0080-U+009F); left-to-right and
  # right-to-left marks and zero-width characters (U+200B-U+200F); embeddings
  # and overrides (U+202A-U+202E); word joiner and isolates (U+2060, U+2066-U+2069);
  # the Arabic letter mark (U+061C); the byte-order mark (U+FEFF); tags (U+E0000-U+E007F).
  # Each pattern is one `$'...'` word: `$'...'` is not expanded inside double quotes.
  local -a __dybatpho_text_bytes_patterns=(
    $'[\x01-\x08\x0b-\x1f\x7f]' $'\xc2[\x80-\x9f]' $'\xe2\x80[\x8b-\x8f\xaa-\xae]'
    $'\xe2\x81[\xa0\xa6-\xa9]' $'\xd8\x9c' $'\xef\xbb\xbf' $'\xf3\xa0[\x80\x81][\x80-\xbf]'
  )
  if [[ "${__dybatpho_text_bytes_utf8}" == true ]]; then
    # Bytes no UTF-8 character starts with, and the overlong forms of controls.
    __dybatpho_text_bytes_patterns+=($'[\xc0\xc1\xf5-\xff]' $'\xe0[\x80-\x9f]' $'\xf0[\x80-\x8f]')
  else
    # An 8-bit terminal reads every byte 0x80-0x9F as a C1 control.
    __dybatpho_text_bytes_patterns+=($'[\x80-\x9f]')
  fi
  local __dybatpho_text_bytes_high=$'[\x80-\xff]'
  # Removing a character joins its neighbours, which can make a new one to
  # remove (`\xc2` ZWSP `\x9b` becomes CSI): go round until nothing changes.
  while :; do
    if ((++__dybatpho_text_bytes_round > 4)); then
      # dyshellint disable=BSG117 # the pattern is a bracket expression, so it must not be quoted
      # shellcheck disable=SC2295
      __dybatpho_text_bytes_value="${__dybatpho_text_bytes_value//${__dybatpho_text_bytes_high}/}"
      break
    fi
    __dybatpho_text_bytes_prev="${__dybatpho_text_bytes_value}"
    for __dybatpho_text_bytes_pattern in "${__dybatpho_text_bytes_patterns[@]}"; do
      # dyshellint disable=BSG117 # the pattern is a bracket expression, so it must not be quoted
      # shellcheck disable=SC2295
      __dybatpho_text_bytes_value="${__dybatpho_text_bytes_value//${__dybatpho_text_bytes_pattern}/}"
    done
    [[ "${__dybatpho_text_bytes_utf8}" == false ]] \
      || __dybatpho_text_sanitize_lone_c1_into __dybatpho_text_bytes_value "${__dybatpho_text_bytes_value}"
    [[ "${__dybatpho_text_bytes_value}" != "${__dybatpho_text_bytes_prev}" ]] || break
  done
  __dybatpho_text_bytes_ref="${__dybatpho_text_bytes_value}"
}

#######################################
# @description Remove every escape sequence from one line, so that none prints
#   its payload as text: CSI and nF escapes, a CSI cut off at the end of the
#   line included; single-character escapes such as `ESC c`; and OSC, DCS, SOS,
#   PM and APC strings, up to a BEL, an 8-bit ST, an `ESC \`, another ESC
#   (which a terminal reads as their end) or the end of the line. Like
#   `__dybatpho_text_strip_ansi_into`, the line is split on ESC once, so the
#   time is linear in its length. Run in the C locale.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string One line of text
# @set The named variable
# @internal
#######################################
function __dybatpho_text_sanitize_escapes_into {
  local -n __dybatpho_text_esc_ref="$1"
  if [[ "$2" != *$'\e'* ]]; then
    __dybatpho_text_esc_ref="$2"
    return 0
  fi
  local IFS=$'\e' __dybatpho_text_esc_part __dybatpho_text_esc_res __dybatpho_text_esc_k
  local __dybatpho_text_esc_open=false
  local -a __dybatpho_text_esc_parts=()
  read -r -a __dybatpho_text_esc_parts <<< "$2x"
  __dybatpho_text_esc_parts[-1]="${__dybatpho_text_esc_parts[-1]%x}"
  __dybatpho_text_esc_res="${__dybatpho_text_esc_parts[0]}"
  local __dybatpho_text_esc_n="${#__dybatpho_text_esc_parts[@]}"
  for ((__dybatpho_text_esc_k = 1; __dybatpho_text_esc_k < __dybatpho_text_esc_n; __dybatpho_text_esc_k++)); do
    __dybatpho_text_esc_part="${__dybatpho_text_esc_parts[__dybatpho_text_esc_k]}"
    # A string still open ends here: with `ESC \`, or with this ESC starting a new sequence.
    if [[ "${__dybatpho_text_esc_open}" == true && "${__dybatpho_text_esc_part}" == \\* ]]; then
      __dybatpho_text_esc_open=false
      __dybatpho_text_esc_res+="${__dybatpho_text_esc_part:1}"
      continue
    fi
    __dybatpho_text_sanitize_escape_into __dybatpho_text_esc_part __dybatpho_text_esc_open \
      "${__dybatpho_text_esc_part}"
    __dybatpho_text_esc_res+="${__dybatpho_text_esc_part}"
  done
  __dybatpho_text_esc_ref="${__dybatpho_text_esc_res}"
}

#######################################
# @description Remove the escape sequence at the start of the text that
#   followed one ESC, up to the next ESC.
# @arg $1 string Name of the variable receiving the text left after the sequence
# @arg $2 string Name of the variable set to `true` when a string runs on past this text
# @arg $3 string The text after the ESC
# @set The two named variables
# @internal
#######################################
function __dybatpho_text_sanitize_escape_into {
  local -n __dybatpho_text_one_ref="$1" __dybatpho_text_one_open="$2"
  local __dybatpho_text_one_part="$3" __dybatpho_text_one_bel __dybatpho_text_one_st
  local __dybatpho_text_one_csi=$'^\\[[0-?]*[ -/]*[@-~]?' __dybatpho_text_one_nf=$'^[ -/]+[0-~]?'
  __dybatpho_text_one_open=false
  case "${__dybatpho_text_one_part}" in
    [PX^_\]]*)
      __dybatpho_text_one_part="${__dybatpho_text_one_part:1}"
      __dybatpho_text_one_bel="${__dybatpho_text_one_part%%$'\a'*}"
      __dybatpho_text_one_st="${__dybatpho_text_one_part%%$'\xc2\x9c'*}"
      if ((${#__dybatpho_text_one_st} < ${#__dybatpho_text_one_bel})); then
        __dybatpho_text_one_ref="${__dybatpho_text_one_part:${#__dybatpho_text_one_st}+2}"
      elif [[ "${__dybatpho_text_one_bel}" != "${__dybatpho_text_one_part}" ]]; then
        __dybatpho_text_one_ref="${__dybatpho_text_one_part:${#__dybatpho_text_one_bel}+1}"
      else
        __dybatpho_text_one_ref=""
        __dybatpho_text_one_open=true
      fi
      ;;
    \[*)
      [[ "${__dybatpho_text_one_part}" =~ ${__dybatpho_text_one_csi} ]]
      __dybatpho_text_one_ref="${__dybatpho_text_one_part:${#BASH_REMATCH[0]}}"
      ;;
    [\ -/]*)
      [[ "${__dybatpho_text_one_part}" =~ ${__dybatpho_text_one_nf} ]]
      __dybatpho_text_one_ref="${__dybatpho_text_one_part:${#BASH_REMATCH[0]}}"
      ;;
    [0-~]*) __dybatpho_text_one_ref="${__dybatpho_text_one_part:1}" ;;
    *) __dybatpho_text_one_ref="${__dybatpho_text_one_part}" ;;
  esac
}

#######################################
# @description Remove the bytes 0x80-0x9F that do not follow a byte of 0x80 or
#   above, so are no part of a UTF-8 character: a terminal in 8-bit mode would
#   read them as C1 controls. Each such byte is marked with a `\x01` before it
#   (C0 controls are gone by now, so the mark is free) and the line is split on
#   the mark once, so the time is linear in its length: indexing into the line
#   instead would measure the whole line on every step. Run in the C locale.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string One line of text, with no C0 controls
# @set The named variable
# @internal
#######################################
function __dybatpho_text_sanitize_lone_c1_into {
  local -n __dybatpho_text_c1_ref="$1"
  if [[ "$2" != *[$'\x80'-$'\x9f']* ]]; then
    __dybatpho_text_c1_ref="$2"
    return 0
  fi
  local __dybatpho_text_c1_line="$2" __dybatpho_text_c1_byte __dybatpho_text_c1_k __dybatpho_text_c1_mark
  local __dybatpho_text_c1_all=$'\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f'
  __dybatpho_text_c1_all+=$'\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f'
  for ((__dybatpho_text_c1_k = 0; __dybatpho_text_c1_k < 32; __dybatpho_text_c1_k++)); do
    __dybatpho_text_c1_byte="${__dybatpho_text_c1_all:__dybatpho_text_c1_k:1}"
    # A substitution costs more than a search: only bytes the line holds are marked.
    [[ "${__dybatpho_text_c1_line}" == *"${__dybatpho_text_c1_byte}"* ]] || continue
    __dybatpho_text_c1_mark=$'\x01'"${__dybatpho_text_c1_byte}"
    __dybatpho_text_c1_line="${__dybatpho_text_c1_line//"${__dybatpho_text_c1_byte}"/"${__dybatpho_text_c1_mark}"}"
  done
  local IFS=$'\x01'
  local -a __dybatpho_text_c1_fields=()
  read -r -a __dybatpho_text_c1_fields <<< "${__dybatpho_text_c1_line}x"
  __dybatpho_text_c1_fields[-1]="${__dybatpho_text_c1_fields[-1]%x}"
  local __dybatpho_text_c1_res="${__dybatpho_text_c1_fields[0]}" __dybatpho_text_c1_field
  local __dybatpho_text_c1_n="${#__dybatpho_text_c1_fields[@]}" __dybatpho_text_c1_keep=false
  # Every field after the first starts with its C1 byte. A run of them is part of a
  # character only after a lead or continuation byte; at the start or after ASCII it is lone.
  [[ "${__dybatpho_text_c1_res: -1}" != [$'\x80'-$'\xff'] ]] || __dybatpho_text_c1_keep=true
  for ((__dybatpho_text_c1_k = 1; __dybatpho_text_c1_k < __dybatpho_text_c1_n; __dybatpho_text_c1_k++)); do
    __dybatpho_text_c1_field="${__dybatpho_text_c1_fields[__dybatpho_text_c1_k]}"
    [[ "${__dybatpho_text_c1_keep}" == true ]] || __dybatpho_text_c1_field="${__dybatpho_text_c1_field:1}"
    __dybatpho_text_c1_res+="${__dybatpho_text_c1_field}"
    # A field of the C1 byte alone continues the run, which keeps its verdict.
    ((${#__dybatpho_text_c1_fields[__dybatpho_text_c1_k]} > 1)) || continue
    __dybatpho_text_c1_keep=false
    [[ "${__dybatpho_text_c1_field: -1}" != [$'\x80'-$'\xff'] ]] || __dybatpho_text_c1_keep=true
  done
  __dybatpho_text_c1_ref="${__dybatpho_text_c1_res}"
}

#######################################
# @description Prefix each non-empty line in a text block as a bullet item.
# @arg $1 string Input text or `-` for stdin
# @arg $2 string [default: -] Bullet marker
# @stdout Bullet-formatted text block
#######################################
function dybatpho::text_bullet_list {
  local input
  dybatpho::expect_args input -- "$@"
  local bullet="${2:--}"
  local -a lines=()
  local line

  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    if dybatpho::string_is_blank "${line}"; then
      printf '\n'
    else
      printf '%s %s\n' "${bullet}" "${line}"
    fi
  done
}

#######################################
# @description Align a delimited text block into plain columns.
#   The columns are laid out by `dybatpho::table_align`, so the `table` module
#   is loaded on demand the first time this runs; name it up front to load it
#   once.
# @example
#   . dybatpho/init.sh --modules text table
#   dybatpho::text_columns $'name|version\ndybatpho|6.0.0'
#
# @arg $1 string Input text or `-` for stdin
# @arg $2 string [default: |] Exact delimiter
# @arg $3 number [default: 2] Gap width between columns
# @stdout Plain aligned columns
# @exitcode 1 Stop the script when the `table` module cannot be loaded on demand
#######################################
function dybatpho::text_columns {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_text_need_table
  local delimiter="${2:-|}"
  local gap="${3:-2}"
  dybatpho::table_align "${input}" "${delimiter}" "" "${gap}"
}

#######################################
# @description Stop unless the `table` module is loaded or can be loaded on demand.
#   Only `dybatpho::text_columns` draws through `table`, and registering it as
#   a dependency would load it into every script that only indents or strips
#   text -- including, through `testing`, every test suite -- so the one
#   function that needs it asks for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `table`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `table` module is not loaded and cannot be loaded on demand
# @internal
#######################################
function __dybatpho_text_need_table {
  __dybatpho_helpers_need_module table __dybatpho_table_measure_widths "${FUNCNAME[1]}"
}

#######################################
# @description Remove ANSI escape sequences from one line, writing the result
#   into a named variable without a subshell.
#   Three kinds are removed: CSI sequences such as colors (`\e[31m`), OSC
#   sequences such as hyperlinks (`\e]8;;url\e\\`), and character-set
#   designations such as the `\e(B` that `tput sgr0` prints before `\e[m`.
#   The match runs in the C locale: the sequence is defined by byte ranges, and
#   a range such as `[ -/]` is not well defined under a UTF-8 collation.
# @arg $1 string Name of the variable receiving the stripped line
# @arg $2 string Line to strip
# @set The named variable
# @internal
#######################################
function __dybatpho_text_strip_ansi_into {
  local __dybatpho_text_strip_target __dybatpho_text_strip_line
  dybatpho::expect_args __dybatpho_text_strip_target __dybatpho_text_strip_line -- "$@"
  local -n __dybatpho_text_strip_out="${__dybatpho_text_strip_target}"
  if [[ "${__dybatpho_text_strip_line}" == *$'\e'* ]]; then
    local LC_ALL=C
    # Split on ESC once, then match each part anchored: no regex ever sees the
    # whole line. An OSC ended by `ESC \` ends one part and starts the next.
    local __dybatpho_text_strip_re='^(\[[0-?]*[ -/]*[@-~]|\][^'$'\a'']*'$'\a''|[ -/]+[0-~])'
    local -a __dybatpho_text_strip_parts=()
    local IFS=$'\e' __dybatpho_text_strip_part __dybatpho_text_strip_k
    local __dybatpho_text_strip_res
    read -r -a __dybatpho_text_strip_parts <<< "${__dybatpho_text_strip_line}x"
    __dybatpho_text_strip_parts[-1]="${__dybatpho_text_strip_parts[-1]%x}"
    __dybatpho_text_strip_res="${__dybatpho_text_strip_parts[0]}"
    local __dybatpho_text_strip_len="${#__dybatpho_text_strip_parts[@]}"
    __dybatpho_text_strip_k=1
    for (( ; __dybatpho_text_strip_k < __dybatpho_text_strip_len; __dybatpho_text_strip_k++)); do
      __dybatpho_text_strip_part="${__dybatpho_text_strip_parts[__dybatpho_text_strip_k]}"
      if [[ "${__dybatpho_text_strip_part}" =~ ${__dybatpho_text_strip_re} ]]; then
        __dybatpho_text_strip_part="${__dybatpho_text_strip_part:${#BASH_REMATCH[0]}}"
      elif [[ "${__dybatpho_text_strip_part}" == ']'* &&
        "${__dybatpho_text_strip_parts[__dybatpho_text_strip_k + 1]-}" == "\\"* ]]; then
        # An OSC ended by ESC \: the next part starts with the backslash.
        __dybatpho_text_strip_part="${__dybatpho_text_strip_parts[++__dybatpho_text_strip_k]:1}"
      else
        __dybatpho_text_strip_part=$'\e'"${__dybatpho_text_strip_part}"
      fi
      __dybatpho_text_strip_res+="${__dybatpho_text_strip_part}"
    done
    __dybatpho_text_strip_line="${__dybatpho_text_strip_res}"
  fi
  __dybatpho_text_strip_out="${__dybatpho_text_strip_line}"
}

#######################################
# @description Measure the columns a line occupies on a terminal.
#   ANSI escape sequences are removed first, then the line is measured with the
#   core logging measurement, which counts a wide glyph as the two columns it
#   occupies. `table` measures its cells through this helper too, so a box drawn
#   by either module is sized the same way.
# @arg $1 string Name of the variable receiving the width
# @arg $2 string Line to measure
# @set The named variable
# @internal
#######################################
function __dybatpho_text_width_into {
  local __dybatpho_text_w_target __dybatpho_text_w_text __dybatpho_text_w_line
  dybatpho::expect_args __dybatpho_text_w_target __dybatpho_text_w_text -- "$@"
  __dybatpho_text_strip_ansi_into __dybatpho_text_w_line "${__dybatpho_text_w_text}"
  __dybatpho_log_width_into "${__dybatpho_text_w_target}" "${__dybatpho_text_w_line}"
}

#######################################
# @description Draw a border around a text block, with an optional title set
#   into the top edge.
#   The box is as wide as the widest line or the title, whichever is wider,
#   with one space of padding on each side. Lines are padded by their visible
#   width, so colored text and wide characters keep the right edge straight.
# @example
#   dybatpho::text_box $'alpha\nbeta' "Notes"
#   # ┌─ Notes ─┐
#   # │ alpha   │
#   # │ beta    │
#   # └─────────┘
#
#   dybatpho::text_box "plain" "" ascii
#   # +-------+
#   # | plain |
#   # +-------+
# @arg $1 string Input text or `-` for stdin
# @arg $2 string? Title shown in the top border, default is none
# @arg $3 string? Border style: `single` (default), `double`, `rounded`, `heavy`, or `ascii`
# @stdout The boxed text block
# @exitcode 1 The border style is unknown
#######################################
function dybatpho::text_box {
  local input
  dybatpho::expect_args input -- "$@"
  local title="${2-}"
  local style="${3:-single}"
  local top_left top_right bottom_left bottom_right horizontal vertical

  case "${style}" in
    single) top_left="┌" top_right="┐" bottom_left="└" bottom_right="┘" horizontal="─" vertical="│" ;;
    double) top_left="╔" top_right="╗" bottom_left="╚" bottom_right="╝" horizontal="═" vertical="║" ;;
    rounded) top_left="╭" top_right="╮" bottom_left="╰" bottom_right="╯" horizontal="─" vertical="│" ;;
    heavy) top_left="┏" top_right="┓" bottom_left="┗" bottom_right="┛" horizontal="━" vertical="┃" ;;
    ascii) top_left="+" top_right="+" bottom_left="+" bottom_right="+" horizontal="-" vertical="|" ;;
    # "dybatpho::text_box rejects an unknown style" runs this arm under `run`.
    *) dybatpho::die "Unknown box style: ${style} (expected single, double, rounded, heavy, or ascii)" ;; # kcov(skip)
  esac

  local -a lines=() widths=()
  local line width inner=0 title_width=0 index
  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    __dybatpho_text_width_into width "${line}"
    widths+=("${width}")
    ((width > inner)) && inner=${width}
  done

  if [[ -n "${title}" ]]; then
    __dybatpho_text_width_into title_width "${title}"
    # The title sits as `─ title ─`, so it needs two more columns than itself.
    ((title_width + 2 > inner)) && inner=$((title_width + 2))
  fi

  # The rules are built by repeating the border character rather than by
  # slicing one long rule, since a slice counts bytes in the C locale.
  local rule title_rule
  printf -v rule '%*s' "$((inner + 2))" ""
  rule="${rule// /"${horizontal}"}"

  if [[ -n "${title}" ]]; then
    printf -v title_rule '%*s' "$((inner - title_width - 1))" ""
    title_rule="${title_rule// /"${horizontal}"}"
    printf '%s%s %s %s%s\n' "${top_left}" "${horizontal}" "${title}" \
      "${title_rule}" "${top_right}"
  else
    printf '%s%s%s\n' "${top_left}" "${rule}" "${top_right}"
  fi
  for index in "${!lines[@]}"; do
    printf '%s %s%*s %s\n' "${vertical}" "${lines[index]}" \
      "$((inner - widths[index]))" "" "${vertical}"
  done
  printf '%s%s%s\n' "${bottom_left}" "${rule}" "${bottom_right}"
}

#######################################
# @description Center each line of a text block within a width.
#   Lines are padded on the left only, so no trailing whitespace is added. When
#   the padding cannot be split evenly, the extra column goes to the right. A
#   line at least as wide as the width is printed unchanged, and a blank line
#   stays blank. Widths are measured as `dybatpho::text_box` measures them.
# @example
#   dybatpho::text_center $'title\nsubtitle here' 20
#   #        title
#   #    subtitle here
# @arg $1 string Input text or `-` for stdin
# @arg $2 number? Width to center within, default is the terminal width
# @stdout The centered text block
# @exitcode 1 The width is not a positive integer
#######################################
function dybatpho::text_center {
  local input
  dybatpho::expect_args input -- "$@"
  local width="${2-}"
  if [[ -z "${width}" ]]; then
    width="$(dybatpho::terminal_width)"
  fi
  [[ "${width}" =~ ^[1-9][0-9]*$ ]] || dybatpho::die "Width must be a positive integer: ${width}"

  local -a lines=()
  local line line_width
  __dybatpho_string_read_lines_into lines "${input}"
  for line in ${lines[@]+"${lines[@]}"}; do
    if dybatpho::string_is_blank "${line}"; then
      printf '\n'
      continue
    fi
    __dybatpho_text_width_into line_width "${line}"
    if ((line_width >= width)); then
      printf '%s\n' "${line}"
    else
      printf '%*s%s\n' "$(((width - line_width) / 2))" "" "${line}"
    fi
  done
}

#######################################
# @description Prefix each line of a text block with its line number.
#   Numbers are right-aligned to the width of the last one, so a block of ten
#   or more lines keeps its text in one column. Blank lines are numbered too.
# @example
#   dybatpho::text_number_lines $'alpha\nbeta'
#   # 1  alpha
#   # 2  beta
#
#   dybatpho::text_number_lines $'alpha\nbeta' 9 ": "
#   #  9: alpha
#   # 10: beta
# @arg $1 string Input text or `-` for stdin
# @arg $2 number [default: 1] Number of the first line
# @arg $3 string? Separator between number and text, default is two spaces
# @stdout The numbered text block
# @exitcode 1 The first line number is not an integer from 0 to 9223372036854775807
#######################################
function dybatpho::text_number_lines {
  local input
  dybatpho::expect_args input -- "$@"
  local start="${2:-1}"
  local separator="${3-  }"
  [[ "${start}" =~ ^[0-9]+$ ]] || dybatpho::die "Start line must be a non-negative integer: ${start}"
  __dybatpho_text_check_int64 "Start line" "${start}"
  # Strip leading zeros so `08` is not read as an invalid octal number.
  start=$((10#${start}))

  local -a lines=()
  local index last digits
  __dybatpho_string_read_lines_into lines "${input}"
  last=$((start + ${#lines[@]} - 1))
  digits=${#last}
  for index in "${!lines[@]}"; do
    printf '%*d%s%s\n' "${digits}" "$((start + index))" "${separator}" "${lines[index]}"
  done
}

#######################################
# @description Refuse a non-negative integer Bash arithmetic cannot hold,
#   rather than let it wrap to an unrelated number.
# @arg $1 string What the value is, for the message
# @arg $2 string The digits, as written
# @exitcode 1 Stop the script when the value is above 9223372036854775807
# @internal
#######################################
function __dybatpho_text_check_int64 {
  local __text_check_digits="${2#"${2%%[!0]*}"}"
  if ((${#__text_check_digits} > 19 || 10#0${__text_check_digits} < 0)); then
    dybatpho::die "$1 must be at most 9223372036854775807: $2"
  fi
}

#######################################
# @description Keep the first lines of a text block and say how many were left
#   out.
#   A block that already fits is printed unchanged, with no marker. Otherwise
#   the first `count` lines are printed, followed by a marker line. The default
#   marker reads `… 1 more line` or `… N more lines`; a custom marker has every
#   `{count}` replaced by the number of lines left out.
# @example
#   dybatpho::text_truncate_lines $'one\ntwo\nthree\nfour' 2
#   # one
#   # two
#   # … 2 more lines
#
#   git log --oneline | dybatpho::text_truncate_lines - 5 "(+{count} commits)"
# @arg $1 string Input text or `-` for stdin
# @arg $2 number Number of lines to keep
# @arg $3 string? Marker template, `{count}` is replaced by the number of lines left out
# @stdout The kept lines and, when lines were left out, the marker
# @exitcode 1 The count is not an integer from 0 to 9223372036854775807
#######################################
function dybatpho::text_truncate_lines {
  local input count
  dybatpho::expect_args input count -- "$@"
  local marker="${3-}"
  [[ "${count}" =~ ^[0-9]+$ ]] || dybatpho::die "Line count must be a non-negative integer: ${count}"
  __dybatpho_text_check_int64 "Line count" "${count}"
  count=$((10#${count}))

  local -a lines=()
  local index hidden
  __dybatpho_string_read_lines_into lines "${input}"
  if ((${#lines[@]} <= count)); then
    printf '%s\n' ${lines[@]+"${lines[@]}"}
    return 0
  fi

  for ((index = 0; index < count; index++)); do
    printf '%s\n' "${lines[index]}"
  done
  hidden=$((${#lines[@]} - count))
  if [[ -z "${marker}" ]]; then
    if ((hidden == 1)); then
      marker="… 1 more line"
    else
      marker="… ${hidden} more lines"
    fi
  else
    marker="${marker//\{count\}/"${hidden}"}"
  fi
  printf '%s\n' "${marker}"
}
