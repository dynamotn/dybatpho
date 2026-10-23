#!/usr/bin/env bash
# @file i18n_cldr.sh
# @brief Regenerate the CLDR tables of src/i18n.sh from cldr-json, or check them
# @description
#   `src/i18n.sh` carries its locale data as hand-copied `declare -gA` tables:
#   number symbols and grouping, currency symbols and digits, currency layouts,
#   month, weekday and day-period names, date and time patterns, and the map of
#   languages to plural rule families. This script derives every one of those
#   values from a local copy of the Unicode CLDR data in its JSON form
#   (https://github.com/unicode-org/cldr-json), so the tables can be refreshed
#   and audited instead of trusted.
#
#   The keys come from the tables themselves: the script regenerates exactly
#   the locales, currencies, fields and languages `src/i18n.sh` already ships.
#   By default it prints the regenerated tables in the `declare -gA` form the
#   module uses; `--check` compares instead and lists every value that differs,
#   exiting non-zero when one does.
#
#   CLDR is richer than the module, so values are brought into the module's
#   conventions before they are compared:
#
#   - no-break and narrow no-break spaces become plain spaces, and bidi marks
#     (U+200E, U+200F, U+061C) are dropped: the module seeds the no-break
#     spaces itself at load time, in `__dybatpho_i18n_seed_symbols`;
#   - a group separator that is a space is not a table entry at all, because
#     that function seeds it; its exact character is still checked against
#     the one the seed writes;
#   - number symbols always come from the `latn` numbering system, since the
#     module never transliterates digits;
#   - a lone `y` in a date pattern becomes `yyyy`, which renders the same
#     year; `{1}` and `{0}` in a date-time pattern become `{date}` and
#     `{time}`, preferring CLDR's "at time" form where it has one;
#   - a currency symbol is the English one, or its narrow form when the English
#     symbol is only the ISO code, because the table is not per locale;
#   - a plural family is matched by evaluating the CLDR cardinal rules for the
#     integers 0 to 1099 against each `__dybatpho_i18n_plural_<family>`
#     function. CLDR's `many` for exact millions, which the integer-only
#     families do not model, is reported as a note rather than as drift.
#
#   The script never downloads anything: it takes the path of an unpacked
#   cldr-json release, the directory holding `cldr-core/`, and either the
#   `-full` or the `-modern` number and date packages.
#
# @example
#   scripts/i18n_cldr.sh --cldr ~/src/cldr-json/cldr-json            # print the tables
#   scripts/i18n_cldr.sh --cldr ~/src/cldr-json/cldr-json --check    # report drift
#
# @see
#   - `src/i18n.sh`
#   - `test/i18n_cldr_script.bats`
# The predicates here answer yes or no, and are called for that answer.
# shellcheck disable=SC2310
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh" --modules "cli i18n"

dybatpho::register_common_handlers

# The tables this script owns, in the order they appear in `src/i18n.sh`.
CLDR_TABLES=(
  __dybatpho_i18n_plural_family
  DYBATPHO_I18N_NUMBER
  DYBATPHO_I18N_CURRENCY
  DYBATPHO_I18N_CURRENCY_LAYOUT
  DYBATPHO_I18N_NAMES
  DYBATPHO_I18N_DATE_PATTERN
)

# The integers every plural rule is evaluated for, and the one count beyond
# them that only CLDR's `many`-for-millions rule tells apart.
CLDR_SAMPLE_MAX=1099
CLDR_MILLION=1000000

# The jq program that turns one locale's CLDR files into `field<TAB>value`
# lines, already in the module's conventions. Kept as data so that each locale
# costs one jq process rather than one per field.
# shellcheck disable=SC2016 # jq variables, not shell ones
CLDR_LOCALE_JQ='
  def norm: if . == null then null else gsub("[\u00a0\u202f\u2009]"; " ") | gsub("[\u200e\u200f\u061c]"; "") end;
  def years: if . == null then null else ([39] | implode) as $quote | split($quote) | to_entries
    | map(if .key % 2 == 0 then (.value | gsub("(?<!y)y(?!y)"; "yyyy")) else .value end)
    | join($quote) end;
  def shape: split(";")[0] | gsub("[#0-9.,]+"; "#") | norm;
  ($numbers[0].main | to_entries[0].value.numbers) as $n
  | ($dates[0].main | to_entries[0].value.dates.calendars.gregorian) as $g
  | ($n["symbols-numberSystem-latn"]) as $s
  | ($n["decimalFormats-numberSystem-latn"].standard | split(";")[0] | split(".")[0]
      | split(",") | map(length)) as $groups
  | [
      ["group", $s.group],
      ["decimal", ($s.decimal | norm)],
      ["minus", ($s.minusSign | norm)],
      ["grouping", (if ($groups | length) < 2 then "0"
        elif ($groups | length) > 2 and $groups[-2] != $groups[-1]
        then "\($groups[-1]);\($groups[-2])" else "\($groups[-1])" end)],
      ["percent", ($n["percentFormats-numberSystem-latn"].standard | shape)],
      ["layout", ($n["currencyFormats-numberSystem-latn"].standard | shape)],
      ["months", ([range(1; 13) | tostring | $g.months.format.wide[.] | norm] | join(","))],
      ["months_abbr", ([range(1; 13) | tostring | $g.months.format.abbreviated[.] | norm] | join(","))],
      ["weekdays", (["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        | map($g.days.format.wide[.] | norm) | join(","))],
      ["weekdays_abbr", (["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        | map($g.days.format.abbreviated[.] | norm) | join(","))],
      ["dayperiods", ([$g.dayPeriods.format.wide.am, $g.dayPeriods.format.wide.pm]
        | map(norm) | join(","))],
      (["short", "medium", "long", "full"][] as $w
        | ["date_" + $w, ($g.dateFormats[$w] | norm | years)],
          ["time_" + $w, ($g.timeFormats[$w] | norm | years)],
          ["datetime_" + $w, ((($g["dateTimeFormats-atTime"].standard // {})[$w] // $g.dateTimeFormats[$w])
            | if . == null then null
              else gsub("\\{1\\}"; "{date}") | gsub("\\{0\\}"; "{time}") | norm end)])
    ]
  | .[] | select(.[1] != null) | "\(.[0])\t\(.[1])"
'

# @description Spell the characters a reader cannot tell apart from a space,
#   or cannot see at all, as their code points.
# @arg $1 string Name of the variable receiving the visible form
# @arg $2 string Value
# @set The named variable
# @internal
function __dybatpho_cldr_visible_into {
  local __dybatpho_cldr_var value
  dybatpho::expect_args __dybatpho_cldr_var value -- "$@"
  local -n __dybatpho_cldr_visible="${__dybatpho_cldr_var}"
  value="${value//$'\xc2\xa0'/<U+00A0>}"
  value="${value//$'\xe2\x80\xaf'/<U+202F>}"
  value="${value//$'\xe2\x80\x89'/<U+2009>}"
  value="${value//$'\xe2\x80\x8e'/<U+200E>}"
  value="${value//$'\xe2\x80\x8f'/<U+200F>}"
  value="${value//$'\xd8\x9c'/<U+061C>}"
  __dybatpho_cldr_visible="${value}"
}

# @description Report whether a value is one of the spaces CLDR separates
#   digit groups with.
# @arg $1 string Value
# @exitcode 0 The value is a space, a no-break space or a narrow no-break space
# @exitcode 1 Otherwise
# @internal
function __dybatpho_cldr_is_space {
  local value
  dybatpho::expect_args value -- "$@"
  case "${value}" in
    ' ' | $'\xc2\xa0' | $'\xe2\x80\xaf' | $'\xe2\x80\x89') return 0 ;;
    *) return 1 ;;
  esac
}

# @description Write the current tables of a source file as
#   `table<TAB>key<TAB>value` lines, keys in source order. The blocks are
#   evaluated by Bash in a child process, so quoting is read exactly as the
#   module reads it. Group separators written by `__dybatpho_i18n_seed_symbols`
#   are added with the character the seed uses when Unicode is available.
# @arg $1 path Source file, normally `src/i18n.sh`
# @arg $2 path File receiving the lines
# @internal
function __dybatpho_cldr_current {
  local source output
  dybatpho::expect_args source output -- "$@"
  local blocks order
  dybatpho::create_temp blocks ".sh" "cldr_blocks"
  dybatpho::create_temp order ".tsv" "cldr_order"

  local table
  for table in "${CLDR_TABLES[@]}"; do
    awk -v name="${table}" '
      $0 ~ "^declare -gA " name "=\\(" { on = 1 }
      on { print }
      on && /^\)/ { exit }
    ' "${source}" >> "${blocks}"
    # Key order, so a regenerated table reads like the one it replaces.
    awk -v name="${table}" '
      $0 ~ "^declare -gA " name "=\\(" { on = 1; next }
      on && /^\)/ { exit }
      on {
        line = $0
        while (match(line, /\[("[^"]+"|[A-Za-z0-9_.]+)\]=/)) {
          key = substr(line, RSTART + 1, RLENGTH - 3)
          gsub(/"/, "", key)
          print name "\t" key
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "${source}" >> "${order}"
  done

  # The seeded separators: `DYBATPHO_I18N_NUMBER["fr.group"]="${narrow}"`.
  local seeded
  seeded="$(sed -n 's/^ *DYBATPHO_I18N_NUMBER\["\([A-Za-z_]*\)\.group"\]="\${\([a-z]*\)}".*/\1 \2/p' \
    "${source}")"

  bash -c '
    set -eu
    . "$1"
    while IFS=$'\''\t'\'' read -r table key; do
      declare -n map="${table}"
      printf "%s\t%s\t%s\n" "${table}" "${key}" "${map[${key}]}"
      unset -n map
    done < "$2"
    while read -r locale kind; do
      [ -n "${locale}" ] || continue
      case "${kind}" in
        narrow) value=$'\''\xe2\x80\xaf'\'' ;;
        nbsp) value=$'\''\xc2\xa0'\'' ;;
        *) value=" " ;;
      esac
      printf "DYBATPHO_I18N_NUMBER\t%s.group\t%s\n" "${locale}" "${value}"
    done <<< "$3"
  ' bash "${blocks}" "${order}" "${seeded}" > "${output}"
}

# @description Find the CLDR locale directory for a module locale tag. The tag
#   is tried as written, then through CLDR's likely subtags (`zh_TW` is
#   `zh-Hant-TW`, held in `zh-Hant`), then as its bare language.
# @arg $1 string Name of the variable receiving the CLDR locale
# @arg $2 path Directory holding one directory per CLDR locale
# @arg $3 string Module locale tag, such as `pt_BR`
# @arg $4 path The `likelySubtags.json` of the release
# @exitcode 1 No candidate exists
# @internal
function __dybatpho_cldr_locale_into {
  local __dybatpho_cldr_var __dybatpho_cldr_main __dybatpho_cldr_tag __dybatpho_cldr_likely
  dybatpho::expect_args __dybatpho_cldr_var __dybatpho_cldr_main __dybatpho_cldr_tag \
    __dybatpho_cldr_likely -- "$@"
  local -n __dybatpho_cldr_out="${__dybatpho_cldr_var}"
  local tag="${__dybatpho_cldr_tag//_/-}" likely candidate
  likely="$(jq -r --arg t "${tag}" '.supplemental.likelySubtags[$t] // empty' \
    "${__dybatpho_cldr_likely}")"
  local -a candidates=("${tag}")
  while [[ "${likely}" == *-* ]]; do
    candidates+=("${likely}")
    likely="${likely%-*}"
  done
  candidates+=("${tag%%-*}")
  for candidate in "${candidates[@]}"; do
    if [[ -d "${__dybatpho_cldr_main}/${candidate}" ]]; then
      __dybatpho_cldr_out="${candidate}"
      return 0
    fi
  done
  return 1
}

# @description Find the symbol of a currency: the English one, unless English
#   only knows the ISO code, in which case the symbol of the currency's home
#   locale -- the country its code starts with, in that country's likely
#   language, `de-CH` for `CHF`. The table is not per locale, and this is the
#   symbol a reader anywhere is most likely to recognise.
# @arg $1 string Name of the variable receiving the symbol, empty when unknown
# @arg $2 string ISO 4217 code
# @arg $3 path Directory holding one directory per CLDR locale for numbers
# @arg $4 path The `likelySubtags.json` of the release
# @internal
function __dybatpho_cldr_symbol_into {
  local __dybatpho_cldr_var __dybatpho_cldr_code __dybatpho_cldr_numbers __dybatpho_cldr_likely
  dybatpho::expect_args __dybatpho_cldr_var __dybatpho_cldr_code __dybatpho_cldr_numbers \
    __dybatpho_cldr_likely -- "$@"
  local -n __dybatpho_cldr_symbol="${__dybatpho_cldr_var}"
  local __dybatpho_cldr_c="${__dybatpho_cldr_code}" __dybatpho_cldr_q __dybatpho_cldr_found
  local __dybatpho_cldr_home __dybatpho_cldr_lang __dybatpho_cldr_loc
  # shellcheck disable=SC2016 # jq variables, not shell ones
  __dybatpho_cldr_q='.main | to_entries[0].value.numbers.currencies[$c].symbol // empty
    | gsub("[\u200e\u200f\u061c]"; "")'
  __dybatpho_cldr_found="$(jq -r --arg c "${__dybatpho_cldr_c}" "${__dybatpho_cldr_q}" \
    "${__dybatpho_cldr_numbers}/en/currencies.json")"
  # English inheriting the bare code from the root locale leaves no entry.
  if [[ -z "${__dybatpho_cldr_found}" || "${__dybatpho_cldr_found}" == "${__dybatpho_cldr_c}" ]]; then
    __dybatpho_cldr_home="${__dybatpho_cldr_c:0:2}"
    # shellcheck disable=SC2016 # jq variables, not shell ones
    __dybatpho_cldr_lang="$(jq -r --arg t "und-${__dybatpho_cldr_home}" '.supplemental.likelySubtags[$t] // empty
      | split("-")[0]' "${__dybatpho_cldr_likely}")"
    if [[ -n "${__dybatpho_cldr_lang}" ]] \
      && __dybatpho_cldr_locale_into __dybatpho_cldr_loc "${__dybatpho_cldr_numbers}" \
        "${__dybatpho_cldr_lang}-${__dybatpho_cldr_home}" "${__dybatpho_cldr_likely}" \
      && [[ -f "${__dybatpho_cldr_numbers}/${__dybatpho_cldr_loc}/currencies.json" ]]; then
      __dybatpho_cldr_found="$(jq -r --arg c "${__dybatpho_cldr_c}" "${__dybatpho_cldr_q}" \
        "${__dybatpho_cldr_numbers}/${__dybatpho_cldr_loc}/currencies.json")"
    fi
  fi
  # The root locale's symbol for every currency is its code.
  __dybatpho_cldr_symbol="${__dybatpho_cldr_found:-${__dybatpho_cldr_c}}"
}

# @description Bring a date pattern to one spelling for comparison: a quoted
#   run holding no ASCII letter is unquoted, since only ASCII letters are
#   pattern letters and anything else is literal either way. CLDR writes
#   `y年M月d日`, the module `yyyy'年'M'月'd'日'`, and both render alike.
# @arg $1 string Name of the variable receiving the canonical pattern
# @arg $2 string Pattern
# @set The named variable
# @internal
function __dybatpho_cldr_canonical_into {
  local __dybatpho_cldr_var pattern
  dybatpho::expect_args __dybatpho_cldr_var pattern -- "$@"
  local -n __dybatpho_cldr_canonical="${__dybatpho_cldr_var}"
  local out="" rest="${pattern}" quoted
  while [[ "${rest}" == *"'"* ]]; do
    out+="${rest%%"'"*}"
    rest="${rest#*"'"}"
    quoted="${rest%%"'"*}"
    if [[ "${rest}" != *"'"* ]]; then
      out+="'${rest}"
      rest=""
      break
    fi
    rest="${rest#*"'"}"
    if [[ "${quoted}" == *[A-Za-z]* || -z "${quoted}" ]]; then
      out+="'${quoted}'"
    else
      out+="${quoted}"
    fi
  done
  __dybatpho_cldr_canonical="${out}${rest}"
}

# @description Print the plural category of every sample count, one line per
#   language, from CLDR's cardinal rules: `lang<TAB>cat,cat,...`. Counts are
#   integers, so the operands for fractions and exponents are all zero.
# @arg $1 path The `plurals.json` of the release
# @arg $2 string Space-separated languages
# @arg $3 path The `aliases.json` of the release, for retired codes
# @stdout One line per language
# @internal
function __dybatpho_cldr_plural_signatures {
  local plurals languages aliases
  dybatpho::expect_args plurals languages aliases -- "$@"
  local rules
  # shellcheck disable=SC2016 # jq variables, not shell ones
  rules="$(jq -r --arg langs "${languages}" --slurpfile aliases "${aliases}" '
    .supplemental["plurals-type-cardinal"] as $p
    | ($aliases[0].supplemental.metadata.alias.languageAlias) as $a
    | $langs | split(" ")[] | select(. != "") as $lang
    | ($p[$lang] // $p[(($a[$lang]._replacement // "") | split("-")[0])] // {}) as $r
    | ["zero", "one", "two", "few", "many"][] as $c
    | ($r["pluralRule-count-" + $c] // empty) | split("@")[0]
    | "\($lang)\t\($c)\t\(.)"
  ' "${plurals}")"
  awk -F'\t' -v max="${CLDR_SAMPLE_MAX}" -v million="${CLDR_MILLION}" -v langs="${languages}" '
    function operand(name, n) { return (name == "n" || name == "i") ? n : 0 }
    function relation(text, n,    parts, left, op, list, value, items, k, bounds, hit) {
      # `x % m = a,b..c` and `x != ...`; x is one operand letter.
      if (match(text, /!=/)) { op = "!=" } else { op = "=" }
      split(text, parts, op == "!=" ? "!=" : "=")
      left = parts[1]; list = parts[2]
      gsub(/ /, "", left); gsub(/ /, "", list)
      if (index(left, "%")) {
        split(left, bounds, "%")
        value = operand(bounds[1], n) % bounds[2]
      } else {
        value = operand(left, n)
      }
      hit = 0
      split(list, items, ",")
      for (k in items) {
        if (index(items[k], "..")) {
          split(items[k], bounds, "\\.\\.")
          if (value >= bounds[1] + 0 && value <= bounds[2] + 0) hit = 1
        } else if (value == items[k] + 0) {
          hit = 1
        }
      }
      return op == "=" ? hit : !hit
    }
    function holds(rule, n,    alternatives, a, conditions, c, all) {
      if (rule ~ /^[[:space:]]*$/) return 0
      split(rule, alternatives, / or /)
      for (a in alternatives) {
        split(alternatives[a], conditions, / and /)
        all = 1
        for (c in conditions) if (!relation(conditions[c], n)) { all = 0; break }
        if (all) return 1
      }
      return 0
    }
    function category(lang, n,    i, order, c) {
      split("zero one two few many", order, " ")
      for (i = 1; i <= 5; i++) {
        c = order[i]
        if ((lang SUBSEP c) in rule && holds(rule[lang, c], n)) return c
      }
      return "other"
    }
    { rule[$1, $2] = $3 }
    END {
      count = split(langs, list, " ")
      for (l = 1; l <= count; l++) {
        lang = list[l]
        if (lang == "") continue
        out = ""
        for (n = 0; n <= max; n++) out = out (n ? "," : "") category(lang, n)
        print lang "\t" out "\t" category(lang, million)
      }
    }
  ' <<< "${rules}"
}

# @description Print the plural category of every sample count for each
#   plural family the module implements: `family<TAB>cat,cat,...<TAB>cat`.
# @arg $@ string Families
# @stdout One line per family
# @internal
function __dybatpho_cldr_family_signatures {
  local family n
  for family in "$@"; do
    declare -F "__dybatpho_i18n_plural_${family}" > /dev/null || continue
    printf '%s\t' "${family}"
    for ((n = 0; n <= CLDR_SAMPLE_MAX; n++)); do
      ((n == 0)) || printf ','
      "__dybatpho_i18n_plural_${family}" "${n}"
    done
    printf '\t'
    "__dybatpho_i18n_plural_${family}" "${CLDR_MILLION}"
    printf '\n'
  done
}

# @description Quote a value for a `declare -gA` entry the way the module's
#   tables do: double quotes, or single quotes when the value holds a
#   character double quotes would expand.
# @arg $1 string Value
# @stdout The quoted value
# @internal
function __dybatpho_cldr_quote {
  local value
  dybatpho::expect_args value -- "$@"
  if [[ "${value}" == *[\$\`\\\"]* && "${value}" != *"'"* ]]; then
    printf "'%s'" "${value}"
  else
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    printf '"%s"' "${value}"
  fi
}

# @description Print regenerated tables as `declare -gA` blocks, one line per
#   locale (or per family for the plural map), in source key order.
# @arg $1 path File of `table<TAB>key<TAB>value` lines
# @stdout The blocks
# @internal
function __dybatpho_cldr_render {
  local generated
  dybatpho::expect_args generated -- "$@"
  local table key value prefix line current rows
  for table in "${CLDR_TABLES[@]}"; do
    printf 'declare -gA %s=(\n' "${table}"
    line="" current=""
    rows="$(awk -F'\t' -v t="${table}" '$1 == t && $3 != "\001seeded"' "${generated}")"
    while IFS=$'\t' read -r _ key value; do
      [[ -n "${key}" ]] || continue
      if [[ "${table}" == __dybatpho_i18n_plural_family ]]; then
        prefix="${value}"
      else
        prefix="${key%%.*}"
        value="$(__dybatpho_cldr_quote "${value}" || true)"
        key="\"${key}\""
      fi
      if [[ "${prefix}" != "${current}" && -n "${line}" ]]; then
        printf '  %s\n' "${line}"
        line=""
      fi
      current="${prefix}"
      line+="${line:+ }[${key}]=${value}"
    done <<< "${rows}"
    [[ -z "${line}" ]] || printf '  %s\n' "${line}"
    printf ')\n\n'
  done
  # Seeded separators are not table entries; say which ones the seed owes.
  local seeded
  seeded="$(awk -F'\t' '$3 == "\001seeded" { print $2 "\t" $4 }' "${generated}")"
  if [[ -n "${seeded}" ]]; then
    printf '# Seeded by __dybatpho_i18n_seed_symbols, not written above:\n'
    local shown
    while IFS=$'\t' read -r key value; do
      __dybatpho_cldr_visible_into shown "${value}"
      printf '#   DYBATPHO_I18N_NUMBER["%s"] = %s\n' "${key}" "${shown}"
    done <<< "${seeded}"
  fi
}

# @description Regenerate or check the tables.
# @noargs
# @internal
function __dybatpho_cldr_run {
  dybatpho::require jq
  # shellcheck disable=SC2154 # set by the option spec of this script
  local root="${CLDR_ROOT}" source="${CLDR_SOURCE}"
  dybatpho::is file "${source}" || dybatpho::die "No module source at ${source}"
  local core="${root}/cldr-core/supplemental" numbers="" dates="" flavour
  for flavour in full modern; do
    [[ -n "${numbers}" || ! -d "${root}/cldr-numbers-${flavour}/main" ]] \
      || numbers="${root}/cldr-numbers-${flavour}/main"
    [[ -n "${dates}" || ! -d "${root}/cldr-dates-${flavour}/main" ]] \
      || dates="${root}/cldr-dates-${flavour}/main"
  done
  [[ -f "${core}/plurals.json" ]] || dybatpho::die "No cldr-core/supplemental/plurals.json under ${root}"
  [[ -n "${numbers}" ]] || dybatpho::die "No cldr-numbers-full or cldr-numbers-modern under ${root}"
  [[ -n "${dates}" ]] || dybatpho::die "No cldr-dates-full or cldr-dates-modern under ${root}"

  # Deliberate deviations: `TABLE[key] reason`, one per line.
  local -A allowed=()
  local id reason
  # shellcheck disable=SC2154 # set by the option spec of this script
  if [[ -n "${CLDR_ALLOW}" ]]; then
    dybatpho::is file "${CLDR_ALLOW}" || dybatpho::die "No allowlist at ${CLDR_ALLOW}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
      id="${line%%[[:space:]]*}"
      reason="${line#"${id}"}"
      reason="${reason#"${reason%%[![:space:]]*}"}"
      [[ -n "${reason}" ]] || dybatpho::die "Allowlist entry without a reason: ${id}"
      allowed["${id}"]="${reason}"
    done < "${CLDR_ALLOW}"
  fi

  local current generated notes
  dybatpho::create_temp current ".tsv" "cldr_current"
  dybatpho::create_temp generated ".tsv" "cldr_generated"
  dybatpho::create_temp notes ".txt" "cldr_notes"
  __dybatpho_cldr_current "${source}" "${current}"

  # One jq run per locale yields every field the locale can have.
  local -A field=() seen=()
  local -a locales=()
  local table key value locale name cldr
  while IFS=$'\t' read -r table key value || [[ -n "${table}" ]]; do
    case "${table}" in
      DYBATPHO_I18N_NUMBER | DYBATPHO_I18N_CURRENCY_LAYOUT | DYBATPHO_I18N_NAMES | DYBATPHO_I18N_DATE_PATTERN)
        locale="${key%%.*}"
        if [[ -z "${seen[${locale}]-}" ]]; then
          seen["${locale}"]=1
          locales+=("${locale}")
        fi
        ;;
      *) ;;
    esac
  done < "${current}"
  for locale in ${locales[@]+"${locales[@]}"}; do
    if ! __dybatpho_cldr_locale_into cldr "${numbers}" "${locale}" "${core}/likelySubtags.json" \
      || [[ ! -f "${dates}/${cldr}/ca-gregorian.json" ]]; then
      printf 'note: %s has no CLDR locale in %s\n' "${locale}" "${root}" >> "${notes}"
      continue
    fi
    local fields
    fields="$(jq -rn --slurpfile numbers "${numbers}/${cldr}/numbers.json" \
      --slurpfile dates "${dates}/${cldr}/ca-gregorian.json" "${CLDR_LOCALE_JQ}")"
    while IFS=$'\t' read -r name value; do
      [[ -n "${name}" ]] && field["${locale}.${name}"]="${value}"
    done <<< "${fields}"
  done

  # Plural families: CLDR's verdict per language against each family's.
  local languages="" families="" line
  local -A family_users=()
  while IFS=$'\t' read -r table key value || [[ -n "${table}" ]]; do
    [[ "${table}" == __dybatpho_i18n_plural_family ]] || continue
    languages+="${key} "
    local users="${family_users[${value}]-0}"
    family_users["${value}"]=$((users + 1))
  done < "${current}"
  # When several families agree for every integer, as `fr`, `pt` and `hi` do,
  # a language joins the one most languages already use.
  local ranking=""
  for line in "${!family_users[@]}"; do
    ranking+="${family_users[${line}]} ${line}"$'\n'
  done
  families="$(printf '%s' "${ranking}" | sort -k1,1nr -k2,2 | cut -d' ' -f2 | tr '\n' ' ')"
  # Families no language uses yet are candidates too, last.
  local defined
  defined="$(compgen -A function __dybatpho_i18n_plural_ || true)"
  defined="${defined//__dybatpho_i18n_plural_/}"
  for line in ${defined}; do
    [[ "${line}" != category && " ${families} " != *" ${line} "* ]] && families+="${line} "
  done
  local -A family_sig=() family_million=() lang_sig=() lang_million=()
  local fam sig million signatures
  local -a family_list=()
  read -r -a family_list <<< "${families}"
  dybatpho::create_temp signatures ".tsv" "cldr_signatures"
  __dybatpho_cldr_family_signatures ${family_list[@]+"${family_list[@]}"} > "${signatures}"
  while IFS=$'\t' read -r fam sig million || [[ -n "${fam}" ]]; do
    family_sig["${fam}"]="${sig}"
    family_million["${fam}"]="${million}"
  done < "${signatures}"
  __dybatpho_cldr_plural_signatures "${core}/plurals.json" "${languages}" "${core}/aliases.json" \
    > "${signatures}"
  while IFS=$'\t' read -r name sig million || [[ -n "${name}" ]]; do
    lang_sig["${name}"]="${sig}"
    lang_million["${name}"]="${million}"
  done < "${signatures}"

  # Build the generated table in the current key order.
  local symbol
  : > "${generated}"
  while IFS=$'\t' read -r table key value || [[ -n "${table}" ]]; do
    case "${table}" in
      __dybatpho_i18n_plural_family)
        local chosen="" candidate
        if [[ "${family_sig[${value}]-}" == "${lang_sig[${key}]-x}" ]]; then
          chosen="${value}"
        elif [[ "${family_sig[${key}]-}" == "${lang_sig[${key}]-x}" ]]; then
          chosen="${key}"
        else
          for candidate in ${families}; do
            if [[ "${family_sig[${candidate}]}" == "${lang_sig[${key}]-x}" ]]; then
              chosen="${candidate}"
              break
            fi
          done
        fi
        if [[ -z "${chosen}" ]]; then
          printf 'note: no plural family matches CLDR for %s; keeping %s\n' "${key}" "${value}" >> "${notes}"
          chosen="${value}"
        elif [[ "${family_million[${chosen}]}" != "${lang_million[${key}]-}" ]]; then
          printf 'note: %s: CLDR says "%s" for 1000000, the %s family says "%s"\n' "${key}" \
            "${lang_million[${key}]-}" "${chosen}" "${family_million[${chosen}]}" >> "${notes}"
        fi
        printf '%s\t%s\t%s\n' "${table}" "${key}" "${chosen}" >> "${generated}"
        ;;
      DYBATPHO_I18N_CURRENCY)
        local code="${key%%.*}" what="${key#*.}"
        if [[ "${what}" == digits ]]; then
          # shellcheck disable=SC2016 # jq variables, not shell ones
          value="$(jq -r --arg c "${code}" '.supplemental.currencyData.fractions
            | (.[$c] // .DEFAULT)._digits' "${core}/currencyData.json")"
        else
          __dybatpho_cldr_symbol_into symbol "${code}" "${numbers}" "${core}/likelySubtags.json"
          if [[ -n "${symbol}" ]]; then
            value="${symbol}"
          else
            printf 'note: CLDR has no symbol for %s; keeping the current value\n' "${code}" >> "${notes}"
          fi
        fi
        printf '%s\t%s\t%s\n' "${table}" "${key}" "${value}" >> "${generated}"
        ;;
      *)
        locale="${key%%.*}" name="${key#*.}"
        [[ "${table}" == DYBATPHO_I18N_CURRENCY_LAYOUT ]] && name="layout"
        local field_key="${locale}.${name}"
        if [[ -n "${field[${field_key}]+set}" ]]; then
          value="${field[${field_key}]}"
        else
          printf 'note: CLDR has no %s for %s; keeping the current value\n' "${name}" "${locale}" >> "${notes}"
        fi
        printf '%s\t%s\t%s\n' "${table}" "${key}" "${value}" >> "${generated}"
        ;;
    esac
  done < "${current}"

  # Spaces as group separators are seeded, not tabled: mark every one CLDR
  # has, including any the source does not seed yet.
  local -A seeded_now=()
  while IFS=$'\t' read -r table key value || [[ -n "${table}" ]]; do
    [[ "${table}" == DYBATPHO_I18N_NUMBER && "${key}" == *.group ]] || continue
    seeded_now["${key}"]="${value}"
  done < "${current}"
  for locale in ${locales[@]+"${locales[@]}"}; do
    local group_key="${locale}.group"
    value="${field[${group_key}]-}"
    [[ -n "${value}" ]] || continue
    if __dybatpho_cldr_is_space "${value}"; then
      awk -F'\t' -v k="${locale}.group" -v v="${value}" 'BEGIN { OFS = "\t" }
        $1 == "DYBATPHO_I18N_NUMBER" && $2 == k { $3 = "\001seeded"; $4 = v; done = 1 }
        { print }
        END { if (!done) print "DYBATPHO_I18N_NUMBER", k, "\001seeded", v }' \
        "${generated}" > "${generated}.next" && mv "${generated}.next" "${generated}"
    elif [[ -z "${seeded_now[${group_key}]+set}" ]]; then
      printf 'note: %s has a group separator in CLDR but none in the table\n' "${locale}" >> "${notes}"
    fi
  done

  # Compare: a seeded entry compares its exact character, a date pattern its
  # canonical spelling. An allowed entry keeps its current value.
  local drift=0 want have id_key canonical_have canonical_cldr shown_have shown_cldr
  local -A current_value=()
  local rendered
  dybatpho::create_temp rendered ".tsv" "cldr_rendered"
  while IFS=$'\t' read -r table key value || [[ -n "${table}" ]]; do
    id_key="${table}|${key}"
    current_value["${id_key}"]="${value}"
  done < "${current}"
  local -a report=()
  local extra
  while IFS=$'\t' read -r table key want extra || [[ -n "${table}" ]]; do
    id="${table}[${key}]"
    id_key="${table}|${key}"
    have="${current_value[${id_key}]-<missing>}"
    local cldr="${want}"
    [[ "${want}" == $'\001seeded' ]] && cldr="${extra}"
    local same=false
    if [[ "${have}" == "${cldr}" ]]; then
      same=true
    elif [[ "${table}" == DYBATPHO_I18N_DATE_PATTERN ]]; then
      __dybatpho_cldr_canonical_into canonical_have "${have}"
      __dybatpho_cldr_canonical_into canonical_cldr "${cldr}"
      [[ "${canonical_have}" != "${canonical_cldr}" ]] || same=true
    fi
    __dybatpho_cldr_visible_into shown_have "${have}"
    __dybatpho_cldr_visible_into shown_cldr "${cldr}"
    if [[ -n "${allowed[${id}]+set}" ]]; then
      if [[ "${same}" == true ]]; then
        report+=("note: ${id} matches CLDR; its allowlist entry can go")
      else
        report+=("allowed: ${id}: source ${shown_have}, CLDR ${shown_cldr} (${allowed[${id}]})")
      fi
      unset 'allowed[${id}]'
      [[ "${want}" == $'\001seeded' ]] || want="${have}"
    elif [[ "${same}" == true ]]; then
      # Keep the source's spelling of an equivalent value, so regenerating
      # tables that match CLDR changes nothing.
      [[ "${want}" == $'\001seeded' ]] || want="${have}"
    else
      drift=$((drift + 1))
      report+=("${id}: source ${shown_have}, CLDR ${shown_cldr}")
    fi
    printf '%s\t%s\t%s%s\n' "${table}" "${key}" "${want}" "${extra:+$'\t'${extra}}" >> "${rendered}"
  done < "${generated}"
  for id in "${!allowed[@]}"; do
    report+=("note: allowlist entry ${id} names nothing in the tables")
  done

  # shellcheck disable=SC2154 # set by the option spec of this script
  if ! dybatpho::is true "${CLDR_CHECK}"; then
    __dybatpho_cldr_render "${rendered}"
    [[ -s "${notes}" ]] && cat "${notes}" >&2
    return 0
  fi
  ((${#report[@]} == 0)) || printf '%s\n' ${report[@]+"${report[@]}"}
  [[ -s "${notes}" ]] && cat "${notes}"
  ((drift == 0)) || dybatpho::die "${drift} value(s) differ from CLDR"
  dybatpho::success "The i18n tables match CLDR"
}

# @description CLI specification for this script.
# @noargs
# dyshellint disable=BSG052 # `dybatpho::generate_from_spec` adds `--help` to every spec, so the option already exists
function _spec {
  dybatpho::opts::setup \
    "Regenerate the CLDR tables of src/i18n.sh from cldr-json, or report their drift" \
    CLDR_ARGS action:"__dybatpho_cldr_run"

  dybatpho::opts::param "Unpacked cldr-json release: the directory holding cldr-core/" \
    CLDR_ROOT --cldr required:true
  dybatpho::opts::param "Module source whose tables are regenerated" CLDR_SOURCE --source \
    init:="${DYBATPHO_DIR}/src/i18n.sh"
  dybatpho::opts::param "Deliberate deviations from CLDR, one 'TABLE[key] reason' per line" \
    CLDR_ALLOW --allow init:="${SCRIPT_DIR}/i18n_cldr.allow"
  dybatpho::opts::flag "Compare with CLDR and exit 1 on any difference" CLDR_CHECK --check \
    on:true off:false init:="false"
}

dybatpho::generate_from_spec _spec "$@"
