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

### 🚀 Highlights

- [`dybatpho::trim`](#dybatphotrim) — Trim leading and trailing whitespace from a string.
- [`dybatpho::split`](#dybatphosplit) — Split a string on an exact delimiter.
- [`dybatpho::string_starts_with`](#dybatphostring_starts_with) — Return success when a string starts with the given prefix.
- [`dybatpho::string_ends_with`](#dybatphostring_ends_with) — Return success when a string ends with the given suffix.
- [`dybatpho::string_contains`](#dybatphostring_contains) — Return success when a string contains the given substring.
- [`dybatpho::string_replace`](#dybatphostring_replace) — Replace all exact substring matches in a string.
- [`dybatpho::string_trim_prefix`](#dybatphostring_trim_prefix) — Remove an exact prefix from a string when it matches.
- [`dybatpho::string_trim_suffix`](#dybatphostring_trim_suffix) — Remove an exact suffix from a string when it matches.
- [`dybatpho::string_slugify`](#dybatphostring_slugify) — Convert a string into a lowercase ASCII slug.
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

### `dybatpho::string_slugify`

Convert a string into a lowercase ASCII slug.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input string |

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

