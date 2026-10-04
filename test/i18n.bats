setup() {
  load test_helper
  dybatpho::i18n_reset
  # Every case pins the locale, the timezone, and the reference time. Left to
  # the environment, this suite would answer differently on a developer machine
  # with LANG set than it does in CI.
  export DYBATPHO_DATE_TIMEZONE=UTC
  export DYBATPHO_I18N_LOCALE=en
  export DYBATPHO_I18N_FALLBACK=en
  export DYBATPHO_I18N_PATH=""
  export DYBATPHO_I18N_STRICT=false
  export DYBATPHO_I18N_MISSING_MARK=""
  export DYBATPHO_I18N_TRANSLATE_LIBRARY=false
  export DYBATPHO_I18N_BYTE_STANDARD=iec
  export DYBATPHO_I18N_CURRENCY_NEGATIVE=sign
  export DYBATPHO_I18N_ASCII=false
  export DYBATPHO_I18N_NOW=""
}

teardown() {
  dybatpho::i18n_reset
}

# 2024-02-29 12:34:56 UTC. A leap day, so the calendar arithmetic gets exercised
# for free, and fixed so that nothing here depends on the clock.
FIXED_EPOCH=1709210096

# Run statements in a fresh shell. The child is written to a file and run from
# it rather than through `bash -c`, because a `-c` shell has an empty
# BASH_SOURCE, which the coverage hook expands on every command and strict mode
# then turns into a failure that only shows up under scripts/test.sh.
_child() {
  local script="${BATS_TEST_TMPDIR}/child.sh"
  {
    # The whole set, because only `dybatpho::` functions are exported into a
    # child while the internal helpers they call are not. Loading a narrower set
    # would leave an inherited function half defined.
    printf '. "%s/init.sh" --modules all\n' "${DYBATPHO_DIR}"
    printf '%s\n' "$@"
  } > "${script}"
  bash "${script}"
}

# Write a catalog and point the search path at the directory holding it.
_catalog() {
  local name="$1"
  shift
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf '%s\n' "$@" > "${dir}/${name}"
  # shellcheck disable=2030,2031
  export DYBATPHO_I18N_PATH="${dir}"
  printf '%s' "${dir}/${name}"
}

# ---------------------------------------------------------------------------
# locale resolution and normalization
# ---------------------------------------------------------------------------

@test "a POSIX locale tag is normalized to language, script, and region" {
  local out=""
  __dybatpho_i18n_normalize out "en_US.UTF-8"
  assert_equal "${out}" "en_US"
  __dybatpho_i18n_normalize out "pt_BR"
  assert_equal "${out}" "pt_BR"
}

@test "a BCP-47 locale tag is accepted and normalized the same way" {
  local out=""
  __dybatpho_i18n_normalize out "zh-Hant-TW"
  assert_equal "${out}" "zh_Hant_TW"
}

@test "locale normalization fixes the case of each part" {
  local out=""
  __dybatpho_i18n_normalize out "EN-us"
  assert_equal "${out}" "en_US"
}

@test "a locale modifier is kept because it can change the text" {
  local out=""
  __dybatpho_i18n_normalize out "sr@latin"
  assert_equal "${out}" "sr@latin"
}

@test "the codeset is dropped so one catalog serves every encoding" {
  local out=""
  __dybatpho_i18n_normalize out "en_US.UTF-8@euro"
  assert_equal "${out}" "en_US@euro"
}

@test "the C and POSIX locales normalize to the same sentinel" {
  local out=""
  __dybatpho_i18n_normalize out "C"
  assert_equal "${out}" "C"
  __dybatpho_i18n_normalize out "POSIX"
  assert_equal "${out}" "C"
}

@test "a string that is not a locale is rejected" {
  local out=""
  run_traced ! __dybatpho_i18n_normalize out "not a locale!"
}

@test "the locale comes from DYBATPHO_I18N_LOCALE before the environment" {
  DYBATPHO_I18N_LOCALE=de_DE LC_ALL=fr_FR LANG=it_IT run -0 dybatpho::i18n_locale
  assert_output "de_DE"
}

@test "the locale falls back through LC_ALL, LC_MESSAGES, and LANG in order" {
  DYBATPHO_I18N_LOCALE="" LC_ALL=fr_FR LANG=it_IT run -0 dybatpho::i18n_locale
  assert_output "fr_FR"
  DYBATPHO_I18N_LOCALE="" LC_ALL="" LC_MESSAGES=es_ES LANG=it_IT run -0 dybatpho::i18n_locale
  assert_output "es_ES"
  DYBATPHO_I18N_LOCALE="" LC_ALL="" LC_MESSAGES="" LANG=it_IT run -0 dybatpho::i18n_locale
  assert_output "it_IT"
}

@test "setting the locale changes what later calls use" {
  dybatpho::i18n_set_locale vi_VN
  run_traced -0 dybatpho::i18n_locale
  assert_output "vi_VN"
}

@test "setting an invalid locale reports failure and changes nothing" {
  run_traced ! dybatpho::i18n_set_locale "not a locale!"
  run_traced -0 dybatpho::i18n_locale
  assert_output "en"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_chain
# ---------------------------------------------------------------------------

@test "the fallback chain drops the region before the script" {
  run_traced -0 dybatpho::i18n_chain zh_Hant_TW
  assert_line --index 0 "zh_Hant_TW"
  assert_line --index 1 "zh_Hant"
  assert_line --index 2 "zh_TW"
  assert_line --index 3 "zh"
  assert_line --index 4 "en"
}

@test "the fallback chain of a language and region ends at the fallback locale" {
  run_traced -0 dybatpho::i18n_chain pt_BR
  assert_line --index 0 "pt_BR"
  assert_line --index 1 "pt"
  assert_line --index 2 "en"
}

@test "the C locale has an empty chain, so nothing is ever translated" {
  run_traced -0 dybatpho::i18n_chain C
  assert_output ""
}

@test "the configured fallback locale contributes its own language" {
  DYBATPHO_I18N_FALLBACK=pt_BR run -0 dybatpho::i18n_chain de
  assert_line --index 0 "de"
  assert_line --index 1 "pt_BR"
  assert_line --index 2 "pt"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_t
# ---------------------------------------------------------------------------

@test "a message is translated for the active locale" {
  local file
  file="$(_catalog vi.msg 'app.greeting = Xin chào')"
  dybatpho::i18n_load vi_VN "${file}"
  dybatpho::i18n_set_locale vi_VN
  run_traced -0 dybatpho::i18n_t app.greeting
  assert_output "Xin chào"
}

@test "a named placeholder is substituted" {
  local file
  file="$(_catalog en.msg 'app.greeting = Hello, {name}!')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.greeting name=Nam
  assert_output "Hello, Nam!"
}

@test "positional values fill the numbered placeholders" {
  local file
  file="$(_catalog en.msg 'app.pair = {1} and {2}')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.pair alpha beta
  assert_output "alpha and beta"
}

@test "a value containing an ampersand survives substitution" {
  # A replacement is not run through ${var//pattern/replacement}, where bash 5.2
  # would expand a bare & to the text that matched.
  local file
  file="$(_catalog en.msg 'app.what = Order: {what}')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.what "what=fish & chips"
  assert_output "Order: fish & chips"
}

@test "a value containing a backslash or a percent survives substitution" {
  local file
  file="$(_catalog en.msg 'app.what = Value: {what}')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.what 'what=100% C:\path\to'
  assert_output 'Value: 100% C:\path\to'
}

@test "doubled braces produce a literal brace" {
  local file
  file="$(_catalog en.msg 'app.brace = {{literal}} and {name}')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.brace name=x
  assert_output "{literal} and x"
}

@test "an unbound placeholder is left visible rather than being dropped" {
  local file
  file="$(_catalog en.msg 'app.greeting = Hello, {name}!')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.greeting
  assert_output "Hello, {name}!"
}

@test "an untranslated key renders as the key itself and still succeeds" {
  run_traced -0 dybatpho::i18n_t no.such.key
  assert_output "no.such.key"
}

@test "an untranslated key can be marked so it stands out" {
  DYBATPHO_I18N_MISSING_MARK="!!" run -0 dybatpho::i18n_t no.such.key
  assert_output "!!no.such.key!!"
}

@test "strict mode stops the script on an untranslated key" {
  export DYBATPHO_I18N_STRICT=true
  run_traced ! _child 'dybatpho::i18n_t no.such.key' 'echo reached'
  refute_output --partial "reached"
}

@test "a lookup falls back from the region to the language" {
  local file
  file="$(_catalog en.msg 'app.only = base')"
  dybatpho::i18n_load en "${file}"
  dybatpho::i18n_set_locale en_GB
  run_traced -0 dybatpho::i18n_t app.only
  assert_output "base"
}

@test "the C locale returns the key without consulting any catalog" {
  local file
  file="$(_catalog en.msg 'app.greeting = Hello')"
  dybatpho::i18n_load en "${file}"
  dybatpho::i18n_set_locale C
  run_traced -0 dybatpho::i18n_t app.greeting
  assert_output "app.greeting"
}

@test "dybatpho::i18n_has answers without recording a miss" {
  local file
  file="$(_catalog en.msg 'app.here = yes')"
  dybatpho::i18n_load en "${file}"
  dybatpho::i18n_has app.here
  run_traced ! dybatpho::i18n_has app.absent
  # The predicate must leave no trace, or it would pollute the missing report.
  run_traced ! dybatpho::i18n_missing
}

@test "a lookup that missed is reported afterwards" {
  dybatpho::i18n_t no.such.key > /dev/null
  run_traced -0 dybatpho::i18n_missing
  assert_output --partial "no.such.key"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_tc
# ---------------------------------------------------------------------------

@test "a context distinguishes one word used in two senses" {
  local file
  file="$(_catalog en.msg \
    '@context = menu' \
    'open = Open a file' \
    '@context = status' \
    'open = Currently open')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_tc menu open
  assert_output "Open a file"
  run_traced -0 dybatpho::i18n_tc status open
  assert_output "Currently open"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_plural_form
# ---------------------------------------------------------------------------

@test "English has a singular and a plural" {
  assert_equal "$(dybatpho::i18n_plural_form 1 en)" "one"
  assert_equal "$(dybatpho::i18n_plural_form 0 en)" "other"
  assert_equal "$(dybatpho::i18n_plural_form 2 en)" "other"
}

@test "Vietnamese, Japanese, and Chinese have a single form" {
  assert_equal "$(dybatpho::i18n_plural_form 1 vi)" "other"
  assert_equal "$(dybatpho::i18n_plural_form 5 ja)" "other"
  assert_equal "$(dybatpho::i18n_plural_form 1 zh)" "other"
}

@test "French counts zero as singular" {
  assert_equal "$(dybatpho::i18n_plural_form 0 fr)" "one"
  assert_equal "$(dybatpho::i18n_plural_form 1 fr)" "one"
  assert_equal "$(dybatpho::i18n_plural_form 2 fr)" "other"
}

@test "Russian selects by the last digit rather than by the number" {
  assert_equal "$(dybatpho::i18n_plural_form 1 ru)" "one"
  assert_equal "$(dybatpho::i18n_plural_form 2 ru)" "few"
  assert_equal "$(dybatpho::i18n_plural_form 5 ru)" "many"
  assert_equal "$(dybatpho::i18n_plural_form 11 ru)" "many"
  assert_equal "$(dybatpho::i18n_plural_form 21 ru)" "one"
}

@test "Polish differs from Russian at twenty one, which is the usual bug" {
  assert_equal "$(dybatpho::i18n_plural_form 21 pl)" "many"
  assert_equal "$(dybatpho::i18n_plural_form 22 pl)" "few"
  assert_equal "$(dybatpho::i18n_plural_form 1 pl)" "one"
}

@test "Arabic uses all six categories" {
  assert_equal "$(dybatpho::i18n_plural_form 0 ar)" "zero"
  assert_equal "$(dybatpho::i18n_plural_form 1 ar)" "one"
  assert_equal "$(dybatpho::i18n_plural_form 2 ar)" "two"
  assert_equal "$(dybatpho::i18n_plural_form 3 ar)" "few"
  assert_equal "$(dybatpho::i18n_plural_form 11 ar)" "many"
  assert_equal "$(dybatpho::i18n_plural_form 100 ar)" "other"
}

@test "a negative count takes the same form as its absolute value" {
  assert_equal "$(dybatpho::i18n_plural_form -1 en)" "one"
}

@test "an unknown language falls back to the one and other rule" {
  assert_equal "$(dybatpho::i18n_plural_form 1 xx)" "one"
  assert_equal "$(dybatpho::i18n_plural_form 3 xx)" "other"
}

@test "a count that is not an integer is rejected" {
  run ! dybatpho::i18n_plural_form "many" en
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_tn
# ---------------------------------------------------------------------------

@test "a plural message picks the form the count takes" {
  local file
  file="$(_catalog en.msg \
    'app.files[one] = {count} file' \
    'app.files[other] = {count} files')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_tn app.files 1
  assert_output "1 file"
  run_traced -0 dybatpho::i18n_tn app.files 5
  assert_output "5 files"
}

@test "a plural message uses the rules of the language it is written in" {
  local file
  file="$(_catalog ru.msg \
    'app.files[one] = {count} файл' \
    'app.files[few] = {count} файла' \
    'app.files[many] = {count} файлов')"
  dybatpho::i18n_load ru "${file}"
  dybatpho::i18n_set_locale ru
  assert_equal "$(dybatpho::i18n_tn app.files 1)" "1 файл"
  assert_equal "$(dybatpho::i18n_tn app.files 2)" "2 файла"
  assert_equal "$(dybatpho::i18n_tn app.files 5)" "5 файлов"
  assert_equal "$(dybatpho::i18n_tn app.files 21)" "21 файл"
}

@test "a count is grouped for the locale before it is substituted" {
  local file
  file="$(_catalog de.msg 'app.files[other] = {count} Dateien')"
  dybatpho::i18n_load de "${file}"
  dybatpho::i18n_set_locale de
  run_traced -0 dybatpho::i18n_tn app.files 1234567
  assert_output "1.234.567 Dateien"
}

@test "a missing plural category falls back to the other form" {
  local file
  file="$(_catalog en.msg 'app.files[other] = {count} files')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_tn app.files 1
  assert_output "1 files"
}

@test "a plural lookup falls back to a plain translation of the same key" {
  local file
  file="$(_catalog en.msg 'app.files = {count} file(s)')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_tn app.files 3
  assert_output "3 file(s)"
}

@test "a plural count that is not an integer is rejected" {
  run ! dybatpho::i18n_tn app.files "lots"
}

# ---------------------------------------------------------------------------
# native catalog format
# ---------------------------------------------------------------------------

@test "comments, blank lines, and directives are ignored" {
  local file
  file="$(_catalog en.msg \
    '# a comment' \
    '' \
    '@locale = en' \
    'app.key = value')"
  dybatpho::i18n_load en "${file}"
  assert_equal "$(dybatpho::i18n_t app.key)" "value"
}

@test "a double quoted value has its escapes expanded" {
  local file
  file="$(_catalog en.msg 'app.two = "one\ntwo"')"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.two
  assert_line --index 0 "one"
  assert_line --index 1 "two"
}

@test "a single quoted value is taken literally" {
  local file
  file="$(_catalog en.msg "app.raw = 'keep \\n and {name}'")"
  dybatpho::i18n_load en "${file}"
  run_traced -0 dybatpho::i18n_t app.raw
  assert_output 'keep \n and {name}'
}

@test "a quoted key may be a whole sentence" {
  local file
  file="$(_catalog vi.msg '"curl is not installed" = curl chưa được cài đặt')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  run_traced -0 dybatpho::i18n_t "curl is not installed"
  assert_output "curl chưa được cài đặt"
}

@test "a malformed catalog entry stops the caller rather than being skipped" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'this line has no equals sign\n' > "${dir}/en.msg"
  run ! _child "dybatpho::i18n_load en '${dir}/en.msg'" 'echo reached'
  refute_output --partial "reached"
  assert_output --partial "Invalid catalog entry"
}

@test "a catalog without a trailing newline keeps its last entry" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.first = one\napp.last = two' > "${dir}/en.msg"
  dybatpho::i18n_load en "${dir}/en.msg"
  assert_equal "$(dybatpho::i18n_t app.last)" "two"
}

# ---------------------------------------------------------------------------
# gettext catalog format
# ---------------------------------------------------------------------------

@test "a po entry is loaded" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/ru.po" << 'PO'
msgid "app.greeting"
msgstr "Привет"
PO
  dybatpho::i18n_load ru "${dir}/ru.po"
  dybatpho::i18n_set_locale ru
  assert_equal "$(dybatpho::i18n_t app.greeting)" "Привет"
}

@test "a po string continued over several lines is joined" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/en.po" << 'PO'
msgid "a long "
"message id"
msgstr "a long "
"translation"
PO
  dybatpho::i18n_load en "${dir}/en.po"
  assert_equal "$(dybatpho::i18n_t "a long message id")" "a long translation"
}

@test "po plural forms are mapped onto the categories of the language" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/ru.po" << 'PO'
msgid "app.files"
msgid_plural "app.files"
msgstr[0] "{count} файл"
msgstr[1] "{count} файла"
msgstr[2] "{count} файлов"
PO
  dybatpho::i18n_load ru "${dir}/ru.po"
  dybatpho::i18n_set_locale ru
  assert_equal "$(dybatpho::i18n_tn app.files 1)" "1 файл"
  assert_equal "$(dybatpho::i18n_tn app.files 2)" "2 файла"
  assert_equal "$(dybatpho::i18n_tn app.files 5)" "5 файлов"
}

@test "a fuzzy po entry is not treated as a translation" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/en.po" << 'PO'
#, fuzzy
msgid "app.guess"
msgstr "DO NOT USE"
PO
  dybatpho::i18n_load en "${dir}/en.po"
  run_traced -0 dybatpho::i18n_t app.guess
  assert_output "app.guess"
}

@test "an empty po translation means untranslated rather than empty" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/en.po" << 'PO'
msgid "app.blank"
msgstr ""
PO
  dybatpho::i18n_load en "${dir}/en.po"
  run_traced -0 dybatpho::i18n_t app.blank
  assert_output "app.blank"
}

@test "an obsolete po entry is ignored" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/en.po" << 'PO'
#~ msgid "app.gone"
#~ msgstr "OLD"
PO
  dybatpho::i18n_load en "${dir}/en.po"
  run_traced -0 dybatpho::i18n_t app.gone
  assert_output "app.gone"
}

@test "a po context is honored" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/en.po" << 'PO'
msgctxt "menu"
msgid "open"
msgstr "Open a file"
PO
  dybatpho::i18n_load en "${dir}/en.po"
  assert_equal "$(dybatpho::i18n_tc menu open)" "Open a file"
}

@test "a po plural expression in the header is never evaluated" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  cat > "${dir}/en.po" << 'PO'
msgid ""
msgstr ""
"Plural-Forms: nplurals=2; plural=$(touch /tmp/dybatpho-i18n-pwned);\n"

msgid "app.key"
msgstr "value"
PO
  dybatpho::i18n_load en "${dir}/en.po"
  assert_equal "$(dybatpho::i18n_t app.key)" "value"
  refute [ -e /tmp/dybatpho-i18n-pwned ]
}

# ---------------------------------------------------------------------------
# catalog discovery
# ---------------------------------------------------------------------------

@test "a catalog is found in the gettext directory layout" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}/vi_VN/LC_MESSAGES"
  printf 'app.greeting = Xin chào\n' > "${dir}/vi_VN/LC_MESSAGES/messages.msg"
  # shellcheck disable=2030,2031
  export DYBATPHO_I18N_PATH="${dir}"
  dybatpho::i18n_init vi_VN
  assert_equal "$(dybatpho::i18n_t app.greeting)" "Xin chào"
}

@test "a catalog is found in the flat layout" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.greeting = Xin chào\n' > "${dir}/vi_VN.msg"
  # shellcheck disable=2030,2031
  export DYBATPHO_I18N_PATH="${dir}"
  dybatpho::i18n_init vi_VN
  assert_equal "$(dybatpho::i18n_t app.greeting)" "Xin chào"
}

@test "loading the same catalog twice does not read it twice" {
  local file
  file="$(_catalog en.msg 'app.key = first')"
  dybatpho::i18n_load en "${file}"
  printf 'app.key = second\n' > "${file}"
  dybatpho::i18n_load en "${file}"
  # The second load is skipped, so the value from the first one stands.
  assert_equal "$(dybatpho::i18n_t app.key)" "first"
}

@test "loading a catalog that does not exist reports failure" {
  run ! dybatpho::i18n_load en "${BATS_TEST_TMPDIR}/absent.msg"
  assert_output --partial "No such catalog"
}

@test "the locales with a catalog are listed" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'a = 1\n' > "${dir}/vi_VN.msg"
  printf 'a = 1\n' > "${dir}/de.msg"
  # shellcheck disable=2030,2031
  export DYBATPHO_I18N_PATH="${dir}"
  run_traced -0 dybatpho::i18n_locales
  assert_line --index 0 "de"
  assert_line --index 1 "vi_VN"
}

@test "resetting forgets every catalog and the resolved locale" {
  local file
  file="$(_catalog en.msg 'app.key = value')"
  dybatpho::i18n_load en "${file}"
  dybatpho::i18n_reset
  run_traced -0 dybatpho::i18n_t app.key
  assert_output "app.key"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_number
# ---------------------------------------------------------------------------

@test "digits are grouped in threes" {
  assert_equal "$(dybatpho::i18n_number 1234567 0 en)" "1,234,567"
}

@test "a number below the group size is left alone" {
  assert_equal "$(dybatpho::i18n_number 999 0 en)" "999"
  assert_equal "$(dybatpho::i18n_number 1000 0 en)" "1,000"
}

@test "German swaps the group and decimal separators" {
  assert_equal "$(dybatpho::i18n_number 1234567.891 2 de)" "1.234.567,89"
}

@test "French groups with a narrow no-break space" {
  assert_equal "$(dybatpho::i18n_number 1234567 0 fr)" "1 234 567"
}

@test "Indian locales group by lakh rather than by thousand" {
  assert_equal "$(dybatpho::i18n_number 12345678 0 hi)" "1,23,45,678"
  # Bengali proves the secondary group size is read from the table rather than
  # being a special case for one locale.
  assert_equal "$(dybatpho::i18n_number 12345678 0 bn)" "1,23,45,678"
}

@test "rounding goes half up" {
  assert_equal "$(dybatpho::i18n_number 1.005 2 en)" "1.01"
  assert_equal "$(dybatpho::i18n_number 1.994 2 en)" "1.99"
}

@test "rounding carries into the integer part" {
  assert_equal "$(dybatpho::i18n_number 9.99 1 en)" "10.0"
}

@test "rounding carries across a group boundary" {
  assert_equal "$(dybatpho::i18n_number 999.99 1 en)" "1,000.0"
}

@test "a short fraction is padded to the requested precision" {
  assert_equal "$(dybatpho::i18n_number 1.5 3 en)" "1.500"
}

@test "the natural precision is kept when none is given" {
  assert_equal "$(dybatpho::i18n_number 1.25 "" en)" "1.25"
}

@test "a negative number keeps its sign" {
  assert_equal "$(dybatpho::i18n_number -1234.5 2 en)" "-1,234.50"
}

@test "negative zero is not printed" {
  assert_equal "$(dybatpho::i18n_number -0.004 2 en)" "0.00"
}

@test "a bare fraction and a trailing dot are both accepted" {
  assert_equal "$(dybatpho::i18n_number .5 1 en)" "0.5"
  assert_equal "$(dybatpho::i18n_number 5. 0 en)" "5"
}

@test "leading zeros are dropped" {
  assert_equal "$(dybatpho::i18n_number 007 0 en)" "7"
}

@test "an integer wider than the machine word is formatted exactly" {
  # Grouping works on the digit string, so nothing here can overflow.
  assert_equal "$(dybatpho::i18n_number 123456789012345678901234567890 0 en)" \
    "123,456,789,012,345,678,901,234,567,890"
}

@test "a value that is not a number is rejected" {
  run ! dybatpho::i18n_number "twelve" 0 en
}

@test "scientific notation is rejected rather than misread" {
  run ! dybatpho::i18n_number "1e6" 0 en
}

@test "a precision that is not a number is rejected" {
  run ! dybatpho::i18n_number 1.5 "two" en
}

@test "an unknown locale falls back to English without complaining" {
  run_traced --separate-stderr -0 dybatpho::i18n_number 1234.5 2 xx_YY
  assert_output "1,234.50"
  assert_equal "${stderr}" ""
}

@test "number formatting is unaffected by the numeric locale of the shell" {
  # Nothing here goes through printf '%f', which would follow LC_NUMERIC and
  # produce a comma on a German machine. This is the regression that guards it.
  local with_c with_other
  with_c="$(LC_NUMERIC=C dybatpho::i18n_number 1234.567 2 en)"
  with_other="$(LC_NUMERIC=de_DE.UTF-8 dybatpho::i18n_number 1234.567 2 en 2> /dev/null)"
  assert_equal "${with_c}" "1,234.57"
  assert_equal "${with_other}" "1,234.57"
}

@test "the plain form ignores the locale entirely" {
  assert_equal "$(dybatpho::i18n_number_plain 1234567.891 2)" "1234567.89"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_percent
# ---------------------------------------------------------------------------

@test "a percentage follows the sign convention of the locale" {
  assert_equal "$(dybatpho::i18n_percent 42.5 1 en)" "42.5%"
  assert_equal "$(dybatpho::i18n_percent 42.5 1 fr)" "42,5 %"
  # Turkish writes the sign first.
  assert_equal "$(dybatpho::i18n_percent 42.5 1 tr)" "%42,5"
}

@test "a percentage defaults to no fraction digits" {
  assert_equal "$(dybatpho::i18n_percent 42.5 "" en)" "43%"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_currency
# ---------------------------------------------------------------------------

@test "the same amount is written differently in two locales" {
  assert_equal "$(dybatpho::i18n_currency 1234.5 EUR en)" "€1,234.50"
  assert_equal "$(dybatpho::i18n_currency 1234.5 EUR de)" "1.234,50 €"
}

@test "a currency without decimal places shows none" {
  assert_equal "$(dybatpho::i18n_currency 1234.5 JPY en)" "¥1,235"
  assert_equal "$(dybatpho::i18n_currency 1234567 VND vi)" "1.234.567 ₫"
}

@test "a currency with three decimal places shows all of them" {
  assert_equal "$(dybatpho::i18n_currency 1234.5678 BHD en)" ".د.ب1,234.568"
}

@test "a lowercase currency code is accepted" {
  assert_equal "$(dybatpho::i18n_currency 1234.5 usd en)" "\$1,234.50"
}

@test "the minus sign goes outside a leading currency symbol" {
  assert_equal "$(dybatpho::i18n_currency -1234.5 USD en)" "-\$1,234.50"
}

@test "accounting style wraps a negative amount in parentheses" {
  DYBATPHO_I18N_CURRENCY_NEGATIVE=parens run -0 dybatpho::i18n_currency -1234.5 USD en
  assert_output "(\$1,234.50)"
}

@test "an unknown currency warns and uses the code, rather than stopping" {
  run_traced --separate-stderr -0 dybatpho::i18n_currency 1234.5 XPF en
  assert_output "XPF1,234.50"
  assert_regex "${stderr}" "Unknown currency"
}

@test "ASCII mode replaces the symbol with the code" {
  DYBATPHO_I18N_ASCII=true run -0 dybatpho::i18n_currency 1234.5 EUR en
  assert_output "EUR1,234.50"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_bytes
# ---------------------------------------------------------------------------

@test "plain bytes are shown without a fraction" {
  assert_equal "$(dybatpho::i18n_bytes 0 iec en)" "0 B"
  assert_equal "$(dybatpho::i18n_bytes 999 iec en)" "999 B"
}

@test "a size below ten keeps one decimal, and above ten keeps none" {
  assert_equal "$(dybatpho::i18n_bytes 1024 iec en)" "1.0 KiB"
  assert_equal "$(dybatpho::i18n_bytes 48128 iec en)" "47 KiB"
  assert_equal "$(dybatpho::i18n_bytes 1610612736 iec en)" "1.5 GiB"
}

@test "the SI standard divides by a thousand and names the units for it" {
  assert_equal "$(dybatpho::i18n_bytes 1500 si en)" "1.5 kB"
  assert_equal "$(dybatpho::i18n_bytes 1500 iec en)" "1.5 KiB"
}

@test "the default standard comes from the environment" {
  DYBATPHO_I18N_BYTE_STANDARD=si run -0 dybatpho::i18n_bytes 1500 "" en
  assert_output "1.5 kB"
}

@test "the number is localized but the unit symbol is not" {
  assert_equal "$(dybatpho::i18n_bytes 1610612736 iec de)" "1,5 GiB"
}

@test "a size near the machine word limit does not overflow" {
  run_traced -0 dybatpho::i18n_bytes 4611686018427387904 iec en
  assert_output --partial "EiB"
}

@test "a byte count that is negative or not a number is rejected" {
  run ! dybatpho::i18n_bytes -1 iec en
  run ! dybatpho::i18n_bytes "big" iec en
}

@test "an unknown byte standard is rejected" {
  run ! dybatpho::i18n_bytes 1024 "binary" en
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_date and friends
# ---------------------------------------------------------------------------

@test "a date is written the way the locale writes it" {
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" medium en)" "Feb 29, 2024"
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" short en)" "2/29/24"
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" long de)" "29. Februar 2024"
}

@test "the full style includes the weekday" {
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" full en)" \
    "Thursday, February 29, 2024"
}

@test "British dates put the day first" {
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" short en_GB)" "29/02/2024"
}

@test "quoted text in a pattern is literal, so its letters are not fields" {
  # Without literal quoting the `d` in `ngày` would expand to the day number.
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" long vi)" \
    "ngày 29 tháng 2 năm 2024"
}

@test "an explicit pattern is rendered" {
  assert_equal "$(dybatpho::i18n_date_pattern "${FIXED_EPOCH}" "EEEE, d MMMM yyyy" fr)" \
    "jeudi, 29 février 2024"
}

@test "an unsupported pattern field is reported rather than ignored" {
  run_traced ! dybatpho::i18n_date_pattern "${FIXED_EPOCH}" "QQQQ" en
}

@test "a locale on a twelve hour clock shows a day period" {
  assert_equal "$(dybatpho::i18n_time "${FIXED_EPOCH}" short en)" "12:34 PM"
}

@test "a locale on a twenty four hour clock shows neither" {
  assert_equal "$(dybatpho::i18n_time "${FIXED_EPOCH}" short de)" "12:34"
}

@test "midnight is written twelve on a twelve hour clock and zero on a twenty four hour one" {
  local midnight=1709164800
  assert_equal "$(dybatpho::i18n_time "${midnight}" short en)" "12:00 AM"
  assert_equal "$(dybatpho::i18n_time "${midnight}" short de)" "00:00"
}

@test "a date and a time are combined by the pattern of the locale" {
  assert_equal "$(dybatpho::i18n_datetime "${FIXED_EPOCH}" medium en)" \
    "Feb 29, 2024, 12:34:56 PM"
  assert_equal "$(dybatpho::i18n_datetime "${FIXED_EPOCH}" long en)" \
    "February 29, 2024 at 12:34:56 PM"
}

@test "the timezone is taken from the date module's setting" {
  DYBATPHO_DATE_TIMEZONE=Asia/Tokyo run -0 dybatpho::i18n_datetime "${FIXED_EPOCH}" medium en
  assert_output "Feb 29, 2024, 9:34:56 PM"
}

@test "month and weekday names come from the module rather than from the host" {
  # A machine almost never has every locale generated, and `date` answers in
  # English when the one it was asked for is missing. This must not happen here.
  LC_TIME=C run -0 dybatpho::i18n_date "${FIXED_EPOCH}" long de
  assert_output "29. Februar 2024"
  LC_ALL=C run -0 dybatpho::i18n_date "${FIXED_EPOCH}" long de
  assert_output "29. Februar 2024"
}

@test "a timestamp that is not an integer is rejected" {
  run ! dybatpho::i18n_date "yesterday" medium en
}

@test "an unknown date style is rejected" {
  run ! dybatpho::i18n_date "${FIXED_EPOCH}" enormous en
}

@test "month names are available at both widths" {
  assert_equal "$(dybatpho::i18n_month_name 2 wide de)" "Februar"
  assert_equal "$(dybatpho::i18n_month_name 2 abbr en)" "Feb"
}

@test "weekday one is Monday and weekday seven is Sunday" {
  assert_equal "$(dybatpho::i18n_weekday_name 1 wide en)" "Monday"
  assert_equal "$(dybatpho::i18n_weekday_name 7 wide en)" "Sunday"
}

@test "a month or weekday outside its range is rejected" {
  run ! dybatpho::i18n_month_name 13 wide en
  run ! dybatpho::i18n_weekday_name 0 wide en
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_relative
# ---------------------------------------------------------------------------

@test "a moment ago reads as just now" {
  dybatpho::i18n_init en
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 10)) "${FIXED_EPOCH}")" "just now"
}

@test "a span in the past is described in the largest sensible unit" {
  dybatpho::i18n_init en
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 300)) "${FIXED_EPOCH}")" "5 minutes ago"
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 7200)) "${FIXED_EPOCH}")" "2 hours ago"
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 259200)) "${FIXED_EPOCH}")" "3 days ago"
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 1209600)) "${FIXED_EPOCH}")" "2 weeks ago"
}

@test "a single unit is described in the singular" {
  dybatpho::i18n_init en
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 3600)) "${FIXED_EPOCH}")" "1 hour ago"
}

@test "a span in the future is described as such" {
  dybatpho::i18n_init en
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH + 7200)) "${FIXED_EPOCH}")" "in 2 hours"
}

@test "a large relative count is grouped for the locale" {
  dybatpho::i18n_init en
  run_traced -0 dybatpho::i18n_relative $((FIXED_EPOCH - 315360000000)) "${FIXED_EPOCH}"
  assert_output --partial ","
  assert_output --partial "years ago"
}

@test "the reference time can come from the environment" {
  dybatpho::i18n_init en
  DYBATPHO_I18N_NOW="${FIXED_EPOCH}" run -0 dybatpho::i18n_relative $((FIXED_EPOCH - 259200))
  assert_output "3 days ago"
}

@test "a duration is described without a direction" {
  dybatpho::i18n_init en
  assert_equal "$(dybatpho::i18n_duration 259200)" "3 days"
  assert_equal "$(dybatpho::i18n_duration 7200)" "2 hours"
}

@test "a relative time can be translated like any other message" {
  local file
  file="$(_catalog vi.msg \
    'i18n.relative.past.day[other] = {count} ngày trước')"
  dybatpho::i18n_init vi
  dybatpho::i18n_load vi "${file}"
  assert_equal "$(dybatpho::i18n_relative $((FIXED_EPOCH - 259200)) "${FIXED_EPOCH}")" \
    "3 ngày trước"
}

@test "a relative time that is not an integer is rejected" {
  run ! dybatpho::i18n_relative "yesterday" "${FIXED_EPOCH}"
}

# ---------------------------------------------------------------------------
# text direction
# ---------------------------------------------------------------------------

@test "right to left languages are recognized" {
  dybatpho::i18n_is_rtl ar
  dybatpho::i18n_is_rtl he
  dybatpho::i18n_is_rtl fa
  dybatpho::i18n_is_rtl ur
}

@test "the region does not change the direction of a language" {
  dybatpho::i18n_is_rtl ar_EG
}

@test "left to right languages are not reported as right to left" {
  run_traced ! dybatpho::i18n_is_rtl en
  run_traced ! dybatpho::i18n_is_rtl de
  run_traced ! dybatpho::i18n_is_rtl ja
}

@test "the direction predicate prints nothing" {
  run_traced -0 dybatpho::i18n_is_rtl ar
  assert_output ""
}

@test "the direction is also available as text" {
  assert_equal "$(dybatpho::i18n_direction ar)" "rtl"
  assert_equal "$(dybatpho::i18n_direction en)" "ltr"
}

@test "a language can be registered as right to left" {
  run_traced ! dybatpho::i18n_is_rtl xx
  dybatpho::i18n_register_rtl xx
  dybatpho::i18n_is_rtl xx
}

# ---------------------------------------------------------------------------
# bidirectional helpers
# ---------------------------------------------------------------------------

@test "isolating text and stripping it again gives back the original" {
  local wrapped
  wrapped="$(dybatpho::i18n_bidi_isolate "مرحبا")"
  refute [ "${wrapped}" = "مرحبا" ]
  assert_equal "$(dybatpho::i18n_bidi_strip "${wrapped}")" "مرحبا"
}

@test "each isolate direction uses its own opening character" {
  local auto ltr rtl
  auto="$(dybatpho::i18n_bidi_isolate x)"
  ltr="$(dybatpho::i18n_bidi_isolate x ltr)"
  rtl="$(dybatpho::i18n_bidi_isolate x rtl)"
  refute [ "${auto}" = "${ltr}" ]
  refute [ "${ltr}" = "${rtl}" ]
}

@test "a bidirectional mark is a single invisible character" {
  local mark
  mark="$(dybatpho::i18n_bidi_mark rtl)"
  # U+200F, spelled out in octal bytes. `${#mark}` counts characters only in a
  # UTF-8 locale and bytes otherwise, and a `\u` escape is left as written when
  # the locale's charset cannot hold the character, so neither one says
  # anything about the mark under the C locale the suite runs in on CI.
  assert_equal "${mark}" "$(printf '\342\200\217')"
  assert_equal "$(dybatpho::i18n_bidi_strip "a${mark}b")" "ab"
}

@test "stripping also removes the older embedding characters" {
  local embedded
  # U+202B and U+202C, in octal bytes for the same reason as above.
  embedded="$(printf 'a\342\200\253b\342\200\254c')"
  assert_equal "$(dybatpho::i18n_bidi_strip "${embedded}")" "abc"
}

@test "an unknown direction is rejected" {
  run ! dybatpho::i18n_bidi_mark sideways
  run ! dybatpho::i18n_bidi_isolate text sideways
}

# ---------------------------------------------------------------------------
# registering locale data
# ---------------------------------------------------------------------------

@test "a locale's number symbols can be registered" {
  dybatpho::i18n_register_number xx "'" "," 3 "-"
  assert_equal "$(dybatpho::i18n_number 1234567.5 1 xx)" "1'234'567,5"
}

@test "a registered grouping may have a secondary size" {
  dybatpho::i18n_register_number xx "," "." "3;2"
  assert_equal "$(dybatpho::i18n_number 12345678 0 xx)" "1,23,45,678"
}

@test "a malformed grouping is rejected at registration time" {
  run ! dybatpho::i18n_register_number xx "," "." "three"
}

@test "a currency can be registered with its own decimal digits" {
  dybatpho::i18n_register_currency NOK "kr" 2
  assert_equal "$(dybatpho::i18n_currency 1234.5 NOK en)" "kr1,234.50"
}

@test "where a locale puts the currency symbol can be registered" {
  dybatpho::i18n_register_currency_layout xx '# ¤'
  dybatpho::i18n_register_number xx "," "." 3
  assert_equal "$(dybatpho::i18n_currency 1234.5 USD xx)" "1,234.50 \$"
}

@test "a currency layout missing a placeholder is rejected" {
  run ! dybatpho::i18n_register_currency_layout xx 'no placeholders'
}

@test "month and weekday names can be registered" {
  dybatpho::i18n_register_names xx months \
    "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec"
  assert_equal "$(dybatpho::i18n_month_name 3 wide xx)" "Mar"
}

@test "a name list of the wrong length is rejected" {
  run ! dybatpho::i18n_register_names xx months "Jan,Feb,Mar"
  run ! dybatpho::i18n_register_names xx weekdays "Mon,Tue"
  run ! dybatpho::i18n_register_names xx nonsense "a,b"
}

@test "a date pattern can be registered and is then used" {
  dybatpho::i18n_register_names xx months \
    "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec"
  dybatpho::i18n_register_date xx date_long "d. MMMM yyyy"
  assert_equal "$(dybatpho::i18n_date "${FIXED_EPOCH}" long xx)" "29. Feb 2024"
}

@test "an unknown pattern slot is rejected" {
  run ! dybatpho::i18n_register_date xx date_enormous "yyyy"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_extract
# ---------------------------------------------------------------------------

@test "keys are extracted from a source file" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  cat > "${source}" << 'SOURCE'
dybatpho::i18n_t app.greeting name=Nam
dybatpho::i18n_t 'app.quoted'
dybatpho::i18n_t "app.double"
SOURCE
  run_traced -0 dybatpho::i18n_extract --locale en "${source}"
  assert_output --partial "app.greeting ="
  assert_output --partial "app.quoted ="
  assert_output --partial "app.double ="
}

@test "a plural call produces every category of the target language" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  printf 'dybatpho::i18n_tn app.files 5\n' > "${source}"
  run_traced -0 dybatpho::i18n_extract --locale ru "${source}"
  assert_output --partial "app.files[one] ="
  assert_output --partial "app.files[few] ="
  assert_output --partial "app.files[many] ="
  refute_output --partial "app.files[other] ="
}

@test "a key built from a variable is reported rather than guessed at" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  # shellcheck disable=2016 # the key must stay unexpanded in the generated file
  printf 'dybatpho::i18n_t "app.${section}.title"\n' > "${source}"
  run_traced --separate-stderr -1 dybatpho::i18n_extract --locale en "${source}"
  assert_regex "${stderr}" "not a literal"
}

@test "a call belonging to another function is not extracted" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  printf 'my_dybatpho::i18n_t should.not.match\n' > "${source}"
  run_traced -1 dybatpho::i18n_extract --locale en "${source}"
}

@test "a context is preserved in the extracted template" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  printf 'dybatpho::i18n_tc menu open\n' > "${source}"
  run_traced -0 dybatpho::i18n_extract --locale en "${source}"
  assert_output --partial "@context = menu"
  assert_output --partial "open ="
}

@test "the extracted template can be written as a po file" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  printf 'dybatpho::i18n_t app.greeting\n' > "${source}"
  run_traced -0 dybatpho::i18n_extract --format po --locale en "${source}"
  assert_output --partial 'msgid "app.greeting"'
  assert_output --partial 'msgstr ""'
}

@test "an extracted template round-trips back through the loader" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  local out="${BATS_TEST_TMPDIR}/en.msg"
  printf 'dybatpho::i18n_t app.greeting\n' > "${source}"
  dybatpho::i18n_extract --locale en --output "${out}" "${source}"
  assert_file_exist "${out}"
  dybatpho::i18n_load en "${out}"
  run_traced -0 dybatpho::i18n_t app.greeting
  assert_output ""
}

@test "extraction from a directory walks it" {
  local dir="${BATS_TEST_TMPDIR}/src"
  mkdir -p "${dir}/nested"
  printf 'dybatpho::i18n_t app.one\n' > "${dir}/a.sh"
  printf 'dybatpho::i18n_t app.two\n' > "${dir}/nested/b.sh"
  run_traced -0 dybatpho::i18n_extract --locale en "${dir}"
  assert_output --partial "app.one ="
  assert_output --partial "app.two ="
}

@test "extraction with no sources or an unknown option is rejected" {
  run ! dybatpho::i18n_extract --locale en
  run ! dybatpho::i18n_extract --nonsense "${BATS_TEST_TMPDIR}"
}

@test "an unknown extraction format is rejected" {
  local source="${BATS_TEST_TMPDIR}/app.sh"
  printf 'dybatpho::i18n_t app.key\n' > "${source}"
  run ! dybatpho::i18n_extract --format yaml "${source}"
}

# ---------------------------------------------------------------------------
# dybatpho::i18n_lint
# ---------------------------------------------------------------------------

@test "a complete translation reports nothing" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.a = A\napp.b = B\n' > "${dir}/en.msg"
  printf 'app.a = A\napp.b = B\n' > "${dir}/vi_VN.msg"
  dybatpho::i18n_load en "${dir}/en.msg"
  dybatpho::i18n_load vi_VN "${dir}/vi_VN.msg"
  run_traced -0 dybatpho::i18n_lint --reference en vi_VN
  assert_output ""
}

@test "a key the translation lacks is reported as missing" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.a = A\napp.b = B\n' > "${dir}/en.msg"
  printf 'app.a = A\n' > "${dir}/vi_VN.msg"
  dybatpho::i18n_load en "${dir}/en.msg"
  dybatpho::i18n_load vi_VN "${dir}/vi_VN.msg"
  run_traced -1 dybatpho::i18n_lint --reference en vi_VN
  assert_output --partial "missing"
  assert_output --partial "app.b"
}

@test "a translation that dropped a placeholder is reported" {
  # This is the finding worth running in continuous integration: the mistake is
  # invisible until the moment the message is rendered.
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.a = Hello, {name}\n' > "${dir}/en.msg"
  printf 'app.a = Xin chào, {ten}\n' > "${dir}/vi_VN.msg"
  dybatpho::i18n_load en "${dir}/en.msg"
  dybatpho::i18n_load vi_VN "${dir}/vi_VN.msg"
  run_traced -1 dybatpho::i18n_lint --reference en vi_VN
  assert_output --partial "placeholder"
  assert_output --partial "name"
}

@test "lint findings are available as tab separated values" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.a = A\napp.b = B\n' > "${dir}/en.msg"
  printf 'app.a = A\n' > "${dir}/vi_VN.msg"
  dybatpho::i18n_load en "${dir}/en.msg"
  dybatpho::i18n_load vi_VN "${dir}/vi_VN.msg"
  run_traced -1 dybatpho::i18n_lint --format tsv --reference en vi_VN
  assert_output --partial "$(printf 'vi_VN\tmissing\tapp.b')"
}

@test "a key carried only as plural forms is not reported as missing" {
  local dir="${BATS_TEST_TMPDIR}/locale"
  mkdir -p "${dir}"
  printf 'app.files[one] = file\napp.files[other] = files\n' > "${dir}/en.msg"
  printf 'app.files[other] = tệp\n' > "${dir}/vi_VN.msg"
  dybatpho::i18n_load en "${dir}/en.msg"
  dybatpho::i18n_load vi_VN "${dir}/vi_VN.msg"
  run_traced -0 dybatpho::i18n_lint --reference en vi_VN
  assert_output ""
}

@test "an unknown lint option or format is rejected" {
  run ! dybatpho::i18n_lint --nonsense en
  run ! dybatpho::i18n_lint --format yaml en
}

# ---------------------------------------------------------------------------
# translating dybatpho's own diagnostics
# ---------------------------------------------------------------------------

@test "library messages are left in English by default" {
  # The whole existing test suite depends on this staying true.
  run_traced --separate-stderr -0 dybatpho::warn "curl is not installed"
  assert_regex "${stderr}" "curl is not installed"
}

@test "library messages are translated once that is turned on" {
  local file
  file="$(_catalog vi.msg '"curl is not installed" = curl chưa được cài đặt')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run --separate-stderr -0 \
    dybatpho::warn "curl is not installed"
  assert_regex "${stderr}" "curl chưa được cài đặt"
}

@test "a library message with no translation is passed through unchanged" {
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run --separate-stderr -0 \
    dybatpho::warn "some other message"
  assert_regex "${stderr}" "some other message"
}

@test "the message id of a library diagnostic is its English text" {
  run_traced -0 dybatpho::i18n_library_message "untranslated text"
  assert_output "untranslated text"
}

@test "the library hook survives a shell that never sourced the module" {
  # Only `dybatpho::` functions are exported, so a child shell inherits the hook
  # while the module's own variables and internal helpers stay behind. Reading
  # its settings without a default would abort the caller under `set -u`, which
  # is what a bundled copy and any `bash` child of a script both look like.
  local script="${BATS_TEST_TMPDIR}/detached.sh"
  {
    printf 'set -euo pipefail\n'
    printf 'unset DYBATPHO_I18N_TRANSLATE_LIBRARY\n'
    printf 'dybatpho::i18n_library_message "a message"\n'
  } > "${script}"
  run_traced -0 bash "${script}"
  assert_output "a message"
}

# ---------------------------------------------------------------------------
# translating dybatpho's own user interface
# ---------------------------------------------------------------------------

@test "a keyed library string is left in English by default" {
  run_traced -0 dybatpho::i18n_library_text cli.heading_options "Options:"
  assert_output "Options:"
}

@test "a keyed library string is translated once that is turned on" {
  local file
  file="$(_catalog vi.msg 'cli.heading_options = Tùy chọn:')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_text cli.heading_options "Options:"
  assert_output "Tùy chọn:"
}

@test "a keyed library string fills the placeholders the translation uses" {
  local file
  file="$(_catalog vi.msg 'cli.unrecognized_option = Tùy chọn không hợp lệ: {option}')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_text cli.unrecognized_option \
    "Unrecognized option: --colr" "option=--colr"
  assert_output "Tùy chọn không hợp lệ: --colr"
}

@test "an untranslated key keeps the English the call site already built" {
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_text cli.no_such_key "Unrecognized option: --colr" \
    "option=--colr"
  assert_output "Unrecognized option: --colr"
}

@test "a counted library string takes the plural form of the target language" {
  # Vietnamese has one form where English has two, and the English call site
  # has already picked the wrong one for it.
  local file
  file="$(_catalog vi.msg 'cli.args_exact = Cần đúng {count} đối số')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_plural cli.args_exact 1 "Expected exactly 1 argument"
  assert_output "Cần đúng 1 đối số"
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_plural cli.args_exact 5 "Expected exactly 5 arguments"
  assert_output "Cần đúng 5 đối số"
}

@test "a counted library string chooses between the forms a catalog declares" {
  local file
  file="$(_catalog en.msg \
    'cli.args_exact[one] = Expected exactly {count} argument' \
    'cli.args_exact[other] = Expected exactly {count} arguments')"
  dybatpho::i18n_load en "${file}"
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_plural cli.args_exact 1 "fallback"
  assert_output "Expected exactly 1 argument"
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_plural cli.args_exact 3 "fallback"
  assert_output "Expected exactly 3 arguments"
}

@test "a counted library string keeps the English when the count is not a number" {
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 \
    dybatpho::i18n_library_plural cli.args_exact "many" "Expected exactly 2 arguments"
  assert_output "Expected exactly 2 arguments"
}

@test "the keyed hooks survive a shell that never sourced the module" {
  local script="${BATS_TEST_TMPDIR}/detached_keyed.sh"
  {
    printf 'set -euo pipefail\n'
    printf 'unset DYBATPHO_I18N_TRANSLATE_LIBRARY\n'
    printf 'dybatpho::i18n_library_text a.key "in English"\n'
    printf "printf '|'\n"
    printf 'dybatpho::i18n_library_plural a.key 2 "two of them"\n'
  } > "${script}"
  run_traced -0 bash "${script}"
  assert_output "in English|two of them"
}

# ---------------------------------------------------------------------------
# the logging banners, which compose their text before boxing it
# ---------------------------------------------------------------------------

@test "the success banner keeps its English label and message by default" {
  run_traced -0 dybatpho::success "Repository lint passed"
  assert_output --partial "DONE: Repository lint passed"
}

@test "the success banner translates both its label and its message" {
  local file
  file="$(_catalog vi.msg \
    'logging.done = XONG:' \
    '"Repository lint passed" = Kiểm tra kho mã đã qua')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 dybatpho::success "Repository lint passed"
  assert_output --partial "XONG: Kiểm tra kho mã đã qua"
}

@test "the progress and header banners are translated too" {
  local file
  file="$(_catalog vi.msg \
    '"Building the bundle" = Đang dựng gói' \
    '"Release" = Phát hành')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 dybatpho::progress "Building the bundle"
  assert_output --partial "Đang dựng gói"
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 dybatpho::header "Release"
  assert_output --partial "Phát hành"
}

# ---------------------------------------------------------------------------
# the cli help and parser errors
# ---------------------------------------------------------------------------

_i18n_spec() {
  dybatpho::opts::setup "A tool" ARGS action:"true"
  dybatpho::opts::param "Where to" DEST -d --dest
}

@test "generated help is in English by default" {
  run_traced -0 dybatpho::generate_help _i18n_spec
  assert_output --partial "Usage:"
  assert_output --partial "Options:"
  assert_output --partial "[OPTIONS]"
  assert_output --partial "Show this help"
}

@test "generated help renders every heading and placeholder from the catalog" {
  local file
  file="$(_catalog vi.msg \
    'cli.heading_usage = Cách dùng:' \
    'cli.heading_options = Tùy chọn:' \
    'cli.placeholder_options = [TÙY-CHỌN]' \
    'cli.placeholder_args = [ĐỐI-SỐ]...' \
    'cli.show_help = Hiện trợ giúp này')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run -0 dybatpho::generate_help _i18n_spec
  assert_output --partial "Cách dùng:"
  assert_output --partial "[TÙY-CHỌN]"
  assert_output --partial "[ĐỐI-SỐ]..."
  assert_output --partial "Tùy chọn:"
  assert_output --partial "Hiện trợ giúp này"
}

@test "a rejected switch is reported through its key, with the switch filled in" {
  # The English sentence carries the switch, so it cannot be its own message id;
  # this is the case the keyed hook exists for.
  local file
  file="$(_catalog vi.msg 'cli.unrecognized_option = Tùy chọn không hợp lệ: {option}')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run --separate-stderr -1 \
    dybatpho::generate_from_spec _i18n_spec --dst x
  assert_regex "${stderr}" "Tùy chọn không hợp lệ: --dst"
  assert_regex "${stderr}" "--dest"
}

@test "a rejected switch stays in English by default" {
  run --separate-stderr -1 dybatpho::generate_from_spec _i18n_spec --dst x
  assert_regex "${stderr}" "Unrecognized option: --dst"
}

_i18n_spec_pattern() {
  dybatpho::opts::setup "A tool" PAT_I18N_ARGS action:"true"
  dybatpho::opts::param "Mode" PAT_I18N_MODE --mode pattern:'fast|slow'
}

_i18n_spec_abbr() {
  dybatpho::opts::setup "A tool" AMB_I18N_ARGS abbr:true action:"true"
  dybatpho::opts::flag "Colorize" AMB_I18N_COLOR --color
  dybatpho::opts::param "Config" AMB_I18N_CFG --config
}

@test "a value rejected by pattern: names the pattern through its key" {
  # Both the pattern and the offending value are baked into the sentence, so
  # neither the English nor the pattern alone can serve as the message id.
  local file
  file="$(_catalog vi.msg 'cli.pattern_mismatch = Không khớp mẫu ({pattern}): {value}')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run --separate-stderr -1 \
    dybatpho::generate_from_spec _i18n_spec_pattern --mode bogus
  assert_regex "${stderr}" "Không khớp mẫu \(fast\|slow\): bogus"
}

@test "a value rejected by pattern: stays in English by default" {
  run --separate-stderr -1 dybatpho::generate_from_spec _i18n_spec_pattern --mode bogus
  assert_regex "${stderr}" "Does not match the pattern"
}

@test "an ambiguous abbreviation lists its candidates through its key" {
  local file
  file="$(_catalog vi.msg 'cli.ambiguous_option = Nhập nhằng: {option} khớp {candidates}')"
  dybatpho::i18n_load vi "${file}"
  dybatpho::i18n_set_locale vi
  DYBATPHO_I18N_TRANSLATE_LIBRARY=true run --separate-stderr -1 \
    dybatpho::generate_from_spec _i18n_spec_abbr --co
  assert_regex "${stderr}" "Nhập nhằng: --co khớp --color, --config"
}

@test "an ambiguous abbreviation stays in English by default" {
  run --separate-stderr -1 dybatpho::generate_from_spec _i18n_spec_abbr --co
  assert_regex "${stderr}" "Ambiguous option: --co"
}

@test "dybatpho::i18n date and time helpers ask for the date module when it is not loaded" {
  # `i18n` does not load `date`, so a script that only translates messages or
  # formats numbers does not pay for it. A child shell started from a file,
  # without the functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules i18n\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'export DYBATPHO_I18N_LOCALE=en DYBATPHO_DATE_TIMEZONE=UTC DYBATPHO_I18N_NOW=""'
    printf '%s\n' 'dybatpho::i18n_init en'
    printf '%s\n' 'dybatpho::i18n_number 1234.5'
    printf '%s\n' "dybatpho::\${1} ${FIXED_EPOCH} \${2-}"
  } > "${script}"

  local fn
  for fn in i18n_date i18n_time i18n_datetime; do
    run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" "${fn}"
    assert_failure
    assert_line --index 0 "1,234.5"
    assert_output --partial "dybatpho::${fn} needs the date module, load it with: dybatpho::load date"
  done
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" i18n_date_pattern "{yyyy}"
  assert_failure
  assert_output --partial "dybatpho::i18n_date_pattern needs the date module"

  # A relative time against a reference needs no clock, and so no `date`.
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" i18n_relative "$((FIXED_EPOCH + 259200))"
  assert_success
  assert_line --index 1 "3 days ago"
  # Without one it reads the clock, which is the `date` module's job.
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" i18n_relative
  assert_failure
  assert_output --partial "dybatpho::i18n_relative needs the date module"

  # Once the script loads it, the same calls format.
  sed_in_place 's/--modules i18n$/--modules i18n date/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" i18n_date
  assert_success
  assert_line --index 1 "Feb 29, 2024"
}

@test "the formatters that build on dybatpho::i18n_number stop on a value that is not a number" {
  # They used to format the number inside `$(...)`, where the refusal ended
  # only the subshell: `i18n_percent abc` printed a bare `%` and succeeded.
  run --separate-stderr dybatpho::i18n_percent abc 0 en
  assert_failure
  assert_output ""
  assert_stderr --partial "dybatpho::i18n_percent: Not a number: abc"

  run --separate-stderr dybatpho::i18n_currency abc EUR en
  assert_failure
  assert_stderr --partial "dybatpho::i18n_currency: Not a number: abc"

  run --separate-stderr dybatpho::i18n_number 1.5 x en
  assert_failure
  assert_stderr --partial "dybatpho::i18n_number: Precision must be a non-negative integer, got 'x'"
}
