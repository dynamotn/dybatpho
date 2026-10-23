setup() {
  load test_helper
  CLDR_SH="${DYBATPHO_DIR}/scripts/i18n_cldr.sh"
  # The release the network test pins, and against which
  # `scripts/i18n_cldr.allow` was written.
  CLDR_TAG="49.0.0"
}

# @description Write a two-locale cldr-json tree under $1, in the `-modern`
#   layout, holding only the fields the script reads.
write_cldr_fixture() {
  local root="$1"
  mkdir -p "${root}/cldr-core/supplemental" \
    "${root}/cldr-numbers-modern/main/en" "${root}/cldr-numbers-modern/main/fr" \
    "${root}/cldr-dates-modern/main/en" "${root}/cldr-dates-modern/main/fr"
  cat > "${root}/cldr-core/supplemental/plurals.json" << 'EOF'
{"supplemental": {"plurals-type-cardinal": {
  "en": {"pluralRule-count-one": "i = 1 and v = 0 @integer 1", "pluralRule-count-other": " @integer 0, 2~16"},
  "fr": {"pluralRule-count-one": "i = 0,1 @integer 0, 1", "pluralRule-count-other": " @integer 2~17"}
}}}
EOF
  printf '%s\n' '{"supplemental": {"metadata": {"alias": {"languageAlias": {}}}}}' \
    > "${root}/cldr-core/supplemental/aliases.json"
  printf '%s\n' '{"supplemental": {"likelySubtags": {"und-JP": "ja-Jpan-JP"}}}' \
    > "${root}/cldr-core/supplemental/likelySubtags.json"
  printf '%s\n' '{"supplemental": {"currencyData": {"fractions": {"DEFAULT": {"_digits": "2"}, "JPY": {"_digits": "0"}}}}}' \
    > "${root}/cldr-core/supplemental/currencyData.json"
  # French groups with U+202F and puts U+00A0 before the percent sign.
  local locale group percent
  for locale in en fr; do
    if [[ "${locale}" == en ]]; then group="," percent="#,##0%"; else group=$'\xe2\x80\xaf' percent=$'#,##0\xc2\xa0%'; fi
    cat > "${root}/cldr-numbers-modern/main/${locale}/numbers.json" << EOF
{"main": {"${locale}": {"numbers": {
  "symbols-numberSystem-latn": {"decimal": ".", "group": "${group}", "minusSign": "-", "percentSign": "%"},
  "decimalFormats-numberSystem-latn": {"standard": "#,##0.###"},
  "percentFormats-numberSystem-latn": {"standard": "${percent}"},
  "currencyFormats-numberSystem-latn": {"standard": "¤#,##0.00"}
}}}}
EOF
    cat > "${root}/cldr-dates-modern/main/${locale}/ca-gregorian.json" << 'EOF'
{"main": {"xx": {"dates": {"calendars": {"gregorian": {
  "months": {"format": {
    "wide": {"1": "January", "2": "February", "3": "March", "4": "April", "5": "May", "6": "June",
      "7": "July", "8": "August", "9": "September", "10": "October", "11": "November", "12": "December"},
    "abbreviated": {"1": "Jan", "2": "Feb", "3": "Mar", "4": "Apr", "5": "May", "6": "Jun",
      "7": "Jul", "8": "Aug", "9": "Sep", "10": "Oct", "11": "Nov", "12": "Dec"}}},
  "days": {"format": {
    "wide": {"mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday",
      "sat": "Saturday", "sun": "Sunday"},
    "abbreviated": {"mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu", "fri": "Fri", "sat": "Sat", "sun": "Sun"}}},
  "dayPeriods": {"format": {"wide": {"am": "AM", "pm": "PM"}}},
  "dateFormats": {"short": "M/d/yy", "medium": "MMM d, y", "long": "MMMM d, y", "full": "EEEE, MMMM d, y"},
  "timeFormats": {"short": "h:mm a", "medium": "h:mm:ss a"},
  "dateTimeFormats": {"short": "{1}, {0}", "medium": "{1}, {0}", "long": "{1}, {0}", "full": "{1}, {0}"},
  "dateTimeFormats-atTime": {"standard": {"long": "{1} 'at' {0}", "full": "{1} 'at' {0}"}}
}}}}}}
EOF
  done
  printf '%s\n' '{"main": {"en": {"numbers": {"currencies": {"USD": {"symbol": "$"}, "JPY": {"symbol": "¥"}}}}}}' \
    > "${root}/cldr-numbers-modern/main/en/currencies.json"
}

# @description Write a module source with small tables in the shape of
#   `src/i18n.sh`: French wrongly in the `one` family, a wrong yen sign, and
#   French seeded with the wrong kind of space.
write_source_fixture() {
  cat > "$1" << 'EOF'
declare -gA __dybatpho_i18n_plural_family=(
  [en]=one [fr]=one
)
declare -gA DYBATPHO_I18N_NUMBER=(
  ["en.group"]="," ["en.decimal"]="." ["en.grouping"]="3" ["en.minus"]="-" ["en.percent"]="#%"
  ["fr.decimal"]="." ["fr.percent"]="# %"
)
declare -gA DYBATPHO_I18N_CURRENCY=(
  ["USD.symbol"]='$' ["USD.digits"]=2
  ["JPY.symbol"]='Y' ["JPY.digits"]=0
)
declare -gA DYBATPHO_I18N_CURRENCY_LAYOUT=(
  ["en.layout"]='¤#'
)
declare -gA DYBATPHO_I18N_NAMES=(
  ["en.weekdays_abbr"]="Mon,Tue,Wed,Thu,Fri,Sat,Sun" ["en.dayperiods"]="AM,PM"
)
declare -gA DYBATPHO_I18N_DATE_PATTERN=(
  ["en.date_short"]="M/d/yy" ["en.date_long"]="MMMM d, yyyy"
  ["en.datetime_long"]="{date} 'at' {time}"
)
function __dybatpho_i18n_seed_symbols {
  DYBATPHO_I18N_NUMBER["fr.group"]="${nbsp}"
}
EOF
}

cldr() {
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${CLDR_SH}" "$@"
}

@test "i18n_cldr.sh --check lists every value that differs from CLDR and fails" {
  write_cldr_fixture "${BATS_TEST_TMPDIR}/cldr"
  write_source_fixture "${BATS_TEST_TMPDIR}/i18n.sh"
  run --separate-stderr cldr --cldr "${BATS_TEST_TMPDIR}/cldr" \
    --source "${BATS_TEST_TMPDIR}/i18n.sh" --allow "" --check
  assert_failure
  assert_line "__dybatpho_i18n_plural_family[fr]: source one, CLDR fr"
  assert_line "DYBATPHO_I18N_CURRENCY[JPY.symbol]: source Y, CLDR ¥"
  # A seeded separator is compared by its exact character, shown by code point.
  assert_line "DYBATPHO_I18N_NUMBER[fr.group]: source <U+00A0>, CLDR <U+202F>"
  # Equal after the module's conventions: `y` read as `yyyy`, the "at" form of a
  # date-time pattern, and a no-break space before the percent sign.
  refute_output --partial "date_long"
  refute_output --partial "datetime_long"
  refute_output --partial "fr.percent"
  assert_stderr --partial "3 value(s) differ from CLDR"
}

@test "i18n_cldr.sh prints the tables regenerated from CLDR in the module's form" {
  write_cldr_fixture "${BATS_TEST_TMPDIR}/cldr"
  write_source_fixture "${BATS_TEST_TMPDIR}/i18n.sh"
  run --separate-stderr cldr --cldr "${BATS_TEST_TMPDIR}/cldr" \
    --source "${BATS_TEST_TMPDIR}/i18n.sh" --allow ""
  assert_success
  assert_output --partial "declare -gA DYBATPHO_I18N_DATE_PATTERN=("
  assert_output --partial "[fr]=fr"
  assert_output --partial "# Seeded by __dybatpho_i18n_seed_symbols"
  assert_output --partial 'DYBATPHO_I18N_NUMBER["fr.group"] = <U+202F>'

  # The output is Bash that builds the corrected tables.
  printf '%s\n' "${output}" > "${BATS_TEST_TMPDIR}/generated.sh"
  run bash -c '. "$1"; printf "%s|%s|%s\n" "${DYBATPHO_I18N_CURRENCY[JPY.symbol]}" \
    "${__dybatpho_i18n_plural_family[fr]}" "${DYBATPHO_I18N_DATE_PATTERN[en.date_long]}"' \
    _ "${BATS_TEST_TMPDIR}/generated.sh"
  assert_success
  # An equivalent value keeps the source's spelling, so no-op runs change nothing.
  assert_output "¥|fr|MMMM d, yyyy"
}

@test "i18n_cldr.sh keeps an allowed deviation and says when it is no longer needed" {
  write_cldr_fixture "${BATS_TEST_TMPDIR}/cldr"
  write_source_fixture "${BATS_TEST_TMPDIR}/i18n.sh"
  printf '%s\n' '# deliberate' \
    'DYBATPHO_I18N_CURRENCY[JPY.symbol] the table spells the yen in ASCII' \
    '__dybatpho_i18n_plural_family[fr] French is kept singular-for-one here' \
    'DYBATPHO_I18N_NUMBER[fr.group] the seed writes a full no-break space' \
    'DYBATPHO_I18N_CURRENCY[USD.symbol] already matches' > "${BATS_TEST_TMPDIR}/allow"
  run --separate-stderr cldr --cldr "${BATS_TEST_TMPDIR}/cldr" \
    --source "${BATS_TEST_TMPDIR}/i18n.sh" --allow "${BATS_TEST_TMPDIR}/allow" --check
  assert_success
  assert_line "allowed: DYBATPHO_I18N_CURRENCY[JPY.symbol]: source Y, CLDR ¥ (the table spells the yen in ASCII)"
  assert_line "note: DYBATPHO_I18N_CURRENCY[USD.symbol] matches CLDR; its allowlist entry can go"

  run --separate-stderr cldr --cldr "${BATS_TEST_TMPDIR}/cldr" \
    --source "${BATS_TEST_TMPDIR}/i18n.sh" --allow "${BATS_TEST_TMPDIR}/allow"
  assert_success
  assert_output --partial "[\"JPY.symbol\"]=\"Y\""
}

@test "i18n_cldr.sh refuses an allowlist entry without a reason and a tree without CLDR data" {
  write_cldr_fixture "${BATS_TEST_TMPDIR}/cldr"
  write_source_fixture "${BATS_TEST_TMPDIR}/i18n.sh"
  printf '%s\n' 'DYBATPHO_I18N_CURRENCY[JPY.symbol]' > "${BATS_TEST_TMPDIR}/allow"
  run --separate-stderr cldr --cldr "${BATS_TEST_TMPDIR}/cldr" \
    --source "${BATS_TEST_TMPDIR}/i18n.sh" --allow "${BATS_TEST_TMPDIR}/allow" --check
  assert_failure
  assert_stderr --partial "Allowlist entry without a reason"

  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  run --separate-stderr cldr --cldr "${BATS_TEST_TMPDIR}/empty" --check
  assert_failure
  assert_stderr --partial "No cldr-core/supplemental/plurals.json"

  run --separate-stderr cldr --check
  assert_failure
}

# @description Fetch the cldr-json files the shipped tables need, at the pinned
#   release, from GitHub. Fails when the network is unavailable.
fetch_cldr() {
  local root="$1" base file locale
  base="https://raw.githubusercontent.com/unicode-org/cldr-json/${CLDR_TAG}/cldr-json"
  local -a files=()
  for file in plurals aliases likelySubtags currencyData; do
    files+=("cldr-core/supplemental/${file}.json")
  done
  # The CLDR locales the tables resolve to, then the home locales of the
  # currencies whose English symbol is only the ISO code.
  for locale in en en-GB de es it nl pt tr vi id pl ru fr ja ko zh zh-Hant th ar he hi bn; do
    files+=("cldr-numbers-full/main/${locale}/numbers.json" "cldr-dates-full/main/${locale}/ca-gregorian.json")
  done
  for locale in en de-CH ru pl tr th ar-AE sv is id ar-BH ar-KW ar-TN es-CL; do
    files+=("cldr-numbers-full/main/${locale}/currencies.json")
  done
  for file in "${files[@]}"; do
    mkdir -p "$(dirname "${root}/${file}")"
    curl -fsSL --retry 2 --max-time 30 -o "${root}/${file}" "${base}/${file}" || return 1
  done
}

@test "the shipped i18n tables match the pinned CLDR release, allowlist aside" {
  # Uses an unpacked cldr-json given in DYBATPHO_CLDR_JSON, or downloads the
  # few files it needs; skipped offline.
  local root="${DYBATPHO_CLDR_JSON:-}"
  if [[ -z "${root}" ]]; then
    root="${BATS_TEST_TMPDIR}/cldr-json"
    command -v curl > /dev/null || skip "curl is not installed"
    fetch_cldr "${root}" || skip "cldr-json ${CLDR_TAG} cannot be downloaded"
  fi
  run --separate-stderr cldr --cldr "${root}" --check
  assert_success
  # Every table locale was found, so nothing was compared against nothing.
  refute_output --partial "has no CLDR locale"
  refute_output --partial "names nothing in the tables"
}
