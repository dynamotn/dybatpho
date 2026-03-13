# array.sh

Utilities for working with array

> 🧭 Source: [src/array.sh](../src/array.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

## ✨ Overview

This module contains helpers for printing, reversing, deduplicating, and
joining Bash arrays by name.

### 🚀 Highlights

- [`dybatpho::array_print`](#dybatphoarray_print) — Print each element of an array on its own line.
- [`dybatpho::array_reverse`](#dybatphoarray_reverse) — Reverse an array in place.
- [`dybatpho::array_unique`](#dybatphoarray_unique) — Remove duplicate elements from an array in place.
- [`dybatpho::array_join`](#dybatphoarray_join) — Join array elements with a separator into one string.

## 🔗 See also

- [example/array_ops.sh](../example/array_ops.sh)

## 📚 Reference

### `dybatpho::array_print`

Print each element of an array on its own line.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |

**📤 Output on stdout**

- Print array with each element separated by newline


---

### `dybatpho::array_reverse`

Reverse an array in place.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the reversed array if $2 is `--`


---

### `dybatpho::array_unique`

Remove duplicate elements from an array in place.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the deduplicated array if $2 is `--`


---

### `dybatpho::array_join`

Join array elements with a separator into one string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Separator |

**📤 Output on stdout**

- Print outputted string

