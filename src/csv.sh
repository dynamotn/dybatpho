# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file csv.sh
# @brief Utilities for reading, filtering and writing CSV data
# @namespace dybatpho
# @description
#   This module reads the tabular format ops scripts keep receiving --
#   spreadsheet exports, cloud billing reports, CI artifacts -- and it parses
#   the quoting that `awk -F,` and `cut -d,` get wrong. A field may contain the
#   delimiter, a doubled quote, or a line break, and none of them end the field.
#
#   `table.sh` renders comma-delimited text and says so: it splits on every
#   comma and refuses a quoted field rather than turning one into two columns.
#   This module is the parser that refusal points at. Render through
#   `table.sh` afterwards by writing the parsed rows back out with
#   `dybatpho::csv_write`.
#
#   Rows are exchanged as an array whose every element is one record, its
#   fields joined by the ASCII unit separator. Splitting a record is then a
#   single unambiguous operation, which is what `dybatpho::csv_fields` does.
#   Data containing that byte is rejected rather than silently re-split.
#
#   Parsing and the bulk operations -- `dybatpho::csv_read`, `csv_header`,
#   `csv_col`, `csv_select`, `csv_filter`, `csv_sort`, `csv_convert` and
#   `csv_to_json` -- run as one POSIX `awk` program once the input reaches a
#   few kilobytes, and in Bash below that or when no `awk` is installed. Both
#   engines print byte for byte the same output; any input the `awk` program
#   would have to refuse -- an unknown column, a row wider than its header, a
#   non-number under `number` -- is handed back to the Bash engine, so the
#   error a script sees is the same too. `DYBATPHO_CSV_ENGINE` pins either one.
# @tip With `awk`, 5,000 rows convert, filter or sort in a few hundredths of a
#   second, and the input is limited by memory rather than time. The Bash
#   engine takes about a millisecond a row, which is comfortable into the low
#   thousands of rows; past the tens of thousands, reach for a real CSV tool
# @tip Values are read and written as text, because CSV carries no types; cast
#   in `jq` after `dybatpho::csv_to_json` when a consumer needs numbers
# @env DYBATPHO_CSV_DELIMITER string [default: ,] Field delimiter; set it to `;`, or to `tab` for TSV
# @see
#   - `example/csv_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CSV_DELIMITER string [default: ,] Field delimiter every function reads; `tab` or `\t` names a tab
DYBATPHO_CSV_DELIMITER="${DYBATPHO_CSV_DELIMITER:-,}"

# @env DYBATPHO_CSV_ENGINE string [default: auto] `auto`, `awk` or `bash`: the engine of parsing and the bulk operations
DYBATPHO_CSV_ENGINE="${DYBATPHO_CSV_ENGINE:-auto}"

# The input size, in characters, from which `auto` starts `awk`. Below it the
# Bash engine finishes before an `awk` process would have started.
__dybatpho_csv_awk_threshold=2048

# The byte that joins the fields of one record. A record is exchanged as a
# single string so that an array of records stays a flat Bash array; the unit
# separator is what makes splitting it back apart unambiguous, because unlike
# the delimiter it can never be part of a value.
__dybatpho_csv_unit=$'\037'

# The `awk` engine: one program for every bulk operation, chosen by its first
# argument. It reads the text on stdin, reproduces the Bash parser below rule for
# rule -- quoted fields, doubled quotes, stray text after a closing quote, line
# breaks inside a field, a carriage return dropped from each line -- and prints
# exactly what the Bash engine prints. It exits 3, before printing anything, for
# any input the Bash engine would refuse, which then runs and reports it.
# Only POSIX `awk` is used, so gawk, mawk, BusyBox and BSD `awk` agree, and it
# runs under `LC_ALL=C`, where a string is bytes the way the Bash engine
# compares them.
# shellcheck disable=SC2016 # an awk program: its `$` are awk's, not the shell's
__dybatpho_csv_awk_program='
  BEGIN {
    MODE = ARGV[1] ""
    D = ARGV[2] ""
    NA = 0
    for (i = 3; i < ARGC; i++) A[++NA] = ARGV[i] ""
    for (i = 1; i < ARGC; i++) ARGV[i] = ""
    FS = "\n"
    U = sprintf("%c", 31)
    QQ = "\""
    for (i = 1; i < 32; i++) {
      c = sprintf("%c", i)
      ESC[c] = sprintf("\\u%04x", i)
      CTL = CTL c
    }
    c = sprintf("%c", 127)
    ESC[c] = "\\u007f"
    CTLRE = "[" CTL c "]"
    ESC["\n"] = "\\n"
    ESC["\r"] = "\\r"
    ESC["\t"] = "\\t"
    ESC[sprintf("%c", 8)] = "\\b"
    ESC[sprintf("%c", 12)] = "\\f"
    ESC["\\"] = "\\\\"
    ESC[QQ] = "\\" QQ
    math_init()
    n = 0
    pending = 0
  }
  {
    # Concatenated, so a line that looks like a number stays a string: `$0` is
    # a "strnum", and two of those compare as numbers.
    line = $0 ""
    if (substr(line, length(line)) == "\r") line = substr(line, 1, length(line) - 1)
    if (pending) buf = buf "\n" line
    else buf = line
    if (is_open(buf, D)) {
      pending = 1
      next
    }
    pending = 0
    record(buf)
  }
  END {
    if (pending) record(buf)
    if (MODE == "read") exit 0
    if (n == 0) exit 0
    NH = W[1]
    if (MODE == "header") {
      for (i = 1; i <= NH; i++) printf "%s\n", F[1, i]
      exit 0
    }
    if (MODE == "convert") {
      for (r = 1; r <= n; r++) emit(r, A[1])
      exit 0
    }
    # Every mode below reads the rows against the header, so a row wider than
    # the header is refused here, before anything is printed.
    for (r = 2; r <= n; r++) if (W[r] > NH) exit 3
    if (MODE == "json") json()
    else if (MODE == "col") {
      c = pick(A[1])
      for (r = 2; r <= n; r++) printf "%s\n", (c <= W[r] ? F[r, c] : "")
    } else if (MODE == "select") {
      for (i = 1; i <= NA; i++) P[i] = pick(A[i])
      for (r = 1; r <= n; r++) {
        out = ""
        for (i = 1; i <= NA; i++) {
          v = (P[i] <= W[r] ? F[r, P[i]] : "")
          out = out (i > 1 ? D : "") quote(v, D)
        }
        printf "%s\n", out
      }
    } else if (MODE == "filter") filter(pick(A[1]), A[2], A[3])
    else if (MODE == "sort") sort(pick(A[1]), A[2], A[3])
    else exit 3
  }

  # Return 1 when the text so far ends inside a quoted field.
  # @internal
  function is_open(rest, d,   p) {
    if (!index(rest, QQ)) return 0
    while (1) {
      if (substr(rest, 1, 1) == QQ) {
        rest = substr(rest, 2)
        while (1) {
          p = index(rest, QQ)
          if (!p) return 1
          rest = substr(rest, p + 1)
          if (substr(rest, 1, 1) != QQ) break
          rest = substr(rest, 2)
        }
      }
      p = index(rest, d)
      if (!p) return 0
      rest = substr(rest, p + length(d))
    }
  }

  # Split one record into F[n + 1, *] and W[n + 1], the way the Bash splitter does.
  # @internal
  function record(rest,   k, field, p, out, i) {
    n++
    k = 0
    while (1) {
      if (substr(rest, 1, 1) == QQ) {
        rest = substr(rest, 2)
        field = ""
        while (1) {
          p = index(rest, QQ)
          if (!p) {
            field = field rest
            rest = ""
            break
          }
          field = field substr(rest, 1, p - 1)
          rest = substr(rest, p + 1)
          if (substr(rest, 1, 1) == QQ) {
            field = field QQ
            rest = substr(rest, 2)
          } else break
        }
        if (rest != "" && substr(rest, 1, length(D)) != D) {
          p = index(rest, D)
          if (!p) {
            F[n, ++k] = field rest
            break
          }
          F[n, ++k] = field substr(rest, 1, p - 1)
          rest = substr(rest, p + length(D))
          continue
        }
        F[n, ++k] = field
        if (rest == "") break
        rest = substr(rest, length(D) + 1)
        continue
      }
      p = index(rest, D)
      if (p) {
        F[n, ++k] = substr(rest, 1, p - 1)
        rest = substr(rest, p + length(D))
      } else {
        F[n, ++k] = rest
        break
      }
    }
    W[n] = k
    if (MODE == "read") {
      out = ""
      for (i = 1; i <= k; i++) {
        field = F[n, i]
        gsub(/\n/, U "1", field)
        out = out (i > 1 ? U "0" : "") field
        delete F[n, i]
      }
      printf "%s\n", out
    }
  }

  # Resolve a column by header name, then by 1-based position.
  # @internal
  function pick(want,   i) {
    for (i = 1; i <= NH; i++) if (F[1, i] == want) return i
    if (want ~ /^[1-9][0-9]*$/ && want + 0 <= NH) return want + 0
    exit 3
  }

  # @internal
  function quote(v, d) {
    if (index(v, QQ) || index(v, "\n") || index(v, "\r") || index(v, d)) {
      gsub(/"/, QQ QQ, v)
      return QQ v QQ
    }
    return v
  }

  # @internal
  function emit(r, d,   i, out) {
    out = ""
    for (i = 1; i <= W[r]; i++) out = out (i > 1 ? d : "") quote(F[r, i], d)
    printf "%s\n", out
  }

  # @internal
  function jesc(s,   out, i, c, len) {
    if (!index(s, "\\") && !index(s, QQ) && s !~ CTLRE) return QQ s QQ
    out = ""
    len = length(s)
    for (i = 1; i <= len; i++) {
      c = substr(s, i, 1)
      out = out ((c in ESC) ? ESC[c] : c)
    }
    return QQ out QQ
  }

  # @internal
  function json(   r, i, obj) {
    for (i = 1; i <= NH; i++) NAME[i] = jesc(F[1, i])
    printf "["
    for (r = 2; r <= n; r++) {
      obj = ""
      for (i = 1; i <= NH; i++) {
        obj = obj (i > 1 ? "," : "") NAME[i] ":" jesc(i <= W[r] ? F[r, i] : "")
      }
      printf "%s{%s}", (r > 2 ? "," : ""), obj
    }
    printf "]\n"
  }

  # @internal
  function filter(c, op, val,   r, v, keep, numval) {
    numval = (val ~ NUMRE)
    emit(1, D)
    for (r = 2; r <= n; r++) {
      v = (c <= W[r] ? F[r, c] : "")
      if (op == "eq") keep = (v == val)
      else if (op == "ne") keep = (v != val)
      else if (op == "contains") keep = (val == "" || index(v, val) > 0)
      else if (op == "gt") keep = ((numval && v ~ NUMRE) ? ncmp(v, val) > 0 : v > val)
      else if (op == "lt") keep = ((numval && v ~ NUMRE) ? ncmp(v, val) < 0 : v < val)
      else exit 3
      if (keep) emit(r, D)
    }
  }

  # @internal
  function sort(c, order, type,   r, m, allnum, k) {
    if (order != "asc" && order != "desc") exit 3
    DESC = (order == "desc")
    allnum = 1
    m = 0
    for (r = 2; r <= n; r++) {
      K[r] = (c <= W[r] ? F[r, c] : "")
      O[++m] = r
      if (K[r] != "" && K[r] !~ NUMRE) {
        if (type == "number") exit 3
        allnum = 0
      }
    }
    if (type == "auto") type = (allnum ? "number" : "text")
    if (type == "number") for (r = 2; r <= n; r++) if (K[r] != "") K[r] = numkey(K[r])
    msort(m)
    emit(1, D)
    for (k = 1; k <= m; k++) emit(O[k], D)
  }
'

#######################################
# @description Return success when a bulk operation should run through the
#   `awk` engine: `DYBATPHO_CSV_ENGINE` allows it, the input is not empty and,
#   under `auto`, large enough to repay starting a process, `awk` is installed,
#   and every delimiter involved is a single byte, which is what the program
#   splits on.
# @arg $1 number Length of the input text
# @arg $@ string Every delimiter the operation reads or writes
# @exitcode 0 Use `awk`
# @exitcode 1 Use the Bash engine
# @internal
#######################################
function __dybatpho_csv_use_awk {
  local __dybatpho_csv_size="$1" __dybatpho_csv_one
  shift
  case "${DYBATPHO_CSV_ENGINE}" in
    bash) return 1 ;;
    awk) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
    auto) ((__dybatpho_csv_size >= __dybatpho_csv_awk_threshold)) || return 1 ;;
    # "DYBATPHO_CSV_ENGINE picks the engine and refuses one it does not know"
    # covers this; `dybatpho::die` exits, so that test uses `run`.
    *)
      local __dybatpho_csv_engine_bad="Unknown DYBATPHO_CSV_ENGINE: ${DYBATPHO_CSV_ENGINE}" # kcov(skip)
      dybatpho::die "${FUNCNAME[1]}: ${__dybatpho_csv_engine_bad}. Use auto, awk, or bash"  # kcov(skip)
      ;;
  esac
  ((__dybatpho_csv_size > 0)) || return 1
  command -v awk &> /dev/null || return 1
  local LC_ALL=C
  for __dybatpho_csv_one in "$@"; do
    ((${#__dybatpho_csv_one} == 1)) || return 1
  done
}

#######################################
# @description Run the `awk` engine on stdin, recording its exit status in a
#   named variable rather than returning it, so a caller under `set -e` reads
#   `3` -- run the Bash engine instead -- without stopping.
# @arg $1 string Name of the variable receiving the exit status
# @arg $2 string Operation: `read`, `header`, `convert`, `col`, `select`, `filter`, `sort`, or `json`
# @arg $3 string Field delimiter
# @arg $@ string The operation's own arguments
# @stdin The CSV text, ending in a newline
# @stdout What the operation prints
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_awk_into {
  local -n __dybatpho_csv_awk_status="$1"
  shift
  __dybatpho_csv_awk_status=0
  # shellcheck disable=SC2154 # `math.sh`, which this module depends on, defines the shared awk helpers
  LC_ALL=C command awk "${__dybatpho_csv_awk_program}${__dybatpho_math_awk_lib}" "$@" || __dybatpho_csv_awk_status=$?
}

#######################################
# @description Read a public function's input the way every reader in this
#   module starts: resolve the delimiter, then read the input. Errors are
#   reported under the public function that called this.
# @arg $1 string Name of the variable receiving the text
# @arg $2 string Name of the variable receiving the delimiter
# @arg $3 string File path, `-` for stdin, or CSV text
# @arg $4 string? Name the errors are reported under, default is the calling function
# @set The two named variables
# @internal
#######################################
function __dybatpho_csv_source_into {
  local __dybatpho_csv_source_who="${4:-${FUNCNAME[1]}}"
  __dybatpho_csv_delimiter_into "$2" "${DYBATPHO_CSV_DELIMITER}" "${__dybatpho_csv_source_who}"
  __dybatpho_csv_input_into "$1" "$3" "${__dybatpho_csv_source_who}"
}

#######################################
# @description Resolve a delimiter to the character it names, into a named
#   variable, and stop on one the parser cannot work with.
#   `tab` and `\t` name a tab, because a literal tab is awkward to type in an
#   environment variable. Anything else must be exactly one character that is
#   neither a quote, a line break, nor the unit separator: an empty delimiter
#   never advances the parser, and the others are already part of the format.
# @arg $1 string Name of the variable receiving the delimiter
# @arg $2 string Delimiter as the caller wrote it
# @set The named variable
# @exitcode 0 The delimiter is usable
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_csv_delimiter_into {
  local -n __dybatpho_csv_delim_ref="$1"
  local __dybatpho_csv_wanted="$2" __dybatpho_csv_caller="${3:-${FUNCNAME[1]}}"

  case "${__dybatpho_csv_wanted}" in
    tab | '\t') __dybatpho_csv_wanted=$'\t' ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac

  # The refusals below are covered by "DYBATPHO_CSV_DELIMITER refuses a
  # delimiter the parser cannot use", which has to use `run` because the path
  # ends in `dybatpho::die`; `run` clears the trap kcov instruments through.
  local __dybatpho_csv_problem=""
  if ((${#__dybatpho_csv_wanted} != 1)); then
    __dybatpho_csv_problem="it must be one character, or \`tab\`" # kcov(skip)
  else
    case "${__dybatpho_csv_wanted}" in
      '"' | $'\n' | $'\r' | "${__dybatpho_csv_unit}")
        __dybatpho_csv_problem="a quote, a line break, or the unit separator" # kcov(skip)
        __dybatpho_csv_problem+=" cannot separate fields"                     # kcov(skip)
        ;;
      *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
    esac
  fi

  if [[ -n "${__dybatpho_csv_problem}" ]]; then
    local __dybatpho_csv_shown                                                                    # kcov(skip)
    printf -v __dybatpho_csv_shown '%q' "${__dybatpho_csv_wanted}"                                # kcov(skip)
    __dybatpho_csv_problem="Invalid delimiter ${__dybatpho_csv_shown}: ${__dybatpho_csv_problem}" # kcov(skip)
    dybatpho::die "${__dybatpho_csv_caller}: ${__dybatpho_csv_problem}"                           # kcov(skip)
  fi
  __dybatpho_csv_delim_ref="${__dybatpho_csv_wanted}"
}

#######################################
# @description Resolve an input argument to the text it names.
#   `-` is stdin, an existing file is its contents, and anything else is the
#   text itself, so a caller can pass a path, a pipe, or a here-string without
#   choosing a different function for each.
# @arg $1 string Name of the variable receiving the text
# @arg $2 string File path, `-`, or CSV text
# @arg $3 string? Name the unit-separator refusal is reported under, default is the calling function
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_input_into {
  local -n __dybatpho_csv_input_ref="$1"
  local __dybatpho_csv_source="$2" __dybatpho_csv_who="${3:-${FUNCNAME[1]:-${FUNCNAME[0]}}}"

  __dybatpho_string_input_into __dybatpho_csv_input_ref "${__dybatpho_csv_source}" files

  local __dybatpho_csv_reason="The input contains the ASCII unit separator,"
  __dybatpho_csv_reason+=" which this module uses to join a record's fields"
  [[ "${__dybatpho_csv_input_ref}" != *"${__dybatpho_csv_unit}"* ]] || dybatpho::die \
    "${__dybatpho_csv_who}: ${__dybatpho_csv_reason}"
}

#######################################
# @description Split one record into its fields, writing them into a named
#   array. Quoting follows RFC 4180: a field that starts with `\"` ends at the
#   next `\"` that is not doubled, and a doubled `\"\"` inside it is one literal
#   quote.
# @arg $1 string Name of the array variable to fill
# @arg $2 string One record
# @arg $3 string Field delimiter
# @set The named array
# @internal
#######################################
function __dybatpho_csv_split_into {
  local -n __dybatpho_csv_fields_ref="$1"
  local __dybatpho_csv_rest="$2"
  local __dybatpho_csv_delimiter="$3"
  __dybatpho_csv_fields_ref=()
  local __dybatpho_csv_field __dybatpho_csv_chunk

  while true; do
    if [[ "${__dybatpho_csv_rest}" == '"'* ]]; then
      __dybatpho_csv_rest="${__dybatpho_csv_rest:1}"
      __dybatpho_csv_field=""
      while true; do
        __dybatpho_csv_chunk="${__dybatpho_csv_rest%%\"*}"
        if [[ "${__dybatpho_csv_chunk}" == "${__dybatpho_csv_rest}" ]]; then
          # No closing quote. The record is malformed, and taking the remainder
          # as the field keeps the data the caller does have.
          __dybatpho_csv_field+="${__dybatpho_csv_rest}"
          __dybatpho_csv_rest=""
          break
        fi
        __dybatpho_csv_field+="${__dybatpho_csv_chunk}"
        __dybatpho_csv_rest="${__dybatpho_csv_rest:$((${#__dybatpho_csv_chunk} + 1))}"
        if [[ "${__dybatpho_csv_rest}" == '"'* ]]; then
          __dybatpho_csv_field+='"'
          __dybatpho_csv_rest="${__dybatpho_csv_rest:1}"
        else
          break
        fi
      done
      # Anything between the closing quote and the delimiter is not valid CSV.
      # It is kept rather than dropped, because dropping it is the silent data
      # loss this module exists to avoid.
      # When no delimiter follows, the stray text is the end of the record:
      # leaving it in the remainder made the next pass read it again as a
      # field of its own.
      if [[ -n "${__dybatpho_csv_rest}" && "${__dybatpho_csv_rest}" != "${__dybatpho_csv_delimiter}"* ]]; then
        __dybatpho_csv_field+="${__dybatpho_csv_rest%%"${__dybatpho_csv_delimiter}"*}"
        __dybatpho_csv_fields_ref+=("${__dybatpho_csv_field}")
        [[ "${__dybatpho_csv_rest}" == *"${__dybatpho_csv_delimiter}"* ]] || break
        __dybatpho_csv_rest="${__dybatpho_csv_rest#*"${__dybatpho_csv_delimiter}"}"
        continue
      fi
      __dybatpho_csv_fields_ref+=("${__dybatpho_csv_field}")
      [[ -n "${__dybatpho_csv_rest}" ]] || break
      __dybatpho_csv_rest="${__dybatpho_csv_rest#"${__dybatpho_csv_delimiter}"}"
      continue
    fi

    if [[ "${__dybatpho_csv_rest}" == *"${__dybatpho_csv_delimiter}"* ]]; then
      __dybatpho_csv_fields_ref+=("${__dybatpho_csv_rest%%"${__dybatpho_csv_delimiter}"*}")
      __dybatpho_csv_rest="${__dybatpho_csv_rest#*"${__dybatpho_csv_delimiter}"}"
    else
      __dybatpho_csv_fields_ref+=("${__dybatpho_csv_rest}")
      break
    fi
  done
}

#######################################
# @description Return success when a record is still inside a quoted field at
#   its end, which is how a record that continues on the next line is
#   recognized.
#   Only a quote that begins a field opens one, the way the field splitter reads
#   it: counting every quote took the inch mark in `55"` for an opening quote and
#   swallowed every following line into that one record.
# @arg $1 string Text so far
# @arg $2 string Delimiter
# @exitcode 0 A quoted field is still open, so the record is not finished
# @exitcode 1 Every quoted field is closed
# @internal
#######################################
function __dybatpho_csv_record_open {
  local __dybatpho_csv_open_rest="$1" __dybatpho_csv_open_delimiter="$2"
  # No quote at all is the common line, and it cannot open a field.
  [[ "${__dybatpho_csv_open_rest}" == *'"'* ]] || return 1
  while true; do
    if [[ "${__dybatpho_csv_open_rest}" == '"'* ]]; then
      __dybatpho_csv_open_rest="${__dybatpho_csv_open_rest:1}"
      while true; do
        [[ "${__dybatpho_csv_open_rest}" == *'"'* ]] || return 0
        __dybatpho_csv_open_rest="${__dybatpho_csv_open_rest#*\"}"
        # A doubled quote is an escaped one; any other quote closes the field.
        [[ "${__dybatpho_csv_open_rest}" == '"'* ]] || break
        __dybatpho_csv_open_rest="${__dybatpho_csv_open_rest:1}"
      done
    fi
    [[ "${__dybatpho_csv_open_rest}" == *"${__dybatpho_csv_open_delimiter}"* ]] || return 1
    __dybatpho_csv_open_rest="${__dybatpho_csv_open_rest#*"${__dybatpho_csv_open_delimiter}"}"
  done
}

#######################################
# @description Parse CSV text into an array of records.
# @arg $1 string Name of the array variable to fill
# @arg $2 string CSV text
# @arg $3 string Field delimiter
# @set The named array
# @internal
#######################################
function __dybatpho_csv_parse_into {
  local -n __dybatpho_csv_records_ref="$1"
  local __dybatpho_csv_text="$2"
  local __dybatpho_csv_delimiter="$3"
  __dybatpho_csv_records_ref=()

  [[ -n "${__dybatpho_csv_text}" ]] || return 0
  # Bytes, not characters: in a UTF-8 locale Bash's pattern operators drop a
  # value that holds an invalid sequence, and the delimiter, the quote and the
  # unit separator are single bytes whatever the locale.
  local LC_ALL=C

  if __dybatpho_csv_use_awk "${#__dybatpho_csv_text}" "${__dybatpho_csv_delimiter}"; then
    # One record a line, with the two bytes a record cannot carry on a line
    # spelled as the unit separator and a digit: the separator itself as `0`,
    # a line break inside a field as `1`. The input never holds the unit
    # separator, so every one in the output starts such a pair. The `.` keeps
    # the trailing newlines that `$(...)` would strip.
    local __dybatpho_csv_encoded __dybatpho_csv_parsed_ok=0
    # shellcheck disable=SC2154 # `math.sh`, which this module depends on, defines the shared awk helpers
    __dybatpho_csv_encoded="$(LC_ALL=C command awk "${__dybatpho_csv_awk_program}${__dybatpho_math_awk_lib}" read \
      "${__dybatpho_csv_delimiter}" <<< "${__dybatpho_csv_text}" && printf '.')" \
      || __dybatpho_csv_parsed_ok=$?
    if ((__dybatpho_csv_parsed_ok == 0)); then
      __dybatpho_csv_encoded="${__dybatpho_csv_encoded%.}"
      local -a __dybatpho_csv_decoded=()
      local __dybatpho_csv_newline=$'\n'
      mapfile -t __dybatpho_csv_decoded <<< "${__dybatpho_csv_encoded%"${__dybatpho_csv_newline}"}"
      __dybatpho_csv_decoded=("${__dybatpho_csv_decoded[@]//"${__dybatpho_csv_unit}1"/${__dybatpho_csv_newline}}")
      __dybatpho_csv_records_ref=("${__dybatpho_csv_decoded[@]//"${__dybatpho_csv_unit}0"/${__dybatpho_csv_unit}}")
      return 0
    fi
  fi

  local -a __dybatpho_csv_lines=()
  mapfile -t __dybatpho_csv_lines <<< "${__dybatpho_csv_text}"

  local __dybatpho_csv_line __dybatpho_csv_buffer="" __dybatpho_csv_pending=0
  local -a __dybatpho_csv_row=()
  local IFS

  for __dybatpho_csv_line in ${__dybatpho_csv_lines[@]+"${__dybatpho_csv_lines[@]}"}; do
    # A CRLF file leaves the carriage return at the end of every line, and a
    # value compared against one would never match what the caller typed.
    __dybatpho_csv_line="${__dybatpho_csv_line%$'\r'}"

    if ((__dybatpho_csv_pending)); then
      __dybatpho_csv_buffer+=$'\n'"${__dybatpho_csv_line}"
    else
      __dybatpho_csv_buffer="${__dybatpho_csv_line}"
    fi

    if __dybatpho_csv_record_open "${__dybatpho_csv_buffer}" "${__dybatpho_csv_delimiter}"; then
      # An open quote means the value runs on into the next line.
      __dybatpho_csv_pending=1
      continue
    fi
    __dybatpho_csv_pending=0

    __dybatpho_csv_split_into __dybatpho_csv_row "${__dybatpho_csv_buffer}" "${__dybatpho_csv_delimiter}"
    IFS="${__dybatpho_csv_unit}"
    __dybatpho_csv_records_ref+=("${__dybatpho_csv_row[*]-}")
    unset IFS
  done

  # A file whose last quote is never closed still has data worth returning.
  if ((__dybatpho_csv_pending)); then
    __dybatpho_csv_split_into __dybatpho_csv_row "${__dybatpho_csv_buffer}" "${__dybatpho_csv_delimiter}"
    IFS="${__dybatpho_csv_unit}"
    __dybatpho_csv_records_ref+=("${__dybatpho_csv_row[*]-}")
    unset IFS
  fi
}

#######################################
# @description Quote one field for output, into a named variable.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Field value
# @arg $3 string Field delimiter
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_quote_into {
  local -n __dybatpho_csv_quoted_ref="$1"
  local __dybatpho_csv_value="$2"
  local __dybatpho_csv_delimiter="$3"
  # Bytes, not characters: in a UTF-8 locale Bash's pattern operators drop a
  # value that holds an invalid sequence, and the delimiter, the quote and the
  # unit separator are single bytes whatever the locale.
  local LC_ALL=C

  local __dybatpho_csv_special=0
  case "${__dybatpho_csv_value}" in
    *'"'* | *$'\n'* | *$'\r'*) __dybatpho_csv_special=1 ;;
    *"${__dybatpho_csv_delimiter}"*) __dybatpho_csv_special=1 ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac

  if ((__dybatpho_csv_special)); then
    __dybatpho_csv_quoted_ref="\"${__dybatpho_csv_value//\"/\"\"}\""
    return 0
  fi
  __dybatpho_csv_quoted_ref="${__dybatpho_csv_value}"
}

#######################################
# @description Read the header of a parsed record set into a named array, and
#   report the column count.
# @arg $1 string Name of the array variable to fill
# @arg $2 string Name of the array of records
# @set The named array
# @internal
#######################################
function __dybatpho_csv_header_into {
  local -n __dybatpho_csv_head_ref="$1"
  local -n __dybatpho_csv_all_ref="$2"
  __dybatpho_csv_head_ref=()

  ((${#__dybatpho_csv_all_ref[@]})) || return 0
  __dybatpho_csv_split_fields_into __dybatpho_csv_head_ref "${__dybatpho_csv_all_ref[0]}"
}

#######################################
# @description Read a public function's input the way every reader in this
#   module starts: resolve the delimiter, read the input, parse it into
#   records, and split the header into column names.
#   Errors are reported under the public function that called this.
# @arg $1 string Name of the array receiving the records
# @arg $2 string Name of the array receiving the header's column names, empty for empty input
# @arg $3 string Name of the variable receiving the delimiter
# @arg $4 string File path, `-` for stdin, or CSV text
# @set The three named variables
# @internal
#######################################
function __dybatpho_csv_load_into {
  local __dybatpho_csv_load_text
  __dybatpho_csv_delimiter_into "$3" "${DYBATPHO_CSV_DELIMITER}" "${FUNCNAME[1]}"
  __dybatpho_csv_input_into __dybatpho_csv_load_text "$4" "${FUNCNAME[1]}"
  local -n __dybatpho_csv_load_delim="$3"
  __dybatpho_csv_parse_into "$1" "${__dybatpho_csv_load_text}" "${__dybatpho_csv_load_delim}"
  __dybatpho_csv_header_into "$2" "$1"
}

#######################################
# @description Parse text a public function has already read into records,
#   and split the header into column names -- the Bash engine's half of
#   `__dybatpho_csv_load_into`, for a caller that tried `awk` first.
# @arg $1 string Name of the array receiving the records
# @arg $2 string Name of the array receiving the header's column names, empty for empty input
# @arg $3 string CSV text
# @arg $4 string Field delimiter
# @set The two named arrays
# @internal
#######################################
function __dybatpho_csv_records_into {
  __dybatpho_csv_parse_into "$1" "$3" "$4"
  __dybatpho_csv_header_into "$2" "$1"
}

#######################################
# @description Split a record on the unit separator into a named array.
# @arg $1 string Name of the array variable to fill
# @arg $2 string One record
# @set The named array
# @internal
#######################################
function __dybatpho_csv_split_fields_into {
  local -n __dybatpho_csv_parts_ref="$1"
  local __dybatpho_csv_remaining="$2"
  __dybatpho_csv_parts_ref=()
  # Bytes, not characters: in a UTF-8 locale Bash's pattern operators drop a
  # value that holds an invalid sequence, and the delimiter, the quote and the
  # unit separator are single bytes whatever the locale.
  local LC_ALL=C

  # Not word splitting on `IFS`: it drops a trailing empty field, so a row
  # ending in the delimiter would come back one column short of its header.
  while [[ "${__dybatpho_csv_remaining}" == *"${__dybatpho_csv_unit}"* ]]; do
    __dybatpho_csv_parts_ref+=("${__dybatpho_csv_remaining%%"${__dybatpho_csv_unit}"*}")
    __dybatpho_csv_remaining="${__dybatpho_csv_remaining#*"${__dybatpho_csv_unit}"}"
  done
  __dybatpho_csv_parts_ref+=("${__dybatpho_csv_remaining}")
}

#######################################
# @description Parse CSV into an array of records.
#   Every element is one record whose fields are joined by the ASCII unit
#   separator; `dybatpho::csv_fields` splits one back apart. Quoted fields are
#   parsed the way RFC 4180 describes, so a delimiter, a doubled quote, or a
#   line break inside a value stays part of that value.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Name of the array variable to fill
# @set The named array
# @exitcode 0 The input was parsed
# @exitcode 1 The input contains the ASCII unit separator, or the name is not bindable
# @example
#   dybatpho::csv_read report.csv rows
#   dybatpho::csv_fields "${rows[1]}" first
#   printf '%s\n' "${first[0]}"
#######################################
function dybatpho::csv_read {
  # The locals carry the module prefix: the array is filled through the name
  # the caller passes, and a plain local of the same name would take the rows.
  local __dybatpho_csv_read_input __dybatpho_csv_read_target
  dybatpho::expect_args __dybatpho_csv_read_input __dybatpho_csv_read_target -- "$@"
  dybatpho::expect_ref "${__dybatpho_csv_read_target}"

  local __dybatpho_csv_read_text __dybatpho_csv_read_delimiter
  __dybatpho_csv_delimiter_into __dybatpho_csv_read_delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_input_into __dybatpho_csv_read_text "${__dybatpho_csv_read_input}"
  __dybatpho_csv_parse_into "${__dybatpho_csv_read_target}" \
    "${__dybatpho_csv_read_text}" "${__dybatpho_csv_read_delimiter}"
}

#######################################
# @description Split one record from `dybatpho::csv_read` into a named array of
#   field values.
# @arg $1 string One record
# @arg $2 string Name of the array variable to fill
# @set The named array
# @exitcode 0 The record was split
# @exitcode 1 The name is not bindable
# @example
#   dybatpho::csv_fields "${rows[0]}" header
#######################################
function dybatpho::csv_fields {
  local __dybatpho_csv_fields_record __dybatpho_csv_fields_target
  dybatpho::expect_args __dybatpho_csv_fields_record __dybatpho_csv_fields_target -- "$@"
  dybatpho::expect_ref "${__dybatpho_csv_fields_target}"

  __dybatpho_csv_split_fields_into "${__dybatpho_csv_fields_target}" "${__dybatpho_csv_fields_record}"
}

#######################################
# @description Serialize records back to CSV.
#   A field is quoted only when it has to be: when it contains the delimiter, a
#   quote, or a line break.
# @arg $1 string Name of the array of records
# @stdout CSV text, one record per line
# @exitcode 0 The records were written
# @exitcode 1 The name is not bindable
# @example
#   dybatpho::csv_read input.csv rows
#   dybatpho::csv_write rows > normalized.csv
#######################################
function dybatpho::csv_write {
  local __dybatpho_csv_write_source
  dybatpho::expect_args __dybatpho_csv_write_source -- "$@"
  dybatpho::expect_ref "${__dybatpho_csv_write_source}"

  local __dybatpho_csv_write_delimiter
  __dybatpho_csv_delimiter_into __dybatpho_csv_write_delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_write_with "${__dybatpho_csv_write_source}" "${__dybatpho_csv_write_delimiter}"
}

#######################################
# @description Serialize records with a delimiter the caller has resolved.
# @arg $1 string Name of the array of records
# @arg $2 string Field delimiter
# @stdout CSV text, one record per line
# @internal
#######################################
function __dybatpho_csv_write_with {
  local -n __dybatpho_csv_out_ref="$1"
  local __dybatpho_csv_delimiter="$2"
  local __dybatpho_csv_record __dybatpho_csv_quoted __dybatpho_csv_line __dybatpho_csv_at
  local -a __dybatpho_csv_parts=()

  for __dybatpho_csv_record in ${__dybatpho_csv_out_ref[@]+"${__dybatpho_csv_out_ref[@]}"}; do
    __dybatpho_csv_split_fields_into __dybatpho_csv_parts "${__dybatpho_csv_record}"
    __dybatpho_csv_line=""
    for __dybatpho_csv_at in "${!__dybatpho_csv_parts[@]}"; do
      __dybatpho_csv_quote_into __dybatpho_csv_quoted \
        "${__dybatpho_csv_parts[${__dybatpho_csv_at}]}" "${__dybatpho_csv_delimiter}"
      if ((__dybatpho_csv_at == 0)); then
        __dybatpho_csv_line="${__dybatpho_csv_quoted}"
      else
        __dybatpho_csv_line+="${__dybatpho_csv_delimiter}${__dybatpho_csv_quoted}"
      fi
    done
    printf '%s\n' "${__dybatpho_csv_line}"
  done
}

#######################################
# @description Rewrite CSV with another delimiter.
#   The input is read with `DYBATPHO_CSV_DELIMITER` and written with the
#   delimiter given, quoting each field for the delimiter it is written with:
#   a comma inside a value no longer needs quotes in a TSV file, and a tab
#   inside one does. This is how a comma-separated export becomes TSV, or a
#   semicolon-separated one becomes plain CSV.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Delimiter to write with: one character, or `tab`
# @stdout The records, written with the new delimiter
# @exitcode 0 The input was rewritten
# @exitcode 1 Either delimiter is invalid, or the input contains the ASCII unit separator
# @example
#   dybatpho::csv_convert report.csv tab > report.tsv
#   DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_convert report.tsv ","
#######################################
function dybatpho::csv_convert {
  local input target
  dybatpho::expect_args input target -- "$@"

  local -a records=()
  local text from to
  __dybatpho_csv_delimiter_into from "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_delimiter_into to "${target}"
  __dybatpho_csv_input_into text "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${from}" "${to}"; then
    local status
    __dybatpho_csv_awk_into status convert "${from}" "${to}" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_parse_into records "${text}" "${from}"
  __dybatpho_csv_write_with records "${to}"
}

#######################################
# @description Print the column names from the first record.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @stdout One column name per line
# @exitcode 0 The header was read, or the input was empty
# @example
#   dybatpho::csv_header report.csv
#######################################
function dybatpho::csv_header {
  local input
  dybatpho::expect_args input -- "$@"

  local -a records=() names=()
  local delimiter
  local text status
  __dybatpho_csv_source_into text delimiter "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${delimiter}"; then
    __dybatpho_csv_awk_into status header "${delimiter}" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_records_into records names "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  printf '%s\n' ${names[@]+"${names[@]}"}
}

#######################################
# @description Print one column's values, chosen by its header name or by its
#   1-based position when no header carries that name.
#   A row shorter than the header reads as an empty value, and a row longer
#   than the header stops the script rather than dropping the extra field.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column: header name, or 1-based position
# @stdout One value per line, excluding the header
# @exitcode 0 The column was printed
# @exitcode 1 No column has that name or position, or a row has more fields than the header
# @tip A value containing a line break spans lines here; read through
#   `dybatpho::csv_read` when every value has to stay one item
# @example
#   dybatpho::csv_col report.csv "Region"
#######################################
function dybatpho::csv_col {
  local input column
  dybatpho::expect_args input column -- "$@"

  local -a records=() names=() fields=()
  local index at
  local delimiter
  local text status
  __dybatpho_csv_source_into text delimiter "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${delimiter}"; then
    __dybatpho_csv_awk_into status col "${delimiter}" "${column}" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_records_into records names "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_pick_into index names "${column}"

  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    printf '%s\n' "${fields[${index}]-}"
  done
}

#######################################
# @description Print chosen columns, in the order given, as CSV with the header.
#   A column is named by its header, or by its position counting from `1` when
#   no header carries that name, so `3` picks the third column unless a column
#   is literally called `3`. A column may be chosen more than once, and a row
#   shorter than the header reads as empty values.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $@ string Columns to keep: header names or 1-based positions
# @stdout CSV text: the chosen header, then every row's chosen fields
# @exitcode 0 The columns were printed, or the input was empty
# @exitcode 1 A column matches neither a name nor a position, or a row is wider than the header
# @example
#   dybatpho::csv_select billing.csv owner cost
#   dybatpho::csv_select billing.csv 4 1   # cost first, then service
#######################################
function dybatpho::csv_select {
  local input
  dybatpho::expect_args input -- "$@"
  shift
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Name at least one column to keep"

  local -a records=() names=() fields=() picks=() chosen=() kept=()
  local delimiter column index at pick
  local IFS
  local text status
  __dybatpho_csv_source_into text delimiter "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${delimiter}"; then
    __dybatpho_csv_awk_into status select "${delimiter}" "$@" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_records_into records names "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  for column in "$@"; do
    __dybatpho_csv_pick_into index names "${column}"
    picks+=("${index}")
  done

  for ((at = 0; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    chosen=()
    for pick in ${picks[@]+"${picks[@]}"}; do
      chosen+=("${fields[${pick}]-}")
    done
    IFS="${__dybatpho_csv_unit}"
    kept+=("${chosen[*]-}")
    unset IFS
  done

  __dybatpho_csv_write_with kept "${delimiter}"
}

#######################################
# @description Sort the data rows by one column and print them as CSV with
#   the header first.
#   The sort is stable, so rows with equal keys keep their input order, and it
#   happens in Bash rather than through `sort`, because a value may hold a line
#   break. `auto` compares as numbers when every non-empty value in the column
#   is one, and as text otherwise; text compares byte by byte, the same on
#   every machine whatever its locale. An empty value sorts last in either
#   direction, so blanks never push the rows that matter off the top.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column: header name, or 1-based position
# @arg $3 string [default: asc] Order: `asc` or `desc`
# @arg $4 string [default: auto] Comparison: `auto`, `text`, or `number`
# @stdout CSV text: the header, then the sorted rows
# @exitcode 0 The rows were sorted, or the input was empty
# @exitcode 1 An unknown column, order or comparison, a non-number under `number`, or a row wider than the header
# @example
#   dybatpho::csv_sort billing.csv cost desc
#   dybatpho::csv_sort billing.csv owner asc text
#######################################
function dybatpho::csv_sort {
  local input column order type
  dybatpho::expect_args input column -- "$@"
  order="${3:-asc}"
  type="${4:-auto}"

  case "${order}" in
    asc | desc) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::csv_sort rejects an unknown order, comparison or value" covers
    # this; `dybatpho::die` exits, so that test uses `run`.
    *) dybatpho::die "${FUNCNAME[0]}: Unknown order: ${order}. Use asc or desc" ;; # kcov(skip)
  esac
  case "${type}" in
    # A case arm has no command to fire on.
    auto | text | number) ;;                                                                     # kcov(skip)
    *) dybatpho::die "${FUNCNAME[0]}: Unknown comparison: ${type}. Use auto, text, or number" ;; # kcov(skip)
  esac

  local -a records=() names=() fields=() keys=() order_of=() sorted=()
  local delimiter index at key
  local text status
  __dybatpho_csv_source_into text delimiter "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${delimiter}"; then
    __dybatpho_csv_awk_into status sort "${delimiter}" "${column}" "${order}" "${type}" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_records_into records names "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_pick_into index names "${column}"

  local all_numbers=1
  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    key="${fields[${index}]-}"
    keys[at]="${key}"
    order_of+=("${at}")
    [[ -z "${key}" ]] || dybatpho::math_is_number "${key}" || {
      [[ "${type}" != "number" ]] \
        || dybatpho::die "${FUNCNAME[0]}: Row ${at} has ${column}=${key}, which is not a number" # kcov(skip)
      all_numbers=0
    }
  done

  [[ "${type}" != "auto" ]] || {
    type="text"
    ((all_numbers == 0)) || type="number"
  }
  if [[ "${type}" == "number" ]]; then
    # Encode each number once into a key that orders correctly as text, so
    # the merge compares strings instead of parsing two numbers every time.
    for at in "${!keys[@]}"; do
      # Through a scalar: Bash 4.3 drops an assignment made through a nameref
      # that names an array element.
      if [[ -n "${keys[${at}]}" ]]; then
        local sort_key
        __dybatpho_math_sort_key_into sort_key "${keys[${at}]}"
        keys[at]="${sort_key}"
      fi
    done
  fi

  __dybatpho_helpers_sort order_of __dybatpho_csv_row_before keys "${order}"

  sorted=("${records[0]}")
  for at in ${order_of[@]+"${order_of[@]}"}; do
    sorted+=("${records[${at}]}")
  done
  __dybatpho_csv_write_with sorted "${delimiter}"
}

#######################################
# @description Join two CSV inputs on a key column and print the result as
#   CSV.
#   The output header is every left column followed by every right column
#   except the right key, which would repeat the left one. Rows come out in
#   the left input's order, and a left row matching several right rows gives
#   one output row per match, in the right input's order, the way SQL does.
#   `inner` keeps only the left rows with a match; `left` keeps every left row
#   and leaves the right columns empty where nothing matched. An empty key
#   matches nothing, the way SQL's `NULL` does, so blank cells never pair up
#   into rows nobody meant to relate.
# @arg $1 string Left CSV: file path, `-` for stdin, or CSV text
# @arg $2 string Right CSV: file path, `-` for stdin, or CSV text
# @arg $3 string Key column in the left input: header name, or 1-based position
# @arg $4 string [default: inner] Join type: `inner` or `left`
# @arg $5 string? Key column in the right input, the same way, default is the left one
# @stdout CSV text: the joined header, then the joined rows
# @exitcode 0 The inputs were joined
# @exitcode 1 An unknown join type or key column, both inputs read from stdin, or a row wider than its header
# @tip A column named the same on both sides appears twice in the output;
#   `dybatpho::csv_col` and the other by-name helpers then read the left one
# @example
#   dybatpho::csv_join services.csv owners.csv team
#   dybatpho::csv_join services.csv costs.csv service left name
#######################################
function dybatpho::csv_join {
  local left_input right_input key type right_key
  dybatpho::expect_args left_input right_input key -- "$@"
  type="${4:-inner}"
  right_key="${5:-${key}}"

  case "${type}" in
    inner | left) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::csv_join rejects an unknown type, a missing key and two
    # stdins" covers this; `dybatpho::die` exits, so that test uses `run`.
    *) dybatpho::die "${FUNCNAME[0]}: Unknown join type: ${type}. Use inner or left" ;; # kcov(skip)
  esac
  [[ "${left_input}" != "-" || "${right_input}" != "-" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Only one input can be read from stdin" # kcov(skip)

  local -a left=() right=() left_names=() right_names=() fields=() extra=() joined=()
  local delimiter left_index right_index at value row
  local -A matches=()
  local IFS
  __dybatpho_csv_load_into left left_names delimiter "${left_input}"
  __dybatpho_csv_load_into right right_names delimiter "${right_input}"
  ((${#left[@]})) || return 0

  __dybatpho_csv_pick_into left_index left_names "${key}"
  ((${#right[@]})) || right_names=("${right_key}")
  __dybatpho_csv_pick_into right_index right_names "${right_key}"

  # Index the right rows by key, keeping every match in input order.
  local -a right_rest=()
  for ((at = 1; at < ${#right[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${right[${at}]}"
    __dybatpho_csv_expect_width fields right_names "${at}"
    value="${fields[${right_index}]-}"
    [[ -n "${value}" ]] || continue
    matches["${value}"]+="${matches[${value}]+ }${at}"
  done

  __dybatpho_csv_without_into extra right_names "${right_index}"
  IFS="${__dybatpho_csv_unit}"
  joined=("${left_names[*]-}${__dybatpho_csv_unit}${extra[*]-}")
  unset IFS

  local -a empty_right=()
  for ((at = 1; at < ${#right_names[@]}; at++)); do
    empty_right+=("")
  done

  local -a left_fields=()
  for ((at = 1; at < ${#left[@]}; at++)); do
    __dybatpho_csv_split_fields_into left_fields "${left[${at}]}"
    __dybatpho_csv_expect_width left_fields left_names "${at}"
    # Pad a short row, so the right columns line up under their header.
    while ((${#left_fields[@]} < ${#left_names[@]})); do
      left_fields+=("")
    done
    value="${left_fields[${left_index}]}"

    if [[ -n "${value}" && -n "${matches[${value}]+set}" ]]; then
      for row in ${matches[${value}]}; do
        __dybatpho_csv_split_fields_into fields "${right[${row}]}"
        while ((${#fields[@]} < ${#right_names[@]})); do
          fields+=("")
        done
        __dybatpho_csv_without_into right_rest fields "${right_index}"
        IFS="${__dybatpho_csv_unit}"
        joined+=("${left_fields[*]-}${__dybatpho_csv_unit}${right_rest[*]-}")
        unset IFS
      done
    elif [[ "${type}" == "left" ]]; then
      IFS="${__dybatpho_csv_unit}"
      joined+=("${left_fields[*]-}${__dybatpho_csv_unit}${empty_right[*]-}")
      unset IFS
    fi
  done

  # A right side holding nothing but its key leaves no column to append, and
  # the joined records then carry one trailing empty field too many.
  if ((${#right_names[@]} == 1)); then
    for at in "${!joined[@]}"; do
      joined[at]="${joined[${at}]%"${__dybatpho_csv_unit}"}"
    done
  fi
  __dybatpho_csv_write_with joined "${delimiter}"
}

#######################################
# @description Copy an array without the element at one index, into a named
#   array.
# @arg $1 string Name of the array variable to fill
# @arg $2 string Name of the source array
# @arg $3 number Index to leave out
# @set The named array
# @internal
#######################################
function __dybatpho_csv_without_into {
  local -n __dybatpho_csv_without_ref="$1"
  local -n __dybatpho_csv_source_ref="$2"
  local __dybatpho_csv_skip="$3" __dybatpho_csv_at
  __dybatpho_csv_without_ref=()

  for __dybatpho_csv_at in "${!__dybatpho_csv_source_ref[@]}"; do
    ((__dybatpho_csv_at == __dybatpho_csv_skip)) \
      || __dybatpho_csv_without_ref+=("${__dybatpho_csv_source_ref[${__dybatpho_csv_at}]}")
  done
}

#######################################
# @description Return success when one row's key strictly comes before
#   another's in the requested order, comparing bytes, for
#   `__dybatpho_helpers_sort`. An empty key comes after every other key,
#   whichever the direction.
# @arg $1 string Row number that might come first
# @arg $2 string Row number it is compared with
# @arg $3 string Name of the array mapping a row number to its key
# @arg $4 string `asc` or `desc`
# @exitcode 0 The first row comes first
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_csv_row_before {
  local -n __dybatpho_csv_before_keys="$3"
  local __dybatpho_csv_first="${__dybatpho_csv_before_keys[$1]}"
  local __dybatpho_csv_second="${__dybatpho_csv_before_keys[$2]}" LC_ALL=C

  [[ -n "${__dybatpho_csv_first}" ]] || return 1
  [[ -n "${__dybatpho_csv_second}" ]] || return 0
  if [[ "$4" == "desc" ]]; then
    [[ "${__dybatpho_csv_second}" < "${__dybatpho_csv_first}" ]]
  else
    [[ "${__dybatpho_csv_first}" < "${__dybatpho_csv_second}" ]]
  fi
}

#######################################
# @description Resolve a column given by name or by 1-based position to its
#   index, into a named variable. A header name wins over a position, so a
#   column literally called `2` is still reachable by name.
# @arg $1 string Name of the variable receiving the index
# @arg $2 string Name of the array of header names
# @arg $3 string Header name, or a position counting from `1`
# @set The named variable
# @exitcode 0 The column was found
# @exitcode 1 Neither a name nor a position matches
# @internal
#######################################
function __dybatpho_csv_pick_into {
  local -n __dybatpho_csv_pick_ref="$1"
  local -n __dybatpho_csv_header_ref="$2"
  local __dybatpho_csv_wanted="$3" __dybatpho_csv_at

  for __dybatpho_csv_at in "${!__dybatpho_csv_header_ref[@]}"; do
    if [[ "${__dybatpho_csv_header_ref[${__dybatpho_csv_at}]}" == "${__dybatpho_csv_wanted}" ]]; then
      __dybatpho_csv_pick_ref="${__dybatpho_csv_at}"
      return 0
    fi
  done

  if [[ "${__dybatpho_csv_wanted}" =~ ^[1-9][0-9]*$ ]] \
    && ((10#${__dybatpho_csv_wanted} <= ${#__dybatpho_csv_header_ref[@]})); then
    __dybatpho_csv_pick_ref="$((10#${__dybatpho_csv_wanted} - 1))"
    return 0
  fi

  local __dybatpho_csv_complaint="No such column: ${__dybatpho_csv_wanted}."
  __dybatpho_csv_complaint+=" The header has ${#__dybatpho_csv_header_ref[@]} columns:"
  __dybatpho_csv_complaint+=" ${__dybatpho_csv_header_ref[*]}"
  # "dybatpho::csv_select reports a column that is neither a name nor a
  # position" covers this; `dybatpho::die` exits, so that test uses `run`.
  dybatpho::die "${FUNCNAME[1]}: ${__dybatpho_csv_complaint}" # kcov(skip)
}

#######################################
# @description Stop when a row carries more fields than the header names.
#   Printing such a row would drop the extra field, which is the silent loss
#   this module exists to prevent.
# @arg $1 string Name of the array of fields
# @arg $2 string Name of the array of header names
# @arg $3 number Row number, counting the header as row 0
# @exitcode 0 The row fits the header
# @exitcode 1 The row has more fields than the header
# @internal
#######################################
function __dybatpho_csv_expect_width {
  local -n __dybatpho_csv_row_ref="$1"
  local -n __dybatpho_csv_names_ref="$2"

  ((${#__dybatpho_csv_row_ref[@]} <= ${#__dybatpho_csv_names_ref[@]})) || {
    local __dybatpho_csv_complaint="Row $3 has ${#__dybatpho_csv_row_ref[@]} fields"
    __dybatpho_csv_complaint+=" but the header names ${#__dybatpho_csv_names_ref[@]}:"
    __dybatpho_csv_complaint+=" ${__dybatpho_csv_row_ref[*]}"
    dybatpho::die "${FUNCNAME[1]}: ${__dybatpho_csv_complaint}"
  }
}

#######################################
# @description Keep the rows whose column satisfies a comparison, and print
#   them as CSV with the header.
#   `gt` and `lt` compare as numbers when both values are numeric, and as text
#   otherwise, so a version column sorts the way a reader expects and a size
#   column the way arithmetic does.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column: header name, or 1-based position
# @arg $3 string Operator: `eq`, `ne`, `gt`, `lt`, or `contains`
# @arg $4 string Value to compare against
# @stdout CSV text: the header, then the matching rows
# @exitcode 0 The rows were filtered
# @exitcode 1 No column has that name, the operator is unknown, or a row is wider than the header
# @example
#   dybatpho::csv_filter billing.csv "Cost" gt 100
#######################################
function dybatpho::csv_filter {
  local input column operator value
  dybatpho::expect_args input column operator value -- "$@"

  local operators="eq, ne, gt, lt, or contains"
  case "${operator}" in
    eq | ne | gt | lt | contains) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::csv_filter rejects an operator it does not have" covers this.
    # `dybatpho::die` exits, so that test uses `run`, which clears the trap
    # kcov instruments through; `--exclude-line` reads the marker on the line.
    *) dybatpho::die "${FUNCNAME[0]}: Unknown operator: ${operator}. Use ${operators}" ;; # kcov(skip)
  esac

  local -a records=() names=() fields=() kept=()
  local index at
  local delimiter
  local text status
  __dybatpho_csv_source_into text delimiter "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${delimiter}"; then
    __dybatpho_csv_awk_into status filter "${delimiter}" "${column}" "${operator}" "${value}" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_records_into records names "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_pick_into index names "${column}"
  kept=("${records[0]}")

  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    if __dybatpho_csv_matches "${fields[${index}]-}" "${operator}" "${value}"; then
      kept+=("${records[${at}]}")
    fi
  done

  dybatpho::csv_write kept
}

#######################################
# @description Compare one field against a value.
# @arg $1 string Field value
# @arg $2 string Operator
# @arg $3 string Value to compare against
# @exitcode 0 The field satisfies the comparison
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_csv_matches {
  local field="$1" operator="$2" value="$3"

  # Text orders in ASCII, the same on every platform; `sort` in this module
  # already does.
  local LC_ALL=C
  case "${operator}" in
    eq) [[ "${field}" == "${value}" ]] ;;
    ne) [[ "${field}" != "${value}" ]] ;;
    contains) [[ "${field}" == *"${value}"* ]] ;;
    gt)
      if dybatpho::math_is_number "${field}" && dybatpho::math_is_number "${value}"; then
        dybatpho::math_gt "${field}" "${value}"
      else
        [[ "${field}" > "${value}" ]]
      fi
      ;;
    lt)
      if dybatpho::math_is_number "${field}" && dybatpho::math_is_number "${value}"; then
        dybatpho::math_lt "${field}" "${value}"
      else
        [[ "${field}" < "${value}" ]]
      fi
      ;;
    *) ;; # kcov(skip) - dybatpho::csv_filter rejects an unknown operator first
  esac
}

#######################################
# @description Convert CSV to a JSON array of objects, keyed by the header.
#   Every value is a JSON string, because CSV carries no types and guessing
#   them is how an identifier with leading zeros or a version number becomes
#   the wrong value. Cast in `jq` when a consumer needs numbers.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @stdout Compact JSON array
# @exitcode 0 The conversion succeeded
# @exitcode 1 A row has more fields than the header
# @example
#   dybatpho::csv_to_json report.csv | dybatpho::json_pretty -
# @note Needs the `json` module: `dybatpho::load json`, or `--modules csv json`
#######################################
function dybatpho::csv_to_json {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_csv_need_json

  local -a records=() names=() fields=()
  local at index object document="" name_json value_json
  local delimiter
  local text status
  __dybatpho_csv_source_into text delimiter "${input}"
  if __dybatpho_csv_use_awk "${#text}" "${delimiter}"; then
    __dybatpho_csv_awk_into status json "${delimiter}" <<< "${text}"
    ((status == 3)) || return "${status}"
  fi
  __dybatpho_csv_records_into records names "${text}" "${delimiter}"

  if ((${#records[@]} == 0)); then
    printf '[]\n'
    return 0
  fi

  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    object=""
    for index in "${!names[@]}"; do
      # Escaped in this shell: a `$(dybatpho::json_string …)` per cell cost two
      # forks a cell, ten times the time of the rest of the conversion.
      __dybatpho_json_escape_into name_json "${names[${index}]}"
      __dybatpho_json_escape_into value_json "${fields[${index}]-}"
      [[ -z "${object}" ]] || object+=","
      object+="${name_json}:${value_json}"
    done
    [[ -z "${document}" ]] || document+=","
    document+="{${object}}"
  done

  printf '[%s]\n' "${document}"
}

#######################################
# @description Stop unless the `json` module is loaded.
#   Encoding each value as a JSON string is the `json` module's work, and only
#   the conversion to JSON does it: reading, filtering, sorting, joining and
#   the conversion from JSON, which runs `jq` or `yq` itself, need nothing from
#   it. Registering it as a dependency would load it into every script that
#   only reads a spreadsheet -- and into every `table` that renders one -- so
#   the conversion asks for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `json`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `json` module is not loaded
# @internal
#######################################
function __dybatpho_csv_need_json {
  __dybatpho_helpers_need_module json __dybatpho_json_escape_into "${FUNCNAME[1]}"
}

#######################################
# @description Convert a JSON array of objects to CSV.
#   The keys of the first object become the header, in their document order,
#   and a later object missing one of them writes an empty value there.
# @arg $1 string JSON file path, `-` for stdin, or JSON text
# @stdout CSV text
# @exitcode 0 The conversion succeeded
# @exitcode 1 The document is not an array of objects
# @exitcode 127 Neither `yq` nor `jq` is installed
# @example
#   dybatpho::csv_from_json pods.json > pods.csv
#######################################
function dybatpho::csv_from_json {
  local input
  dybatpho::expect_args input -- "$@"

  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"

  local command_name
  command_name=$(dybatpho::coalesce_cmd jq yq) \
    || dybatpho::die "${FUNCNAME[0]}: Neither jq nor yq is installed" 127

  local text
  __dybatpho_string_input_into text "${input}" files

  # Both backends are asked for CSV and the result is then read back and
  # written out by this module, so the quoting a caller sees comes from one
  # place no matter which command was available.
  local converted
  if [[ "${command_name}" == "jq" ]]; then
    # An empty array has no first object to take a header from, and is still
    # an array of objects: it converts to nothing, as it does through `yq`.
    local filter='if . == [] then empty else'
    # shellcheck disable=SC2016 # the `$` names a jq variable inside the filter, not a shell one
    filter+=' (.[0] | keys_unsorted) as $k'
    # shellcheck disable=SC2016 # the `$` names a jq variable inside the filter, not a shell one
    # Only a missing value or `null` is empty: `// ""` blanked `false` too.
    filter+=' | ([$k] + [.[] | [ $k[] as $key | .[$key] | if . == null then "" else tostring end ]])'
    filter+=' | .[] | @csv end'
    converted="$(printf '%s' "${text}" | jq -r "${filter}")" \
      || dybatpho::die "${FUNCNAME[0]}: The document is not an array of objects"
  else
    # `yq` writes `null` as the word; `jq` above writes it as an empty value.
    converted="$(printf '%s' "${text}" | yq eval -p=json -o=csv '(.[][] | select(tag == "!!null")) |= ""')" \
      || dybatpho::die "${FUNCNAME[0]}: The document is not an array of objects"
  fi

  local -a records=()
  # `jq` uses `,` whatever the caller set, so the conversion is read back with
  # the delimiter the backend wrote and written out with the configured one.
  __dybatpho_csv_parse_into records "${converted}" ","
  __dybatpho_csv_write_with records "${delimiter}"
}
