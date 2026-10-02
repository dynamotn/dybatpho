# math.sh

Exact decimal arithmetic, comparison, rounding and aggregation

> 🧭 Source: [src/math.sh](../src/math.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

Bash only does integer arithmetic, so a script that has to divide, average,
or add two prices reaches for `bc` or `awk`. `bc` is not installed
everywhere, and `awk` computes in binary floating point, where `0.1 + 0.2`
is not `0.3` and a money total drifts by a cent.

This module does the arithmetic itself, on digit strings, the way it is done
on paper. Values are exact decimals of any length: they are not limited to
the 64 bits `$(( ))` works in, and no result is ever a binary approximation.
Nothing outside Bash is required.

```sh
dybatpho::math_add 0.1 0.2                 # 0.3
dybatpho::math_mul 99999999999 99999999999 # 9999999999800000000001
dybatpho::math_div 2 3 5                   # 0.66667
```

Every function takes and prints plain decimal notation — an optional sign,
digits, an optional `.` and more digits. Scientific notation such as `1e3`,
thousands separators, and hexadecimal are rejected rather than guessed at.
Results are canonical: leading and trailing zeros are dropped, so `1.50` and
`1.5` are the same value and `-0` is printed as `0`. Presentation — grouping,
a fixed number of decimals, a locale's decimal mark — belongs to `i18n`.

Division and averaging cannot always be exact, so they round half away from
zero to `DYBATPHO_MATH_SCALE` fraction digits. Every other operation is
exact, and no operation ever rounds silently at a width the caller did not
ask for.

Long multiplication and division are quadratic in the number of digits and
run in the shell, so they are meant for the sizes a script deals with —
money, sizes, counters, percentages — not for cryptographic bignums.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Fraction digits kept by division, averaging and percentages (default `10`) |

### 🚀 Highlights

- [`dybatpho::math_is_number`](#dybatphomath_is_number) — Return success when a value is a plain decimal number. Scientific notation, thousands separators and hexadecimal are not numbers here: every other function in this module rejects them, and this is the test that says so before one of them stops the script.
- [`dybatpho::math_is_integer`](#dybatphomath_is_integer) — Return success when a value is a whole number. A fraction that is only zeros still counts, so `2.00` is an integer.
- [`dybatpho::math_add`](#dybatphomath_add) — Add numbers exactly.
- [`dybatpho::math_sub`](#dybatphomath_sub) — Subtract the second number from the first, and any further numbers from the running result.
- [`dybatpho::math_mul`](#dybatphomath_mul) — Multiply numbers exactly. The result keeps every digit both operands contributed, so a price times a quantity is never rounded.
- [`dybatpho::math_div`](#dybatphomath_div) — Divide one number by another, rounding half away from zero.
- [`dybatpho::math_mod`](#dybatphomath_mod) — Print the remainder of an integer division. The sign follows the dividend, the way `%` does in Bash and in C.
- [`dybatpho::math_pow`](#dybatphomath_pow) — Raise a number to a whole power.
- [`dybatpho::math_abs`](#dybatphomath_abs) — Print a number without its sign.
- [`dybatpho::math_neg`](#dybatphomath_neg) — Print a number with its sign flipped.
- [`dybatpho::math_compare`](#dybatphomath_compare) — Compare two numbers by value rather than as strings.
- [`dybatpho::math_gt`](#dybatphomath_gt) — Return success when the first number is greater than the second.
- [`dybatpho::math_lt`](#dybatphomath_lt) — Return success when the first number is less than the second.
- [`dybatpho::math_eq`](#dybatphomath_eq) — Return success when two numbers have the same value, whatever their spelling: `2.50`, `2.5` and `+2.5` are all equal.
- [`dybatpho::math_trunc`](#dybatphomath_trunc) — Truncate toward zero, dropping the fractional part.
- [`dybatpho::math_floor`](#dybatphomath_floor) — Round down, toward negative infinity.
- [`dybatpho::math_ceil`](#dybatphomath_ceil) — Round up, toward positive infinity.
- [`dybatpho::math_round`](#dybatphomath_round) — Round to a number of fraction digits, halves away from zero. `printf '%.2f'` rounds binary floats to even and follows `LC_NUMERIC`, so it answers `2.66` for `2.665` on one machine and `2,67` on another; this rounds the decimal digits themselves and always answers `2.67`.
- [`dybatpho::math_min`](#dybatphomath_min) — Print the smallest of a list of numbers.
- [`dybatpho::math_max`](#dybatphomath_max) — Print the largest of a list of numbers.
- [`dybatpho::math_sum`](#dybatphomath_sum) — Add up a list of numbers exactly.
- [`dybatpho::math_avg`](#dybatphomath_avg) — Print the mean of a list of numbers.
- [`dybatpho::math_median`](#dybatphomath_median) — Print the median of a list of numbers. The values are ordered by value; an odd count answers with the middle one as it was written, an even count with the exact mean of the two middle ones. Halving a decimal adds at most one digit, so the median is never rounded.
- [`dybatpho::math_percentile`](#dybatphomath_percentile) — Print a percentile of a list of numbers. Percentiles are interpolated linearly between the two nearest ranks — the inclusive definition that spreadsheets call `PERCENTILE.INC`, R calls type 7 and NumPy uses by default: the values are sorted, the rank `(n - 1) * p / 100` is taken counting from zero, and a fractional rank lies that far between its neighbours. `0` is the smallest value, `100` the largest and `50` the median. Every step is a multiplication by a decimal, so the answer is exact.
- [`dybatpho::math_sqrt`](#dybatphomath_sqrt) — Print the square root of a number. The root is computed digit by digit on the decimal value, so it is the true root rounded half away from zero at the requested width, not a binary approximation.
- [`dybatpho::math_stddev`](#dybatphomath_stddev) — Print the standard deviation of a list of numbers. By default this is the population standard deviation, which describes the values given and divides by their count. `--sample` gives the sample standard deviation, which estimates the spread of a larger population the values were drawn from and divides by one less than the count. The variance is computed exactly from the sum and the sum of squares, so only the final square root is rounded.
- [`dybatpho::math_clamp`](#dybatphomath_clamp) — Hold a number inside a range.
- [`dybatpho::math_percent`](#dybatphomath_percent) — Print what percentage one number is of another.
- [`dybatpho::math_gcd`](#dybatphomath_gcd) — Print the greatest common divisor of whole numbers.
- [`dybatpho::math_lcm`](#dybatphomath_lcm) — Print the least common multiple of whole numbers.
- [`dybatpho::math_random`](#dybatphomath_random) — Print a random whole number in an inclusive range. `$((RANDOM % n))` is biased whenever `n` does not divide the generator's range, which is most of the time: with `RANDOM % 10` the low digits come up noticeably more often. This draws sixty bits and rejects the tail that would cause the bias, so every value in the range is equally likely.

<a id="see-also"></a>
## 🔗 See also

- [example/math_ops.sh](../example/math_ops.sh)
- [docs/spec/math.md](spec/math.md)

<a id="tips"></a>
## 💡 Tips

- Reach for `dybatpho::i18n_number` when the number is about to be shown to a person, and for this module when it is about to be computed with

### `dybatpho::math_div`

- Division is the one operation that cannot always be exact; every other operation in this module keeps all of its digits

### `dybatpho::math_round`

- This rounds for computation. Use `dybatpho::i18n_number` when the result is going to be shown, since that one keeps the digits a person expects to see

### `dybatpho::math_percent`

- Pair it with `dybatpho::i18n_percent` to print the result the way the reader's locale writes a percentage

<a id="reference"></a>
## 📚 Reference

### `dybatpho::math_is_number`

Return success when a value is a plain decimal number.
Scientific notation, thousands separators and hexadecimal are not numbers
here: every other function in this module rejects them, and this is the test
that says so before one of them stops the script.

**🧪 Example**

```bash
dybatpho::math_is_number "-12.5" && echo yes   # yes
dybatpho::math_is_number "1e3" || echo no      # no

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a number
- `1`: It is not


---

### `dybatpho::math_is_integer`

Return success when a value is a whole number.
A fraction that is only zeros still counts, so `2.00` is an integer.

**🧪 Example**

```bash
dybatpho::math_is_integer "2.00" && echo yes   # yes
dybatpho::math_is_integer "2.01" || echo no    # no

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a whole number
- `1`: It is not a number, or it has a fractional part


---

### `dybatpho::math_add`

Add numbers exactly.

**🧪 Example**

```bash
dybatpho::math_add 0.1 0.2           # 0.3
dybatpho::math_add 19.99 5.01 0.5    # 25.5

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Two or more values |

**📤 Output on stdout**

- The sum

**🚦 Exit codes**

- `1`: Stop the script when a value is not a number


---

### `dybatpho::math_sub`

Subtract the second number from the first, and any further
numbers from the running result.

**🧪 Example**

```bash
dybatpho::math_sub 1 0.9         # 0.1
dybatpho::math_sub 100 10 5      # 85

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Two or more values |

**📤 Output on stdout**

- The difference

**🚦 Exit codes**

- `1`: Stop the script when a value is not a number


---

### `dybatpho::math_mul`

Multiply numbers exactly. The result keeps every digit both
operands contributed, so a price times a quantity is never rounded.

**🧪 Example**

```bash
dybatpho::math_mul 19.99 3               # 59.97
dybatpho::math_mul 99999999999 99999999999  # 9999999999800000000001

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Two or more values |

**📤 Output on stdout**

- The product

**🚦 Exit codes**

- `1`: Stop the script when a value is not a number


---

### `dybatpho::math_div`

Divide one number by another, rounding half away from zero.

**🧪 Example**

```bash
dybatpho::math_div 10 4        # 2.5
dybatpho::math_div 2 3 5       # 0.66667
dybatpho::math_div 1 3 0       # 0

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Dividend |
| `$2` | string | Divisor |
| `$3` | number | Fraction digits to keep, default `DYBATPHO_MATH_SCALE` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Default fraction digits |

**📤 Output on stdout**

- The quotient

**🚦 Exit codes**

- `1`: Stop the script on a non-number, a bad scale, or a zero divisor


---

### `dybatpho::math_mod`

Print the remainder of an integer division. The sign follows the
dividend, the way `%` does in Bash and in C.

**🧪 Example**

```bash
dybatpho::math_mod 17 5     # 2
dybatpho::math_mod -17 5    # -2

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Dividend, a whole number |
| `$2` | string | Divisor, a whole number |

**📤 Output on stdout**

- The remainder

**🚦 Exit codes**

- `1`: Stop the script on a fractional operand or a zero divisor


---

### `dybatpho::math_pow`

Raise a number to a whole power.

**🧪 Example**

```bash
dybatpho::math_pow 2 10        # 1024
dybatpho::math_pow 1.05 3      # 1.157625
dybatpho::math_pow 2 -3        # 0.125

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Base |
| `$2` | string | Exponent, a whole number |
| `$3` | number | Fraction digits for a negative exponent, default `DYBATPHO_MATH_SCALE` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Default fraction digits for a negative exponent |
| **`DYBATPHO_MATH_MAX_EXPONENT`** | number | Largest exponent magnitude accepted |

**📝 Notes**

- A positive exponent is exact. A negative one is a division, so it rounds at the requested scale like `dybatpho::math_div`.

**📤 Output on stdout**

- The power

**🚦 Exit codes**

- `1`: Stop the script on a fractional or oversized exponent, or on `0` raised to a negative power


---

### `dybatpho::math_abs`

Print a number without its sign.

**🧪 Example**

```bash
dybatpho::math_abs -12.5    # 12.5

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |

**📤 Output on stdout**

- The magnitude

**🚦 Exit codes**

- `1`: Stop the script when the value is not a number


---

### `dybatpho::math_neg`

Print a number with its sign flipped.

**🧪 Example**

```bash
dybatpho::math_neg 12.5    # -12.5
dybatpho::math_neg -12.5   # 12.5
dybatpho::math_neg 0       # 0

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |

**📤 Output on stdout**

- The negated value

**🚦 Exit codes**

- `1`: Stop the script when the value is not a number


---

### `dybatpho::math_compare`

Compare two numbers by value rather than as strings.

**🧪 Example**

```bash
dybatpho::math_compare 1.10 1.9     # -1
dybatpho::math_compare 2.50 2.5     # 0
(($(dybatpho::math_compare "${used}" "${quota}") > 0)) && dybatpho::warn "Over quota"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | First value |
| `$2` | string | Second value |

**📤 Output on stdout**

- `-1` when the first is smaller, `0` when they are equal, `1` when it is larger

**🚦 Exit codes**

- `1`: Stop the script when a value is not a number


---

### `dybatpho::math_gt`

Return success when the first number is greater than the second.

**🧪 Example**

```bash
dybatpho::math_gt "${balance}" 0 || dybatpho::die "Account is empty"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | First value |
| `$2` | string | Second value |

**🚦 Exit codes**

- `0`: The first value is greater
- `1`: It is not


---

### `dybatpho::math_lt`

Return success when the first number is less than the second.

**🧪 Example**

```bash
dybatpho::math_lt "${free_gb}" 1 && dybatpho::warn "Disk nearly full"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | First value |
| `$2` | string | Second value |

**🚦 Exit codes**

- `0`: The first value is smaller
- `1`: It is not


---

### `dybatpho::math_eq`

Return success when two numbers have the same value, whatever
their spelling: `2.50`, `2.5` and `+2.5` are all equal.

**🧪 Example**

```bash
dybatpho::math_eq 2.50 2.5 && echo same

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | First value |
| `$2` | string | Second value |

**🚦 Exit codes**

- `0`: The values are equal
- `1`: They are not


---

### `dybatpho::math_trunc`

Truncate toward zero, dropping the fractional part.

**🧪 Example**

```bash
dybatpho::math_trunc 2.9     # 2
dybatpho::math_trunc -2.9    # -2

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |

**📤 Output on stdout**

- The whole part

**🚦 Exit codes**

- `1`: Stop the script when the value is not a number


---

### `dybatpho::math_floor`

Round down, toward negative infinity.

**🧪 Example**

```bash
dybatpho::math_floor 2.9     # 2
dybatpho::math_floor -2.1    # -3

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |

**📤 Output on stdout**

- The largest whole number that is not greater than the value

**🚦 Exit codes**

- `1`: Stop the script when the value is not a number


---

### `dybatpho::math_ceil`

Round up, toward positive infinity.

**🧪 Example**

```bash
dybatpho::math_ceil 2.1      # 3
dybatpho::math_ceil -2.9     # -2

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |

**📤 Output on stdout**

- The smallest whole number that is not less than the value

**🚦 Exit codes**

- `1`: Stop the script when the value is not a number


---

### `dybatpho::math_round`

Round to a number of fraction digits, halves away from zero.
`printf '%.2f'` rounds binary floats to even and follows `LC_NUMERIC`, so it
answers `2.66` for `2.665` on one machine and `2,67` on another; this
rounds the decimal digits themselves and always answers `2.67`.

**🧪 Example**

```bash
dybatpho::math_round 2.665 2    # 2.67
dybatpho::math_round -0.5       # -1
dybatpho::math_round 1.005 2    # 1.01

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |
| `$2` | number | Fraction digits to keep, default `0` |

**📤 Output on stdout**

- The rounded value, with trailing zeros dropped

**🚦 Exit codes**

- `1`: Stop the script when the value is not a number or the scale is not a non-negative integer


---

### `dybatpho::math_min`

Print the smallest of a list of numbers.

**🧪 Example**

```bash
dybatpho::math_min 3 1.5 2          # 1.5
dybatpho::math_min < durations.txt

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values, or none to read them from standard input |

**📥 Input on stdin**

- One or more values per line, when no argument is given

**📤 Output on stdout**

- The smallest value, as it was written

**🚦 Exit codes**

- `1`: Stop the script when no value is given or one is not a number


---

### `dybatpho::math_max`

Print the largest of a list of numbers.

**🧪 Example**

```bash
dybatpho::math_max 3 1.5 2          # 3
dybatpho::math_max < durations.txt

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values, or none to read them from standard input |

**📥 Input on stdin**

- One or more values per line, when no argument is given

**📤 Output on stdout**

- The largest value, as it was written

**🚦 Exit codes**

- `1`: Stop the script when no value is given or one is not a number


---

### `dybatpho::math_sum`

Add up a list of numbers exactly.

**🧪 Example**

```bash
dybatpho::math_sum 19.99 5.01 0.5           # 25.5
awk '{print $3}' sizes.txt | dybatpho::math_sum

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values, or none to read them from standard input |

**📥 Input on stdin**

- One or more values per line, when no argument is given

**📤 Output on stdout**

- The total, or `0` for an empty list

**🚦 Exit codes**

- `1`: Stop the script when a value is not a number


---

### `dybatpho::math_avg`

Print the mean of a list of numbers.

**🧪 Example**

```bash
dybatpho::math_avg 10 20 25                         # 18.3333333333
DYBATPHO_MATH_SCALE=2 dybatpho::math_avg 10 20 25   # 18.33

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values, or none to read them from standard input |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Fraction digits kept in the result |

**📝 Notes**

- Every argument is a value, so the scale is taken from `DYBATPHO_MATH_SCALE` rather than from a trailing argument that could not be told apart from the data

**📥 Input on stdin**

- One or more values per line, when no argument is given

**📤 Output on stdout**

- The mean

**🚦 Exit codes**

- `1`: Stop the script when no value is given or one is not a number


---

### `dybatpho::math_median`

Print the median of a list of numbers.
The values are ordered by value; an odd count answers with the middle one
as it was written, an even count with the exact mean of the two middle
ones. Halving a decimal adds at most one digit, so the median is never
rounded.

**🧪 Example**

```bash
dybatpho::math_median 7 1 3              # 3
dybatpho::math_median 1 2 3 10           # 2.5
dybatpho::math_median < durations.txt

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values, or none to read them from standard input |

**📥 Input on stdin**

- One or more values per line, when no argument is given

**📤 Output on stdout**

- The median

**🚦 Exit codes**

- `1`: Stop the script when no value is given or one is not a number


---

### `dybatpho::math_percentile`

Print a percentile of a list of numbers.
Percentiles are interpolated linearly between the two nearest ranks — the
inclusive definition that spreadsheets call `PERCENTILE.INC`, R calls type 7
and NumPy uses by default: the values are sorted, the rank
`(n - 1) * p / 100` is taken counting from zero, and a fractional rank lies
that far between its neighbours. `0` is the smallest value, `100` the
largest and `50` the median. Every step is a multiplication by a decimal, so
the answer is exact.

**🧪 Example**

```bash
dybatpho::math_percentile 90 1 2 3 4 5 6 7 8 9 10    # 9.1
dybatpho::math_percentile 50 3 1 2                   # 2
dybatpho::math_percentile 99 < latencies.txt

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Percentile, from `0` to `100`, fractions allowed |
| `$@` | string | Values, or none to read them from standard input |

**📥 Input on stdin**

- One or more values per line, when no value argument is given

**📤 Output on stdout**

- The percentile

**🚦 Exit codes**

- `1`: Stop the script on a percentile outside `0`–`100`, an empty list, or a value that is not a number


---

### `dybatpho::math_sqrt`

Print the square root of a number.
The root is computed digit by digit on the decimal value, so it is the true
root rounded half away from zero at the requested width, not a binary
approximation.

**🧪 Example**

```bash
dybatpho::math_sqrt 16          # 4
dybatpho::math_sqrt 2 5         # 1.41421
dybatpho::math_sqrt 0.25        # 0.5

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value, not negative |
| `$2` | number | Fraction digits to keep, default `DYBATPHO_MATH_SCALE` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Default fraction digits |

**📤 Output on stdout**

- The square root

**🚦 Exit codes**

- `1`: Stop the script on a non-number, a negative value, or a bad scale


---

### `dybatpho::math_stddev`

Print the standard deviation of a list of numbers.
By default this is the population standard deviation, which describes the
values given and divides by their count. `--sample` gives the sample
standard deviation, which estimates the spread of a larger population the
values were drawn from and divides by one less than the count. The
variance is computed exactly from the sum and the sum of squares, so only
the final square root is rounded.

**🧪 Example**

```bash
dybatpho::math_stddev 2 4 4 4 5 5 7 9            # 2
dybatpho::math_stddev --sample 2 4 4 4 5 5 7 9   # 2.1380899353
DYBATPHO_MATH_SCALE=3 dybatpho::math_stddev 1 2 3 4   # 1.118

```

**🎛️ Options**

| Option | Description |
| --- | --- |
| **--sample** | Divide by `n - 1` instead of `n` |

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values, or none to read them from standard input |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Fraction digits kept in the result |

**📥 Input on stdin**

- One or more values per line, when no value argument is given

**📤 Output on stdout**

- The standard deviation

**🚦 Exit codes**

- `1`: Stop the script on an empty list, a single value with `--sample`, or a value that is not a number


---

### `dybatpho::math_clamp`

Hold a number inside a range.

**🧪 Example**

```bash
dybatpho::math_clamp 42 0 10      # 10
dybatpho::math_clamp -3 0 10      # 0
dybatpho::math_clamp 7.5 0 10     # 7.5

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |
| `$2` | string | Lower bound |
| `$3` | string | Upper bound |

**📤 Output on stdout**

- The value, or whichever bound it crossed

**🚦 Exit codes**

- `1`: Stop the script on a non-number or a lower bound above the upper one


---

### `dybatpho::math_percent`

Print what percentage one number is of another.

**🧪 Example**

```bash
dybatpho::math_percent 42 200       # 21
dybatpho::math_percent 1 3 2        # 33.33

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Part |
| `$2` | string | Whole |
| `$3` | number | Fraction digits to keep, default `DYBATPHO_MATH_SCALE` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_MATH_SCALE`** | number | Default fraction digits |

**📤 Output on stdout**

- The percentage, without a `%` sign

**🚦 Exit codes**

- `1`: Stop the script on a non-number, a bad scale, or a whole of zero


---

### `dybatpho::math_gcd`

Print the greatest common divisor of whole numbers.

**🧪 Example**

```bash
dybatpho::math_gcd 12 18        # 6
dybatpho::math_gcd 24 36 60     # 12

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Two or more whole numbers; signs are ignored |

**📤 Output on stdout**

- The greatest common divisor, `0` only when every value is zero

**🚦 Exit codes**

- `1`: Stop the script on a fractional or non-numeric value


---

### `dybatpho::math_lcm`

Print the least common multiple of whole numbers.

**🧪 Example**

```bash
dybatpho::math_lcm 4 6         # 12
dybatpho::math_lcm 2 3 5       # 30

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Two or more whole numbers; signs are ignored |

**📤 Output on stdout**

- The least common multiple, `0` when any value is zero

**🚦 Exit codes**

- `1`: Stop the script on a fractional or non-numeric value


---

### `dybatpho::math_random`

Print a random whole number in an inclusive range.
`$((RANDOM % n))` is biased whenever `n` does not divide the generator's
range, which is most of the time: with `RANDOM % 10` the low digits come up
noticeably more often. This draws sixty bits and rejects the tail that would
cause the bias, so every value in the range is equally likely.

**🧪 Example**

```bash
dybatpho::math_random 1 6              # a die roll
sleep "$(dybatpho::math_random 1 5)"   # jittered backoff

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lower bound, a whole number |
| `$2` | string | Upper bound, a whole number, not below the lower one |

**📝 Notes**

- `RANDOM` is not a cryptographic generator. Read `/dev/urandom` for anything that guards a secret

**📤 Output on stdout**

- A whole number between the bounds, both included

**🚦 Exit codes**

- `1`: Stop the script on a fractional bound, a reversed range, or a range wider than the generator
