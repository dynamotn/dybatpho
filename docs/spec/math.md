# Feature Specification: Exact Decimal Arithmetic

**Feature Branch**: `[feature-math]`
**Status**: Implemented
**Input**: Source analysis: `src/math.sh`, `docs/math.md`, `test/math.bats`, and `example/math_ops.sh`

## Problem Statement *(mandatory)*

Bash arithmetic is integer-only and 64 bits wide, so a script that has to
divide, average, apply a tax rate, or add two prices has to leave the shell.
`bc` is not installed on a minimal container or on macOS by default, and `awk`
computes in binary floating point, where `0.1 + 0.2` is not `0.3`, a money
total drifts by a cent over a long invoice, and `printf '%.2f'` rounds halves
to even while following `LC_NUMERIC`, so the same script prints `2.66` on one
machine and `2,67` on another. Scripts also open-code comparisons as string
tests, where `1.10` sorts below `1.9`, and open-code `$((RANDOM % n))`, which
is biased for almost every `n`.

## Business Value *(mandatory)*

- Let a script compute with decimals without depending on `bc` or `awk`.
- Keep money and measurement arithmetic exact, so totals do not drift.
- Give rounding one stated rule — half away from zero — that does not vary by
  machine, locale, or value size.
- Remove the 64-bit ceiling from sums, products and powers.
- Replace open-coded string comparisons and biased random draws with helpers
  that state what they do and fail loudly on input they cannot honor.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compute with decimals exactly (Priority: P1)

As a script author, I want to add, subtract, multiply and divide decimal
values so that a price list or a set of measurements totals correctly without
an external calculator.

**Why this priority**: Arithmetic that a script cannot do at all in the shell
is the reason the module exists.

**Independent Test**: Add, subtract, multiply and divide decimal values and
verify the results are exact and canonical.

**Acceptance Scenarios**:

1. **Given** the values `0.1` and `0.2`, **When** they are added, **Then** the
   result is `0.3` rather than a binary approximation
2. **Given** two eleven-digit values, **When** they are multiplied, **Then**
   every digit of the product is kept rather than wrapping at 64 bits
3. **Given** a divisor that does not divide evenly, **When** the values are
   divided, **Then** the result is rounded half away from zero at the
   requested number of fraction digits
4. **Given** a divisor of zero, **When** the values are divided, **Then** the
   script stops with a division-by-zero error

---

### User Story 2 - Compare numbers by value (Priority: P1)

As a script author, I want comparisons that read the numbers rather than the
strings so that a threshold check is correct for `1.10` against `1.9` and for
values written with different numbers of zeros.

**Why this priority**: A wrong comparison silently produces wrong decisions
rather than an error.

**Independent Test**: Compare values that string ordering gets wrong, and
values that are equal but spelled differently.

**Acceptance Scenarios**:

1. **Given** `1.10` and `1.9`, **When** they are compared, **Then** `1.10` is
   reported as the smaller value
2. **Given** `2.50` and `2.5`, **When** they are compared, **Then** they are
   reported as equal
3. **Given** a comparison used as a condition, **When** the greater, lesser or
   equal helper runs, **Then** the answer is the exit code rather than text

---

### User Story 3 - Round on purpose (Priority: P1)

As a script author, I want to state how a value is rounded — to a width, down,
up, or toward zero — so that a charged total or a progress figure is the one I
intended on every machine.

**Why this priority**: Rounding is where a money bug becomes visible, and it is
the part `printf` does differently by locale and by binary representation.

**Independent Test**: Round positive and negative values at several widths, and
compare against floor, ceiling and truncation of the same values.

**Acceptance Scenarios**:

1. **Given** the value `2.665` and a width of two digits, **When** it is
   rounded, **Then** the result is `2.67`
2. **Given** the value `-0.5`, **When** it is rounded to a whole number,
   **Then** the result is `-1`, because halves round away from zero
3. **Given** the value `-2.1`, **When** floor, ceiling and truncation are
   applied, **Then** the results are `-3`, `-2` and `-2`

---

### User Story 4 - Summarize a list of numbers (Priority: P2)

As a script author, I want the total, mean, smallest and largest of a list,
from arguments or from a pipe, so that a batch of timings or sizes can be
reported without a custom loop.

**Why this priority**: A summary is the most common reason a script needs
arithmetic in the first place, and its input usually arrives on a pipe.

**Independent Test**: Aggregate a list passed as arguments and the same list
piped in, and verify an empty list is handled as specified.

**Acceptance Scenarios**:

1. **Given** values as arguments, **When** they are summed, **Then** the exact
   total is printed
2. **Given** the same values on standard input, **When** no argument is passed,
   **Then** the values are read from the pipe, several per line if need be
3. **Given** an empty list, **When** the mean, smallest or largest is asked
   for, **Then** the script stops with a clear error, while the sum is `0`

---

### User Story 5 - Keep a value inside a range and express a share (Priority: P2)

As a script author, I want to clamp a value to bounds and to express one value
as a percentage of another so that progress bars, quotas and reports do not
need hand-written guards.

**Why this priority**: These are the two shapes a computed number takes when it
reaches a user interface.

**Independent Test**: Clamp values below, inside and above a range, and compute
percentages at different widths.

**Acceptance Scenarios**:

1. **Given** a value outside its bounds, **When** it is clamped, **Then** the
   crossed bound is printed
2. **Given** a lower bound above the upper one, **When** clamping runs,
   **Then** the script stops with a clear error
3. **Given** a part and a whole, **When** the percentage is computed, **Then**
   the share is printed without a percent sign, rounded at the requested width

---

### User Story 6 - Work with whole numbers (Priority: P3)

As a script author, I want remainders, powers, greatest common divisors, least
common multiples and unbiased random draws so that ratios, retry jitter and
scheduling intervals are correct.

**Why this priority**: These complete the arithmetic a script reaches for once
the decimal operations exist.

**Independent Test**: Compute remainders with mixed signs, reduce an aspect
ratio through the greatest common divisor, and draw many random values inside a
small range.

**Acceptance Scenarios**:

1. **Given** a negative dividend, **When** the remainder is computed, **Then**
   its sign follows the dividend
2. **Given** a fractional operand, **When** a whole-number helper runs,
   **Then** the script stops with a clear error
3. **Given** an inclusive range, **When** random values are drawn, **Then**
   every value lies inside the range and both bounds can occur

---

### User Story 7 - Describe the spread of a list (Priority: P2)

As a script author, I want the median, any percentile, and the standard
deviation of a list of numbers, plus a square root, so that latency reports
and benchmark summaries can say what is typical and how far values stray
without leaving the shell.

**Why this priority**: A mean hides outliers; the percentiles and the spread
are what a timing report is actually read for, and they are where scripts
reach for `awk` or a Python one-liner today.

**Independent Test**: Compute the median, several percentiles, the population
and sample standard deviations, and square roots of known lists and values, and
verify each exact or rounded result and each refusal.

**Acceptance Scenarios**:

1. **Given** an odd number of values in any order, **When** the median is asked
   for, **Then** the middle value by value is printed as it was written
2. **Given** an even number of values, **When** the median is asked for,
   **Then** the exact mean of the two middle values is printed, unrounded
3. **Given** a percentile between `0` and `100`, **When** it is computed,
   **Then** the result is interpolated linearly between the two nearest ranks
   (`PERCENTILE.INC`, R type 7), with `0`, `50` and `100` meeting the minimum,
   median and maximum
4. **Given** a list, **When** the standard deviation is asked for, **Then** the
   population deviation is printed, or the sample deviation with `--sample`,
   rounded half away from zero to `DYBATPHO_MATH_SCALE`
5. **Given** a non-negative value, **When** its square root is asked for,
   **Then** the true root rounded half away from zero at the requested width is
   printed; a negative value stops the script

---

### Example Workflow

```bash
subtotal="$(dybatpho::math_mul 19.99 3)"                 # 59.97
discount="$(dybatpho::math_mul "${subtotal}" 0.10)"      # 5.997
taxable="$(dybatpho::math_sub "${subtotal}" "${discount}")"
total="$(dybatpho::math_round \
  "$(dybatpho::math_add "${taxable}" \
    "$(dybatpho::math_mul "${taxable}" 0.0825)")" 2)"    # charged to the cent

if dybatpho::math_gt "${total}" "${budget}"; then
  dybatpho::warn "Over budget by $(dybatpho::math_sub "${total}" "${budget}")"
fi

dybatpho::info "Mean duration: $(dybatpho::math_avg "${durations[@]}")"
dybatpho::info "Done: $(dybatpho::math_percent "${finished}" "${jobs}" 1)%"
```

## Edge Cases

- A value is not a plain decimal: scientific notation, a thousands separator,
  a hexadecimal literal, an empty string, or a lone `.`.
- A value carries redundant zeros — `007`, `2.50`, `-0.0` — and must compare
  and print as its canonical form.
- A result is zero and must never print as `-0`.
- The divisor, or the whole of a percentage, is zero.
- A requested scale is negative or not a number.
- Division produces a value smaller than the scale can express, so the result
  rounds to `0`.
- Rounding carries all the way through the integer part, as `9.99` does at one
  fraction digit.
- The exponent is fractional, or large enough that the computation would not
  finish.
- Zero is raised to a negative power.
- An aggregate is asked for with no values at all.
- A random range is reversed, fractional, or wider than the generator can cover
  uniformly.
- Values exceed what `$(( ))` can represent, in a sum, a product, or a
  comparison.
- A percentile is below `0`, above `100`, or not a number.
- The median or a percentile is asked of a single value, or of values that
  tie.
- A sample standard deviation is asked of a single value, which has no spread
  to estimate.
- A square root is asked of a negative value, or of a value with more fraction
  digits than the requested width needs.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST perform its arithmetic without `bc`, `awk`, or
  any other external command.
- **FR-002**: Addition, subtraction and multiplication MUST be exact and MUST
  NOT be limited to the range of Bash integer arithmetic.
- **FR-003**: The module MUST accept plain decimal notation with an optional
  sign, and MUST reject every other notation with a message naming the value
  and the public function that received it.
- **FR-004**: Results MUST be canonical: no leading zeros, no trailing
  fraction zeros, and no sign on zero.
- **FR-005**: Division MUST round half away from zero at a caller-supplied
  number of fraction digits, defaulting to `DYBATPHO_MATH_SCALE`.
- **FR-006**: Division, the percentage helper, and the remainder helper MUST
  fail when the divisor or whole is zero.
- **FR-007**: The module MUST provide comparison that prints `-1`, `0` or `1`
  by value, and greater/lesser/equal helpers that answer through the exit code.
- **FR-008**: The module MUST provide rounding to a width, flooring, ceiling
  and truncation, each applying its stated rule to positive and negative values
  alike.
- **FR-009**: The module MUST provide sum, mean, smallest and largest helpers
  that read their values from arguments or from standard input.
- **FR-010**: The sum of an empty list MUST be `0`; the mean, smallest and
  largest of an empty list MUST fail with a clear error.
- **FR-011**: The module MUST provide a clamp helper that fails when the lower
  bound is above the upper bound.
- **FR-012**: The module MUST provide a percentage helper that prints the share
  without a percent sign.
- **FR-013**: The remainder helper MUST take whole numbers, MUST give the
  remainder the sign of the dividend, and MUST reject fractional operands.
- **FR-014**: The power helper MUST accept a whole exponent, MUST be exact for
  a non-negative exponent, MUST divide at the requested scale for a negative
  one, MUST reject zero raised to a negative power, and MUST refuse an exponent
  larger in magnitude than `DYBATPHO_MATH_MAX_EXPONENT`.
- **FR-015**: The greatest-common-divisor and least-common-multiple helpers
  MUST accept two or more whole numbers, MUST ignore signs, and MUST reject
  fractional values.
- **FR-016**: The random helper MUST draw uniformly from an inclusive range of
  whole numbers, MUST reject a reversed, fractional or unsupportable range, and
  MUST NOT be presented as cryptographically secure.
- **FR-017**: The module MUST provide predicates that report whether a value is
  a number and whether it is whole, without stopping the script.
- **FR-018**: The module MUST depend only on the core modules, so that it loads
  on its own.
- **FR-019**: The module MUST provide a median helper that orders values by
  value, prints the middle value as written for an odd count, prints the exact
  mean of the two middle values for an even count, and fails on an empty list.
- **FR-020**: The module MUST provide a percentile helper that takes a
  percentile from `0` to `100`, interpolates linearly between the two nearest
  ranks counting from zero at rank `(n - 1) * p / 100`, computes the result
  exactly, and fails on a percentile outside the range or an empty list.
- **FR-021**: The module MUST provide a square root helper that rounds half
  away from zero at a caller-supplied width, defaulting to
  `DYBATPHO_MATH_SCALE`, and fails on a negative value.
- **FR-022**: The module MUST provide a standard deviation helper that prints
  the population deviation by default and the sample deviation with
  `--sample`, computes the variance exactly so that only the root is rounded,
  and fails on an empty list or on a single value with `--sample`.
- **FR-023**: The median, percentile and standard deviation helpers MUST read
  their values from arguments or from standard input, like the other
  aggregates.

### Key Entities *(include if feature involves data)*

- **Value**: A decimal written as an optional sign, digits, an optional `.`,
  and more digits.
- **Digit String**: The internal representation of a magnitude, one character
  per decimal digit, which is what lifts the 64-bit limit.
- **Scale**: The number of fraction digits an inexact operation keeps.
- **Bound**: A lower or upper limit used by clamping and by random drawing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script computes decimal totals, shares and averages with no
  external dependency beyond Bash itself.
- **SC-002**: A sum of decimal values is exact: repeated addition of values
  such as `0.1` never accumulates an error.
- **SC-003**: The same rounded result is produced on every machine and under
  every locale.
- **SC-004**: Sums, products and comparisons remain correct for values beyond
  the 64-bit range.
- **SC-005**: Invalid input stops the script with a message naming the value
  and the function, rather than producing a wrong number.
- **SC-006**: Random draws over a small range are uniform rather than biased
  toward the low values.
- **SC-007**: A script reports the median, the 90th or 99th percentile, and the
  standard deviation of a list of timings with no external command, and gets
  the same answer on every machine.

## Integration Tests *(mandatory)*

- **IT-001**: Add, subtract and multiply decimal values, including
  `0.1 + 0.2`, and verify exact canonical results.
- **IT-002**: Add and multiply values beyond 64 bits and verify no wrapping.
- **IT-003**: Divide at several scales, including `0`, and verify half-away
  rounding, a value smaller than the scale, and the environment default.
- **IT-004**: Verify division, the percentage helper and the remainder helper
  all fail on a zero divisor or whole.
- **IT-005**: Compare values that string ordering gets wrong and values that
  are equal but spelled differently, through both the printed result and the
  exit-code helpers.
- **IT-006**: Round, floor, ceil and truncate positive and negative values,
  including a rounding carry and an exact half.
- **IT-007**: Aggregate a list from arguments and from standard input, and
  verify the empty-list behavior of each aggregate.
- **IT-008**: Clamp below, inside and above a range and verify reversed bounds
  fail.
- **IT-009**: Compute remainders, powers, greatest common divisors and least
  common multiples, and verify fractional or oversized input fails.
- **IT-010**: Draw many random values over small and negative ranges, verify
  they stay inside the range and cover it, and verify invalid ranges fail.
- **IT-011**: Load the module on its own and run an operation, proving it has
  no optional-module dependency.
- **IT-012**: Compute the median of odd and even lists, including decimals,
  negatives, a single value and redundant zeros, from arguments and from
  standard input, and verify an empty list and a non-number fail.
- **IT-013**: Compute percentiles that interpolate, that land on a rank, and at
  `0`, `50` and `100`, from arguments and from standard input, and verify an
  out-of-range percentile and an empty list fail.
- **IT-014**: Take exact and inexact square roots at several widths, including
  a root beyond 64 bits, and verify a negative value, a bad width and a
  non-number fail.
- **IT-015**: Compute population and sample standard deviations of known lists,
  including a single value and a custom scale, and verify an empty list, a lone
  sample and a bad scale fail.

## Acceptance Criteria *(mandatory)*

1. Every arithmetic, comparison, rounding, aggregation and whole-number helper
   advertised in the library README, docs and example is available and behaves
   as specified.
2. No operation depends on an external command, on binary floating point, or on
   the host locale.
3. Every failure mode listed in the requirements stops the script with a
   message naming the public function and the offending value.
