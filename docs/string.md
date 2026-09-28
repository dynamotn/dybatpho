# string.sh

Utilities for working with string

> 🧭 Source: [src/string.sh](../src/string.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for trimming, splitting, matching, replacing,
trimming exact prefixes/suffixes and characters, slugifying, truncating,
counting lines, testing blank strings, wrapping text, repeating, padding,
encoding, decoding, and case-converting shell strings.

The naming-convention helpers convert between `snake_case`, `kebab-case`,
`camelCase`, and `PascalCase`, reading the word boundaries whichever
convention the input arrived in. `dybatpho::string_quote` prepares a value
to be written into shell code that will be evaluated later.

### 🚀 Highlights

- [`dybatpho::trim`](#dybatphotrim) — Trim leading and trailing whitespace from a string.
- [`dybatpho::split`](#dybatphosplit) — Split a string on an exact delimiter. The delimiter is matched literally, never as a glob pattern, so `*`, `?` and `[` are ordinary characters in it. An empty delimiter prints the input unchanged. A run of `n` delimiters yields `n + 1` fields, including the empty ones at either end: splitting `a,b,,` on `,` gives `a`, `b`, an empty field and a trailing empty field. Consumers that do not want the empty fields drop them themselves, because only the caller knows whether an empty field is data.
- [`dybatpho::string_starts_with`](#dybatphostring_starts_with) — Return success when a string starts with the given prefix.
- [`dybatpho::string_ends_with`](#dybatphostring_ends_with) — Return success when a string ends with the given suffix.
- [`dybatpho::string_contains`](#dybatphostring_contains) — Return success when a string contains the given substring.
- [`dybatpho::string_replace`](#dybatphostring_replace) — Replace all exact substring matches in a string.
- [`dybatpho::string_trim_prefix`](#dybatphostring_trim_prefix) — Remove an exact prefix from a string when it matches.
- [`dybatpho::string_trim_suffix`](#dybatphostring_trim_suffix) — Remove an exact suffix from a string when it matches.
- [`__dybatpho_string_build_ascii`](#__dybatpho_string_build_ascii) — Fill the transliteration table, once, when the module loads.
- [`dybatpho::string_slugify`](#dybatphostring_slugify) — Convert a string into a lowercase ASCII slug. A letter carrying a diacritic becomes the ASCII letter underneath it, so `Thế Giới` slugs to `the-gioi` rather than to `th-gi-i`. Anything else outside `a-z0-9` is a separator, and a run of separators collapses into a single `-`.
- [`dybatpho::string_is_blank`](#dybatphostring_is_blank) — Return success when a string is empty or contains only whitespace.
- [`dybatpho::string_trim_chars`](#dybatphostring_trim_chars) — Trim a set of exact characters from both ends of a string.
- [`dybatpho::string_truncate`](#dybatphostring_truncate) — Truncate a string to a maximum width and append a suffix when needed.
- [`dybatpho::string_lines`](#dybatphostring_lines) — Count the number of logical lines in a string.
- [`dybatpho::string_wrap`](#dybatphostring_wrap) — Wrap a string to a maximum width, normalizing whitespace between words.
- [`dybatpho::string_repeat`](#dybatphostring_repeat) — Repeat a string a fixed number of times.
- [`dybatpho::string_pad`](#dybatphostring_pad) — Pad a string on the right to a minimum width.
- [`dybatpho::url_encode`](#dybatphourl_encode) — URL-encode a string.
- [`dybatpho::url_decode`](#dybatphourl_decode) — URL-decode a string.
- [`dybatpho::lower`](#dybatpholower) — Convert a string to lowercase.
- [`dybatpho::upper`](#dybatphoupper) — Convert a string to uppercase.
- [`__dybatpho_string_words`](#__dybatpho_string_words) — Split a string into the words its naming convention implies. Every case helper in this module goes through here, so they all accept the same input whatever convention it arrived in: `fooBar`, `foo_bar`, `foo-bar`, `Foo Bar` and `FOO_BAR` all give the same two words. A capital opens a new word after a lowercase letter or a digit, and at the end of a run of capitals that is followed by a lowercase one, which is what keeps `XMLHttpRequest` reading as `xml http request` rather than as one word or as one letter per word. A digit stays attached to the word it follows, so `foo2bar` is one word: splitting there would be guessing. The cost of that acronym rule is single-letter words: `ABC` reads as one word, because nothing in it says whether it was an acronym or `a b c`. A name that went through `dybatpho::string_to_pascal` as `a_b_c` does not come back. There is no rule that gets both cases right, and acronyms are the ones that turn up in real names.
- [`dybatpho::string_to_snake`](#dybatphostring_to_snake) — Convert a string to `snake_case`.
- [`dybatpho::string_to_kebab`](#dybatphostring_to_kebab) — Convert a string to `kebab-case`. Unlike `dybatpho::string_slugify`, this reads the word boundaries a naming convention implies, so `XMLHttpRequest` becomes `xml-http-request` rather than `xmlhttprequest`. Slugify is for prose; this is for identifiers.
- [`dybatpho::string_to_camel`](#dybatphostring_to_camel) — Convert a string to `camelCase`.
- [`dybatpho::string_to_pascal`](#dybatphostring_to_pascal) — Convert a string to `PascalCase`.
- [`dybatpho::string_quote`](#dybatphostring_quote) — Quote a string so the shell reads it back as one literal value. This is what to reach for when a value is going into generated shell code: a completion script, a `--command` argument, or anything that will be evaluated later. Writing the value in by hand leaves whitespace, quotes and `$` to be read as syntax rather than as data. The empty string quotes to `''` rather than to nothing, which is the whole point: an unquoted empty value disappears from the command it was part of.

<a id="see-also"></a>
## 🔗 See also

- [example/string_ops.sh](../example/string_ops.sh)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::trim`

Trim leading and trailing whitespace from a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to trim |

**📤 Output on stdout**

- Trimmed string


---

### `dybatpho::split`

Split a string on an exact delimiter.
The delimiter is matched literally, never as a glob pattern, so `*`, `?`
and `[` are ordinary characters in it. An empty delimiter prints the input
unchanged.

A run of `n` delimiters yields `n + 1` fields, including the empty ones at
either end: splitting `a,b,,` on `,` gives `a`, `b`, an empty field and a
trailing empty field. Consumers that do not want the empty fields drop them
themselves, because only the caller knows whether an empty field is data.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to split |
| `$2` | string | Delimiter string |

**📤 Output on stdout**

- Print each split part on its own line


---

### `dybatpho::string_starts_with`

Return success when a string starts with the given prefix.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Prefix to match |

**🚦 Exit codes**

- `0`: The input starts with the prefix
- `1`: The input does not start with the prefix


---

### `dybatpho::string_ends_with`

Return success when a string ends with the given suffix.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Suffix to match |

**🚦 Exit codes**

- `0`: The input ends with the suffix
- `1`: The input does not end with the suffix


---

### `dybatpho::string_contains`

Return success when a string contains the given substring.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Substring to match |

**🚦 Exit codes**

- `0`: The input contains the substring
- `1`: The input does not contain the substring


---

### `dybatpho::string_replace`

Replace all exact substring matches in a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Substring to replace |
| `$3` | string | Replacement text |

**📤 Output on stdout**

- String with all matches replaced


---

### `dybatpho::string_trim_prefix`

Remove an exact prefix from a string when it matches.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Prefix to remove |

**📤 Output on stdout**

- String without the matching prefix, or the original string


---

### `dybatpho::string_trim_suffix`

Remove an exact suffix from a string when it matches.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Suffix to remove |

**📤 Output on stdout**

- String without the matching suffix, or the original string


---

### `__dybatpho_string_build_ascii`

Fill the transliteration table, once, when the module loads.

**🧩 Variable sets**

- __DYBATPHO_STRING_ASCII


---

### `dybatpho::string_slugify`

Convert a string into a lowercase ASCII slug.
A letter carrying a diacritic becomes the ASCII letter underneath it, so
`Thế Giới` slugs to `the-gioi` rather than to `th-gi-i`. Anything else
outside `a-z0-9` is a separator, and a run of separators collapses into a
single `-`.

**🧪 Example**

```bash
dybatpho::string_slugify "Thế Giới"   # the-gioi
dybatpho::string_slugify "Crème brûlée 2024" # creme-brulee-2024

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |

**📝 Notes**

- The input is walked character by character, so a locale that reports UTF-8 text as single bytes (`LC_ALL=C`) transliterates nothing

**📤 Output on stdout**

- Slugified string


---

### `dybatpho::string_is_blank`

Return success when a string is empty or contains only whitespace.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |

**🚦 Exit codes**

- `0`: The input is blank
- `1`: The input contains non-whitespace characters


---

### `dybatpho::string_trim_chars`

Trim a set of exact characters from both ends of a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | string | Characters to trim |

**📤 Output on stdout**

- Trimmed string


---

### `dybatpho::string_truncate`

Truncate a string to a maximum width and append a suffix when needed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | number | Maximum width |
| `$3` | string | Optional truncation suffix, default is `...` |

**📤 Output on stdout**

- Truncated string


---

### `dybatpho::string_lines`

Count the number of logical lines in a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |

**📤 Output on stdout**

- Number of lines


---

### `dybatpho::string_wrap`

Wrap a string to a maximum width, normalizing whitespace between words.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | number | Maximum width |
| `$3` | string | Optional indent prefix for wrapped continuation lines |

**📤 Output on stdout**

- Wrapped lines


---

### `dybatpho::string_repeat`

Repeat a string a fixed number of times.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | number | Repeat count |

**📤 Output on stdout**

- Repeated string


---

### `dybatpho::string_pad`

Pad a string on the right to a minimum width.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |
| `$2` | number | Minimum width |
| `$3` | string | Optional padding token, default is a space |

**📤 Output on stdout**

- Padded string


---

### `dybatpho::url_encode`

URL-encode a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to encode |

**📤 Output on stdout**

- Encoded string


---

### `dybatpho::url_decode`

URL-decode a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to decode |

**📤 Output on stdout**

- Decoded string


---

### `dybatpho::lower`

Convert a string to lowercase.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- Converted string


---

### `dybatpho::upper`

Convert a string to uppercase.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- Converted string


---

### `__dybatpho_string_words`

Split a string into the words its naming convention implies.
Every case helper in this module goes through here, so they all accept the
same input whatever convention it arrived in: `fooBar`, `foo_bar`,
`foo-bar`, `Foo Bar` and `FOO_BAR` all give the same two words.

A capital opens a new word after a lowercase letter or a digit, and at the
end of a run of capitals that is followed by a lowercase one, which is what
keeps `XMLHttpRequest` reading as `xml http request` rather than as one
word or as one letter per word. A digit stays attached to the word it
follows, so `foo2bar` is one word: splitting there would be guessing.

The cost of that acronym rule is single-letter words: `ABC` reads as one
word, because nothing in it says whether it was an acronym or `a b c`. A
name that went through `dybatpho::string_to_pascal` as `a_b_c` does not come
back. There is no rule that gets both cases right, and acronyms are the ones
that turn up in real names.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to split |
| `$2` | string | Name of the array variable receiving the lower-cased words |

**🧩 Variable sets**

- **`The`** (named): array


---

### `dybatpho::string_to_snake`

Convert a string to `snake_case`.

**🧪 Example**

```bash
dybatpho::string_to_snake "XMLHttpRequest"   # xml_http_request
dybatpho::string_to_snake "deploy-to-prod"   # deploy_to_prod

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- The string in snake case, empty when it holds no letters or digits

**🔗 See also**

- [- `dybatpho::string_to_kebab` - `dybatpho::string_slugify](#dybatphostring_to_kebab-dybatphostring_slugify)


---

### `dybatpho::string_to_kebab`

Convert a string to `kebab-case`.
Unlike `dybatpho::string_slugify`, this reads the word boundaries a naming
convention implies, so `XMLHttpRequest` becomes `xml-http-request` rather
than `xmlhttprequest`. Slugify is for prose; this is for identifiers.

**🧪 Example**

```bash
dybatpho::string_to_kebab "XMLHttpRequest"   # xml-http-request
dybatpho::string_to_kebab "deploy_to_prod"   # deploy-to-prod

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- The string in kebab case, empty when it holds no letters or digits

**🔗 See also**

- [- `dybatpho::string_to_snake` - `dybatpho::string_slugify](#dybatphostring_to_snake-dybatphostring_slugify)


---

### `dybatpho::string_to_camel`

Convert a string to `camelCase`.

**🧪 Example**

```bash
dybatpho::string_to_camel "deploy_to_prod"   # deployToProd
dybatpho::string_to_camel "XMLHttpRequest"   # xmlHttpRequest

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- The string in camel case, empty when it holds no letters or digits

**🔗 See also**

- [- `dybatpho::string_to_pascal](#dybatphostring_to_pascal)


---

### `dybatpho::string_to_pascal`

Convert a string to `PascalCase`.

**🧪 Example**

```bash
dybatpho::string_to_pascal "deploy_to_prod"   # DeployToProd

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- The string in Pascal case, empty when it holds no letters or digits

**🔗 See also**

- [- `dybatpho::string_to_camel](#dybatphostring_to_camel)


---

### `dybatpho::string_quote`

Quote a string so the shell reads it back as one literal value.
This is what to reach for when a value is going into generated shell code:
a completion script, a `--command` argument, or anything that will be
evaluated later. Writing the value in by hand leaves whitespace, quotes and
`$` to be read as syntax rather than as data.

The empty string quotes to `''` rather than to nothing, which is the whole
point: an unquoted empty value disappears from the command it was part of.

**🧪 Example**

```bash
dybatpho::string_quote "a b"          # a\ b
dybatpho::string_quote ""             # ''
printf 'ssh host %s\n' "$(dybatpho::string_quote "${remote_command}")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to quote |

**📤 Output on stdout**

- The value quoted for the shell
