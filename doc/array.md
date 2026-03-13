# array.sh

Utilities for working with array

> 🧭 Source: [src/array.sh](../src/array.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for printing, reversing, deduplicating,
compacting, filtering, mapping, rejecting, finding values, checking
membership, checking every/some values, finding positions, and joining Bash
arrays by name.

### 🚀 Highlights

- [`dybatpho::array_print`](#dybatphoarray_print) — Print each element of an array on its own line.
- [`dybatpho::array_reverse`](#dybatphoarray_reverse) — Reverse an array in place.
- [`dybatpho::array_unique`](#dybatphoarray_unique) — Remove duplicate elements from an array in place.
- [`dybatpho::array_contains`](#dybatphoarray_contains) — Return success when an array contains the given element.
- [`dybatpho::array_index_of`](#dybatphoarray_index_of) — Print the first index of an array element that matches exactly.
- [`dybatpho::array_compact`](#dybatphoarray_compact) — Remove empty-string elements from an array in place.
- [`dybatpho::array_filter`](#dybatphoarray_filter) — Keep only array elements accepted by a predicate function.
- [`dybatpho::array_map`](#dybatphoarray_map) — Transform each array element with a mapper function.
- [`dybatpho::array_find`](#dybatphoarray_find) — Print the first array element accepted by a predicate function.
- [`dybatpho::array_every`](#dybatphoarray_every) — Return success when every array element is accepted by a predicate function.
- [`dybatpho::array_some`](#dybatphoarray_some) — Return success when at least one array element is accepted by a predicate function.
- [`dybatpho::array_reject`](#dybatphoarray_reject) — Keep only array elements rejected by a predicate function.
- [`dybatpho::array_first`](#dybatphoarray_first) — Print the first element of an array.
- [`dybatpho::array_last`](#dybatphoarray_last) — Print the last element of an array.
- [`dybatpho::array_join`](#dybatphoarray_join) — Join array elements with a separator into one string.

<a id="see-also"></a>
## 🔗 See also

- [example/array_ops.sh](../example/array_ops.sh)

<a id="reference"></a>
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

### `dybatpho::array_contains`

Return success when an array contains the given element.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Element to search for |

**🚦 Exit codes**

- `0`: The element exists in the array
- `1`: The element does not exist in the array


---

### `dybatpho::array_index_of`

Print the first index of an array element that matches exactly.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Element to search for |

**📤 Output on stdout**

- First matching index

**🚦 Exit codes**

- `0`: A matching element is found
- `1`: No matching element is found


---

### `dybatpho::array_compact`

Remove empty-string elements from an array in place.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the compacted array if $2 is `--`


---

### `dybatpho::array_filter`

Keep only array elements accepted by a predicate function.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Predicate function name, called with each element |
| `$3` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the filtered array if $3 is `--`


---

### `dybatpho::array_map`

Transform each array element with a mapper function.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Mapper function name, called with each element |
| `$3` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the mapped array if $3 is `--`


---

### `dybatpho::array_find`

Print the first array element accepted by a predicate function.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Predicate function name, called with each element |

**📤 Output on stdout**

- First matching array element

**🚦 Exit codes**

- `0`: A matching element is found
- `1`: No matching element is found


---

### `dybatpho::array_every`

Return success when every array element is accepted by a predicate function.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Predicate function name, called with each element |

**🚦 Exit codes**

- `0`: Every element matches, or the array is empty
- `1`: At least one element does not match


---

### `dybatpho::array_some`

Return success when at least one array element is accepted by a predicate function.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Predicate function name, called with each element |

**🚦 Exit codes**

- `0`: At least one element matches
- `1`: No elements match


---

### `dybatpho::array_reject`

Keep only array elements rejected by a predicate function.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | string | Predicate function name, called with each element |
| `$3` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the rejected array if $3 is `--`


---

### `dybatpho::array_first`

Print the first element of an array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |

**📤 Output on stdout**

- First array element

**🚦 Exit codes**

- `0`: The array contains at least one element
- `1`: The array is empty


---

### `dybatpho::array_last`

Print the last element of an array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |

**📤 Output on stdout**

- Last array element

**🚦 Exit codes**

- `0`: The array contains at least one element
- `1`: The array is empty


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

