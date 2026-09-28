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
arrays by name. It also sorts and slices them, and treats them as sets for
union, intersection, and difference.


Every helper takes an array by name and changes it in place, with a final
`--` to print the result as well.

### 🚀 Highlights

- [`dybatpho::array_print`](#dybatphoarray_print) — Print each element of an array on its own line.
- [`dybatpho::array_reverse`](#dybatphoarray_reverse) — Reverse an array in place.
- [`dybatpho::array_unique`](#dybatphoarray_unique) — Remove duplicate elements from an array in place, keeping the first occurrence of each value. The surviving elements stay in the order they arrived in, which is what `dybatpho::array_union` already does and what a caller deduplicating a list of hosts or services expects to print. An earlier version collected the values as the keys of an associative array and handed back whatever order Bash happened to hash them into, so `1 2 3 4 5` came out as `5 4 3 2 1` and the order changed with the contents. Empty elements are dropped, as before.
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
- [`__dybatpho_array_copy`](#__dybatpho_array_copy) — Copy the values of one array into another. Bash 4.3 treats `"${empty[@]}"` as unset under `nounset`, so every copy in this module goes through the length check here rather than repeating it.
- [`__dybatpho_array_index`](#__dybatpho_array_index) — Build a lookup of the values an array holds.
- [`__dybatpho_array_sorts_after`](#__dybatpho_array_sorts_after) — Return success when one value must sort after another.
- [`__dybatpho_array_merge_sort`](#__dybatpho_array_merge_sort) — Sort an array of values in place, bottom-up and stable. Runs of length one are already sorted, so the passes start by merging pairs of them and double the run length until one run covers everything. That is `n log n` comparisons instead of the `n²` an insertion sort pays, and the comparison stays in `__dybatpho_array_sorts_after` so text, numeric and reversed order are all decided in one place. The merge takes the left run whenever the two compare equal, which is what makes the sort stable.
- [`dybatpho::array_sort`](#dybatphoarray_sort) — Sort an array in place. Text is ordered by the current locale's collation, the same rule `sort` follows, so a script that needs one fixed order everywhere sets `LC_ALL` as it would for `sort`. `--numeric` compares values as numbers, which is the reason a shell script wants a sort at all: as text, `10` comes before `9`. It takes integers, negative ones included, and stops the script on anything else rather than quietly ordering it as text. The sort is a bottom-up merge sort rather than a pipe through `sort(1)`: it keeps an element containing a newline intact and needs no external command. It is also stable, so values that compare equal stay in the order they arrived in. The insertion sort it replaces cost a comparison per pair and took ~39s over 2000 elements, which is a size a list of files or packages reaches without trying.
- [`dybatpho::array_slice`](#dybatphoarray_slice) — Keep a run of an array in place and drop the rest. A negative start counts back from the end, so `-2` takes the last two elements without the caller working out the length first. A start past either end leaves an empty array rather than failing: asking for elements that are not there is a shape the data can have, not a mistake in the call.
- [`dybatpho::array_union`](#dybatphoarray_union) — Replace an array with the union of it and another, in place. The result is a set: every value appears once, in the order it was first seen, the first array's values ahead of the second's. A set operation that kept duplicates would not be one, so `dybatpho::array_unique` afterwards has nothing left to do.
- [`dybatpho::array_intersect`](#dybatphoarray_intersect) — Keep only the values an array shares with another, in place. The result is a set, in the order the first array had them.
- [`dybatpho::array_difference`](#dybatphoarray_difference) — Drop the values an array shares with another, in place. The result is a set, in the order the first array had them. The operation is one-sided: values only the second array holds are not added.

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

Remove duplicate elements from an array in place, keeping the
  first occurrence of each value.


  The surviving elements stay in the order they arrived in, which is what
  `dybatpho::array_union` already does and what a caller deduplicating a list
  of hosts or services expects to print. An earlier version collected the
  values as the keys of an associative array and handed back whatever order
  Bash happened to hash them into, so `1 2 3 4 5` came out as `5 4 3 2 1` and
  the order changed with the contents.


  Empty elements are dropped, as before.

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


---

### `__dybatpho_array_copy`

Copy the values of one array into another.
  Bash 4.3 treats `"${empty[@]}"` as unset under `nounset`, so every copy in
  this module goes through the length check here rather than repeating it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array to fill |
| `$2` | string | Name of the array to read |

**🧩 Variable sets**

- **`The`**: named array


---

### `__dybatpho_array_index`

Build a lookup of the values an array holds.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the associative array to fill |
| `$2` | string | Name of the array to read |

**🧩 Variable sets**

- **`The`**: named associative array, one key per distinct value


---

### `__dybatpho_array_sorts_after`

Return success when one value must sort after another.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Left value |
| `$2` | string | Right value |
| `$3` | bool | Compare as numbers rather than as text |
| `$4` | bool | Reverse the order |

**🚦 Exit codes**

- `0`: The left value belongs after the right one
- `1`: It does not


---

### `__dybatpho_array_merge_sort`

Sort an array of values in place, bottom-up and stable.
  Runs of length one are already sorted, so the passes start by merging pairs
  of them and double the run length until one run covers everything. That is
  `n log n` comparisons instead of the `n²` an insertion sort pays, and the
  comparison stays in `__dybatpho_array_sorts_after` so text, numeric and
  reversed order are all decided in one place.


  The merge takes the left run whenever the two compare equal, which is what
  makes the sort stable.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array to sort in place |
| `$2` | bool | Compare as numbers rather than as text |
| `$3` | bool | Reverse the order |

**🧩 Variable sets**

- **`The`**: named array


---

### `dybatpho::array_sort`

Sort an array in place.
  Text is ordered by the current locale's collation, the same rule `sort`
  follows, so a script that needs one fixed order everywhere sets `LC_ALL` as
  it would for `sort`.


  `--numeric` compares values as numbers, which is the reason a shell script
  wants a sort at all: as text, `10` comes before `9`. It takes integers,
  negative ones included, and stops the script on anything else rather than
  quietly ordering it as text.


  The sort is a bottom-up merge sort rather than a pipe through `sort(1)`: it
  keeps an element containing a newline intact and needs no external command.
  It is also stable, so values that compare equal stay in the order they
  arrived in. The insertion sort it replaces cost a comparison per pair and
  took ~39s over 2000 elements, which is a size a list of files or packages
  reaches without trying.

**🧪 Examples**

```bash
releases=(1.10 1.9 2.0)
dybatpho::array_sort releases --
# 1.10
# 1.9
# 2.0

```

```bash
sizes=(10 9 100 -3)
dybatpho::array_sort sizes --numeric --          # -3 9 10 100
dybatpho::array_sort sizes --numeric --reverse

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$@` | string | Any of `--numeric`/`-n`, `--reverse`/`-r`, and `--` to print |

**📤 Output on stdout**

- Print the sorted array if `--` is given

**🚦 Exit codes**

- `1`: Stop the script on an unknown option, or on a value that is not an integer under `--numeric`

**🔗 See also**

- [- `dybatpho::semver_sort](#dybatphosemver_sort)


---

### `dybatpho::array_slice`

Keep a run of an array in place and drop the rest.
  A negative start counts back from the end, so `-2` takes the last two
  elements without the caller working out the length first. A start past
  either end leaves an empty array rather than failing: asking for elements
  that are not there is a shape the data can have, not a mistake in the call.

**🧪 Example**

```bash
items=(a b c d e)
dybatpho::array_slice items 1 3 --   # b c d
dybatpho::array_slice items -2 --    # the last two

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of array |
| `$2` | number | Index to start at, negative to count back from the end |
| `$3` | number | Optional count, defaulting to everything from the start on |
| `$4` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the sliced array if `--` is given

**🚦 Exit codes**

- `1`: Stop the script when the start or the count is not a whole number


---

### `dybatpho::array_union`

Replace an array with the union of it and another, in place.
  The result is a set: every value appears once, in the order it was first
  seen, the first array's values ahead of the second's. A set operation that
  kept duplicates would not be one, so `dybatpho::array_unique` afterwards has
  nothing left to do.

**🧪 Example**

```bash
allowed=(read write read)
extra=(write admin)
dybatpho::array_union allowed extra --   # read write admin

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array to replace |
| `$2` | string | Name of the array to merge in |
| `$3` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the union if $3 is `--`


---

### `dybatpho::array_intersect`

Keep only the values an array shares with another, in place.
  The result is a set, in the order the first array had them.

**🧪 Example**

```bash
requested=(read write admin)
granted=(write read)
dybatpho::array_intersect requested granted --   # read write

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array to replace |
| `$2` | string | Name of the array to intersect with |
| `$3` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the intersection if $3 is `--`


---

### `dybatpho::array_difference`

Drop the values an array shares with another, in place.
  The result is a set, in the order the first array had them. The operation is
  one-sided: values only the second array holds are not added.

**🧪 Example**

```bash
wanted=(read write admin)
granted=(write)
dybatpho::array_difference wanted granted --   # read admin

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array to replace |
| `$2` | string | Name of the array to subtract |
| `$3` | string | Set `--` to print to stdout |

**📤 Output on stdout**

- Print the difference if $3 is `--`

