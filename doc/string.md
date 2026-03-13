# string.sh

Utilities for working with string

> 🧭 Source: [src/string.sh](../src/string.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

## ✨ Overview

This module contains helpers for trimming, splitting, encoding, decoding,
and case-converting shell strings.

### 🚀 Highlights

- [`dybatpho::trim`](#dybatphotrim) — Trim leading and trailing whitespace from a string.
- [`dybatpho::split`](#dybatphosplit) — Split a string on an exact delimiter.
- [`dybatpho::url_encode`](#dybatphourl_encode) — URL-encode a string.
- [`dybatpho::url_decode`](#dybatphourl_decode) — URL-decode a string.
- [`dybatpho::lower`](#dybatpholower) — Convert a string to lowercase.
- [`dybatpho::upper`](#dybatphoupper) — Convert a string to uppercase.

## 🔗 See also

- [example/string_ops.sh](../example/string_ops.sh)

## 📚 Reference

### `dybatpho::trim`

Trim leading and trailing whitespace from a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to trim |

**📤 Output on stdout**

- Trimmed string


### `dybatpho::split`

Split a string on an exact delimiter.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to split |
| `$2` | string | Delimiter string |

**📤 Output on stdout**

- Print each split part on its own line


### `dybatpho::url_encode`

URL-encode a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to encode |

**📤 Output on stdout**

- Encoded string


### `dybatpho::url_decode`

URL-decode a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to decode |

**📤 Output on stdout**

- Decoded string


### `dybatpho::lower`

Convert a string to lowercase.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- Converted string


### `dybatpho::upper`

Convert a string to uppercase.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String to convert |

**📤 Output on stdout**

- Converted string

