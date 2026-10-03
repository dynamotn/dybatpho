# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it keeps its declarations with the functions they
# describe; it parses its own arguments, so the raw form is what the reader
# sees.
# dyshellint disable=BSG050,BSG011,BSG033,BSG051
# @file i18n.sh
# @brief Utilities for translating messages and formatting values for a locale
# @namespace dybatpho
# @description
#   This module covers the two halves of speaking a user's language. The first
#   is internationalization: message catalogs, a locale fallback chain, named
#   placeholders, and plural forms chosen by the rules of the target language
#   rather than by `count == 1`. The second is localization: numbers, currency,
#   percentages, byte sizes, dates, times, and relative times rendered the way
#   the locale writes them, plus the direction the text reads in.
#
#   Two decisions shape everything else.
#
#   Month names, weekday names, and date patterns come from tables this module
#   owns, never from `LC_TIME`. Asking `date` for a German month name only works
#   when the host has generated the German locale, and when it has not, `date`
#   silently answers in English. A localization library that returns the wrong
#   language rather than an error is worse than useless, so the only thing
#   `date` is asked for is the numeric calendar fields, under `LC_ALL=C`.
#   Those fields, and the clock, come from the `date` module, which this one
#   does not load: a script formatting dates or times loads it too, and the
#   date and time helpers stop with a message naming it when it is missing.
#
#   Fractional values are rendered by manipulating digit strings, never through
#   `printf '%f'`. That conversion follows `LC_NUMERIC`, so on a machine with a
#   German numeric locale it produces `1234,50`, which is precisely the bug this
#   module exists to prevent; it also writes a warning to standard error when
#   the locale is missing. Working on strings avoids both, and has the side
#   benefit of formatting integers wider than 64 bits exactly.
#
#   Catalogs are read from a dependency-free `key = value` format and from GNU
#   gettext `.po` files. Nothing here needs `jq`, `gettext`, `bc`, or `awk`.
# @tip Load `date` as well to format dates and times: `--modules i18n date`
# @see
#   - `example/i18n_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_I18N_LOCALE string Locale to use, overriding the environment
DYBATPHO_I18N_LOCALE="${DYBATPHO_I18N_LOCALE:-}"
# @env DYBATPHO_I18N_FALLBACK string Locale consulted when the active one has no translation, default is `en`
DYBATPHO_I18N_FALLBACK="${DYBATPHO_I18N_FALLBACK:-en}"
# @env DYBATPHO_I18N_PATH string Colon-separated catalog directories, searched before the XDG and system ones
DYBATPHO_I18N_PATH="${DYBATPHO_I18N_PATH:-}"
# @env DYBATPHO_I18N_DOMAIN string Default catalog domain, default is `messages`
DYBATPHO_I18N_DOMAIN="${DYBATPHO_I18N_DOMAIN:-messages}"
# @env DYBATPHO_I18N_STRICT string When true-like, a missing translation or catalog stops the script
DYBATPHO_I18N_STRICT="${DYBATPHO_I18N_STRICT:-false}"
# @env DYBATPHO_I18N_MISSING_MARK string When set, an untranslated key is rendered wrapped in this marker
DYBATPHO_I18N_MISSING_MARK="${DYBATPHO_I18N_MISSING_MARK:-}"
# @env DYBATPHO_I18N_TRANSLATE_LIBRARY string When true-like, dybatpho's own diagnostics are translated too
DYBATPHO_I18N_TRANSLATE_LIBRARY="${DYBATPHO_I18N_TRANSLATE_LIBRARY:-false}"
# @env DYBATPHO_I18N_BYTE_STANDARD string `iec` for 1024-based KiB/MiB, `si` for 1000-based kB/MB, default is `iec`
DYBATPHO_I18N_BYTE_STANDARD="${DYBATPHO_I18N_BYTE_STANDARD:-iec}"
# @env DYBATPHO_I18N_CURRENCY_NEGATIVE string `sign` for `-$1.00` or `parens` for accounting style `($1.00)`
DYBATPHO_I18N_CURRENCY_NEGATIVE="${DYBATPHO_I18N_CURRENCY_NEGATIVE:-sign}"
# @env DYBATPHO_I18N_ASCII string When true-like, prefer ASCII over currency symbols and exotic spaces
DYBATPHO_I18N_ASCII="${DYBATPHO_I18N_ASCII:-false}"
# @env DYBATPHO_I18N_NOW number Epoch seconds used as "now" by relative time, for reproducible output
DYBATPHO_I18N_NOW="${DYBATPHO_I18N_NOW:-}"

# Catalog storage. Every message key is `<locale><US><key>` and every plural
# form `<locale><US><key><US><category>`, joined with the ASCII unit separator.
# That byte cannot appear in a locale or a domain, and it is rejected in a key,
# so one flat map per kind gives an O(1) lookup with no nesting and no
# name-mangled per-locale arrays. These describe the current shell only and are
# deliberately never exported: a child shell reloads its own catalogs.
declare -gA __dybatpho_i18n_msg=()
declare -gA __dybatpho_i18n_plural=()
declare -gA __dybatpho_i18n_files=()
declare -gA __dybatpho_i18n_missing=()
declare -gA __dybatpho_i18n_state=()

# Not `readonly`: the module has to survive being sourced twice in one shell,
# which is what `test/test_helper.bash` does across a bats file.
__DYBATPHO_I18N_US=$'\x1f'
# Returned by a lookup that found nothing. A translation may legitimately be the
# empty string, so "absent" needs a value that no catalog can produce, and the
# record separator cannot survive the key validation on the way in.
__DYBATPHO_I18N_NONE=$'\x1e\x1e'
# gettext's own separator between a context and its message id.
__DYBATPHO_I18N_CTX=$'\x04'

#######################################
# @description Forget every loaded catalog, the resolved locale, and the
#   recorded misses. Loading is tracked per shell, so a script that changes
#   `DYBATPHO_I18N_PATH` at run time calls this before loading again.
# @noargs
#######################################
function dybatpho::i18n_reset {
  __dybatpho_i18n_msg=()
  __dybatpho_i18n_plural=()
  __dybatpho_i18n_files=()
  __dybatpho_i18n_missing=()
  __dybatpho_i18n_state=()
}

#######################################
# @description Split a locale tag into its parts and build the canonical form.
#   Accepts the POSIX spelling `pt_BR.UTF-8@euro` and the BCP-47 spelling
#   `zh-Hant-TW`, and normalizes both to `lang[_Script][_REGION][@modifier]`.
# @arg $1 string Name of the variable that receives the canonical tag
# @arg $2 string Raw locale tag
# @set The named variable
# @exitcode 1 The tag is not a locale
# @internal
#######################################
function __dybatpho_i18n_normalize {
  local __norm_target raw
  __norm_target="$1"
  raw="${2-}"
  local -n __norm_out="${__norm_target}"
  __norm_out=""
  [[ -n "${raw}" ]] || return 1
  # `POSIX` matches the language branch of the regex below, so the C locale has
  # to be recognized before it runs rather than after.
  case "${raw}" in
    C | POSIX | C.* | POSIX.*)
      __norm_out="C"
      return 0
      ;;
    *) ;;
  esac
  local language script region modifier
  if [[ "${raw}" =~ ^([a-zA-Z]{2,8})([_-]([a-zA-Z]{4}))?([_-]([a-zA-Z]{2}|[0-9]{3}))?(\.([^@]+))?(@(.+))?$ ]]; then
    language="${BASH_REMATCH[1],,}"
    script="${BASH_REMATCH[3]-}"
    region="${BASH_REMATCH[5]-}"
    modifier="${BASH_REMATCH[9]-}"
  else
    return 1
  fi
  if [[ -n "${script}" ]]; then
    script="${script,,}"
    script="${script^}"
  fi
  region="${region^^}"
  modifier="${modifier,,}"
  __norm_out="${language}"
  [[ -n "${script}" ]] && __norm_out+="_${script}"
  [[ -n "${region}" ]] && __norm_out+="_${region}"
  [[ -n "${modifier}" ]] && __norm_out+="@${modifier}"
  return 0
}

#######################################
# @description Print the language subtag of a locale.
# @arg $1 string Locale tag
# @stdout Language subtag, lowercased
# @internal
#######################################
function __dybatpho_i18n_language {
  local tag="${1-}"
  tag="${tag%%@*}"
  printf '%s' "${tag%%[_-]*}"
}

#######################################
# @description Resolve the locale the runtime should use, honoring an explicit
#   override first and then the POSIX environment variables in the order the
#   specification gives them.
# @arg $1 string Name of the variable that receives the locale
# @set The named variable
# @internal
#######################################
function __dybatpho_i18n_resolve {
  local __resolve_target
  __resolve_target="$1"
  local -n __resolve_out="${__resolve_target}"
  local raw candidate
  for raw in "${DYBATPHO_I18N_LOCALE-}" "${LC_ALL-}" "${LC_MESSAGES-}" "${LANG-}"; do
    [[ -n "${raw}" ]] || continue
    if __dybatpho_i18n_normalize candidate "${raw}"; then
      __resolve_out="${candidate}"
      return 0
    fi
  done
  # `LANGUAGE` holds a priority list rather than a single locale, and GNU only
  # honors it when the POSIX chain selected something other than C. Taking its
  # first entry as a last resort is honest about how much of that we implement.
  if [[ -n "${LANGUAGE-}" ]]; then
    raw="${LANGUAGE%%:*}"
    if [[ -n "${raw}" ]] && __dybatpho_i18n_normalize candidate "${raw}"; then
      __resolve_out="${candidate}"
      return 0
    fi
  fi
  __dybatpho_i18n_normalize __resolve_out "${DYBATPHO_I18N_FALLBACK}" || __resolve_out="en"
  return 0
}

#######################################
# @description Print the locale currently in effect, resolving it on first use.
# @noargs
# @stdout Canonical locale tag
#######################################
function dybatpho::i18n_locale {
  if [[ -z "${__dybatpho_i18n_state[locale]-}" ]]; then
    local resolved
    __dybatpho_i18n_resolve resolved
    __dybatpho_i18n_state[locale]="${resolved}"
  fi
  printf '%s\n' "${__dybatpho_i18n_state[locale]}"
}

#######################################
# @description Use a locale for every later translation and formatting call.
# @example
#   dybatpho::i18n_set_locale vi_VN
#
# @arg $1 string Locale tag
# @set DYBATPHO_I18N_LOCALE is not touched; the resolved locale is stored internally
# @exitcode 1 The tag is not a locale
#######################################
function dybatpho::i18n_set_locale {
  local tag
  dybatpho::expect_args tag -- "$@"
  local canonical
  __dybatpho_i18n_normalize canonical "${tag}" \
    || {
      dybatpho::error "${FUNCNAME[0]}: Not a locale: ${tag}"
      return 1
    }
  __dybatpho_i18n_state[locale]="${canonical}"
  # The chain is memoized per locale, so switching locales invalidates nothing
  # except the answer to "which chain is current".
  return 0
}

#######################################
# @description Print the fallback chain a lookup walks for a locale, most
#   specific first. A catalog that translates three keys for `zh_Hant_TW` and
#   the rest for `zh` needs no duplication because of this chain.
# @example
#   dybatpho::i18n_chain zh_Hant_TW
#
# @arg $1 string Optional locale tag, default is the active locale
# @stdout One locale tag per line
#######################################
function dybatpho::i18n_chain {
  local locale="${1-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local cached="${__dybatpho_i18n_state["chain:${locale}"]-}"
  if [[ -n "${cached}" ]]; then
    printf '%s' "${cached}"
    return 0
  fi
  local -a chain=()
  local -A seen=()
  local bare="${locale%%@*}"
  local language script region rest
  language="$(__dybatpho_i18n_language "${locale}")"
  rest="${bare#"${language}"}"
  rest="${rest#_}"
  script=""
  region=""
  if [[ "${rest}" =~ ^([A-Z][a-z]{3})(_([A-Za-z0-9]+))?$ ]]; then
    script="${BASH_REMATCH[1]}"
    region="${BASH_REMATCH[3]-}"
  elif [[ -n "${rest}" ]]; then
    region="${rest}"
  fi

  local candidate
  for candidate in \
    "${locale}" \
    "${bare}" \
    "${script:+${language}_${script}}" \
    "${region:+${language}_${region}}" \
    "${language}"; do
    [[ -n "${candidate}" ]] || continue
    [[ -n "${seen[${candidate}]-}" ]] && continue
    seen["${candidate}"]=1
    chain+=("${candidate}")
  done

  if [[ "${locale}" != "C" ]]; then
    local fallback
    if __dybatpho_i18n_normalize fallback "${DYBATPHO_I18N_FALLBACK}"; then
      for candidate in "${fallback}" "$(__dybatpho_i18n_language "${fallback}")"; do
        [[ -n "${candidate}" ]] || continue
        [[ -n "${seen[${candidate}]-}" ]] && continue
        seen["${candidate}"]=1
        chain+=("${candidate}")
      done
    fi
  else
    # The C locale is a request for untranslated output, not a language.
    chain=()
  fi

  local joined=""
  for candidate in ${chain[@]+"${chain[@]}"}; do
    joined+="${candidate}"$'\n'
  done
  __dybatpho_i18n_state["chain:${locale}"]="${joined}"
  printf '%s' "${joined}"
}

#######################################
# @description Fail unless a message key can be stored and looked up safely.
#   The key becomes part of a composite associative-array subscript, so the one
#   byte that has to be excluded is the separator joining it. Everything else is
#   allowed on purpose: a gettext catalog uses whole English sentences as message
#   ids, and rejecting punctuation would make those unusable.
# @arg $1 string Message key
# @exitcode 1 The key is empty or contains the separator
# @internal
#######################################
function __dybatpho_i18n_check_key {
  local key="${1-}"
  if [[ -z "${key}" ]]; then
    dybatpho::error "${FUNCNAME[1]}: Message key must not be empty"
    return 1
  fi
  if [[ "${key}" == *"${__DYBATPHO_I18N_US}"* ]]; then
    dybatpho::error "${FUNCNAME[1]}: Message key must not contain a unit separator"
    return 1
  fi
  return 0
}

#######################################
# @description Record one translation.
# @arg $1 string Locale tag
# @arg $2 string Message key
# @arg $3 string Translation
# @arg $4 string Optional plural category
# @set __dybatpho_i18n_msg __dybatpho_i18n_plural
# @exitcode 1 The key is not storable
# @internal
#######################################
function __dybatpho_i18n_store {
  local locale key value category
  locale="$1"
  key="$2"
  value="$3"
  category="${4-}"
  __dybatpho_i18n_check_key "${key}" || return 1
  if [[ -n "${category}" ]]; then
    __dybatpho_i18n_plural["${locale}${__DYBATPHO_I18N_US}${key}${__DYBATPHO_I18N_US}${category}"]="${value}"
  else
    __dybatpho_i18n_msg["${locale}${__DYBATPHO_I18N_US}${key}"]="${value}"
  fi
  return 0
}

#######################################
# @description Look a key up along the fallback chain of the active locale.
# @arg $1 string Name of the variable that receives the translation
# @arg $2 string Message key
# @arg $3 string Optional count; when given, plural forms are consulted first
# @set The named variable
# @exitcode 1 No locale in the chain carries the key
# @internal
#######################################
function __dybatpho_i18n_lookup {
  local __lookup_target key count
  __lookup_target="$1"
  key="$2"
  count="${3-}"
  local -n __lookup_out="${__lookup_target}"
  __lookup_out=""
  local locale chain hit category language
  chain="$(dybatpho::i18n_chain)"
  while IFS= read -r locale; do
    [[ -n "${locale}" ]] || continue
    if [[ -n "${count}" ]]; then
      # The plural rule follows the language of the catalog being consulted,
      # not the one that was asked for. Falling back from Russian to English has
      # to switch rules too, or a Russian `few` would be looked for in an
      # English catalog that has no such category.
      language="$(__dybatpho_i18n_language "${locale}")"
      category="$(__dybatpho_i18n_plural_category "${language}" "${count}")"
      local plural_key="${locale}${__DYBATPHO_I18N_US}${key}${__DYBATPHO_I18N_US}${category}"
      hit="${__dybatpho_i18n_plural[${plural_key}]-${__DYBATPHO_I18N_NONE}}"
      if [[ "${hit}" != "${__DYBATPHO_I18N_NONE}" ]]; then
        __lookup_out="${hit}"
        return 0
      fi
      # Every language has `other`, so it is the one category a catalog can be
      # relied on to carry when it omits the one this count selected.
      local other_key="${locale}${__DYBATPHO_I18N_US}${key}${__DYBATPHO_I18N_US}other"
      hit="${__dybatpho_i18n_plural[${other_key}]-${__DYBATPHO_I18N_NONE}}"
      if [[ "${hit}" != "${__DYBATPHO_I18N_NONE}" ]]; then
        __lookup_out="${hit}"
        return 0
      fi
    fi
    hit="${__dybatpho_i18n_msg[${locale}${__DYBATPHO_I18N_US}${key}]-${__DYBATPHO_I18N_NONE}}"
    if [[ "${hit}" != "${__DYBATPHO_I18N_NONE}" ]]; then
      __lookup_out="${hit}"
      return 0
    fi
  done <<< "${chain}"
  return 1
}

#######################################
# @description Substitute `{name}` placeholders in a template.
#   The scan splits the template on each brace and concatenates rather than
#   using `${variable//pattern/replacement}`. Bash 5.2 enabled
#   `patsub_replacement`, which makes an unescaped `&` in the replacement expand
#   to the text that matched, while the backslash escape that fixes it is taken
#   literally on 5.1 and earlier. Translations are data and routinely contain
#   `&`, so neither form is correct across the versions this library supports.
#   Concatenation has neither behavior anywhere.
# @arg $1 string Name of the variable that receives the rendered text
# @arg $2 string Template
# @arg $@ string `name=value` bindings, or bare values bound to `{1}`, `{2}`, ...
# @set The named variable
# @internal
#######################################
function __dybatpho_i18n_interpolate {
  local __interp_target __interp_template
  __interp_target="$1"
  __interp_template="$2"
  shift 2
  local -n __interp_out="${__interp_target}"
  local -A __interp_bind=()
  local __interp_arg __interp_pos=0
  for __interp_arg in "$@"; do
    if [[ "${__interp_arg}" == *=* ]] \
      && [[ "${__interp_arg%%=*}" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
      __interp_bind["${__interp_arg%%=*}"]="${__interp_arg#*=}"
    else
      __interp_pos=$((__interp_pos + 1))
      __interp_bind["${__interp_pos}"]="${__interp_arg}"
    fi
  done

  local result="" rest="${__interp_template}" head name
  while [[ "${rest}" == *'{'* ]]; do
    head="${rest%%\{*}"
    rest="${rest#*\{}"
    # Only literal template text is rewritten here, never a bound value, so the
    # replacement is a constant and nothing can be smuggled in through it.
    result+="${head//\}\}/\}}"
    if [[ "${rest}" == '{'* ]]; then
      result+='{'
      rest="${rest#\{}"
      continue
    fi
    if [[ "${rest}" != *'}'* ]]; then
      result+='{'
      break
    fi
    name="${rest%%\}*}"
    if [[ ! "${name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      result+='{'
      continue
    fi
    rest="${rest#*\}}"
    if [[ -n "${__interp_bind[${name}]+set}" ]]; then
      result+="${__interp_bind[${name}]}"
    else
      # A template shared across locales legitimately omits a placeholder that
      # only some of them use, so an unbound name stays visible instead of
      # being treated as an error.
      dybatpho::debug "Unbound placeholder '{${name}}'"
      result+="{${name}}"
    fi
  done
  result+="${rest//\}\}/\}}"
  __interp_out="${result}"
}

# CLDR cardinal plural rule families, keyed by language subtag. A language that
# is not listed uses the `one` family, which is right for most languages and
# wrong in a way that is visible rather than silent. Only integer counts are
# supported, which collapses the rules that distinguish fractional forms.
declare -gA __dybatpho_i18n_plural_family=(
  [ja]=other [ko]=other [zh]=other [th]=other [vi]=other [id]=other [ms]=other
  [my]=other [km]=other [lo]=other [bo]=other [yo]=other [ig]=other [jv]=other
  [su]=other [to]=other [wo]=other [yue]=other [ii]=other [kde]=other
  [en]=one [de]=one [nl]=one [sv]=one [da]=one [no]=one [nb]=one [nn]=one
  [fi]=one [et]=one [el]=one [es]=one [it]=one [bg]=one [ca]=one [eu]=one
  [gl]=one [hu]=one [tr]=one [az]=one [kk]=one [ky]=one [uz]=one [sq]=one
  [sw]=one [af]=one [zu]=one [ta]=one [te]=one [kn]=one [ml]=one [mr]=one
  [pa]=one [gu]=one [ur]=one [ne]=one [si]=one [ka]=one [hy]=one [eo]=one
  [ast]=one [nso]=one
  [pt]=pt [fr]=fr [hi]=hi [fa]=hi [bn]=hi [am]=hi [as]=hi
  [ru]=ru [uk]=ru [be]=ru [sr]=ru [hr]=ru [bs]=ru [sh]=ru
  [pl]=pl [cs]=cs [sk]=cs
  [ar]=ar [he]=he [iw]=he [lt]=lt [lv]=lv [ro]=ro [mo]=ro [sl]=sl
  [is]=is [mk]=mk [fil]=fil [tl]=fil [cy]=cy [mt]=mt [ga]=ga [gd]=gd
)

#######################################
# @description Print `other` for a language with a single cardinal form.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_other {
  printf 'other'
}

#######################################
# @description Print the plural category for a one-versus-other language.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_one {
  if (($1 == 1)); then printf 'one'; else printf 'other'; fi
}

#######################################
# @description Print the plural category for French, which counts zero as singular.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_fr {
  if (($1 == 0 || $1 == 1)); then printf 'one'; else printf 'other'; fi
}

#######################################
# @description Print the plural category for Portuguese, which counts zero as singular.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_pt {
  if (($1 == 0 || $1 == 1)); then printf 'one'; else printf 'other'; fi
}

#######################################
# @description Print the plural category for Hindi and its relatives, which
#   count zero as singular.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_hi {
  if (($1 == 0 || $1 == 1)); then printf 'one'; else printf 'other'; fi
}

#######################################
# @description Print the plural category for Russian and the other East Slavic
#   languages. The singular test is on the last digit, not on the whole number,
#   which is what separates this rule from the Polish one below.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_ru {
  local last=$(($1 % 10)) pair=$(($1 % 100))
  if ((last == 1 && pair != 11)); then
    printf 'one'
  elif ((last >= 2 && last <= 4 && (pair < 12 || pair > 14))); then
    printf 'few'
  else
    printf 'many'
  fi
}

#######################################
# @description Print the plural category for Polish, whose singular is the
#   number one itself rather than anything ending in one.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_pl {
  local last=$(($1 % 10)) pair=$(($1 % 100))
  if (($1 == 1)); then
    printf 'one'
  elif ((last >= 2 && last <= 4 && (pair < 12 || pair > 14))); then
    printf 'few'
  else
    printf 'many'
  fi
}

#######################################
# @description Print the plural category for Czech and Slovak. Their `many`
#   category applies only to fractions, which integer counts never produce.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_cs {
  if (($1 == 1)); then
    printf 'one'
  elif (($1 >= 2 && $1 <= 4)); then
    printf 'few'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Arabic, the one language that uses
#   all six.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_ar {
  local pair=$(($1 % 100))
  if (($1 == 0)); then
    printf 'zero'
  elif (($1 == 1)); then
    printf 'one'
  elif (($1 == 2)); then
    printf 'two'
  elif ((pair >= 3 && pair <= 10)); then
    printf 'few'
  elif ((pair >= 11 && pair <= 99)); then
    printf 'many'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Hebrew, which has a dual form.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_he {
  if (($1 == 1)); then
    printf 'one'
  elif (($1 == 2)); then
    printf 'two'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Lithuanian.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_lt {
  local last=$(($1 % 10)) pair=$(($1 % 100))
  if ((last == 1 && (pair < 11 || pair > 19))); then
    printf 'one'
  elif ((last >= 2 && last <= 9 && (pair < 11 || pair > 19))); then
    printf 'few'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Latvian, which has a zero form.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_lv {
  local last=$(($1 % 10)) pair=$(($1 % 100))
  if ((last == 0 || (pair >= 11 && pair <= 19))); then
    printf 'zero'
  elif ((last == 1 && pair != 11)); then
    printf 'one'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Romanian.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_ro {
  local pair=$(($1 % 100))
  if (($1 == 1)); then
    printf 'one'
  elif (($1 == 0 || (pair >= 1 && pair <= 19))); then
    printf 'few'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Slovenian, which has a dual form.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_sl {
  local pair=$(($1 % 100))
  if ((pair == 1)); then
    printf 'one'
  elif ((pair == 2)); then
    printf 'two'
  elif ((pair == 3 || pair == 4)); then
    printf 'few'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Icelandic.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_is {
  local last=$(($1 % 10)) pair=$(($1 % 100))
  if ((last == 1 && pair != 11)); then printf 'one'; else printf 'other'; fi
}

#######################################
# @description Print the plural category for Macedonian.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_mk {
  local last=$(($1 % 10)) pair=$(($1 % 100))
  if ((last == 1 && pair != 11)); then printf 'one'; else printf 'other'; fi
}

#######################################
# @description Print the plural category for Filipino and Tagalog.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_fil {
  local last=$(($1 % 10))
  if (($1 == 1 || $1 == 2 || $1 == 3)); then
    printf 'one'
  elif ((last != 4 && last != 6 && last != 9)); then
    printf 'one'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Welsh, which uses all six.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_cy {
  case "$1" in
    0) printf 'zero' ;;
    1) printf 'one' ;;
    2) printf 'two' ;;
    3) printf 'few' ;;
    6) printf 'many' ;;
    *) printf 'other' ;;
  esac
}

#######################################
# @description Print the plural category for Maltese.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_mt {
  local pair=$(($1 % 100))
  if (($1 == 1)); then
    printf 'one'
  elif (($1 == 0 || (pair >= 2 && pair <= 10))); then
    printf 'few'
  elif ((pair >= 11 && pair <= 19)); then
    printf 'many'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Irish.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_ga {
  if (($1 == 1)); then
    printf 'one'
  elif (($1 == 2)); then
    printf 'two'
  elif (($1 >= 3 && $1 <= 6)); then
    printf 'few'
  elif (($1 >= 7 && $1 <= 10)); then
    printf 'many'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the plural category for Scottish Gaelic.
# @arg $1 number Count
# @stdout Plural category
# @internal
#######################################
function __dybatpho_i18n_plural_gd {
  if (($1 == 1 || $1 == 11)); then
    printf 'one'
  elif (($1 == 2 || $1 == 12)); then
    printf 'two'
  elif (($1 >= 3 && $1 <= 19)); then
    printf 'few'
  else
    printf 'other'
  fi
}

#######################################
# @description Print the CLDR plural category a count takes in a language.
# @example
#   dybatpho::i18n_plural_form 5 ru   # many
#
# @arg $1 number Count, which may be negative
# @arg $2 string Optional locale or language, default is the active locale
# @stdout One of `zero`, `one`, `two`, `few`, `many`, `other`
# @exitcode 1 The count is not an integer
#######################################
function dybatpho::i18n_plural_form {
  local count
  dybatpho::expect_args count -- "$@"
  local locale="${2-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local i18n_language
  i18n_language=$(__dybatpho_i18n_language "${locale}")
  __dybatpho_i18n_plural_category "${i18n_language}" "${count}"
}

#######################################
# @description Print the CLDR plural category for a count in a language.
# @arg $1 string Language subtag
# @arg $2 number Count
# @stdout One of `zero`, `one`, `two`, `few`, `many`, `other`
# @internal
#######################################
function __dybatpho_i18n_plural_category {
  local language count
  dybatpho::expect_args language count -- "$@"
  [[ "${count}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Count must be an integer, got '${count}'"
  # Every CLDR rule is defined on the absolute value: minus one takes the same
  # form as one in every language the tables cover.
  ((count < 0)) && count=$((-count))
  local family="${__dybatpho_i18n_plural_family[${language}]-one}"
  # The family name comes from a table this module owns, but the indirect call
  # is guarded anyway so that a typo in the table fails loudly rather than
  # running whatever else happens to carry that name.
  dybatpho::is function "__dybatpho_i18n_plural_${family}" \
    || dybatpho::die "${FUNCNAME[0]}: No plural rule for family '${family}'"
  "__dybatpho_i18n_plural_${family}" "${count}"
}

#######################################
# @description Record an untranslated key, and stop the script when strict mode
#   asked for that. Recording is best effort: `dybatpho::i18n_t` is normally
#   called inside a command substitution, which is a subshell, so a miss seen
#   there cannot reach the parent. `dybatpho::i18n_lint` is the reliable way to
#   find untranslated keys.
# @arg $1 string Message key
# @arg $2 string Locale the lookup started from
# @set __dybatpho_i18n_missing
# @exitcode 1 Always, so the caller can render the fallback
# @internal
#######################################
function __dybatpho_i18n_miss {
  local key locale
  key="$1"
  locale="$2"
  local slot="${locale}${__DYBATPHO_I18N_US}${key}"
  __dybatpho_i18n_missing["${slot}"]=$((${__dybatpho_i18n_missing[${slot}]-0} + 1))
  if dybatpho::is true "${DYBATPHO_I18N_STRICT}"; then
    dybatpho::die "No translation for '${key}' in locale '${locale}'"
  fi
  dybatpho::debug "No translation for '${key}' in locale '${locale}'"
  return 1
}

#######################################
# @description Render the text shown when a key has no translation.
# @arg $1 string Message key
# @stdout The key, wrapped in the missing marker when one is configured
# @internal
#######################################
function __dybatpho_i18n_fallback_text {
  local key="$1"
  if [[ -n "${DYBATPHO_I18N_MISSING_MARK}" ]]; then
    printf '%s%s%s' "${DYBATPHO_I18N_MISSING_MARK}" "${key}" "${DYBATPHO_I18N_MISSING_MARK}"
  else
    printf '%s' "${key}"
  fi
}

#######################################
# @description Translate a message and fill in its placeholders.
#   An argument shaped like `name=value` binds `{name}`; any other argument is
#   bound to the next position, so `{1}` is the first of them.
# @example
#   dybatpho::i18n_load vi_VN "${PWD}/locale/vi.msg"
#   dybatpho::i18n_set_locale vi_VN
#   printf '%s\n' "$(dybatpho::i18n_t app.greeting name=Nam)"
#
# @arg $1 string Message key
# @arg $@ string `name=value` bindings, or bare positional values
# @stdout The translation, with no trailing newline
# @exitcode 0 Always in the default lenient mode, including for a missing key
# @exitcode 1 Strict mode is off but the key was missing and the caller asked
# @tip Call `dybatpho::i18n_init` or `dybatpho::i18n_load` in the parent shell.
#   This function is almost always used inside `$( )`, which is a subshell, so a
#   catalog loaded from within it is discarded as soon as it returns
#######################################
function dybatpho::i18n_t {
  local key
  dybatpho::expect_args key -- "$@"
  shift
  local locale template rendered
  locale="$(dybatpho::i18n_locale)"
  if __dybatpho_i18n_lookup template "${key}"; then
    __dybatpho_i18n_interpolate rendered "${template}" "$@"
    printf '%s' "${rendered}"
    return 0
  fi
  # The C locale is a request for untranslated output rather than a failure, so
  # it is not recorded as a miss and never stops a strict run.
  if [[ "${locale}" != "C" ]]; then
    __dybatpho_i18n_miss "${key}" "${locale}" || true
  fi
  local i18n_fallback_text
  i18n_fallback_text=$(__dybatpho_i18n_fallback_text "${key}")
  __dybatpho_i18n_interpolate rendered "${i18n_fallback_text}" "$@"
  printf '%s' "${rendered}"
  return 0
}

#######################################
# @description Translate a message, choosing the plural form the count takes in
#   the target language. The count is bound to `{count}` and `{n}` on top of any
#   bindings given, and is grouped for the locale before being substituted.
# @example
#   printf '%s\n' "$(dybatpho::i18n_tn app.files 5)"
#
# @arg $1 string Message key
# @arg $2 number Count
# @arg $@ string Further `name=value` bindings, or bare positional values
# @stdout The translation, with no trailing newline
# @exitcode 0 Always in the default lenient mode
#######################################
function dybatpho::i18n_tn {
  local key count
  dybatpho::expect_args key count -- "$@"
  shift 2
  [[ "${count}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Count must be an integer, got '${count}'"
  local locale template rendered grouped
  locale="$(dybatpho::i18n_locale)"
  grouped="$(dybatpho::i18n_number "${count}" 0 "${locale}")"
  if __dybatpho_i18n_lookup template "${key}" "${count}"; then
    __dybatpho_i18n_interpolate rendered "${template}" \
      "count=${grouped}" "n=${grouped}" "$@"
    printf '%s' "${rendered}"
    return 0
  fi
  if [[ "${locale}" != "C" ]]; then
    __dybatpho_i18n_miss "${key}" "${locale}" || true
  fi
  __dybatpho_i18n_interpolate rendered "$(__dybatpho_i18n_fallback_text "${key}")" \
    "count=${grouped}" "n=${grouped}" "$@"
  printf '%s' "${rendered}"
  return 0
}

#######################################
# @description Translate a message that is qualified by a context, so that one
#   English word with two meanings can be translated two ways.
# @example
#   dybatpho::i18n_tc menu open        # the verb
#   dybatpho::i18n_tc status open      # the adjective
#
# @arg $1 string Context
# @arg $2 string Message key
# @arg $@ string `name=value` bindings, or bare positional values
# @stdout The translation, with no trailing newline
# @exitcode 0 Always in the default lenient mode
#######################################
function dybatpho::i18n_tc {
  local context key
  dybatpho::expect_args context key -- "$@"
  shift 2
  dybatpho::i18n_t "${context}${__DYBATPHO_I18N_CTX}${key}" "$@"
}

#######################################
# @description Report whether a key has a translation, without recording a miss
#   and without rendering anything. This is the predicate to branch on.
# @arg $1 string Message key
# @exitcode 0 Some locale in the chain carries the key
# @exitcode 1 The key is untranslated
#######################################
function dybatpho::i18n_has {
  local key
  dybatpho::expect_args key -- "$@"
  local found
  __dybatpho_i18n_lookup found "${key}"
}

#######################################
# @description Print every key that was looked up and not found in this shell.
# @noargs
# @stdout `<locale>`, `<key>` and the number of lookups, tab separated
# @exitcode 1 Nothing was recorded
#######################################
function dybatpho::i18n_missing {
  local slot locale key
  local -i printed=0
  for slot in "${!__dybatpho_i18n_missing[@]}"; do
    locale="${slot%%"${__DYBATPHO_I18N_US}"*}"
    key="${slot#*"${__DYBATPHO_I18N_US}"}"
    printf '%s\t%s\t%s\n' "${locale}" "${key}" "${__dybatpho_i18n_missing[${slot}]}"
    printed+=1
  done
  ((printed > 0))
}

#######################################
# @description Translate a diagnostic that dybatpho itself emitted.
#   Library call sites are not rewritten to use message keys; the English text
#   is the key, which is how gettext works and what lets one hook cover every
#   `dybatpho::die`, `warn`, and `error` in the library at once. The hook is
#   inert unless it is switched on, so output is byte for byte unchanged by
#   default and the existing test suite is unaffected.
# @arg $1 string The English message
# @stdout The translation when one exists, otherwise the message unchanged
#######################################
function dybatpho::i18n_library_message {
  local message
  message="${1-}"
  # This is reachable from a shell that never sourced the module. Only
  # `dybatpho::` functions are exported, so a child shell inherits this one
  # while the module's variables and internal helpers stay behind, and the
  # `declare -F` guard in `logging` cannot tell the two situations apart.
  # Reading its own settings without a default would then abort the caller under
  # `set -u`, which is a steep price for a hook that is off by default.
  if ! dybatpho::is true "${DYBATPHO_I18N_TRANSLATE_LIBRARY:-false}"; then
    printf '%s' "${message}"
    return 0
  fi
  if ! declare -F __dybatpho_i18n_lookup > /dev/null; then
    printf '%s' "${message}"
    return 0
  fi
  local found
  if __dybatpho_i18n_lookup found "${message}"; then
    printf '%s' "${found}"
  else
    printf '%s' "${message}"
  fi
  return 0
}

#######################################
# @description Translate a piece of dybatpho's own user interface that carries a
#   value. The English text a call site already builds cannot serve as the
#   message id here, because the value is baked into it and no catalog can list
#   `Unrecognized option: --colr`. So the caller names a stable key and hands
#   over the English rendering it would otherwise have printed; the key is what
#   translators see, and the English is what is printed whenever the hook is off,
#   the module is absent, or the key is untranslated.
# @arg $1 string Message key
# @arg $2 string The English rendering, already complete
# @arg $@ string `name=value` bindings, or bare positional values
# @stdout The translation with its placeholders filled, otherwise $2 unchanged
#######################################
function dybatpho::i18n_library_text {
  local key english
  key="${1-}"
  english="${2-}"
  shift 2 2> /dev/null || true
  if ! dybatpho::is true "${DYBATPHO_I18N_TRANSLATE_LIBRARY:-false}"; then
    printf '%s' "${english}"
    return 0
  fi
  # Reachable from a child shell that inherited this exported function without
  # the module's internals; see `dybatpho::i18n_library_message`.
  if ! declare -F __dybatpho_i18n_lookup > /dev/null; then
    printf '%s' "${english}"
    return 0
  fi
  local template rendered
  if __dybatpho_i18n_lookup template "${key}"; then
    __dybatpho_i18n_interpolate rendered "${template}" "$@"
    printf '%s' "${rendered}"
    return 0
  fi
  printf '%s' "${english}"
  return 0
}

#######################################
# @description Translate a piece of dybatpho's own user interface that counts
#   something, choosing the plural form the count takes in the target language.
#   This is the half a generated English string cannot express: the call site
#   picks between `argument` and `arguments` by testing for one, which is the
#   wrong question in Russian and a question Vietnamese never asks.
# @arg $1 string Message key
# @arg $2 number Count
# @arg $3 string The English rendering, already complete
# @arg $@ string Further `name=value` bindings, or bare positional values
# @stdout The translation with `{count}` filled, otherwise $3 unchanged
#######################################
function dybatpho::i18n_library_plural {
  local key count english
  key="${1-}"
  count="${2-}"
  english="${3-}"
  shift 3 2> /dev/null || true
  if ! dybatpho::is true "${DYBATPHO_I18N_TRANSLATE_LIBRARY:-false}"; then
    printf '%s' "${english}"
    return 0
  fi
  if ! declare -F __dybatpho_i18n_lookup > /dev/null; then
    printf '%s' "${english}"
    return 0
  fi
  [[ "${count}" =~ ^-?[0-9]+$ ]] || {
    printf '%s' "${english}"
    return 0
  }
  local template rendered grouped
  local i18n_locale
  i18n_locale=$(dybatpho::i18n_locale)
  grouped="$(dybatpho::i18n_number "${count}" 0 "${i18n_locale}")"
  if __dybatpho_i18n_lookup template "${key}" "${count}"; then
    __dybatpho_i18n_interpolate rendered "${template}" \
      "count=${grouped}" "n=${grouped}" "$@"
    printf '%s' "${rendered}"
    return 0
  fi
  printf '%s' "${english}"
  return 0
}

# Number symbols per locale, keyed `<locale>.<field>`. `grouping` is the primary
# group size, optionally followed by `;` and the size of every further group:
# `3;2` is the Indian lakh system, where 12345678 reads 1,23,45,678. Holding it
# as data rather than assuming three is the whole reason this is a table.
declare -gA DYBATPHO_I18N_NUMBER=(
  ["en.group"]="," ["en.decimal"]="." ["en.grouping"]="3" ["en.minus"]="-" ["en.percent"]="#%"
  ["en_GB.group"]="," ["en_GB.decimal"]="." ["en_GB.grouping"]="3" ["en_GB.minus"]="-" ["en_GB.percent"]="#%"
  ["de.group"]="." ["de.decimal"]="," ["de.grouping"]="3" ["de.minus"]="-" ["de.percent"]="# %"
  ["es.group"]="." ["es.decimal"]="," ["es.grouping"]="3" ["es.minus"]="-" ["es.percent"]="# %"
  ["it.group"]="." ["it.decimal"]="," ["it.grouping"]="3" ["it.minus"]="-" ["it.percent"]="#%"
  ["nl.group"]="." ["nl.decimal"]="," ["nl.grouping"]="3" ["nl.minus"]="-" ["nl.percent"]="#%"
  ["pt_BR.group"]="." ["pt_BR.decimal"]="," ["pt_BR.grouping"]="3" ["pt_BR.minus"]="-" ["pt_BR.percent"]="#%"
  ["pt.group"]="." ["pt.decimal"]="," ["pt.grouping"]="3" ["pt.minus"]="-" ["pt.percent"]="#%"
  ["tr.group"]="." ["tr.decimal"]="," ["tr.grouping"]="3" ["tr.minus"]="-" ["tr.percent"]="%#"
  ["vi.group"]="." ["vi.decimal"]="," ["vi.grouping"]="3" ["vi.minus"]="-" ["vi.percent"]="#%"
  ["id.group"]="." ["id.decimal"]="," ["id.grouping"]="3" ["id.minus"]="-" ["id.percent"]="#%"
  ["pl.decimal"]="," ["pl.grouping"]="3" ["pl.minus"]="-" ["pl.percent"]="# %"
  ["ru.decimal"]="," ["ru.grouping"]="3" ["ru.minus"]="-" ["ru.percent"]="# %"
  ["fr.decimal"]="," ["fr.grouping"]="3" ["fr.minus"]="-" ["fr.percent"]="# %"
  ["ja.group"]="," ["ja.decimal"]="." ["ja.grouping"]="3" ["ja.minus"]="-" ["ja.percent"]="#%"
  ["ko.group"]="," ["ko.decimal"]="." ["ko.grouping"]="3" ["ko.minus"]="-" ["ko.percent"]="#%"
  ["zh_CN.group"]="," ["zh_CN.decimal"]="." ["zh_CN.grouping"]="3" ["zh_CN.minus"]="-" ["zh_CN.percent"]="#%"
  ["zh_TW.group"]="," ["zh_TW.decimal"]="." ["zh_TW.grouping"]="3" ["zh_TW.minus"]="-" ["zh_TW.percent"]="#%"
  ["zh.group"]="," ["zh.decimal"]="." ["zh.grouping"]="3" ["zh.minus"]="-" ["zh.percent"]="#%"
  ["th.group"]="," ["th.decimal"]="." ["th.grouping"]="3" ["th.minus"]="-" ["th.percent"]="#%"
  ["ar.group"]="," ["ar.decimal"]="." ["ar.grouping"]="3" ["ar.minus"]="-" ["ar.percent"]="#%"
  ["he.group"]="," ["he.decimal"]="." ["he.grouping"]="3" ["he.minus"]="-" ["he.percent"]="#%"
  ["hi.group"]="," ["hi.decimal"]="." ["hi.grouping"]="3;2" ["hi.minus"]="-" ["hi.percent"]="#%"
  ["bn.group"]="," ["bn.decimal"]="." ["bn.grouping"]="3;2" ["bn.minus"]="-" ["bn.percent"]="#%"
)

# Currency metadata, keyed `<code>.symbol` and `<code>.digits`. The digit count
# is a property of the currency and not of the locale, which is why yen and dong
# have none and dinars have three.
declare -gA DYBATPHO_I18N_CURRENCY=(
  ["USD.symbol"]='$' ["USD.digits"]=2
  ["EUR.symbol"]='€' ["EUR.digits"]=2
  ["GBP.symbol"]='£' ["GBP.digits"]=2
  ["CHF.symbol"]='CHF' ["CHF.digits"]=2
  ["RUB.symbol"]='₽' ["RUB.digits"]=2
  ["PLN.symbol"]='zł' ["PLN.digits"]=2
  ["TRY.symbol"]='₺' ["TRY.digits"]=2
  ["BRL.symbol"]='R$' ["BRL.digits"]=2
  ["INR.symbol"]='₹' ["INR.digits"]=2
  ["CNY.symbol"]='¥' ["CNY.digits"]=2
  ["TWD.symbol"]='NT$' ["TWD.digits"]=2
  ["THB.symbol"]='฿' ["THB.digits"]=2
  ["ILS.symbol"]='₪' ["ILS.digits"]=2
  ["AED.symbol"]='د.إ' ["AED.digits"]=2
  ["AUD.symbol"]='A$' ["AUD.digits"]=2
  ["CAD.symbol"]='CA$' ["CAD.digits"]=2
  ["SEK.symbol"]='kr' ["SEK.digits"]=2
  ["JPY.symbol"]='¥' ["JPY.digits"]=0
  ["KRW.symbol"]='₩' ["KRW.digits"]=0
  ["VND.symbol"]='₫' ["VND.digits"]=0
  ["CLP.symbol"]='$' ["CLP.digits"]=0
  ["ISK.symbol"]='kr' ["ISK.digits"]=0
  ["IDR.symbol"]='Rp' ["IDR.digits"]=0
  ["BHD.symbol"]='.د.ب' ["BHD.digits"]=3
  ["KWD.symbol"]='د.ك' ["KWD.digits"]=3
  ["TND.symbol"]='د.ت' ["TND.digits"]=3
)

# Where the symbol sits relative to the amount, per locale. `¤` is the symbol
# and `#` the number. Dutch and German are neighbours with opposite conventions,
# which is why this cannot be derived and has to be looked up.
declare -gA DYBATPHO_I18N_CURRENCY_LAYOUT=(
  ["en.layout"]='¤#' ["en_GB.layout"]='¤#' ["ja.layout"]='¤#' ["ko.layout"]='¤#'
  ["zh.layout"]='¤#' ["zh_CN.layout"]='¤#' ["zh_TW.layout"]='¤#' ["th.layout"]='¤#'
  ["hi.layout"]='¤#' ["bn.layout"]='¤#' ["he.layout"]='¤ #' ["ar.layout"]='¤ #'
  ["nl.layout"]='¤ #' ["tr.layout"]='¤#' ["id.layout"]='¤#'
  ["de.layout"]='# ¤' ["fr.layout"]='# ¤' ["es.layout"]='# ¤' ["it.layout"]='# ¤'
  ["pt.layout"]='¤ #' ["pt_BR.layout"]='¤ #' ["ru.layout"]='# ¤' ["pl.layout"]='# ¤'
  ["vi.layout"]='# ¤'
)

# Languages written right to left, matched on the language subtag. Held as a
# string because the only question ever asked of it is membership, which is the
# same shape `init.sh` uses for the loaded module list.
DYBATPHO_I18N_RTL="${DYBATPHO_I18N_RTL:-ar he fa ur yi dv ps sd ug ckb arc syr nqo}"

#######################################
# @description Seed the locale data that cannot be written as ASCII source.
#   French and Russian group digits with a narrow no-break space, and the
#   currency layouts separate symbol from amount with a non-breaking space, so
#   that neither a terminal nor a text wrapper can split an amount. Older or
#   reduced `printf` builds do not understand `\u`, so the escape is probed once
#   and degraded rather than assumed.
# @noargs
# @set DYBATPHO_I18N_NUMBER DYBATPHO_I18N_CURRENCY_LAYOUT
# @internal
#######################################
function __dybatpho_i18n_seed_symbols {
  local narrow nbsp probe
  probe="$(printf ' ' 2> /dev/null)" || probe=""
  if [[ "${probe}" == ' ' || -z "${probe}" ]]; then
    narrow=" "
    nbsp=" "
  else
    narrow="${probe}"
    nbsp="$(printf ' ')"
  fi
  if dybatpho::is true "${DYBATPHO_I18N_ASCII}"; then
    narrow=" "
    nbsp=" "
  fi
  DYBATPHO_I18N_NUMBER["fr.group"]="${narrow}"
  DYBATPHO_I18N_NUMBER["ru.group"]="${narrow}"
  DYBATPHO_I18N_NUMBER["pl.group"]="${narrow}"
  local locale layout
  for locale in "${!DYBATPHO_I18N_CURRENCY_LAYOUT[@]}"; do
    layout="${DYBATPHO_I18N_CURRENCY_LAYOUT[${locale}]}"
    DYBATPHO_I18N_CURRENCY_LAYOUT[${locale}]="${layout// /${nbsp}}"
  done
}
__dybatpho_i18n_seed_symbols

#######################################
# @description Read one field of locale data, degrading from the exact tag to
#   the bare language, then to the configured fallback, then to English.
#   The last step matters: a missing group separator that came back empty would
#   silently turn 1234 into 1234 rather than 1,234.
# @arg $1 string Name of the map to read
# @arg $2 string Locale tag
# @arg $3 string Field name
# @stdout The value
# @exitcode 1 No candidate carried the field
# @internal
#######################################
function __dybatpho_i18n_data {
  local map_name locale field
  map_name="$1"
  locale="$2"
  field="$3"
  local -n __data_map="${map_name}"
  local language candidate
  language="$(__dybatpho_i18n_language "${locale}")"
  for candidate in "${locale}" "${locale%%@*}" "${language}" "${DYBATPHO_I18N_FALLBACK}" "en"; do
    [[ -n "${candidate}" ]] || continue
    local hit="${__data_map["${candidate}.${field}"]-${__DYBATPHO_I18N_NONE}}"
    if [[ "${hit}" != "${__DYBATPHO_I18N_NONE}" ]]; then
      printf '%s' "${hit}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Split a decimal number into sign, integer digits, and fraction
#   digits. No arithmetic touches the integer part, so a value wider than a
#   64-bit integer survives intact where `$(( ))` would wrap to nonsense.
# @arg $1 string Value
# @arg $2 string Name of the variable that receives the sign
# @arg $3 string Name of the variable that receives the integer digits
# @arg $4 string Name of the variable that receives the fraction digits
# @set The three named variables
# @internal
#######################################
function __dybatpho_i18n_split_number {
  local __split_value __split_sign_name __split_int_name __split_frac_name
  __split_value="$1"
  __split_sign_name="$2"
  __split_int_name="$3"
  __split_frac_name="$4"
  local -n __split_sign="${__split_sign_name}"
  local -n __split_int="${__split_int_name}"
  local -n __split_frac="${__split_frac_name}"
  # Character ranges and digit classes follow the collation of the ambient
  # locale, which is exactly what this module must not depend on.
  local LC_ALL=C
  [[ "${__split_value}" =~ ^[[:space:]]*([+-]?)([0-9]*)(\.([0-9]*))?[[:space:]]*$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Not a number: ${__split_value}"
  __split_sign="${BASH_REMATCH[1]}"
  __split_int="${BASH_REMATCH[2]}"
  __split_frac="${BASH_REMATCH[4]-}"
  [[ -n "${__split_int}${__split_frac}" ]] \
    || dybatpho::die "${FUNCNAME[1]}: Not a number: ${__split_value}"
  __split_int="${__split_int:-0}"
  # Leading zeros would otherwise survive grouping as 0,001,234.
  while [[ "${__split_int}" == 0?* ]]; do
    __split_int="${__split_int#0}"
  done
  [[ "${__split_sign}" == "-" ]] || __split_sign=""
}

#######################################
# @description Round a fraction to a width, carrying into the integer part.
#   Both sides stay digit strings, so a thirty digit value rounds exactly the
#   same way a small one does. Ties round away from zero, which is what a person
#   reading an invoice expects; note that `printf` rounds binary floats to even
#   and so disagrees on exact halves.
# @arg $1 string Name of the variable holding the integer digits
# @arg $2 string Name of the variable holding the fraction digits
# @arg $3 number Requested number of fraction digits
# @set The two named variables
# @internal
#######################################
function __dybatpho_i18n_round {
  local __round_int_name __round_frac_name precision
  __round_int_name="$1"
  __round_frac_name="$2"
  precision="$3"
  local -n __round_int="${__round_int_name}"
  local -n __round_frac="${__round_frac_name}"

  if ((${#__round_frac} <= precision)); then
    while ((${#__round_frac} < precision)); do
      __round_frac="${__round_frac}0"
    done
    return 0
  fi

  local next="${__round_frac:precision:1}"
  __round_frac="${__round_frac:0:precision}"
  ((next >= 5)) || return 0

  local combined="${__round_int}${__round_frac}"
  local index=$((${#combined} - 1))
  local carry=1 digit result=""
  while ((index >= 0 && carry)); do
    digit=$((${combined:index:1} + carry))
    carry=$((digit / 10))
    result="$((digit % 10))${result}"
    ((index--))
  done
  combined="${combined:0:index+1}${result}"
  ((carry)) && combined="1${combined}"

  if ((precision > 0)); then
    __round_frac="${combined: -precision}"
    __round_int="${combined:0:${#combined}-precision}"
  else
    __round_frac=""
    __round_int="${combined}"
  fi
  __round_int="${__round_int:-0}"
}

#######################################
# @description Insert a group separator into a string of digits, honoring a
#   secondary group size when the locale has one.
# @arg $1 string Digits
# @arg $2 string Grouping specification, such as `3` or `3;2`, or `0` for none
# @arg $3 string Group separator
# @stdout The grouped digits
# @internal
#######################################
function __dybatpho_i18n_group {
  local digits grouping separator
  digits="$1"
  grouping="$2"
  separator="$3"
  if [[ "${grouping}" == "0" || -z "${separator}" ]]; then
    printf '%s' "${digits}"
    return 0
  fi
  local primary="${grouping%%;*}"
  local secondary="${grouping#*;}"
  [[ "${secondary}" != "${grouping}" ]] || secondary="${primary}"

  local head="${digits}" tail=""
  if ((${#head} > primary)); then
    # The space before the minus is required: `${head:-primary}` would be read
    # as a default value rather than as an offset from the end.
    tail="${separator}${head: -primary}"
    head="${head:0:${#head}-primary}"
    while ((${#head} > secondary)); do
      tail="${separator}${head: -secondary}${tail}"
      head="${head:0:${#head}-secondary}"
    done
  fi
  printf '%s' "${head}${tail}"
}

#######################################
# @description Format a number the way a locale writes it.
# @example
#   dybatpho::i18n_number 1234567.891 2 de   # 1.234.567,89
#   dybatpho::i18n_number 12345678 0 hi      # 1,23,45,678
#
# @arg $1 string Value, in plain decimal notation
# @arg $2 number Optional fraction digits, default keeps what the input had
# @arg $3 string Optional locale, default is the active locale
# @stdout The formatted number
# @exitcode 1 The value is not a number or the precision is not an integer
# @tip Formatted output is for display. Never parse it back: several locales
#   group with a narrow no-break space, which is invisible but is not a space
#######################################
function dybatpho::i18n_number {
  local value
  dybatpho::expect_args value -- "$@"
  local precision="${2-}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local sign integer fraction
  __dybatpho_i18n_split_number "${value}" sign integer fraction
  if [[ -z "${precision}" ]]; then
    precision=${#fraction}
    ((precision <= 6)) || precision=6
  fi
  [[ "${precision}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Precision must be a non-negative integer, got '${precision}'"
  __dybatpho_i18n_round integer fraction "${precision}"

  local group_sep decimal_sep grouping minus grouped
  group_sep="$(__dybatpho_i18n_data DYBATPHO_I18N_NUMBER "${locale}" group)" || group_sep=","
  decimal_sep="$(__dybatpho_i18n_data DYBATPHO_I18N_NUMBER "${locale}" decimal)" || decimal_sep="."
  grouping="$(__dybatpho_i18n_data DYBATPHO_I18N_NUMBER "${locale}" grouping)" || grouping="3"
  minus="$(__dybatpho_i18n_data DYBATPHO_I18N_NUMBER "${locale}" minus)" || minus="-"
  grouped="$(__dybatpho_i18n_group "${integer}" "${grouping}" "${group_sep}")"

  # Rounding turns -0.004 into -0, which no locale wants to see printed.
  if [[ "${grouped}" == "0" && "${fraction}" != *[1-9]* ]]; then
    sign=""
  fi
  if ((precision > 0)); then
    printf '%s%s%s%s\n' "${sign:+${minus}}" "${grouped}" "${decimal_sep}" "${fraction}"
  else
    printf '%s%s\n' "${sign:+${minus}}" "${grouped}"
  fi
}

#######################################
# @description Format a number without grouping and with a dot decimal mark,
#   whatever the locale. This is the rounding primitive for machine-readable
#   output, and exists so that nothing in a script has to reach for
#   `printf '%f'`, which follows `LC_NUMERIC` and would vary by machine.
# @arg $1 string Value
# @arg $2 number Optional fraction digits
# @stdout The formatted number
#######################################
function dybatpho::i18n_number_plain {
  local value
  dybatpho::expect_args value -- "$@"
  local precision="${2-}"
  local sign integer fraction
  __dybatpho_i18n_split_number "${value}" sign integer fraction
  if [[ -z "${precision}" ]]; then
    precision=${#fraction}
    ((precision <= 6)) || precision=6
  fi
  [[ "${precision}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Precision must be a non-negative integer, got '${precision}'"
  __dybatpho_i18n_round integer fraction "${precision}"
  if [[ "${integer}" == "0" && "${fraction}" != *[1-9]* ]]; then
    sign=""
  fi
  if ((precision > 0)); then
    printf '%s%s.%s\n' "${sign}" "${integer}" "${fraction}"
  else
    printf '%s%s\n' "${sign}" "${integer}"
  fi
}

#######################################
# @description Format a value as a percentage the way a locale writes it.
# @example
#   dybatpho::i18n_percent 42.5 1 fr   # 42,5 %
#   dybatpho::i18n_percent 42.5 1 tr   # %42,5
#
# @arg $1 string Value, already expressed in percent
# @arg $2 number Optional fraction digits, default is none
# @arg $3 string Optional locale, default is the active locale
# @stdout The formatted percentage
#######################################
function dybatpho::i18n_percent {
  local value
  dybatpho::expect_args value -- "$@"
  local precision="${2:-0}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local number pattern
  number="$(dybatpho::i18n_number "${value}" "${precision}" "${locale}")"
  pattern="$(__dybatpho_i18n_data DYBATPHO_I18N_NUMBER "${locale}" percent)" || pattern="#%"
  local rendered="${pattern//\#/${number}}"
  printf '%s\n' "${rendered}"
}

#######################################
# @description Move a negative sign outside the rendered amount, or wrap the
#   amount in parentheses when accounting style was asked for. Without this a
#   prefix symbol produces `$-1,234.50`, which no locale writes.
# @arg $1 string Rendered amount
# @arg $2 string Minus glyph the number was formatted with
# @stdout The corrected amount
# @internal
#######################################
function __dybatpho_i18n_negative {
  local rendered minus
  rendered="$1"
  minus="$2"
  if [[ "${rendered}" != *"${minus}"* ]]; then
    printf '%s' "${rendered}"
    return 0
  fi
  local stripped="${rendered/"${minus}"/}"
  if [[ "${DYBATPHO_I18N_CURRENCY_NEGATIVE}" == "parens" ]]; then
    printf '(%s)' "${stripped}"
  else
    printf '%s%s' "${minus}" "${stripped}"
  fi
}

#######################################
# @description Format a monetary amount for a locale.
#   How many decimal digits to show is a property of the currency, while how the
#   digits are grouped and where the symbol sits are properties of the locale,
#   so the same euro amount reads `€1,234.50` in English and `1.234,50 €` in
#   German, and yen never shows a decimal at all.
# @example
#   dybatpho::i18n_currency 1234.5 EUR de   # 1.234,50 €
#   dybatpho::i18n_currency 1234.5 JPY en   # ¥1,235
#
# @arg $1 string Amount
# @arg $2 string ISO 4217 currency code
# @arg $3 string Optional locale, default is the active locale
# @stdout The formatted amount
# @stderr A warning when the currency is not in the table
# @exitcode 1 The amount is not a number
#######################################
function dybatpho::i18n_currency {
  local amount code
  dybatpho::expect_args amount code -- "$@"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  code="${code^^}"
  local symbol digits
  symbol="${DYBATPHO_I18N_CURRENCY["${code}.symbol"]-${__DYBATPHO_I18N_NONE}}"
  if [[ "${symbol}" == "${__DYBATPHO_I18N_NONE}" ]]; then
    # ISO 4217 sanctions the code itself as a presentation form, and two digits
    # covers most currencies, so this is reported and carried on with rather
    # than being fatal: a cost report should not die on an unusual currency.
    dybatpho::warn "${FUNCNAME[0]}: Unknown currency '${code}', using the code as its symbol"
    symbol="${code}"
    digits=2
  else
    digits="${DYBATPHO_I18N_CURRENCY["${code}.digits"]}"
    if dybatpho::is true "${DYBATPHO_I18N_ASCII}"; then
      symbol="${code}"
    fi
  fi
  local number layout minus rendered
  number="$(dybatpho::i18n_number "${amount}" "${digits}" "${locale}")"
  layout="$(__dybatpho_i18n_data DYBATPHO_I18N_CURRENCY_LAYOUT "${locale}" layout)" || layout='¤#'
  minus="$(__dybatpho_i18n_data DYBATPHO_I18N_NUMBER "${locale}" minus)" || minus="-"
  rendered="${layout/¤/${symbol}}"
  rendered="${rendered/\#/${number}}"
  local i18n_negative
  i18n_negative=$(__dybatpho_i18n_negative "${rendered}" "${minus}")
  printf '%s\n' "${i18n_negative}"
}

#######################################
# @description Format a byte count for people, grouping the digits for the
#   locale. Units stay in their international symbols: `KiB` and `MB` are
#   symbols rather than words, every other tool on the machine prints them that
#   way, and translating them would break anything parsing the output.
# @example
#   dybatpho::i18n_bytes 1610612736 iec de   # 1,5 GiB
#   dybatpho::i18n_bytes 1500 si en          # 1.5 kB
#
# @arg $1 number Byte count
# @arg $2 string Optional standard, `iec` for 1024 or `si` for 1000
# @arg $3 string Optional locale, default is the active locale
# @stdout The formatted size
# @exitcode 1 The count is not a non-negative integer, or the standard is unknown
# @tip `dybatpho::file_size` and `dybatpho::dir_size` return the raw byte count
#   this takes
#######################################
function dybatpho::i18n_bytes {
  local bytes
  dybatpho::expect_args bytes -- "$@"
  local standard="${2-}"
  local locale="${3-}"
  [[ -n "${standard}" ]] || standard="${DYBATPHO_I18N_BYTE_STANDARD}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  [[ "${bytes}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Byte count must be a non-negative integer, got '${bytes}'"
  local base
  local -a units
  case "${standard}" in
    iec)
      base=1024
      units=(B KiB MiB GiB TiB PiB EiB)
      ;;
    si)
      base=1000
      units=(B kB MB GB TB PB EB)
      ;;
    *)
      dybatpho::die "${FUNCNAME[0]}: Unknown standard '${standard}', expected iec or si"
      ;;
  esac

  # Divide down while keeping the divisor rather than scaling the input up. A
  # byte count near the top of the signed 64-bit range would overflow the moment
  # it was multiplied, and silently produce a negative size.
  local index=0 divisor=1
  while ((bytes / divisor >= base && index < ${#units[@]} - 1)); do
    divisor=$((divisor * base))
    index=$((index + 1))
  done
  local whole=$((bytes / divisor))
  local remainder=$((bytes % divisor))
  local formatted
  # One decimal below ten and none above keeps every size to four characters of
  # number, and plain bytes are never shown with a decimal at all. The decimal
  # branch is skipped for the largest unit because `remainder * 10` is the one
  # multiplication here that could overflow.
  if ((index == 0 || whole >= 10 || index >= ${#units[@]} - 1)); then
    if ((index > 0 && remainder * 2 >= divisor)); then
      whole=$((whole + 1))
    fi
    formatted="$(dybatpho::i18n_number "${whole}" 0 "${locale}")"
  else
    local tenths=$(((remainder * 10 + divisor / 2) / divisor))
    if ((tenths >= 10)); then
      whole=$((whole + 1))
      tenths=0
    fi
    formatted="$(dybatpho::i18n_number "${whole}.${tenths}" 1 "${locale}")"
  fi
  printf '%s %s\n' "${formatted}" "${units[index]}"
}

# Month, weekday, and day-period names. These maps are read through a nameref in
# `__dybatpho_i18n_data` rather than by name, which static analysis cannot
# follow, so they look unused where they are written.
# shellcheck disable=SC2034
# Weekdays are stored Monday first so that
# their index is the one `date +%u` already reports; storing them Sunday first
# would put an off-by-one conversion at every use site. Values are comma
# separated because no name in any shipped locale contains a comma.
declare -gA DYBATPHO_I18N_NAMES=(
  ["en.months"]="January,February,March,April,May,June,July,August,September,October,November,December"
  ["en.months_abbr"]="Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec"
  ["en.weekdays"]="Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday"
  ["en.weekdays_abbr"]="Mon,Tue,Wed,Thu,Fri,Sat,Sun"
  ["en.dayperiods"]="AM,PM"

  ["de.months"]="Januar,Februar,März,April,Mai,Juni,Juli,August,September,Oktober,November,Dezember"
  ["de.months_abbr"]="Jan,Feb,Mär,Apr,Mai,Jun,Jul,Aug,Sep,Okt,Nov,Dez"
  ["de.weekdays"]="Montag,Dienstag,Mittwoch,Donnerstag,Freitag,Samstag,Sonntag"
  ["de.weekdays_abbr"]="Mo,Di,Mi,Do,Fr,Sa,So"
  ["de.dayperiods"]="AM,PM"

  ["fr.months"]="janvier,février,mars,avril,mai,juin,juillet,août,septembre,octobre,novembre,décembre"
  ["fr.months_abbr"]="janv.,févr.,mars,avr.,mai,juin,juil.,août,sept.,oct.,nov.,déc."
  ["fr.weekdays"]="lundi,mardi,mercredi,jeudi,vendredi,samedi,dimanche"
  ["fr.weekdays_abbr"]="lun.,mar.,mer.,jeu.,ven.,sam.,dim."
  ["fr.dayperiods"]="AM,PM"

  ["es.months"]="enero,febrero,marzo,abril,mayo,junio,julio,agosto,septiembre,octubre,noviembre,diciembre"
  ["es.months_abbr"]="ene,feb,mar,abr,may,jun,jul,ago,sept,oct,nov,dic"
  ["es.weekdays"]="lunes,martes,miércoles,jueves,viernes,sábado,domingo"
  ["es.weekdays_abbr"]="lun,mar,mié,jue,vie,sáb,dom"
  ["es.dayperiods"]="a. m.,p. m."

  ["it.months"]="gennaio,febbraio,marzo,aprile,maggio,giugno,luglio,agosto,settembre,ottobre,novembre,dicembre"
  ["it.months_abbr"]="gen,feb,mar,apr,mag,giu,lug,ago,set,ott,nov,dic"
  ["it.weekdays"]="lunedì,martedì,mercoledì,giovedì,venerdì,sabato,domenica"
  ["it.weekdays_abbr"]="lun,mar,mer,gio,ven,sab,dom"
  ["it.dayperiods"]="AM,PM"

  ["pt.months"]="janeiro,fevereiro,março,abril,maio,junho,julho,agosto,setembro,outubro,novembro,dezembro"
  ["pt.months_abbr"]="jan,fev,mar,abr,mai,jun,jul,ago,set,out,nov,dez"
  ["pt.weekdays"]="segunda-feira,terça-feira,quarta-feira,quinta-feira,sexta-feira,sábado,domingo"
  ["pt.weekdays_abbr"]="seg,ter,qua,qui,sex,sáb,dom"
  ["pt.dayperiods"]="AM,PM"

  ["nl.months"]="januari,februari,maart,april,mei,juni,juli,augustus,september,oktober,november,december"
  ["nl.months_abbr"]="jan,feb,mrt,apr,mei,jun,jul,aug,sep,okt,nov,dec"
  ["nl.weekdays"]="maandag,dinsdag,woensdag,donderdag,vrijdag,zaterdag,zondag"
  ["nl.weekdays_abbr"]="ma,di,wo,do,vr,za,zo"
  ["nl.dayperiods"]="a.m.,p.m."

  ["ru.months"]="января,февраля,марта,апреля,мая,июня,июля,августа,сентября,октября,ноября,декабря"
  ["ru.months_abbr"]="янв.,февр.,мар.,апр.,мая,июн.,июл.,авг.,сент.,окт.,нояб.,дек."
  ["ru.weekdays"]="понедельник,вторник,среда,четверг,пятница,суббота,воскресенье"
  ["ru.weekdays_abbr"]="пн,вт,ср,чт,пт,сб,вс"
  ["ru.dayperiods"]="AM,PM"

  ["pl.months"]="stycznia,lutego,marca,kwietnia,maja,czerwca,lipca,sierpnia,września,października,listopada,grudnia"
  ["pl.months_abbr"]="sty,lut,mar,kwi,maj,cze,lip,sie,wrz,paź,lis,gru"
  ["pl.weekdays"]="poniedziałek,wtorek,środa,czwartek,piątek,sobota,niedziela"
  ["pl.weekdays_abbr"]="pon,wt,śr,czw,pt,sob,niedz"
  ["pl.dayperiods"]="AM,PM"

  ["tr.months"]="Ocak,Şubat,Mart,Nisan,Mayıs,Haziran,Temmuz,Ağustos,Eylül,Ekim,Kasım,Aralık"
  ["tr.months_abbr"]="Oca,Şub,Mar,Nis,May,Haz,Tem,Ağu,Eyl,Eki,Kas,Ara"
  ["tr.weekdays"]="Pazartesi,Salı,Çarşamba,Perşembe,Cuma,Cumartesi,Pazar"
  ["tr.weekdays_abbr"]="Pzt,Sal,Çar,Per,Cum,Cmt,Paz"
  ["tr.dayperiods"]="ÖÖ,ÖS"

  ["vi.months"]="tháng 1,tháng 2,tháng 3,tháng 4,tháng 5,tháng 6,tháng 7,tháng 8,tháng 9,tháng 10,tháng 11,tháng 12"
  ["vi.months_abbr"]="thg 1,thg 2,thg 3,thg 4,thg 5,thg 6,thg 7,thg 8,thg 9,thg 10,thg 11,thg 12"
  ["vi.weekdays"]="Thứ Hai,Thứ Ba,Thứ Tư,Thứ Năm,Thứ Sáu,Thứ Bảy,Chủ Nhật"
  ["vi.weekdays_abbr"]="Th 2,Th 3,Th 4,Th 5,Th 6,Th 7,CN"
  ["vi.dayperiods"]="SA,CH"

  ["ja.months"]="1月,2月,3月,4月,5月,6月,7月,8月,9月,10月,11月,12月"
  ["ja.weekdays"]="月曜日,火曜日,水曜日,木曜日,金曜日,土曜日,日曜日"
  ["ja.weekdays_abbr"]="月,火,水,木,金,土,日"
  ["ja.dayperiods"]="午前,午後"

  ["ko.months"]="1월,2월,3월,4월,5월,6월,7월,8월,9월,10월,11월,12월"
  ["ko.weekdays"]="월요일,화요일,수요일,목요일,금요일,토요일,일요일"
  ["ko.weekdays_abbr"]="월,화,수,목,금,토,일"
  ["ko.dayperiods"]="오전,오후"

  ["zh.months"]="一月,二月,三月,四月,五月,六月,七月,八月,九月,十月,十一月,十二月"
  ["zh.months_abbr"]="1月,2月,3月,4月,5月,6月,7月,8月,9月,10月,11月,12月"
  ["zh.weekdays"]="星期一,星期二,星期三,星期四,星期五,星期六,星期日"
  ["zh.weekdays_abbr"]="周一,周二,周三,周四,周五,周六,周日"
  ["zh.dayperiods"]="上午,下午"

  ["ar.months"]="يناير,فبراير,مارس,أبريل,مايو,يونيو,يوليو,أغسطس,سبتمبر,أكتوبر,نوفمبر,ديسمبر"
  ["ar.weekdays"]="الاثنين,الثلاثاء,الأربعاء,الخميس,الجمعة,السبت,الأحد"
  ["ar.dayperiods"]="ص,م"

  ["he.months"]="ינואר,פברואר,מרץ,אפריל,מאי,יוני,יולי,אוגוסט,ספטמבר,אוקטובר,נובמבר,דצמבר"
  ["he.weekdays"]="יום שני,יום שלישי,יום רביעי,יום חמישי,יום שישי,יום שבת,יום ראשון"
  ["he.dayperiods"]="AM,PM"

  ["hi.months"]="जनवरी,फ़रवरी,मार्च,अप्रैल,मई,जून,जुलाई,अगस्त,सितंबर,अक्तूबर,नवंबर,दिसंबर"
  ["hi.weekdays"]="सोमवार,मंगलवार,बुधवार,गुरुवार,शुक्रवार,शनिवार,रविवार"
  ["hi.dayperiods"]="पूर्वाह्न,अपराह्न"

  ["id.months"]="Januari,Februari,Maret,April,Mei,Juni,Juli,Agustus,September,Oktober,November,Desember"
  ["id.months_abbr"]="Jan,Feb,Mar,Apr,Mei,Jun,Jul,Agu,Sep,Okt,Nov,Des"
  ["id.weekdays"]="Senin,Selasa,Rabu,Kamis,Jumat,Sabtu,Minggu"
  ["id.weekdays_abbr"]="Sen,Sel,Rab,Kam,Jum,Sab,Min"
  ["id.dayperiods"]="AM,PM"

  ["th.months"]="มกราคม,กุมภาพันธ์,มีนาคม,เมษายน,พฤษภาคม,มิถุนายน,กรกฎาคม,สิงหาคม,กันยายน,ตุลาคม,พฤศจิกายน,ธันวาคม"
  ["th.weekdays"]="จันทร์,อังคาร,พุธ,พฤหัสบดี,ศุกร์,เสาร์,อาทิตย์"
  ["th.dayperiods"]="ก่อนเที่ยง,หลังเที่ยง"
)

# Date and time patterns per locale. The letters follow the CLDR convention and
# are interpreted by this module rather than handed to `date`, which is what
# keeps month names independent of whatever locales the host happens to have
# generated. Text inside single quotes is literal, and that quoting is load
# bearing: without it the `d` in the Vietnamese word `ngày` would expand to the
# day number. Whether a locale shows a 12-hour or a 24-hour clock is carried by
# its pattern rather than by a separate flag.
declare -gA DYBATPHO_I18N_DATE_PATTERN=(
  ["en.date_short"]="M/d/yy" ["en.date_medium"]="MMM d, yyyy"
  ["en.date_long"]="MMMM d, yyyy" ["en.date_full"]="EEEE, MMMM d, yyyy"
  ["en.time_short"]="h:mm a" ["en.time_medium"]="h:mm:ss a"
  ["en.datetime_short"]="{date}, {time}" ["en.datetime_medium"]="{date}, {time}"
  ["en.datetime_long"]="{date} 'at' {time}" ["en.datetime_full"]="{date} 'at' {time}"

  ["en_GB.date_short"]="dd/MM/yyyy" ["en_GB.date_medium"]="d MMM yyyy"
  ["en_GB.date_long"]="d MMMM yyyy" ["en_GB.date_full"]="EEEE d MMMM yyyy"
  ["en_GB.time_short"]="HH:mm" ["en_GB.time_medium"]="HH:mm:ss"

  ["de.date_short"]="dd.MM.yy" ["de.date_medium"]="dd.MM.yyyy"
  ["de.date_long"]="d. MMMM yyyy" ["de.date_full"]="EEEE, d. MMMM yyyy"
  ["de.time_short"]="HH:mm" ["de.time_medium"]="HH:mm:ss"

  ["fr.date_short"]="dd/MM/yyyy" ["fr.date_medium"]="d MMM yyyy"
  ["fr.date_long"]="d MMMM yyyy" ["fr.date_full"]="EEEE d MMMM yyyy"
  ["fr.time_short"]="HH:mm" ["fr.time_medium"]="HH:mm:ss"

  ["es.date_short"]="d/M/yy" ["es.date_medium"]="d MMM yyyy"
  ["es.date_long"]="d 'de' MMMM 'de' yyyy" ["es.date_full"]="EEEE, d 'de' MMMM 'de' yyyy"
  ["es.time_short"]="H:mm" ["es.time_medium"]="H:mm:ss"

  ["it.date_short"]="dd/MM/yy" ["it.date_medium"]="d MMM yyyy"
  ["it.date_long"]="d MMMM yyyy" ["it.date_full"]="EEEE d MMMM yyyy"
  ["it.time_short"]="HH:mm" ["it.time_medium"]="HH:mm:ss"

  ["pt.date_short"]="dd/MM/yyyy" ["pt.date_medium"]="d 'de' MMM 'de' yyyy"
  ["pt.date_long"]="d 'de' MMMM 'de' yyyy" ["pt.date_full"]="EEEE, d 'de' MMMM 'de' yyyy"
  ["pt.time_short"]="HH:mm" ["pt.time_medium"]="HH:mm:ss"

  ["nl.date_short"]="dd-MM-yyyy" ["nl.date_medium"]="d MMM yyyy"
  ["nl.date_long"]="d MMMM yyyy" ["nl.date_full"]="EEEE d MMMM yyyy"
  ["nl.time_short"]="HH:mm" ["nl.time_medium"]="HH:mm:ss"

  ["ru.date_short"]="dd.MM.yyyy" ["ru.date_medium"]="d MMM yyyy"
  ["ru.date_long"]="d MMMM yyyy" ["ru.date_full"]="EEEE, d MMMM yyyy"
  ["ru.time_short"]="HH:mm" ["ru.time_medium"]="HH:mm:ss"

  ["pl.date_short"]="d.MM.yyyy" ["pl.date_medium"]="d MMM yyyy"
  ["pl.date_long"]="d MMMM yyyy" ["pl.date_full"]="EEEE, d MMMM yyyy"
  ["pl.time_short"]="HH:mm" ["pl.time_medium"]="HH:mm:ss"

  ["tr.date_short"]="d.MM.yyyy" ["tr.date_medium"]="d MMM yyyy"
  ["tr.date_long"]="d MMMM yyyy" ["tr.date_full"]="d MMMM yyyy EEEE"
  ["tr.time_short"]="HH:mm" ["tr.time_medium"]="HH:mm:ss"

  ["vi.date_short"]="dd/MM/yyyy" ["vi.date_medium"]="d MMM, yyyy"
  ["vi.date_long"]="'ngày' d 'tháng' M 'năm' yyyy"
  ["vi.date_full"]="EEEE, 'ngày' d 'tháng' M 'năm' yyyy"
  ["vi.time_short"]="HH:mm" ["vi.time_medium"]="HH:mm:ss"

  ["ja.date_short"]="yyyy/MM/dd" ["ja.date_medium"]="yyyy/MM/dd"
  ["ja.date_long"]="yyyy'年'M'月'd'日'" ["ja.date_full"]="yyyy'年'M'月'd'日' EEEE"
  ["ja.time_short"]="H:mm" ["ja.time_medium"]="H:mm:ss"
  ["ja.datetime_medium"]="{date} {time}" ["ja.datetime_short"]="{date} {time}"
  ["ja.datetime_long"]="{date} {time}" ["ja.datetime_full"]="{date} {time}"

  ["ko.date_short"]="yy. M. d." ["ko.date_medium"]="yyyy. M. d."
  ["ko.date_long"]="yyyy'년' M'월' d'일'" ["ko.date_full"]="yyyy'년' M'월' d'일' EEEE"
  ["ko.time_short"]="a h:mm" ["ko.time_medium"]="a h:mm:ss"

  ["zh.date_short"]="yyyy/M/d" ["zh.date_medium"]="yyyy'年'M'月'd'日'"
  ["zh.date_long"]="yyyy'年'M'月'd'日'" ["zh.date_full"]="yyyy'年'M'月'd'日' EEEE"
  ["zh.time_short"]="HH:mm" ["zh.time_medium"]="HH:mm:ss"
  ["zh.datetime_medium"]="{date} {time}" ["zh.datetime_short"]="{date} {time}"
  ["zh.datetime_long"]="{date} {time}" ["zh.datetime_full"]="{date} {time}"

  ["ar.date_short"]="d/M/yyyy" ["ar.date_medium"]="dd/MM/yyyy"
  ["ar.date_long"]="d MMMM yyyy" ["ar.date_full"]="EEEE، d MMMM yyyy"
  ["ar.time_short"]="h:mm a" ["ar.time_medium"]="h:mm:ss a"

  ["he.date_short"]="d.M.yyyy" ["he.date_medium"]="d MMM yyyy"
  ["he.date_long"]="d MMMM yyyy" ["he.date_full"]="EEEE, d MMMM yyyy"
  ["he.time_short"]="HH:mm" ["he.time_medium"]="HH:mm:ss"

  ["hi.date_short"]="d/M/yy" ["hi.date_medium"]="d MMM yyyy"
  ["hi.date_long"]="d MMMM yyyy" ["hi.date_full"]="EEEE, d MMMM yyyy"
  ["hi.time_short"]="h:mm a" ["hi.time_medium"]="h:mm:ss a"

  ["id.date_short"]="dd/MM/yy" ["id.date_medium"]="d MMM yyyy"
  ["id.date_long"]="d MMMM yyyy" ["id.date_full"]="EEEE, dd MMMM yyyy"
  ["id.time_short"]="HH.mm" ["id.time_medium"]="HH.mm.ss"

  ["th.date_short"]="d/M/yy" ["th.date_medium"]="d MMM yyyy"
  ["th.date_long"]="d MMMM yyyy" ["th.date_full"]="EEEEที่ d MMMM yyyy"
  ["th.time_short"]="HH:mm" ["th.time_medium"]="HH:mm:ss"
)

#######################################
# @description Read one name out of a comma separated list of them.
# @arg $1 string Locale tag
# @arg $2 string Name set, such as `months` or `weekdays`
# @arg $3 number One-based index into the list
# @stdout The name
# @exitcode 1 The locale has no such list, or the index is outside it
# @internal
#######################################
function __dybatpho_i18n_name {
  local locale set index
  locale="$1"
  set="$2"
  index="$3"
  local list
  list="$(__dybatpho_i18n_data DYBATPHO_I18N_NAMES "${locale}" "${set}")" || return 1
  local -a names=()
  local old_ifs="${IFS}"
  IFS=','
  read -r -a names <<< "${list}"
  IFS="${old_ifs}"
  ((index >= 1 && index <= ${#names[@]})) || return 1
  printf '%s' "${names[index - 1]}"
}

#######################################
# @description Print the name of a month in a locale.
# @example
#   dybatpho::i18n_month_name 2 wide de   # Februar
#
# @arg $1 number Month, 1 through 12
# @arg $2 string Optional width, `wide` or `abbr`, default is `wide`
# @arg $3 string Optional locale, default is the active locale
# @stdout The month name
# @exitcode 1 The month is outside 1 through 12
#######################################
function dybatpho::i18n_month_name {
  local month
  dybatpho::expect_args month -- "$@"
  local width="${2:-wide}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  if ! [[ "${month}" =~ ^[0-9]+$ ]] || ((month < 1 || month > 12)); then
    dybatpho::die "${FUNCNAME[0]}: Month must be between 1 and 12, got '${month}'"
  fi
  local name=""
  if [[ "${width}" == "abbr" ]]; then
    # A locale that writes its months the same way at both widths simply has no
    # abbreviated list, so the wide one answers for both.
    name="$(__dybatpho_i18n_name "${locale}" months_abbr "${month}")" || name=""
  fi
  [[ -n "${name}" ]] || name="$(__dybatpho_i18n_name "${locale}" months "${month}")" \
    || dybatpho::die "${FUNCNAME[0]}: No month names for locale '${locale}'"
  printf '%s\n' "${name}"
}

#######################################
# @description Print the name of a weekday in a locale.
# @example
#   dybatpho::i18n_weekday_name 4 wide en   # Thursday
#
# @arg $1 number Weekday, 1 for Monday through 7 for Sunday
# @arg $2 string Optional width, `wide` or `abbr`, default is `wide`
# @arg $3 string Optional locale, default is the active locale
# @stdout The weekday name
# @exitcode 1 The weekday is outside 1 through 7
#######################################
function dybatpho::i18n_weekday_name {
  local weekday
  dybatpho::expect_args weekday -- "$@"
  local width="${2:-wide}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  if ! [[ "${weekday}" =~ ^[0-9]+$ ]] || ((weekday < 1 || weekday > 7)); then
    dybatpho::die "${FUNCNAME[0]}: Weekday must be between 1 and 7, got '${weekday}'"
  fi
  local name=""
  if [[ "${width}" == "abbr" ]]; then
    name="$(__dybatpho_i18n_name "${locale}" weekdays_abbr "${weekday}")" || name=""
  fi
  [[ -n "${name}" ]] || name="$(__dybatpho_i18n_name "${locale}" weekdays "${weekday}")" \
    || dybatpho::die "${FUNCNAME[0]}: No weekday names for locale '${locale}'"
  printf '%s\n' "${name}"
}

#######################################
# @description Stop unless the `date` module is loaded.
#   Formatting a timestamp reads its calendar fields through `date`, and so
#   does reading the clock. Message catalogs, plurals, numbers and text
#   direction need neither, so `date` is not a dependency of the module and
#   the functions that need it ask for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `date`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `date` module is not loaded
# @internal
#######################################
function __dybatpho_i18n_need_date {
  declare -F __dybatpho_date_parse > /dev/null \
    || dybatpho::die "${FUNCNAME[1]} needs the date module, load it with: dybatpho::load date"
}

#######################################
# @description Read the numeric calendar fields of a timestamp.
#   This is the only place the module runs `date`, and it asks only for numbers,
#   which are the same in every locale. `LC_ALL=C` is scoped to the function and
#   inherited by the child process, so the result cannot vary with the ambient
#   locale; it is never exported.
# @arg $1 number Epoch seconds
# @arg $2 string Name of the array that receives year, month, day, hour, minute,
#   second, and ISO weekday
# @set The named array
# @internal
#######################################
function __dybatpho_i18n_date_fields {
  local __fields_stamp __fields_target
  __fields_stamp="$1"
  __fields_target="$2"
  local -n __fields_out="${__fields_target}"
  [[ "${__fields_stamp}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Timestamp must be an integer, got '${__fields_stamp}'"
  local LC_ALL=C
  local raw
  raw="$(dybatpho::date_format "${__fields_stamp}" "%Y %m %d %H %M %S %u")" \
    || dybatpho::die "${FUNCNAME[1]}: Cannot read the calendar fields of ${__fields_stamp}"
  read -r -a __fields_out <<< "${raw}"
}

#######################################
# @description Convert a 24-hour hour into its 12-hour form.
# @arg $1 number Hour, 0 through 23
# @stdout Hour, 1 through 12
# @internal
#######################################
function __dybatpho_i18n_hour12 {
  local hour=$((10#$1))
  ((hour == 0)) && hour=12
  ((hour > 12)) && hour=$((hour - 12))
  printf '%s' "${hour}"
}

#######################################
# @description Render a CLDR-style pattern against calendar fields.
#   Supported fields are `yyyy`, `yy`, `MMMM`, `MMM`, `MM`, `M`, `dd`, `d`,
#   `EEEE`, `EEE`, `HH`, `H`, `hh`, `h`, `mm`, `ss`, and `a`, plus `'literal'`.
#   Anything else stops the caller by name, so a typo in a registered pattern
#   fails immediately rather than rendering something subtly wrong.
# @arg $1 string Pattern
# @arg $2 string Locale tag
# @arg $@ string Calendar fields: year, month, day, hour, minute, second, weekday
# @stdout The rendered text
# @internal
#######################################
function __dybatpho_i18n_render_pattern {
  local pattern locale
  pattern="$1"
  locale="$2"
  shift 2
  local year="$1" month="$2" day="$3" hour="$4" minute="$5" second="$6" weekday="$7"
  local out="" index=0 length=${#pattern} char count run
  while ((index < length)); do
    char="${pattern:index:1}"
    if [[ "${char}" == "'" ]]; then
      index=$((index + 1))
      # Two quotes in a row stand for one literal quote.
      if ((index < length)) && [[ "${pattern:index:1}" == "'" ]]; then
        out+="'"
        index=$((index + 1))
        continue
      fi
      while ((index < length)); do
        if [[ "${pattern:index:1}" == "'" ]]; then
          index=$((index + 1))
          break
        fi
        out+="${pattern:index:1}"
        index=$((index + 1))
      done
      continue
    fi
    if [[ "${char}" != [a-zA-Z] ]]; then
      out+="${char}"
      index=$((index + 1))
      continue
    fi
    count=0
    while ((index + count < length)) && [[ "${pattern:index+count:1}" == "${char}" ]]; do
      count=$((count + 1))
    done
    run="${char}${count}"
    case "${run}" in
      y4 | y3) out+="${year}" ;;
      y2 | y1) out+="${year: -2}" ;;
      M4) out+="$(dybatpho::i18n_month_name "$((10#${month}))" wide "${locale}")" ;;
      M3) out+="$(dybatpho::i18n_month_name "$((10#${month}))" abbr "${locale}")" ;;
      M2) out+="${month}" ;;
      M1) out+="$((10#${month}))" ;;
      d2) out+="${day}" ;;
      d1) out+="$((10#${day}))" ;;
      E4 | E5 | E6) out+="$(dybatpho::i18n_weekday_name "${weekday}" wide "${locale}")" ;;
      E1 | E2 | E3) out+="$(dybatpho::i18n_weekday_name "${weekday}" abbr "${locale}")" ;;
      H2) out+="${hour}" ;;
      H1) out+="$((10#${hour}))" ;;
      h2)
        local hour12
        hour12=$(__dybatpho_i18n_hour12 "${hour}")
        out+="$(printf '%02d' "${hour12}")"
        ;;
      h1) out+="$(__dybatpho_i18n_hour12 "${hour}")" ;;
      m2 | m1) out+="${minute}" ;;
      s2 | s1) out+="${second}" ;;
      a1) out+="$(__dybatpho_i18n_dayperiod "${hour}" "${locale}")" ;;
      G1 | G2 | G3) out+="" ;;
      *) dybatpho::die "${FUNCNAME[1]}: Unsupported pattern field '${char}' repeated ${count} times" ;;
    esac
    index=$((index + count))
  done
  printf '%s' "${out}"
}

#######################################
# @description Print the day period marker an hour falls in.
# @arg $1 number Hour, 0 through 23
# @arg $2 string Locale tag
# @stdout The day period name
# @internal
#######################################
function __dybatpho_i18n_dayperiod {
  local hour=$((10#$1))
  local locale="$2"
  local index=1
  ((hour >= 12)) && index=2
  __dybatpho_i18n_name "${locale}" dayperiods "${index}" || printf '%s' "$((index == 1 ? 0 : 0))"
}

#######################################
# @description Look a date or time pattern up, degrading within the locale
#   before it degrades to another one, so a locale that defines only the short
#   and medium forms still renders the long ones sensibly.
# @arg $1 string Locale tag
# @arg $2 string Kind, `date` or `time` or `datetime`
# @arg $3 string Style, `short`, `medium`, `long`, or `full`
# @stdout The pattern
# @internal
#######################################
function __dybatpho_i18n_pattern {
  local locale kind style
  locale="$1"
  kind="$2"
  style="$3"
  local -a order=()
  case "${style}" in
    full) order=(full long medium short) ;;
    long) order=(long medium short full) ;;
    medium) order=(medium short long full) ;;
    short) order=(short medium long full) ;;
    *) dybatpho::die "${FUNCNAME[1]}: Unknown style '${style}', expected short, medium, long, or full" ;;
  esac
  local candidate pattern
  for candidate in "${order[@]}"; do
    pattern="$(__dybatpho_i18n_data DYBATPHO_I18N_DATE_PATTERN "${locale}" "${kind}_${candidate}")" \
      && {
        printf '%s' "${pattern}"
        return 0
      }
  done
  return 1
}

#######################################
# @description Format a timestamp as a date the way a locale writes it.
# @example
#   dybatpho::i18n_date 1709210096 long de   # 29. Februar 2024
#
# @arg $1 number Epoch seconds
# @arg $2 string Optional style, `short`, `medium`, `long`, or `full`
# @arg $3 string Optional locale, default is the active locale
# @env DYBATPHO_DATE_TIMEZONE string Timezone the fields are read in
# @stdout The formatted date
# @tip This takes epoch seconds. Convert a date string first with
#   `dybatpho::date_parse`
#######################################
function dybatpho::i18n_date {
  local timestamp
  dybatpho::expect_args timestamp -- "$@"
  __dybatpho_i18n_need_date
  local style="${2:-medium}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local -a fields=()
  __dybatpho_i18n_date_fields "${timestamp}" fields
  local pattern rendered
  pattern="$(__dybatpho_i18n_pattern "${locale}" date "${style}")" \
    || dybatpho::die "${FUNCNAME[0]}: No date pattern for locale '${locale}'"
  # The renderer stops the shell on a bad pattern, but it runs here inside a
  # command substitution, which is a subshell, so that only ends the subshell.
  # Its status has to be checked and passed on or the caller would see success.
  rendered="$(__dybatpho_i18n_render_pattern "${pattern}" "${locale}" "${fields[@]}")" \
    || return 1
  printf '%s\n' "${rendered}"
}

#######################################
# @description Format a timestamp as a time of day the way a locale writes it,
#   including whether it uses a 12-hour or a 24-hour clock.
# @example
#   dybatpho::i18n_time 1709210096 short en   # 12:34 PM
#
# @arg $1 number Epoch seconds
# @arg $2 string Optional style, `short`, `medium`, `long`, or `full`
# @arg $3 string Optional locale, default is the active locale
# @stdout The formatted time
#######################################
function dybatpho::i18n_time {
  local timestamp
  dybatpho::expect_args timestamp -- "$@"
  __dybatpho_i18n_need_date
  local style="${2:-short}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local -a fields=()
  __dybatpho_i18n_date_fields "${timestamp}" fields
  local pattern rendered
  pattern="$(__dybatpho_i18n_pattern "${locale}" time "${style}")" \
    || dybatpho::die "${FUNCNAME[0]}: No time pattern for locale '${locale}'"
  rendered="$(__dybatpho_i18n_render_pattern "${pattern}" "${locale}" "${fields[@]}")" \
    || return 1
  printf '%s\n' "${rendered}"
}

#######################################
# @description Format a timestamp as a date and time together.
# @arg $1 number Epoch seconds
# @arg $2 string Optional style, `short`, `medium`, `long`, or `full`
# @arg $3 string Optional locale, default is the active locale
# @stdout The formatted date and time
#######################################
function dybatpho::i18n_datetime {
  local timestamp
  dybatpho::expect_args timestamp -- "$@"
  __dybatpho_i18n_need_date
  local style="${2:-medium}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local combined date_part time_part
  combined="$(__dybatpho_i18n_pattern "${locale}" datetime "${style}")" || combined="{date}, {time}"
  date_part="$(dybatpho::i18n_date "${timestamp}" "${style}" "${locale}")"
  time_part="$(dybatpho::i18n_time "${timestamp}" "${style}" "${locale}")"
  local rendered
  # The combining pattern may itself carry quoted literals, such as the English
  # "at", so it is rendered rather than merely substituted into.
  rendered="${combined//\{date\}/${date_part}}"
  rendered="${rendered//\{time\}/${time_part}}"
  local out="" index=0 length=${#rendered}
  while ((index < length)); do
    if [[ "${rendered:index:1}" == "'" ]]; then
      index=$((index + 1))
      while ((index < length)); do
        if [[ "${rendered:index:1}" == "'" ]]; then
          index=$((index + 1))
          break
        fi
        out+="${rendered:index:1}"
        index=$((index + 1))
      done
      continue
    fi
    out+="${rendered:index:1}"
    index=$((index + 1))
  done
  printf '%s\n' "${out}"
}

#######################################
# @description Format a timestamp against an explicit pattern.
# @example
#   dybatpho::i18n_date_pattern 1709210096 "EEEE, d MMMM yyyy" fr
#
# @arg $1 number Epoch seconds
# @arg $2 string CLDR-style pattern
# @arg $3 string Optional locale, default is the active locale
# @stdout The rendered text
#######################################
function dybatpho::i18n_date_pattern {
  local timestamp pattern
  dybatpho::expect_args timestamp pattern -- "$@"
  __dybatpho_i18n_need_date
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local -a fields=()
  __dybatpho_i18n_date_fields "${timestamp}" fields
  local rendered
  rendered="$(__dybatpho_i18n_render_pattern "${pattern}" "${locale}" "${fields[@]}")" \
    || return 1
  printf '%s\n' "${rendered}"
}

#######################################
# @description Seed the English strings this module needs for relative time.
#   They live in the catalog rather than in the code so that they can be
#   translated like any other message, and they are stored under the `en` locale
#   so the normal fallback chain reaches them.
# @noargs
# @set __dybatpho_i18n_msg __dybatpho_i18n_plural
# @internal
#######################################
function __dybatpho_i18n_seed_relative {
  __dybatpho_i18n_store en i18n.relative.now "just now"
  local unit singular plural
  # The units share a shape, so the English forms are generated rather than
  # spelled out twenty four times.
  for unit in minute hour day week month year; do
    singular="${unit}"
    plural="${unit}s"
    __dybatpho_i18n_store en "i18n.relative.past.${unit}" "{count} ${singular} ago" one
    __dybatpho_i18n_store en "i18n.relative.past.${unit}" "{count} ${plural} ago" other
    __dybatpho_i18n_store en "i18n.relative.future.${unit}" "in {count} ${singular}" one
    __dybatpho_i18n_store en "i18n.relative.future.${unit}" "in {count} ${plural}" other
    __dybatpho_i18n_store en "i18n.duration.${unit}" "{count} ${singular}" one
    __dybatpho_i18n_store en "i18n.duration.${unit}" "{count} ${plural}" other
  done
}

#######################################
# @description Choose the unit and count that best describe a span of seconds.
#   The thresholds are the conventional ones rather than exact unit multiples,
#   because an hour and fifty minutes reads better as two hours than as a
#   hundred and ten minutes. Months and years use the average Gregorian length,
#   so they are approximate by design.
# @arg $1 number Absolute span in seconds
# @arg $2 string Name of the variable that receives the unit
# @arg $3 string Name of the variable that receives the count
# @set The two named variables
# @internal
#######################################
function __dybatpho_i18n_span {
  local __span_seconds __span_unit_name __span_count_name
  __span_seconds="$1"
  __span_unit_name="$2"
  __span_count_name="$3"
  local -n __span_unit="${__span_unit_name}"
  local -n __span_count="${__span_count_name}"
  if ((__span_seconds < 45)); then
    __span_unit="now"
    __span_count=0
  elif ((__span_seconds < 2700)); then
    __span_unit="minute"
    __span_count=$(((__span_seconds + 30) / 60))
  elif ((__span_seconds < 79200)); then
    __span_unit="hour"
    __span_count=$(((__span_seconds + 1800) / 3600))
  elif ((__span_seconds < 518400)); then
    __span_unit="day"
    __span_count=$(((__span_seconds + 43200) / 86400))
  elif ((__span_seconds < 2419200)); then
    __span_unit="week"
    __span_count=$(((__span_seconds + 302400) / 604800))
  elif ((__span_seconds < 31536000)); then
    __span_unit="month"
    __span_count=$(((__span_seconds + 1314900) / 2629800))
  else
    __span_unit="year"
    __span_count=$(((__span_seconds + 15778800) / 31557600))
  fi
  ((__span_count >= 1 || __span_unit == "now")) || __span_count=1
  [[ "${__span_unit}" == "now" ]] || ((__span_count >= 1)) || __span_count=1
}

#######################################
# @description Describe when a timestamp happened relative to another one.
# @example
#   dybatpho::i18n_relative 1709210096 1709469296   # 3 days ago
#
# @arg $1 number Epoch seconds being described
# @arg $2 number Optional epoch seconds to compare against, default is now
# @arg $3 string Optional locale, default is the active locale
# @env DYBATPHO_I18N_NOW number Epoch seconds used as now when none is given
# @stdout The description
# @exitcode 1 Either timestamp is not an integer
# @tip Pass the second argument in tests. Leaving it to the clock is what makes
#   a suite that formats relative times flake
#######################################
function dybatpho::i18n_relative {
  local timestamp
  dybatpho::expect_args timestamp -- "$@"
  local now="${2-}"
  local locale="${3-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  if [[ -z "${now}" ]]; then
    if [[ -n "${DYBATPHO_I18N_NOW}" ]]; then
      now="${DYBATPHO_I18N_NOW}"
    else
      __dybatpho_i18n_need_date
      now="$(dybatpho::date_now)"
    fi
  fi
  [[ "${timestamp}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Timestamp must be an integer, got '${timestamp}'"
  [[ "${now}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Reference time must be an integer, got '${now}'"

  local delta=$((now - timestamp))
  local direction="past"
  ((delta < 0)) && {
    direction="future"
    delta=$((-delta))
  }
  local unit count
  __dybatpho_i18n_span "${delta}" unit count
  if [[ "${unit}" == "now" ]]; then
    local i18n_t
    i18n_t=$(dybatpho::i18n_t i18n.relative.now)
    printf '%s\n' "${i18n_t}"
    return 0
  fi
  local i18n_tn
  i18n_tn=$(dybatpho::i18n_tn "i18n.relative.${direction}.${unit}" "${count}")
  printf '%s\n' "${i18n_tn}"
}

#######################################
# @description Describe a span of time without saying whether it is past or
#   future.
# @example
#   dybatpho::i18n_duration 259200   # 3 days
#
# @arg $1 number Seconds
# @arg $2 string Optional locale, default is the active locale
# @stdout The description
# @exitcode 1 The span is not an integer
#######################################
function dybatpho::i18n_duration {
  local seconds
  dybatpho::expect_args seconds -- "$@"
  [[ "${seconds}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Seconds must be an integer, got '${seconds}'"
  ((seconds < 0)) && seconds=$((-seconds))
  local unit count
  __dybatpho_i18n_span "${seconds}" unit count
  if [[ "${unit}" == "now" ]]; then
    local i18n_tn_2
    i18n_tn_2=$(dybatpho::i18n_tn i18n.duration.minute 0)
    printf '%s\n' "${i18n_tn_2}"
    return 0
  fi
  local i18n_tn
  i18n_tn=$(dybatpho::i18n_tn "i18n.duration.${unit}" "${count}")
  printf '%s\n' "${i18n_tn}"
}

#######################################
# @description Report whether a locale is written right to left.
# @example
#   if dybatpho::i18n_is_rtl ar; then ...
#
# @arg $1 string Optional locale, default is the active locale
# @env DYBATPHO_I18N_RTL string Space-separated list of right-to-left languages
# @exitcode 0 The locale reads right to left
# @exitcode 1 The locale reads left to right
#######################################
function dybatpho::i18n_is_rtl {
  local locale="${1-}"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"
  local language
  language="$(__dybatpho_i18n_language "${locale}")"
  # A script-qualified tag is checked first, because the script is what decides
  # direction: Punjabi is left to right in Gurmukhi and right to left in Arabic.
  [[ " ${DYBATPHO_I18N_RTL} " == *" ${locale} "* ]] && return 0
  [[ " ${DYBATPHO_I18N_RTL} " == *" ${language} "* ]]
}

#######################################
# @description Print the direction a locale is written in.
# @arg $1 string Optional locale, default is the active locale
# @stdout `rtl` or `ltr`
#######################################
function dybatpho::i18n_direction {
  if dybatpho::i18n_is_rtl "${1-}"; then
    printf 'rtl\n'
  else
    printf 'ltr\n'
  fi
}

#######################################
# @description Print a bidirectional mark, which forces the direction of the
#   text around it without being visible itself.
# @arg $1 string `ltr` for a left-to-right mark, `rtl` for a right-to-left one
# @stdout The mark
# @exitcode 1 The direction is neither `ltr` nor `rtl`
#######################################
function dybatpho::i18n_bidi_mark {
  local direction
  dybatpho::expect_args direction -- "$@"
  case "${direction}" in
    ltr) printf '‎' ;;
    rtl) printf '‏' ;;
    *) dybatpho::die "${FUNCNAME[0]}: Direction must be ltr or rtl, got '${direction}'" ;;
  esac
}

#######################################
# @description Wrap text so that its direction cannot leak into the text around
#   it. The default isolates by first strong character, which is what to use
#   when splicing in a value whose language is not known in advance.
# @example
#   printf 'Package %s installed\n' "$(dybatpho::i18n_bidi_isolate "${name}")"
#
# @arg $1 string Text
# @arg $2 string Optional direction, `ltr`, `rtl`, or `auto`, default is `auto`
# @stdout The wrapped text
# @exitcode 1 The direction is not recognized
# @tip Wrap for display only. These are invisible but real characters, so text
#   that has been wrapped no longer compares equal to text that has not. Never
#   put them in a filename, a config value, a JSON payload, or anything another
#   program will compare. They also count toward `${#text}`, so strip them with
#   `dybatpho::i18n_bidi_strip` before measuring a column width
#######################################
function dybatpho::i18n_bidi_isolate {
  local text
  dybatpho::expect_args text -- "$@"
  local direction="${2:-auto}"
  local opener
  case "${direction}" in
    ltr) opener="$(printf '⁦')" ;;
    rtl) opener="$(printf '⁧')" ;;
    auto) opener="$(printf '⁨')" ;;
    *) dybatpho::die "${FUNCNAME[0]}: Direction must be ltr, rtl, or auto, got '${direction}'" ;;
  esac
  printf '%s%s%s\n' "${opener}" "${text}" "$(printf '⁩')"
}

#######################################
# @description Remove every bidirectional control character from text, so that
#   it can be compared or measured.
# @arg $1 string Text
# @stdout The text without marks, isolates, or embeddings
#######################################
function dybatpho::i18n_bidi_strip {
  local text
  dybatpho::expect_args text -- "$@"
  local control
  # Isolates and the marks, plus the embeddings and overrides they replaced.
  for control in \
    "$(printf '‎')" "$(printf '‏')" \
    "$(printf '‪')" "$(printf '‫')" "$(printf '‬')" \
    "$(printf '‭')" "$(printf '‮')" \
    "$(printf '⁦')" "$(printf '⁧')" "$(printf '⁨')" \
    "$(printf '⁩')"; do
    text="${text//"${control}"/}"
  done
  printf '%s\n' "${text}"
}

#######################################
# @description Add or replace the number symbols of a locale.
# @example
#   dybatpho::i18n_register_number da . , 3 -
#
# @arg $1 string Locale tag
# @arg $2 string Group separator, or the empty string for none
# @arg $3 string Decimal separator
# @arg $4 string Grouping, such as `3` or `3;2`, or `0` for no grouping
# @arg $5 string Optional minus sign, default is `-`
# @set DYBATPHO_I18N_NUMBER
# @exitcode 1 The grouping is malformed
#######################################
function dybatpho::i18n_register_number {
  local locale group decimal grouping
  dybatpho::expect_args locale group decimal grouping -- "$@"
  local minus="${5:--}"
  [[ "${grouping}" =~ ^[0-9]+(\;[0-9]+)?$ ]] \
    || dybatpho::die \
      "${FUNCNAME[0]}: Grouping must be a number, optionally two separated by a semicolon, got '${grouping}'"
  [[ -n "${decimal}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Decimal separator must not be empty"
  DYBATPHO_I18N_NUMBER["${locale}.group"]="${group}"
  DYBATPHO_I18N_NUMBER["${locale}.decimal"]="${decimal}"
  DYBATPHO_I18N_NUMBER["${locale}.grouping"]="${grouping}"
  DYBATPHO_I18N_NUMBER["${locale}.minus"]="${minus}"
  [[ -n "${DYBATPHO_I18N_NUMBER["${locale}.percent"]-}" ]] \
    || DYBATPHO_I18N_NUMBER["${locale}.percent"]="#%"
}

#######################################
# @description Add or replace a currency's symbol and decimal digits.
# @example
#   dybatpho::i18n_register_currency NOK kr 2
#
# @arg $1 string ISO 4217 code
# @arg $2 string Symbol
# @arg $3 number Decimal digits
# @set DYBATPHO_I18N_CURRENCY
# @exitcode 1 The digit count is not a number
#######################################
function dybatpho::i18n_register_currency {
  local code symbol digits
  dybatpho::expect_args code symbol digits -- "$@"
  [[ "${digits}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Decimal digits must be a non-negative integer, got '${digits}'"
  DYBATPHO_I18N_CURRENCY["${code^^}.symbol"]="${symbol}"
  DYBATPHO_I18N_CURRENCY["${code^^}.digits"]="${digits}"
}

#######################################
# @description Set where a locale puts a currency symbol.
# @arg $1 string Locale tag
# @arg $2 string Layout, using `¤` for the symbol and `#` for the amount
# @set DYBATPHO_I18N_CURRENCY_LAYOUT
# @exitcode 1 The layout does not contain both placeholders
#######################################
function dybatpho::i18n_register_currency_layout {
  local locale layout
  dybatpho::expect_args locale layout -- "$@"
  [[ "${layout}" == *'¤'* && "${layout}" == *'#'* ]] \
    || dybatpho::die "${FUNCNAME[0]}: Layout must contain both ¤ and #, got '${layout}'"
  DYBATPHO_I18N_CURRENCY_LAYOUT["${locale}.layout"]="${layout}"
}

#######################################
# @description Add or replace one date or time pattern of a locale.
# @example
#   dybatpho::i18n_register_date da date_long "d. MMMM yyyy"
#
# @arg $1 string Locale tag
# @arg $2 string Slot, such as `date_long` or `time_short`
# @arg $3 string Pattern
# @set DYBATPHO_I18N_DATE_PATTERN
# @exitcode 1 The slot is not one this module renders
#######################################
function dybatpho::i18n_register_date {
  local locale slot pattern
  dybatpho::expect_args locale slot pattern -- "$@"
  [[ "${slot}" =~ ^(date|time|datetime)_(short|medium|long|full)$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Unknown pattern slot '${slot}'"
  # shellcheck disable=SC2034 # read through a nameref in __dybatpho_i18n_data
  DYBATPHO_I18N_DATE_PATTERN["${locale}.${slot}"]="${pattern}"
}

#######################################
# @description Add or replace a locale's month, weekday, or day period names.
# @example
#   dybatpho::i18n_register_names da weekdays "mandag,tirsdag,onsdag,torsdag,fredag,lørdag,søndag"
#
# @arg $1 string Locale tag
# @arg $2 string Name set: `months`, `months_abbr`, `weekdays`, `weekdays_abbr`, or `dayperiods`
# @arg $3 string Comma separated names, twelve for months, seven for weekdays, two for day periods
# @set DYBATPHO_I18N_NAMES
# @exitcode 1 The set is unknown or the wrong number of names was given
#######################################
function dybatpho::i18n_register_names {
  local locale set names
  dybatpho::expect_args locale set names -- "$@"
  local expected
  case "${set}" in
    months | months_abbr) expected=12 ;;
    weekdays | weekdays_abbr) expected=7 ;;
    dayperiods) expected=2 ;;
    *) dybatpho::die "${FUNCNAME[0]}: Unknown name set '${set}'" ;;
  esac
  local -a parsed=()
  local old_ifs="${IFS}"
  IFS=','
  read -r -a parsed <<< "${names}"
  IFS="${old_ifs}"
  ((${#parsed[@]} == expected)) \
    || dybatpho::die "${FUNCNAME[0]}: ${set} needs ${expected} names, got ${#parsed[@]}"
  # shellcheck disable=SC2034 # read through a nameref in __dybatpho_i18n_data
  DYBATPHO_I18N_NAMES["${locale}.${set}"]="${names}"
}

#######################################
# @description Record additional languages as being written right to left.
# @arg $@ string Language subtags
# @set DYBATPHO_I18N_RTL
#######################################
function dybatpho::i18n_register_rtl {
  local language
  for language in "$@"; do
    [[ " ${DYBATPHO_I18N_RTL} " == *" ${language} "* ]] && continue
    DYBATPHO_I18N_RTL="${DYBATPHO_I18N_RTL} ${language}"
  done
}

#######################################
# @description Read a native `key = value` catalog.
#   The quoting rules are those of the `config` module's dotenv reader, so a
#   value in double quotes has its escapes expanded and one in single quotes is
#   taken literally. A plural form is written `key[category]`, which keeps the
#   format flat and one line per entry while leaving the dot free for
#   hierarchical keys: writing `menu.file.one` as a plural would be ambiguous.
# @arg $1 string File path
# @arg $2 string Locale the entries belong to
# @set __dybatpho_i18n_msg __dybatpho_i18n_plural
# @exitcode 1 An entry is malformed
# @internal
#######################################
function __dybatpho_i18n_read_msg {
  local file locale
  file="$1"
  locale="$2"
  local line key category value context=""
  local -i number=0
  # A bare key: anything but a bracket, a quote, whitespace or the separator,
  # with an optional plural category in brackets.
  local __dybatpho_i18n_bare_key_re='^([^][\"[:space:]=]+)(\[(zero|one|two|few|many|other)\])?'
  __dybatpho_i18n_bare_key_re+='[[:space:]]*=[[:space:]]*(.*)$'
  # The `|| [[ -n ... ]]` clause keeps the last line when the file does not end
  # in a newline, which generators and editors both produce.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    number+=1
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line:0:1}" == "#" ]] && continue
    # Directives describe the file rather than adding a message. `@context`
    # applies to every entry after it, which is how a catalog distinguishes one
    # English word used in two senses without repeating the context per line.
    if [[ "${line:0:1}" == "@" ]]; then
      if [[ "${line}" =~ ^@context[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        context="${BASH_REMATCH[1]}"
        context="${context%"${context##*[![:space:]]}"}"
      fi
      continue
    fi
    # A key in double quotes may contain anything, including spaces, which is
    # what lets a whole English sentence act as its own message id the way a
    # gettext catalog does. The bare form stays available for short keys.
    if [[ "${line}" =~ ^\"([^\"]*)\"(\[(zero|one|two|few|many|other)\])?[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ${__dybatpho_i18n_bare_key_re} ]]; then
      key="${BASH_REMATCH[1]}"
    else
      dybatpho::die "Invalid catalog entry in ${file}:${number}: ${line}"
    fi
    category="${BASH_REMATCH[3]-}"
    value="${BASH_REMATCH[4]}"
    [[ -n "${context}" ]] && key="${context}${__DYBATPHO_I18N_CTX}${key}"
    if [[ "${value}" == \"*\" && ${#value} -ge 2 ]]; then
      value="${value:1:${#value}-2}"
      printf -v value '%b' "${value}"
    elif [[ "${value}" == \'*\' && ${#value} -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    else
      value="${value%%[[:space:]]#*}"
      value="${value%"${value##*[![:space:]]}"}"
    fi
    __dybatpho_i18n_store "${locale}" "${key}" "${value}" "${category}" \
      || dybatpho::die "Invalid catalog entry in ${file}:${number}: ${line}"
  done < "${file}"
  return 0
}

#######################################
# @description Turn the body of a `.po` string into its text.
#   `printf '%b'` does not know about `\"`, so the escaped quotes are lifted out
#   before it runs and put back afterwards.
# @arg $1 string Text between the quotes
# @stdout The unescaped text
# @internal
#######################################
function __dybatpho_i18n_po_unescape {
  local text="$1"
  local sentinel=$'\x01'
  text="${text//\\\"/${sentinel}}"
  printf -v text '%b' "${text}"
  text="${text//${sentinel}/\"}"
  printf '%s' "${text}"
}

#######################################
# @description Read a GNU gettext `.po` catalog.
#   The subset parsed is the one that carries translations: `msgctxt`, `msgid`,
#   `msgid_plural`, `msgstr`, and `msgstr[N]`, including strings continued over
#   several lines. Obsolete entries are skipped, and so are fuzzy ones, because
#   gettext treats a fuzzy entry as an unreviewed guess rather than a
#   translation. An empty `msgstr` means untranslated, not "translates to
#   nothing", which is what makes a template file load as empty rather than as a
#   catalog of blanks.
#
#   The header's `Plural-Forms` expression is read for its count but never
#   evaluated. A catalog is a data file that arrives from a translation
#   platform, and turning an arbitrary C expression from one into shell
#   arithmetic would be a way to run code. The CLDR rules this module carries
#   decide the category instead, and `msgstr[N]` indices are mapped onto them.
# @arg $1 string File path
# @arg $2 string Locale the entries belong to
# @set __dybatpho_i18n_msg __dybatpho_i18n_plural
# @internal
#######################################
function __dybatpho_i18n_read_po {
  local file locale
  file="$1"
  locale="$2"
  local language
  language="$(__dybatpho_i18n_language "${locale}")"
  local -a order=()
  local order_spec="${__dybatpho_i18n_po_order[${__dybatpho_i18n_plural_family[${language}]-one}]-one other}"
  read -r -a order <<< "${order_spec}"

  # The flags comment precedes the entry it describes, so the flag it sets has
  # to wait in `next_fuzzy` until that entry actually begins. Clearing `fuzzy`
  # when the `msgid` line arrives would discard the very flag just read.
  local line mode="" context="" msgid="" msgid_plural="" fuzzy=0 next_fuzzy=0 index=0
  local -A forms=()
  local single=""

  # Flush whatever entry has been accumulated so far.
  local flush_key
  #######################################
  # @description Store the entry the parser has just finished reading, singular
  #   or plural, and drop it when it is marked fuzzy: a fuzzy entry is a
  #   translator's draft, not a translation.
  # @noargs
  # @internal
  #######################################
  function __dybatpho_i18n_po_flush {
    [[ -n "${msgid}${context}" ]] || return 0
    ((fuzzy)) && return 0
    flush_key="${msgid}"
    [[ -n "${context}" ]] && flush_key="${context}${__DYBATPHO_I18N_CTX}${msgid}"
    if [[ -n "${msgid_plural}" ]]; then
      local slot category
      for slot in "${!forms[@]}"; do
        category="${order[slot]-other}"
        [[ -n "${forms[${slot}]}" ]] || continue
        __dybatpho_i18n_store "${locale}" "${flush_key}" "${forms[${slot}]}" "${category}" || true
      done
    elif [[ -n "${single}" ]]; then
      __dybatpho_i18n_store "${locale}" "${flush_key}" "${single}" || true
    fi
    return 0
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    # An obsolete entry is commented out with `#~` and must not be revived.
    [[ "${line}" == "#~"* ]] && continue
    if [[ "${line}" == "#"* ]]; then
      [[ "${line}" == "#,"*fuzzy* ]] && next_fuzzy=1
      continue
    fi
    if [[ -z "${line}" ]]; then
      __dybatpho_i18n_po_flush
      mode=""
      context=""
      msgid=""
      msgid_plural=""
      single=""
      forms=()
      fuzzy=0
      next_fuzzy=0
      continue
    fi
    if [[ "${line}" =~ ^msgctxt[[:space:]]+\"(.*)\"$ ]]; then
      __dybatpho_i18n_po_flush
      context=""
      msgid=""
      msgid_plural=""
      single=""
      forms=()
      fuzzy="${next_fuzzy}"
      next_fuzzy=0
      context="$(__dybatpho_i18n_po_unescape "${BASH_REMATCH[1]}")"
      mode="msgctxt"
      continue
    fi
    if [[ "${line}" =~ ^msgid[[:space:]]+\"(.*)\"$ ]]; then
      if [[ "${mode}" != "msgctxt" ]]; then
        __dybatpho_i18n_po_flush
        context=""
        msgid_plural=""
        single=""
        forms=()
        fuzzy="${next_fuzzy}"
        next_fuzzy=0
      fi
      msgid="$(__dybatpho_i18n_po_unescape "${BASH_REMATCH[1]}")"
      mode="msgid"
      continue
    fi
    if [[ "${line}" =~ ^msgid_plural[[:space:]]+\"(.*)\"$ ]]; then
      msgid_plural="$(__dybatpho_i18n_po_unescape "${BASH_REMATCH[1]}")"
      mode="msgid_plural"
      continue
    fi
    if [[ "${line}" =~ ^msgstr\[([0-9]+)\][[:space:]]+\"(.*)\"$ ]]; then
      index="${BASH_REMATCH[1]}"
      forms["${index}"]="$(__dybatpho_i18n_po_unescape "${BASH_REMATCH[2]}")"
      mode="msgstr_n"
      continue
    fi
    if [[ "${line}" =~ ^msgstr[[:space:]]+\"(.*)\"$ ]]; then
      single="$(__dybatpho_i18n_po_unescape "${BASH_REMATCH[1]}")"
      mode="msgstr"
      continue
    fi
    if [[ "${line}" =~ ^\"(.*)\"$ ]]; then
      local piece
      piece="$(__dybatpho_i18n_po_unescape "${BASH_REMATCH[1]}")"
      case "${mode}" in
        msgctxt) context+="${piece}" ;;
        msgid) msgid+="${piece}" ;;
        msgid_plural) msgid_plural+="${piece}" ;;
        msgstr) single+="${piece}" ;;
        msgstr_n) forms["${index}"]+="${piece}" ;;
        *) ;;
      esac
      continue
    fi
  done < "${file}"
  __dybatpho_i18n_po_flush
  unset -f __dybatpho_i18n_po_flush
  return 0
}

# The order in which gettext's conventional plural expression for each rule
# family emits its forms. This is what lets a positional `msgstr[N]` be mapped
# onto a named category without evaluating the expression that produced it.
declare -gA __dybatpho_i18n_po_order=(
  [other]="other"
  [one]="one other"
  [pt]="one other"
  [fr]="one other"
  [hi]="one other"
  [he]="one two other"
  [ru]="one few many"
  [pl]="one few many"
  [cs]="one few other"
  [ar]="zero one two few many other"
  [lt]="one few other"
  [lv]="zero one other"
  [ro]="one few other"
  [sl]="one two few other"
  [is]="one other"
  [mk]="one other"
  [fil]="one other"
  [cy]="zero one two few many other"
  [mt]="one few many other"
  [ga]="one two few many other"
  [gd]="one two few other"
)

#######################################
# @description Load a catalog file, at most once per shell.
# @arg $1 string File path
# @arg $2 string Locale the entries belong to
# @set __dybatpho_i18n_files
# @exitcode 1 The file cannot be read
# @internal
#######################################
function __dybatpho_i18n_load_file {
  local file locale
  file="$1"
  locale="$2"
  dybatpho::is file "${file}" || return 1
  local resolved
  resolved="$(dybatpho::path_normalize "${file}")"
  local slot="${locale}${__DYBATPHO_I18N_US}${resolved}"
  [[ -n "${__dybatpho_i18n_files[${slot}]-}" ]] && return 0
  __dybatpho_i18n_files["${slot}"]=1
  case "${file}" in
    *.po | *.pot) __dybatpho_i18n_read_po "${file}" "${locale}" ;;
    *) __dybatpho_i18n_read_msg "${file}" "${locale}" ;;
  esac
  dybatpho::debug "Loaded catalog ${resolved} for ${locale}"
  return 0
}

#######################################
# @description Print the directories a catalog is looked for in, least specific
#   first. The order is deliberately the reverse of how specific each root is:
#   a later file overrides an earlier one, so the directories a caller named
#   themselves have to be loaded last in order to win.
# @noargs
# @stdout One directory per line
# @internal
#######################################
function __dybatpho_i18n_roots {
  local -a roots=()
  local entry
  roots+=("${DYBATPHO_DIR}/locale")
  local old_ifs="${IFS}"
  local -a parts=()
  IFS=':'
  read -r -a parts <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  IFS="${old_ifs}"
  for entry in ${parts[@]+"${parts[@]}"}; do
    [[ -n "${entry}" ]] && roots+=("${entry%/}/locale")
  done
  if [[ -n "${HOME-}" || -n "${XDG_DATA_HOME-}" ]]; then
    roots+=("$(dybatpho::xdg_data_dir)/locale")
  fi
  parts=()
  IFS=':'
  read -r -a parts <<< "${DYBATPHO_I18N_PATH}"
  IFS="${old_ifs}"
  for entry in ${parts[@]+"${parts[@]}"}; do
    [[ -n "${entry}" ]] && roots+=("${entry%/}")
  done
  printf '%s\n' "${roots[@]}"
}

#######################################
# @description Load every catalog that exists for a locale and domain, across
#   the whole search path and both file layouts.
# @arg $1 string Locale tag
# @arg $2 string Domain
# @exitcode 1 Nothing was found
# @internal
#######################################
function __dybatpho_i18n_discover {
  local locale domain
  locale="$1"
  domain="$2"
  local root candidate
  local -i found=0
  local i18n_roots_output
  i18n_roots_output=$(__dybatpho_i18n_roots)
  while IFS= read -r root || [[ -n "${root}" ]]; do
    [[ -n "${root}" ]] || continue
    for candidate in \
      "${root}/${locale}/LC_MESSAGES/${domain}.po" \
      "${root}/${locale}/LC_MESSAGES/${domain}.msg" \
      "${root}/${locale}/${domain}.po" \
      "${root}/${locale}/${domain}.msg" \
      "${root}/${domain}.${locale}.po" \
      "${root}/${domain}.${locale}.msg" \
      "${root}/${locale}.po" \
      "${root}/${locale}.msg"; do
      if dybatpho::is file "${candidate}"; then
        __dybatpho_i18n_load_file "${candidate}" "${locale}"
        found+=1
      fi
    done
  done < <(printf '%s' "${i18n_roots_output}")
  ((found > 0))
}

#######################################
# @description Load message catalogs.
#   With a file, that file is loaded for the given locale. Without one, every
#   catalog on the search path is loaded for each locale in the fallback chain,
#   so that a partially translated locale is backed by the ones behind it.
# @example
#   dybatpho::i18n_load vi_VN "${PWD}/locale/vi.msg"
#   dybatpho::i18n_load vi_VN
#
# @arg $1 string Locale tag
# @arg $2 string Optional catalog file; when omitted the search path is used
# @arg $3 string Optional domain, default is `DYBATPHO_I18N_DOMAIN`
# @env DYBATPHO_I18N_PATH string Colon separated catalog directories
# @exitcode 1 A named file is missing, or no catalog was found in lenient mode
#######################################
function dybatpho::i18n_load {
  local locale
  dybatpho::expect_args locale -- "$@"
  local file="${2-}"
  local domain="${3:-${DYBATPHO_I18N_DOMAIN}}"
  local canonical
  __dybatpho_i18n_normalize canonical "${locale}" \
    || dybatpho::die "${FUNCNAME[0]}: Not a locale: ${locale}"
  if [[ -n "${file}" ]]; then
    if ! dybatpho::is file "${file}"; then
      if dybatpho::is true "${DYBATPHO_I18N_STRICT}"; then
        dybatpho::die "${FUNCNAME[0]}: No such catalog: ${file}"
      fi
      dybatpho::error "${FUNCNAME[0]}: No such catalog: ${file}"
      return 1
    fi
    __dybatpho_i18n_load_file "${file}" "${canonical}"
    return 0
  fi
  local entry
  local -i found=0
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    __dybatpho_i18n_discover "${entry}" "${domain}" && found+=1
  done <<< "$(dybatpho::i18n_chain "${canonical}")"
  if ((found == 0)); then
    if dybatpho::is true "${DYBATPHO_I18N_STRICT}"; then
      dybatpho::die "${FUNCNAME[0]}: No catalog found for locale '${canonical}' in domain '${domain}'"
    fi
    dybatpho::debug "No catalog found for locale '${canonical}' in domain '${domain}'"
    return 1
  fi
  return 0
}

#######################################
# @description Resolve the locale and load its catalogs, once.
#   Call this in the shell the script runs in. Translation is normally used
#   inside a command substitution, which is a subshell, so a catalog loaded
#   there would be discarded the moment the substitution returned.
# @example
#   dybatpho::i18n_init
#   printf '%s\n' "$(dybatpho::i18n_t app.ready)"
#
# @arg $1 string Optional locale tag, default is resolved from the environment
# @arg $2 string Optional domain, default is `DYBATPHO_I18N_DOMAIN`
# @exitcode 0 Always in lenient mode, even when no catalog was found
#######################################
function dybatpho::i18n_init {
  local locale="${1-}"
  local domain="${2:-${DYBATPHO_I18N_DOMAIN}}"
  if [[ -n "${locale}" ]]; then
    dybatpho::i18n_set_locale "${locale}" || return 1
  fi
  locale="$(dybatpho::i18n_locale)"
  __dybatpho_i18n_seed_relative
  dybatpho::i18n_load "${locale}" "" "${domain}" || true
  __dybatpho_i18n_state[initialised]=1
  return 0
}

#######################################
# @description Print the locales that have a catalog somewhere on the search
#   path.
# @arg $1 string Optional domain, default is `DYBATPHO_I18N_DOMAIN`
# @stdout One locale tag per line, sorted
# @exitcode 1 No catalog was found anywhere
#######################################
function dybatpho::i18n_locales {
  local domain="${1:-${DYBATPHO_I18N_DOMAIN}}"
  local root entry base name
  local -A seen=()
  local i18n_roots_output
  i18n_roots_output=$(__dybatpho_i18n_roots)
  while IFS= read -r root || [[ -n "${root}" ]]; do
    [[ -n "${root}" ]] || continue
    dybatpho::is dir "${root}" || continue
    for entry in "${root}"/*; do
      base="$(dybatpho::path_basename "${entry}")"
      if dybatpho::is dir "${entry}"; then
        if dybatpho::is file "${entry}/LC_MESSAGES/${domain}.po" \
          || dybatpho::is file "${entry}/LC_MESSAGES/${domain}.msg" \
          || dybatpho::is file "${entry}/${domain}.po" \
          || dybatpho::is file "${entry}/${domain}.msg"; then
          seen["${base}"]=1
        fi
        continue
      fi
      case "${base}" in
        "${domain}".*.po | "${domain}".*.msg)
          name="${base#"${domain}".}"
          seen["${name%.*}"]=1
          ;;
        *.po | *.msg) seen["${base%.*}"]=1 ;;
        *) ;;
      esac
    done
  done < <(printf '%s' "${i18n_roots_output}")
  ((${#seen[@]} > 0)) || return 1
  # The sort runs under the C locale so that the list is identical on every
  # machine rather than following whatever collation the user happens to have.
  printf '%s\n' "${!seen[@]}" | LC_ALL=C sort
}

#######################################
# @description Read the first argument of a translation call, when it is a
#   literal this tool can be sure of.
#   A key assembled from a variable cannot be resolved by reading the source, so
#   it is reported rather than guessed at. That report is the point: it tells
#   the author exactly which call sites the tooling cannot see.
# @arg $1 string The text following the function name
# @arg $2 string Name of the variable that receives the key
# @arg $3 string Name of the variable that receives the remaining text
# @set The two named variables
# @exitcode 1 The argument is not a literal
# @internal
#######################################
function __dybatpho_i18n_literal {
  local __lit_text __lit_key_name __lit_rest_name
  __lit_text="$1"
  __lit_key_name="$2"
  __lit_rest_name="$3"
  local -n __lit_key="${__lit_key_name}"
  local -n __lit_rest="${__lit_rest_name}"
  __lit_key=""
  __lit_rest=""
  __lit_text="${__lit_text#"${__lit_text%%[![:space:]]*}"}"
  case "${__lit_text}" in
    "'"*)
      __lit_text="${__lit_text#\'}"
      [[ "${__lit_text}" == *"'"* ]] || return 1
      __lit_key="${__lit_text%%\'*}"
      __lit_rest="${__lit_text#*\'}"
      ;;
    '"'*)
      __lit_text="${__lit_text#\"}"
      [[ "${__lit_text}" == *'"'* ]] || return 1
      __lit_key="${__lit_text%%\"*}"
      __lit_rest="${__lit_text#*\"}"
      # A double-quoted key that expands something is not a constant.
      [[ "${__lit_key}" == *'$'* || "${__lit_key}" == *'`'* ]] && return 1
      ;;
    *)
      __lit_key="${__lit_text%%[[:space:]]*}"
      __lit_rest="${__lit_text#"${__lit_key}"}"
      [[ -n "${__lit_key}" ]] || return 1
      [[ "${__lit_key}" == *'$'* || "${__lit_key}" == *'`'* ]] && return 1
      [[ "${__lit_key}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.:/-]*$ ]] || return 1
      ;;
  esac
  return 0
}

#######################################
# @description Collect every translation key a set of sources refers to.
# @arg $1 string Name of the array that receives `<key>` and its kind
# @arg $@ string Files or directories to scan
# @set The named associative array, mapping key to `plain`, `plural`, or `both`
# @internal
#######################################
function __dybatpho_i18n_scan {
  local __scan_target
  __scan_target="$1"
  shift
  local -n __scan_out="${__scan_target}"
  local path file line call rest key kind
  local -a files=()
  for path in "$@"; do
    if dybatpho::is dir "${path}"; then
      local find_output
      local find_scripts
      find_scripts=$(find "${path}" -type f -name '*.sh' -o -type f -name '*.bash')
      find_output=$(printf '%s\n' "${find_scripts}" | LC_ALL=C sort)
      while IFS= read -r file || [[ -n "${file}" ]]; do
        files+=("${file}")
      done < <(printf '%s' "${find_output}")
    elif dybatpho::is file "${path}"; then
      files+=("${path}")
    else
      dybatpho::warn "${FUNCNAME[1]}: Cannot read '${path}'"
    fi
  done
  local -i number
  for file in ${files[@]+"${files[@]}"}; do
    number=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
      number+=1
      [[ "${line}" == *"dybatpho::i18n_t"* ]] || continue
      # The character before the call must not be part of an identifier, so a
      # function whose own name ends in these is not mistaken for one of them.
      [[ "${line}" =~ (^|[^A-Za-z0-9_:])dybatpho::(i18n_tn|i18n_tc|i18n_t)[[:space:]]+(.*)$ ]] || continue
      call="${BASH_REMATCH[2]}"
      rest="${BASH_REMATCH[3]}"
      local context=""
      if [[ "${call}" == "i18n_tc" ]]; then
        # The context is the first argument, so it is read before the key and
        # kept, because the pair is what identifies the message.
        __dybatpho_i18n_literal "${rest}" context rest || {
          dybatpho::warn "${file}:${number}: context is not a literal, not extracted"
          continue
        }
      fi
      if ! __dybatpho_i18n_literal "${rest}" key rest; then
        dybatpho::warn "${file}:${number}: key is not a literal, not extracted"
        continue
      fi
      [[ -n "${context}" ]] && key="${context}${__DYBATPHO_I18N_CTX}${key}"
      kind="plain"
      [[ "${call}" == "i18n_tn" ]] && kind="plural"
      if [[ -n "${__scan_out[${key}]-}" && "${__scan_out[${key}]}" != "${kind}" ]]; then
        kind="both"
      fi
      __scan_out["${key}"]="${kind}"
    done < "${file}"
  done
}

#######################################
# @description Write a catalog template covering every key a source tree
#   refers to, so a translator has something to fill in rather than a blank file.
# @example
#   dybatpho::i18n_extract --locale vi_VN src/ bin/ > locale/vi_VN.msg
#
# @arg $1 string Options: `--locale <tag>`, `--format msg|po`, `--output <file>`
# @arg $@ string Files or directories to scan
# @stdout The template, unless `--output` was given
# @stderr One warning per call site whose key could not be read
# @exitcode 1 No keys were found
#######################################
function dybatpho::i18n_extract {
  local locale="" format="msg" output=""
  local -a sources=()
  while (($# > 0)); do
    case "$1" in
      --locale)
        locale="${2-}"
        shift 2
        ;;
      --format)
        format="${2-}"
        shift 2
        ;;
      --output)
        output="${2-}"
        shift 2
        ;;
      --)
        shift
        sources+=("$@")
        break
        ;;
      -*) dybatpho::die "${FUNCNAME[0]}: Unknown option '$1'" ;;
      *)
        sources+=("$1")
        shift
        ;;
    esac
  done
  ((${#sources[@]} > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Give at least one file or directory to scan"
  [[ "${format}" == "msg" || "${format}" == "po" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Format must be msg or po, got '${format}'"
  [[ -n "${locale}" ]] || locale="$(dybatpho::i18n_locale)"

  local -A found=()
  __dybatpho_i18n_scan found "${sources[@]}"
  ((${#found[@]} > 0)) || {
    dybatpho::warn "${FUNCNAME[0]}: No translation keys found"
    return 1
  }

  local language family
  language="$(__dybatpho_i18n_language "${locale}")"
  family="${__dybatpho_i18n_plural_family[${language}]-one}"
  local -a categories=()
  read -r -a categories <<< "${__dybatpho_i18n_po_order[${family}]-one other}"

  local rendered="" key kind category
  local -i index
  if [[ "${format}" == "msg" ]]; then
    rendered+="# Generated by dybatpho::i18n_extract"$'\n'
    rendered+="@locale = ${locale}"$'\n'
    rendered+=$'\n'
  else
    rendered+="msgid \"\""$'\n'
    rendered+="msgstr \"\""$'\n'
    rendered+="\"Language: ${locale}\\n\""$'\n'
    rendered+="\"Plural-Forms: nplurals=${#categories[@]};\\n\""$'\n'
    rendered+=$'\n'
  fi
  # Sorted under the C locale so the template is byte identical everywhere and
  # a regenerated file diffs cleanly.
  local context bare written_context=""
  local printf_output
  printf_output=$(printf '%s\n' "${!found[@]}" | LC_ALL=C sort)
  while IFS= read -r key || [[ -n "${key}" ]]; do
    kind="${found[${key}]}"
    context=""
    bare="${key}"
    if [[ "${key}" == *"${__DYBATPHO_I18N_CTX}"* ]]; then
      context="${key%%"${__DYBATPHO_I18N_CTX}"*}"
      bare="${key#*"${__DYBATPHO_I18N_CTX}"}"
    fi
    if [[ "${format}" == "msg" ]]; then
      # Entries are already sorted, so keys sharing a context are adjacent and
      # one directive covers the run of them.
      if [[ "${context}" != "${written_context}" ]]; then
        rendered+="@context = ${context}"$'\n'
        written_context="${context}"
      fi
      # A key that is a whole sentence, or that would otherwise be read as a
      # directive, is written quoted.
      local shown="${bare}"
      if [[ "${bare}" =~ [[:space:]=\"] || "${bare}" == @* || "${bare}" == \#* ]]; then
        shown="\"${bare}\""
      fi
      if [[ "${kind}" == "plain" || "${kind}" == "both" ]]; then
        rendered+="${shown} ="$'\n'
      fi
      if [[ "${kind}" == "plural" || "${kind}" == "both" ]]; then
        for category in "${categories[@]}"; do
          rendered+="${shown}[${category}] ="$'\n'
        done
      fi
    else
      [[ -n "${context}" ]] && rendered+="msgctxt \"${context}\""$'\n'
      rendered+="msgid \"${bare}\""$'\n'
      if [[ "${kind}" == "plain" ]]; then
        rendered+="msgstr \"\""$'\n'
      else
        rendered+="msgid_plural \"${bare}\""$'\n'
        for ((index = 0; index < ${#categories[@]}; index++)); do
          rendered+="msgstr[${index}] \"\""$'\n'
        done
      fi
    fi
    rendered+=$'\n'
  done < <(printf '%s' "${printf_output}")

  if [[ -n "${output}" ]]; then
    printf '%s' "${rendered}" | dybatpho::file_write_atomic "${output}"
  else
    printf '%s' "${rendered}"
  fi
  return 0
}

#######################################
# @description Print the placeholders a template uses, one per line, sorted.
# @arg $1 string Template
# @stdout Placeholder names
# @internal
#######################################
function __dybatpho_i18n_placeholders {
  local template="$1"
  local -A seen=()
  local rest="${template}" name
  while [[ "${rest}" == *'{'* ]]; do
    rest="${rest#*\{}"
    if [[ "${rest}" == '{'* ]]; then
      rest="${rest#\{}"
      continue
    fi
    [[ "${rest}" == *'}'* ]] || break
    name="${rest%%\}*}"
    if [[ "${name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      seen["${name}"]=1
    fi
    rest="${rest#*\}}"
  done
  ((${#seen[@]} > 0)) || return 0
  printf '%s\n' "${!seen[@]}" | LC_ALL=C sort
}

#######################################
# @description Compare a locale's catalog against a reference one and report
#   what a translator still has to do.
#   The placeholder check is the one worth running in continuous integration: a
#   translation that dropped `{count}` looks perfectly fine until the moment it
#   is rendered.
# @example
#   dybatpho::i18n_lint --reference en vi_VN || exit 1
#
# @arg $1 string Options: `--reference <tag>`, `--format text|tsv`
# @arg $@ string Locales to check, default is every locale with a catalog
# @stdout One finding per line: the locale, the kind, the key, and any detail
# @exitcode 1 At least one finding was reported
#######################################
function dybatpho::i18n_lint {
  local reference="" format="text"
  local -a targets=()
  while (($# > 0)); do
    case "$1" in
      --reference)
        reference="${2-}"
        shift 2
        ;;
      --format)
        format="${2-}"
        shift 2
        ;;
      --)
        shift
        targets+=("$@")
        break
        ;;
      -*) dybatpho::die "${FUNCNAME[0]}: Unknown option '$1'" ;;
      *)
        targets+=("$1")
        shift
        ;;
    esac
  done
  [[ "${format}" == "text" || "${format}" == "tsv" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Format must be text or tsv, got '${format}'"
  [[ -n "${reference}" ]] || reference="${DYBATPHO_I18N_FALLBACK}"
  local line
  if ((${#targets[@]} == 0)); then
    while IFS= read -r line; do
      [[ -n "${line}" && "${line}" != "${reference}" ]] && targets+=("${line}")
    done < <(dybatpho::i18n_locales || true)
  fi
  ((${#targets[@]} > 0)) || {
    dybatpho::warn "${FUNCNAME[0]}: No locales to check"
    return 0
  }

  local -A reference_keys=()
  local slot key locale
  for slot in "${!__dybatpho_i18n_msg[@]}"; do
    [[ "${slot}" == "${reference}${__DYBATPHO_I18N_US}"* ]] || continue
    reference_keys["${slot#*"${__DYBATPHO_I18N_US}"}"]=1
  done
  for slot in "${!__dybatpho_i18n_plural[@]}"; do
    [[ "${slot}" == "${reference}${__DYBATPHO_I18N_US}"* ]] || continue
    key="${slot#*"${__DYBATPHO_I18N_US}"}"
    reference_keys["${key%"${__DYBATPHO_I18N_US}"*}"]=1
  done

  local -i findings=0
  local detail reference_text target_text reference_marks target_marks category
  for locale in "${targets[@]}"; do
    local printf_output
    printf_output=$(printf '%s\n' "${!reference_keys[@]}" | LC_ALL=C sort)
    while IFS= read -r key || [[ -n "${key}" ]]; do
      [[ -n "${key}" ]] || continue
      reference_text="${__dybatpho_i18n_msg[${reference}${__DYBATPHO_I18N_US}${key}]-${__DYBATPHO_I18N_NONE}}"
      target_text="${__dybatpho_i18n_msg[${locale}${__DYBATPHO_I18N_US}${key}]-${__DYBATPHO_I18N_NONE}}"
      if [[ "${target_text}" == "${__DYBATPHO_I18N_NONE}" ]]; then
        # A key carried only as plural forms is not missing just because it has
        # no plain form, so the plural table is consulted before reporting.
        local has_plural=0
        for category in zero one two few many other; do
          local plural_key="${locale}${__DYBATPHO_I18N_US}${key}${__DYBATPHO_I18N_US}${category}"
          if [[ -n "${__dybatpho_i18n_plural[${plural_key}]+set}" ]]; then
            has_plural=1
            break
          fi
        done
        if ((has_plural == 0)); then
          __dybatpho_i18n_finding "${format}" "${locale}" missing "${key}" ""
          findings+=1
          continue
        fi
      fi
      if [[ "${target_text}" != "${__DYBATPHO_I18N_NONE}" && -z "${target_text}" ]]; then
        __dybatpho_i18n_finding "${format}" "${locale}" empty "${key}" ""
        findings+=1
        continue
      fi
      if [[ "${reference_text}" != "${__DYBATPHO_I18N_NONE}" &&
        "${target_text}" != "${__DYBATPHO_I18N_NONE}" ]]; then
        local i18n_placeholders_2
        i18n_placeholders_2=$(__dybatpho_i18n_placeholders "${reference_text}" | tr '\n' ' ')
        reference_marks="${i18n_placeholders_2}"
        local i18n_placeholders
        i18n_placeholders=$(__dybatpho_i18n_placeholders "${target_text}" | tr '\n' ' ')
        target_marks="${i18n_placeholders}"
        if [[ "${reference_marks}" != "${target_marks}" ]]; then
          detail="reference={${reference_marks% }} target={${target_marks% }}"
          __dybatpho_i18n_finding "${format}" "${locale}" placeholder "${key}" "${detail}"
          findings+=1
        fi
      fi
    done < <(printf '%s' "${printf_output}")
  done
  ((findings == 0))
}

#######################################
# @description Print one lint finding in the requested shape.
# @arg $1 string Format, `text` or `tsv`
# @arg $2 string Locale
# @arg $3 string Finding kind
# @arg $4 string Message key
# @arg $5 string Optional detail
# @stdout The finding
# @internal
#######################################
function __dybatpho_i18n_finding {
  local format locale kind key detail
  format="$1"
  locale="$2"
  kind="$3"
  key="$4"
  detail="${5-}"
  if [[ "${format}" == "tsv" ]]; then
    printf '%s\t%s\t%s\t%s\n' "${locale}" "${kind}" "${key}" "${detail}"
  else
    # Padded with printf rather than through the table module, so that wanting
    # translations never drags a formatting module into the dependency graph.
    printf '%-10s %-12s %-28s %s\n' "${locale}" "${kind}" "${key}" "${detail}"
  fi
}
