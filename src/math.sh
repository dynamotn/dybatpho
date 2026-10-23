# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# The library returns its values on stdout, so its own functions are called inside `$(...)` by design. Every call
# here that can stop the script was reviewed: it is fixed, or listed with its reason in test/die-in-substitution.allow,
# which test/conventions.bats enforces.
# dyshellint disable=BSG047 # reviewed in test/die-in-substitution.allow
# @file math.sh
# @brief Exact decimal arithmetic, comparison, rounding and aggregation
# @namespace dybatpho
# @description
#   Bash only does integer arithmetic, so a script that has to divide, average,
#   or add two prices reaches for `bc` or `awk`. `bc` is not installed
#   everywhere, and `awk` computes in binary floating point, where `0.1 + 0.2`
#   is not `0.3` and a money total drifts by a cent.
#
#   This module does the arithmetic itself, on digit strings, the way it is done
#   on paper. Values are exact decimals of any length: they are not limited to
#   the 64 bits `$(( ))` works in, and no result is ever a binary approximation.
#   Nothing outside Bash is required.
#
#   ```sh
#   dybatpho::math_add 0.1 0.2                 # 0.3
#   dybatpho::math_mul 99999999999 99999999999 # 9999999999800000000001
#   dybatpho::math_div 2 3 5                   # 0.66667
#   ```
#
#   Every function takes and prints plain decimal notation — an optional sign,
#   digits, an optional `.` and more digits. Scientific notation such as `1e3`,
#   thousands separators, and hexadecimal are rejected rather than guessed at.
#   Results are canonical: leading and trailing zeros are dropped, so `1.50` and
#   `1.5` are the same value and `-0` is printed as `0`. Presentation — grouping,
#   a fixed number of decimals, a locale's decimal mark — belongs to `i18n`.
#
#   Division and averaging cannot always be exact, so they round half away from
#   zero to `DYBATPHO_MATH_SCALE` fraction digits. Every other operation is
#   exact, and no operation ever rounds silently at a width the caller did not
#   ask for.
#
#   Long multiplication and division are quadratic in the number of digits and
#   run in the shell, so they are meant for the sizes a script deals with —
#   money, sizes, counters, percentages — not for cryptographic bignums.
#   Operands of up to seventeen significant digits are added, multiplied and
#   compared in Bash's own arithmetic, which is exact at that size.
#
#   A loop that accumulates should use the `_into` variants —
#   `dybatpho::math_add_into total "${total}" "${x}"` — which fill a variable
#   instead of printing, so no step pays for a `$(...)` subshell.
#
#   The list aggregates — sum, mean, minimum, maximum, median, percentile and
#   standard deviation — run through `awk` from 32 values up when it is
#   installed. `awk` is used only for exact work: sums are carried as integer
#   limbs well below 2^53 and comparisons are made on the digit strings, so the
#   answer is the Bash engine's to the last digit. `DYBATPHO_MATH_ENGINE` pins
#   either engine.
# @tip With `awk`, an aggregate over 5,000 values takes a few hundredths of a
#   second; the Bash engine takes about a millisecond a value, so it is
#   comfortable into the low thousands
# @see
#   - `example/math_ops.sh`
#   - `docs/spec/math.md`
# @tip Reach for `dybatpho::i18n_number` when the number is about to be shown to
#   a person, and for this module when it is about to be computed with
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_MATH_SCALE number [default: 10] Fraction digits kept by division, averaging and percentages
DYBATPHO_MATH_SCALE="${DYBATPHO_MATH_SCALE:-10}"

# Plain decimal notation, with an optional sign: `12`, `-0.5`, `+.25`, `7.`
DYBATPHO_MATH_NUMBER_REGEX='^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$'
# The largest exponent `dybatpho::math_pow` accepts. Each step is a full long
# multiplication, so an unbounded exponent is an unbounded wait rather than an
# answer.
DYBATPHO_MATH_MAX_EXPONENT=4096

# @env DYBATPHO_MATH_ENGINE string [default: auto] `auto`, `awk` or `bash`: the engine of the list aggregates
DYBATPHO_MATH_ENGINE="${DYBATPHO_MATH_ENGINE:-auto}"

# The number of values from which `auto` starts `awk`. Below it the Bash engine
# finishes before an `awk` process would have started.
__dybatpho_math_awk_threshold=32

# Decimal helpers shared by every `awk` program in the library: the number
# test, an exact comparison, the sort key `__dybatpho_math_sort_key_into`
# builds, and a stable merge sort. Each one reproduces its Bash counterpart on
# the digit strings, so no value is ever read as a binary float.
# shellcheck disable=SC2016 # an awk program: its `$` are awk's, not the shell's
__dybatpho_math_awk_lib='
  # @internal
  function math_init(   i, digits) {
    NUMRE = "^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$"
    split("j i h g f e d c b a", digits, " ")
    for (i = 0; i < 10; i++) NEG[i ""] = digits[i + 1]
    NEG["."] = "."
  }

  # Split a plain decimal into CS (sign), CI (integer digits) and CF (fraction
  # digits), canonical the way the Bash engine parses one.
  # @internal
  function canon(v,   c, p) {
    CS = ""
    c = substr(v, 1, 1)
    if (c == "-") {
      CS = "-"
      v = substr(v, 2)
    } else if (c == "+") v = substr(v, 2)
    p = index(v, ".")
    if (p) {
      CI = substr(v, 1, p - 1)
      CF = substr(v, p + 1)
    } else {
      CI = v ""
      CF = ""
    }
    sub(/^0+/, "", CI)
    if (CI == "") CI = "0"
    sub(/0+$/, "", CF)
    if (CI == "0" && CF == "") CS = ""
  }

  # Compare two decimals by value: -1, 0 or 1.
  # @internal
  function ncmp(a, b,   sa, ia, fa, r) {
    canon(a)
    sa = CS
    ia = CI
    fa = CF
    canon(b)
    if (sa != CS) return (sa == "" ? 1 : -1)
    if (length(ia) != length(CI)) r = (length(ia) > length(CI) ? 1 : -1)
    else if (ia != CI) r = (ia > CI ? 1 : -1)
    else {
      while (length(fa) < length(CF)) fa = fa "0"
      while (length(CF) < length(fa)) CF = CF "0"
      r = (fa == CF ? 0 : (fa > CF ? 1 : -1))
    }
    return (sa == "-" ? -r : r)
  }

  # The key whose byte order is the number order, as `__dybatpho_math_sort_key_into`
  # builds it.
  # @internal
  function numkey(v,   neg, c, p, ip, fp, d, out, j) {
    neg = 0
    c = substr(v, 1, 1)
    if (c == "-") {
      neg = 1
      v = substr(v, 2)
    } else if (c == "+") v = substr(v, 2)
    p = index(v, ".")
    if (p) {
      ip = substr(v, 1, p - 1)
      fp = substr(v, p + 1)
    } else {
      ip = v ""
      fp = ""
    }
    sub(/^0+/, "", ip)
    sub(/0+$/, "", fp)
    if ((ip fp) == "") neg = 0
    if (!neg) return "1" sprintf("%05d", length(ip)) ip "." fp
    d = ip "." fp
    out = ""
    for (j = 1; j <= length(d); j++) out = out NEG[substr(d, j, 1)]
    return "0" sprintf("%05d", 99999 - length(ip)) out "~"
  }

  # Return 1 when position a strictly comes before position b: by the keys in
  # K, an empty key last, descending when DESC is set.
  # @internal
  function before(a, b,   ka, kb) {
    ka = K[a] ""
    kb = K[b] ""
    if (ka == "") return 0
    if (kb == "") return 1
    if (DESC) return (kb < ka)
    return (ka < kb)
  }

  # Stable bottom-up merge sort of O[1..m] by `before`.
  # @internal
  function msort(m,   width, lo, mid, hi, i, j, k) {
    for (width = 1; width < m; width *= 2) {
      for (lo = 1; lo <= m; lo += 2 * width) {
        mid = lo + width - 1
        hi = lo + 2 * width - 1
        if (hi > m) hi = m
        if (mid >= hi) {
          for (k = lo; k <= hi; k++) T[k] = O[k]
          continue
        }
        i = lo
        j = mid + 1
        k = lo
        while (i <= mid && j <= hi) {
          if (before(O[j], O[i])) T[k++] = O[j++]
          else T[k++] = O[i++]
        }
        while (i <= mid) T[k++] = O[i++]
        while (j <= hi) T[k++] = O[j++]
      }
      for (k = 1; k <= m; k++) O[k] = T[k]
    }
  }
'

# The `awk` engine for the list aggregates, chosen by its first argument:
# `sum`, `sumsq` (the sum, then the sum of squares), `min`, `max`, or `sort`.
# It reads one value a line and exits 3 at the first one that is not a number,
# leaving the Bash engine to report it.
# shellcheck disable=SC2016 # an awk program: its `$` are awk's, not the shell's
__dybatpho_math_awk_program='
  BEGIN {
    MODE = ARGV[1] ""
    ARGV[1] = ""
    math_init()
    bad = 0
    n = 0
    # Sums are kept as base-10^7 limbs, squares as base-10^4 limbs, each an
    # integer, so every addition is exact: a limb only loses precision past
    # 2^53, which takes hundreds of millions of values.
    B = 10000000
    LO = 0
    HI = 0
    ACC[0] = 0
    B2 = 10000
    LO2 = 0
    HI2 = 0
    SQ[0] = 0
  }
  {
    v = $0 ""
    if (v !~ NUMRE || NR > 100000000) {
      bad = 1
      exit
    }
    n++
    if (MODE == "sum" || MODE == "sumsq") add(v)
    if (MODE == "sumsq") square(v)
    if (MODE == "min" && (n == 1 || ncmp(v, best) < 0)) best = v
    if (MODE == "max" && (n == 1 || ncmp(v, best) > 0)) best = v
    if (MODE == "sort") {
      V[n] = v
      K[n] = numkey(v)
      O[n] = n
    }
  }
  END {
    if (bad) exit 3
    if (MODE == "sum") print total()
    else if (MODE == "sumsq") {
      print total()
      print squares()
    } else if (MODE == "min" || MODE == "max") {
      if (n == 0) exit 3
      print best
    } else if (MODE == "sort") {
      msort(n)
      for (i = 1; i <= n; i++) print V[O[i]]
    } else exit 3
  }

  # Split v into SG (1 or -1), IP (integer digits) and FP (fraction digits).
  # @internal
  function parts(v,   c, p) {
    SG = 1
    c = substr(v, 1, 1)
    if (c == "-") {
      SG = -1
      v = substr(v, 2)
    } else if (c == "+") v = substr(v, 2)
    p = index(v, ".")
    if (p) {
      IP = substr(v, 1, p - 1)
      FP = substr(v, p + 1)
    } else {
      IP = v
      FP = ""
    }
  }

  # @internal
  function add(v,   k, e, s, limb) {
    parts(v)
    k = 0
    for (e = length(IP); e > 0; e -= 7) {
      s = (e > 7 ? e - 6 : 1)
      ACC[k] += SG * (substr(IP, s, e - s + 1) + 0)
      if (k > HI) HI = k
      k++
    }
    k = -1
    for (s = 1; s <= length(FP); s += 7) {
      limb = substr(FP, s, 7)
      while (length(limb) < 7) limb = limb "0"
      ACC[k] += SG * (limb + 0)
      if (k < LO) LO = k
      k--
    }
  }

  # Add v * v: every pair of its base-10^4 limbs lands on the sum of their places.
  # @internal
  function square(v,   k, e, s, limb, m, i, j) {
    parts(v)
    m = 0
    for (e = length(IP); e > 0; e -= 4) {
      s = (e > 4 ? e - 3 : 1)
      L[m] = substr(IP, s, e - s + 1) + 0
      P[m] = m
      m++
    }
    k = -1
    for (s = 1; s <= length(FP); s += 4) {
      limb = substr(FP, s, 4)
      while (length(limb) < 4) limb = limb "0"
      L[m] = limb + 0
      P[m] = k
      m++
      k--
    }
    for (i = 0; i < m; i++) {
      if (L[i] == 0) continue
      for (j = 0; j < m; j++) {
        k = P[i] + P[j]
        SQ[k] += L[i] * L[j]
        if (k > HI2) HI2 = k
        if (k < LO2) LO2 = k
      }
    }
  }

  # Carry every limb of A (LO..HI, base b) into [0, b). Returns the carry out
  # of the top limb, which is negative when the total is.
  # @internal
  function settle(acc, b, lo,   k, v, c) {
    c = 0
    for (k = lo; k <= TOP; k++) {
      v = acc[k] + c
      c = int(v / b)
      v -= c * b
      if (v < 0) {
        v += b
        c--
      }
      if (v >= b) {
        v -= b
        c++
      }
      acc[k] = v
    }
    while (c > 0) {
      TOP++
      acc[TOP] = c % b
      c = int(c / b)
    }
    return c
  }

  # Print a settled number: limbs of `width` digits from TOP down to lo.
  # @internal
  function render(acc, lo, width, sign,   k, ip, fp, fmt) {
    fmt = "%0" width "d"
    ip = ""
    for (k = TOP; k >= 0; k--) ip = ip sprintf(fmt, acc[k])
    fp = ""
    for (k = -1; k >= lo; k--) fp = fp sprintf(fmt, acc[k])
    sub(/^0+/, "", ip)
    if (ip == "") ip = "0"
    sub(/0+$/, "", fp)
    if (ip == "0" && fp == "") sign = ""
    return sign ip (fp == "" ? "" : "." fp)
  }

  # @internal
  function total(   c, k, sign) {
    TOP = HI
    c = settle(ACC, B, LO)
    sign = ""
    if (c < 0) {
      # The limbs hold total + |c| * B^(TOP+1); negating every limb and the
      # carry gives the magnitude, which settles without a carry out.
      for (k = LO; k <= TOP; k++) ACC[k] = -ACC[k]
      TOP++
      ACC[TOP] = -c
      settle(ACC, B, LO)
      sign = "-"
    }
    return render(ACC, LO, 7, sign)
  }

  # @internal
  function squares() {
    TOP = HI2
    settle(SQ, B2, LO2)
    return render(SQ, LO2, 4, "")
  }
'

#######################################
# @description Name the public function a failure should be reported against.
#   The digit helpers call one another, so `FUNCNAME[1]` is usually another
#   internal name; the caller wants to read the name they typed.
# @noargs
# @stdout The nearest `dybatpho::` function on the call stack
# @internal
#######################################
function __dybatpho_math_caller {
  local index
  for ((index = 1; index < ${#FUNCNAME[@]}; index++)); do
    if [[ "${FUNCNAME[index]}" == dybatpho::* ]]; then
      printf '%s' "${FUNCNAME[index]}"
      return 0
    fi
  done
  printf '%s' "${FUNCNAME[1]-math}" # kcov(skip)
}

#######################################
# @description Split a decimal into its sign and its two digit strings.
#   Both sides come back normalized — no leading zeros on the integer part, no
#   trailing zeros on the fraction, no sign on zero — so that every later step
#   works on one canonical shape.
# @arg $1 string Value in plain decimal notation
# @arg $2 string Name of the variable receiving the sign, `-` or empty
# @arg $3 string Name of the variable receiving the integer digits
# @arg $4 string Name of the variable receiving the fraction digits
# @set The three named variables
# @exitcode 1 Stop the script when the value is not a plain decimal number
# @internal
#######################################
function __dybatpho_math_parse {
  local __parse_value __parse_sign_name __parse_int_name __parse_frac_name
  dybatpho::expect_args __parse_value __parse_sign_name __parse_int_name __parse_frac_name -- "$@"
  local -n __parse_sign="${__parse_sign_name}"
  local -n __parse_int="${__parse_int_name}"
  local -n __parse_frac="${__parse_frac_name}"

  [[ "${__parse_value}" =~ ${DYBATPHO_MATH_NUMBER_REGEX} ]] \
    || {
      local math_caller_detail
      math_caller_detail=$(__dybatpho_math_caller)
      dybatpho::die "${math_caller_detail}: Not a number: '${__parse_value}'"
    }

  local __parse_rest="${__parse_value}"
  __parse_sign=""
  case "${__parse_rest}" in
    -*)
      __parse_sign="-"
      __parse_rest="${__parse_rest#-}"
      ;;
    +*) __parse_rest="${__parse_rest#+}" ;;
    *) ;;
  esac

  if [[ "${__parse_rest}" == *.* ]]; then
    __parse_int="${__parse_rest%%.*}"
    __parse_frac="${__parse_rest#*.}"
  else
    __parse_int="${__parse_rest}"
    __parse_frac=""
  fi

  while ((${#__parse_int} > 1)) && [[ "${__parse_int}" == 0* ]]; do
    __parse_int="${__parse_int#0}"
  done
  [[ -n "${__parse_int}" ]] || __parse_int="0"
  while [[ "${__parse_frac}" == *0 ]]; do
    __parse_frac="${__parse_frac%0}"
  done
  # Zero has no sign. Printing `-0` would be a true statement about the
  # computation and a confusing one about the value.
  [[ "${__parse_int}" == "0" && -z "${__parse_frac}" ]] && __parse_sign=""
  return 0
}

#######################################
# @description Drop the leading zeros of a digit string, in place.
# @arg $1 string Name of the variable holding the digits
# @set The named variable, never left empty
# @internal
#######################################
function __dybatpho_math_strip {
  local -n __strip_digits="$1"
  while ((${#__strip_digits} > 1)) && [[ "${__strip_digits}" == 0* ]]; do
    __strip_digits="${__strip_digits#0}"
  done
  [[ -n "${__strip_digits}" ]] || __strip_digits="0"
}

#######################################
# @description Compare two unsigned digit strings.
# @arg $1 string Name of the variable receiving `-1`, `0` or `1`
# @arg $2 string First digit string
# @arg $3 string Second digit string
# @set The named variable
# @internal
#######################################
function __dybatpho_math_cmp_abs {
  local __cmp_out_name __cmp_a __cmp_b
  dybatpho::expect_args __cmp_out_name __cmp_a __cmp_b -- "$@"
  local -n __cmp_out="${__cmp_out_name}"
  __dybatpho_math_strip __cmp_a
  __dybatpho_math_strip __cmp_b
  if ((${#__cmp_a} != ${#__cmp_b})); then
    if ((${#__cmp_a} > ${#__cmp_b})); then
      __cmp_out=1
    else
      __cmp_out=-1
    fi
    return 0
  fi
  if [[ "${__cmp_a}" == "${__cmp_b}" ]]; then
    __cmp_out=0
  elif [[ "${__cmp_a}" > "${__cmp_b}" ]]; then
    __cmp_out=1
  else
    __cmp_out=-1
  fi
}

#######################################
# @description Add two unsigned digit strings.
# @arg $1 string Name of the variable receiving the sum
# @arg $2 string First digit string
# @arg $3 string Second digit string
# @set The named variable
# @internal
#######################################
function __dybatpho_math_add_abs {
  local __add_out_name __add_a __add_b
  dybatpho::expect_args __add_out_name __add_a __add_b -- "$@"
  local -n __add_out="${__add_out_name}"
  local __add_ia=$((${#__add_a} - 1))
  local __add_ib=$((${#__add_b} - 1))
  local __add_carry=0 __add_sum __add_result=""
  while ((__add_ia >= 0 || __add_ib >= 0 || __add_carry)); do
    __add_sum="${__add_carry}"
    ((__add_ia >= 0)) && __add_sum=$((__add_sum + 10#${__add_a:__add_ia:1}))
    ((__add_ib >= 0)) && __add_sum=$((__add_sum + 10#${__add_b:__add_ib:1}))
    __add_result="$((__add_sum % 10))${__add_result}"
    __add_carry=$((__add_sum / 10))
    __add_ia=$((__add_ia - 1))
    __add_ib=$((__add_ib - 1))
  done
  __add_out="${__add_result:-0}"
  __dybatpho_math_strip __add_out
}

#######################################
# @description Subtract one unsigned digit string from a larger one.
# @arg $1 string Name of the variable receiving the difference
# @arg $2 string Digit string to subtract from, never smaller than `$3`
# @arg $3 string Digit string to subtract
# @set The named variable
# @internal
#######################################
function __dybatpho_math_sub_abs {
  local __sub_out_name __sub_a __sub_b
  dybatpho::expect_args __sub_out_name __sub_a __sub_b -- "$@"
  local -n __sub_out="${__sub_out_name}"
  local __sub_ia=$((${#__sub_a} - 1))
  local __sub_ib=$((${#__sub_b} - 1))
  local __sub_borrow=0 __sub_digit __sub_result=""
  while ((__sub_ia >= 0)); do
    __sub_digit=$((10#${__sub_a:__sub_ia:1} - __sub_borrow))
    ((__sub_ib >= 0)) && __sub_digit=$((__sub_digit - 10#${__sub_b:__sub_ib:1}))
    if ((__sub_digit < 0)); then
      __sub_digit=$((__sub_digit + 10))
      __sub_borrow=1
    else
      __sub_borrow=0
    fi
    __sub_result="${__sub_digit}${__sub_result}"
    __sub_ia=$((__sub_ia - 1))
    __sub_ib=$((__sub_ib - 1))
  done
  __sub_out="${__sub_result:-0}"
  __dybatpho_math_strip __sub_out
}

#######################################
# @description Multiply two unsigned digit strings, the long way.
# @arg $1 string Name of the variable receiving the product
# @arg $2 string First digit string
# @arg $3 string Second digit string
# @set The named variable
# @internal
#######################################
function __dybatpho_math_mul_abs {
  local __mul_out_name __mul_a __mul_b
  dybatpho::expect_args __mul_out_name __mul_a __mul_b -- "$@"
  local -n __mul_out="${__mul_out_name}"
  local -a __mul_columns=()
  local __mul_width=$((${#__mul_a} + ${#__mul_b}))
  local __mul_ia __mul_ib __mul_index __mul_digit __mul_carry __mul_product
  for ((__mul_index = 0; __mul_index < __mul_width; __mul_index++)); do
    __mul_columns[__mul_index]=0
  done
  for ((__mul_ia = ${#__mul_a} - 1; __mul_ia >= 0; __mul_ia--)); do
    __mul_digit=$((10#${__mul_a:__mul_ia:1}))
    __mul_carry=0
    for ((__mul_ib = ${#__mul_b} - 1; __mul_ib >= 0; __mul_ib--)); do
      __mul_index=$((__mul_ia + __mul_ib + 1))
      __mul_product=$((__mul_columns[__mul_index] + __mul_digit * 10#${__mul_b:__mul_ib:1} + __mul_carry))
      __mul_columns[__mul_index]=$((__mul_product % 10))
      __mul_carry=$((__mul_product / 10))
    done
    # Column `__mul_ia` is untouched until this point, so the carry lands in it
    # whole and can never push it past a single digit.
    __mul_columns[__mul_ia]=$((__mul_columns[__mul_ia] + __mul_carry))
  done
  printf -v __mul_out '%s' ${__mul_columns[@]+"${__mul_columns[@]}"}
  __dybatpho_math_strip __mul_out
}

#######################################
# @description Divide one unsigned digit string by another, long division.
# @arg $1 string Name of the variable receiving the quotient digits
# @arg $2 string Name of the variable receiving the remainder digits
# @arg $3 string Digit string to divide
# @arg $4 string Digit string to divide by, never zero
# @set The two named variables
# @internal
#######################################
function __dybatpho_math_divmod_abs {
  local __div_quot_name __div_rem_name __div_a __div_b
  dybatpho::expect_args __div_quot_name __div_rem_name __div_a __div_b -- "$@"
  local -n __div_quot="${__div_quot_name}"
  local -n __div_rem="${__div_rem_name}"
  local __div_index __div_digit __div_cmp __div_remainder="0" __div_result=""
  for ((__div_index = 0; __div_index < ${#__div_a}; __div_index++)); do
    __div_remainder="${__div_remainder}${__div_a:__div_index:1}"
    __dybatpho_math_strip __div_remainder
    __div_digit=0
    # A decimal digit is at most nine subtractions away, which keeps the inner
    # step to the same borrow arithmetic the rest of the module uses.
    while :; do
      __dybatpho_math_cmp_abs __div_cmp "${__div_remainder}" "${__div_b}"
      ((__div_cmp >= 0)) || break
      __dybatpho_math_sub_abs __div_remainder "${__div_remainder}" "${__div_b}"
      __div_digit=$((__div_digit + 1))
    done
    __div_result="${__div_result}${__div_digit}"
  done
  __div_quot="${__div_result}"
  __dybatpho_math_strip __div_quot
  __div_rem="${__div_remainder}"
  __dybatpho_math_strip __div_rem
}

#######################################
# @description Round a fraction to a width, carrying into the integer part.
#   Ties round away from zero, which is what a person reading an invoice
#   expects; `printf` rounds binary floats to even and disagrees on exact halves.
# @arg $1 string Name of the variable holding the integer digits
# @arg $2 string Name of the variable holding the fraction digits
# @arg $3 number Requested number of fraction digits
# @set The two named variables
# @internal
#######################################
function __dybatpho_math_round_digits {
  local __round_int_name __round_frac_name __round_precision
  dybatpho::expect_args __round_int_name __round_frac_name __round_precision -- "$@"
  local -n __round_int="${__round_int_name}"
  local -n __round_frac="${__round_frac_name}"

  if ((${#__round_frac} <= __round_precision)); then
    while ((${#__round_frac} < __round_precision)); do
      __round_frac="${__round_frac}0"
    done
    return 0
  fi

  local __round_next="${__round_frac:__round_precision:1}"
  __round_frac="${__round_frac:0:__round_precision}"
  ((10#${__round_next} >= 5)) || return 0

  local __round_carried
  __dybatpho_math_add_abs __round_carried "${__round_int}${__round_frac}" "1"
  while ((${#__round_carried} < __round_precision + 1)); do
    __round_carried="0${__round_carried}"
  done
  if ((__round_precision > 0)); then
    __round_frac="${__round_carried: -__round_precision}"
    __round_int="${__round_carried:0:${#__round_carried}-__round_precision}"
  else
    __round_frac=""
    __round_int="${__round_carried}"
  fi
  __dybatpho_math_strip __round_int
}

#######################################
# @description Split a digit string that carries an implied decimal point.
# @arg $1 string Name of the variable receiving the integer digits
# @arg $2 string Name of the variable receiving the fraction digits
# @arg $3 string Digit string
# @arg $4 number Number of digits that belong to the fraction
# @set The two named variables
# @internal
#######################################
function __dybatpho_math_unscale {
  local __unscale_int_name __unscale_frac_name __unscale_digits __unscale_scale
  dybatpho::expect_args __unscale_int_name __unscale_frac_name __unscale_digits __unscale_scale -- "$@"
  local -n __unscale_int="${__unscale_int_name}"
  local -n __unscale_frac="${__unscale_frac_name}"
  while ((${#__unscale_digits} <= __unscale_scale)); do
    __unscale_digits="0${__unscale_digits}"
  done
  __unscale_int="${__unscale_digits:0:${#__unscale_digits}-__unscale_scale}"
  if ((__unscale_scale > 0)); then
    __unscale_frac="${__unscale_digits: -__unscale_scale}"
  else
    __unscale_frac=""
  fi
  __dybatpho_math_strip __unscale_int
}

#######################################
# @description Assemble a sign and two digit strings into a canonical number.
# @arg $1 string Name of the variable receiving the number
# @arg $2 string Sign, `-` or empty
# @arg $3 string Integer digits
# @arg $4 string Fraction digits
# @set The named variable
# @internal
#######################################
function __dybatpho_math_compose {
  local __compose_out_name __compose_sign __compose_int __compose_frac
  dybatpho::expect_args __compose_out_name __compose_sign __compose_int __compose_frac -- "$@"
  local -n __compose_out="${__compose_out_name}"
  __dybatpho_math_strip __compose_int
  while [[ "${__compose_frac}" == *0 ]]; do
    __compose_frac="${__compose_frac%0}"
  done
  [[ "${__compose_int}" == "0" && -z "${__compose_frac}" ]] && __compose_sign=""
  if [[ -n "${__compose_frac}" ]]; then
    __compose_out="${__compose_sign}${__compose_int}.${__compose_frac}"
  else
    __compose_out="${__compose_sign}${__compose_int}"
  fi
}

#######################################
# @description Line two parsed values up on the same number of fraction digits.
# @arg $1 string Name of the variable receiving the first digit string
# @arg $2 string Name of the variable receiving the second digit string
# @arg $3 string Name of the variable receiving the shared fraction width
# @arg $4 string Integer digits of the first value
# @arg $5 string Fraction digits of the first value
# @arg $6 string Integer digits of the second value
# @arg $7 string Fraction digits of the second value
# @set The three named variables
# @internal
#######################################
function __dybatpho_math_align {
  local __align_a_name __align_b_name __align_scale_name
  local __align_int_a __align_frac_a __align_int_b __align_frac_b
  dybatpho::expect_args __align_a_name __align_b_name __align_scale_name \
    __align_int_a __align_frac_a __align_int_b __align_frac_b -- "$@"
  local -n __align_a="${__align_a_name}"
  local -n __align_b="${__align_b_name}"
  local -n __align_scale="${__align_scale_name}"
  __align_scale=${#__align_frac_a}
  ((${#__align_frac_b} > __align_scale)) && __align_scale=${#__align_frac_b}
  while ((${#__align_frac_a} < __align_scale)); do __align_frac_a="${__align_frac_a}0"; done
  while ((${#__align_frac_b} < __align_scale)); do __align_frac_b="${__align_frac_b}0"; done
  __align_a="${__align_int_a}${__align_frac_a}"
  __align_b="${__align_int_b}${__align_frac_b}"
}

#######################################
# @description Read a short decimal as a Bash integer of all its digits, into
#   named variables, so a sum, product or comparison of two short values can
#   run in `$(( ))` instead of digit by digit. A value is short when it has at
#   most seventeen significant digits, which keeps every intermediate result
#   below the 2^63 Bash arithmetic holds, so the answer stays exact.
# @arg $1 string Name of the variable receiving the signed integer of the digits
# @arg $2 string Name of the variable receiving the number of fraction digits
# @arg $3 string Name of the variable receiving the number of integer digits
# @arg $4 string Value
# @set The three named variables
# @exitcode 0 The value is a short decimal
# @exitcode 1 It is long, or not a number; the caller takes the digit path, which reports the latter
# @internal
#######################################
function __dybatpho_math_short_into {
  local -n __dybatpho_math_short_digits="$1" __dybatpho_math_short_scale="$2" __dybatpho_math_short_width="$3"
  local __dybatpho_math_short_value="$4" __dybatpho_math_short_sign=""
  [[ "${__dybatpho_math_short_value}" =~ ${DYBATPHO_MATH_NUMBER_REGEX} ]] || return 1
  case "${__dybatpho_math_short_value}" in
    -*) __dybatpho_math_short_sign="-" __dybatpho_math_short_value="${__dybatpho_math_short_value:1}" ;;
    +*) __dybatpho_math_short_value="${__dybatpho_math_short_value:1}" ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac
  local __dybatpho_math_short_int="${__dybatpho_math_short_value%%.*}" __dybatpho_math_short_frac=""
  [[ "${__dybatpho_math_short_value}" != *.* ]] || __dybatpho_math_short_frac="${__dybatpho_math_short_value#*.}"
  __dybatpho_math_short_int="${__dybatpho_math_short_int#"${__dybatpho_math_short_int%%[!0]*}"}"
  __dybatpho_math_short_frac="${__dybatpho_math_short_frac%"${__dybatpho_math_short_frac##*[!0]}"}"
  ((${#__dybatpho_math_short_int} + ${#__dybatpho_math_short_frac} <= 17)) || return 1
  __dybatpho_math_short_width=${#__dybatpho_math_short_int}
  # The leading `0` keeps an empty digit string valid, and `10#` keeps a
  # leading zero of the fraction from reading as octal.
  __dybatpho_math_short_int+="${__dybatpho_math_short_frac}"
  __dybatpho_math_short_digits=$((${__dybatpho_math_short_sign}10#0${__dybatpho_math_short_int}))
  __dybatpho_math_short_scale=${#__dybatpho_math_short_frac}
}

#######################################
# @description Write a Bash integer carrying an implied decimal point as a
#   canonical number, into a named variable.
# @arg $1 string Name of the variable receiving the number
# @arg $2 number Integer of all the digits, signed
# @arg $3 number Number of those digits that belong to the fraction
# @set The named variable
# @internal
#######################################
function __dybatpho_math_unshort_into {
  local -n __dybatpho_math_unshort_out="$1"
  local __dybatpho_math_unshort_digits="${2#-}" __dybatpho_math_unshort_sign=""
  [[ "$2" != -* ]] || __dybatpho_math_unshort_sign="-"
  local __dybatpho_math_unshort_scale="$3" __dybatpho_math_unshort_frac="" __dybatpho_math_unshort_cut
  while ((${#__dybatpho_math_unshort_digits} <= __dybatpho_math_unshort_scale)); do
    __dybatpho_math_unshort_digits="0${__dybatpho_math_unshort_digits}"
  done
  if ((__dybatpho_math_unshort_scale > 0)); then
    __dybatpho_math_unshort_cut=$((${#__dybatpho_math_unshort_digits} - __dybatpho_math_unshort_scale))
    __dybatpho_math_unshort_frac="${__dybatpho_math_unshort_digits:__dybatpho_math_unshort_cut}"
    __dybatpho_math_unshort_digits="${__dybatpho_math_unshort_digits:0:__dybatpho_math_unshort_cut}"
    __dybatpho_math_unshort_frac="${__dybatpho_math_unshort_frac%"${__dybatpho_math_unshort_frac##*[!0]}"}"
  fi
  # `$(( ))` printed the digits without leading zeros, so only the padding
  # above can leave one, and then the integer part is exactly `0`.
  if [[ -n "${__dybatpho_math_unshort_frac}" ]]; then
    __dybatpho_math_unshort_out="${__dybatpho_math_unshort_sign}${__dybatpho_math_unshort_digits}"
    __dybatpho_math_unshort_out+=".${__dybatpho_math_unshort_frac}"
  elif [[ "${__dybatpho_math_unshort_digits}" == "0" ]]; then
    __dybatpho_math_unshort_out="0"
  else
    __dybatpho_math_unshort_out="${__dybatpho_math_unshort_sign}${__dybatpho_math_unshort_digits}"
  fi
}

#######################################
# @description Line two short values up on one scale, into named variables,
#   when both still fit in Bash arithmetic once aligned.
# @arg $1 string Name of the variable receiving the first aligned integer
# @arg $2 string Name of the variable receiving the second aligned integer
# @arg $3 string Name of the variable receiving the shared scale
# @arg $4 string First value
# @arg $5 string Second value
# @set The three named variables
# @exitcode 0 Both are short and aligned
# @exitcode 1 Either is long or not a number
# @internal
#######################################
function __dybatpho_math_short_pair_into {
  local -n __dybatpho_math_pair_a="$1" __dybatpho_math_pair_b="$2" __dybatpho_math_pair_scale="$3"
  local __dybatpho_math_pair_sa __dybatpho_math_pair_sb __dybatpho_math_pair_wa __dybatpho_math_pair_wb
  __dybatpho_math_short_into __dybatpho_math_pair_a __dybatpho_math_pair_sa __dybatpho_math_pair_wa "$4" || return 1
  __dybatpho_math_short_into __dybatpho_math_pair_b __dybatpho_math_pair_sb __dybatpho_math_pair_wb "$5" || return 1
  __dybatpho_math_pair_scale=${__dybatpho_math_pair_sa}
  ((__dybatpho_math_pair_sb <= __dybatpho_math_pair_scale)) || __dybatpho_math_pair_scale=${__dybatpho_math_pair_sb}
  # Seventeen digits either side of the point keeps both below 10^17 and their
  # sum below 2^63.
  ((__dybatpho_math_pair_wa + __dybatpho_math_pair_scale <= 17)) || return 1
  ((__dybatpho_math_pair_wb + __dybatpho_math_pair_scale <= 17)) || return 1
  while ((__dybatpho_math_pair_sa < __dybatpho_math_pair_scale)); do
    __dybatpho_math_pair_a=$((__dybatpho_math_pair_a * 10))
    __dybatpho_math_pair_sa=$((__dybatpho_math_pair_sa + 1))
  done
  while ((__dybatpho_math_pair_sb < __dybatpho_math_pair_scale)); do
    __dybatpho_math_pair_b=$((__dybatpho_math_pair_b * 10))
    __dybatpho_math_pair_sb=$((__dybatpho_math_pair_sb + 1))
  done
}

#######################################
# @description Flip the sign of a number.
# @arg $1 string Name of the variable receiving the negated value
# @arg $2 string Value
# @set The named variable
# @exitcode 1 Stop the script when the value is not a number
# @internal
#######################################
function __dybatpho_math_negate {
  local __neg_out_name __neg_value
  dybatpho::expect_args __neg_out_name __neg_value -- "$@"
  local -n __neg_out="${__neg_out_name}"
  local __neg_sign __neg_int __neg_frac
  __dybatpho_math_parse "${__neg_value}" __neg_sign __neg_int __neg_frac
  if [[ -n "${__neg_sign}" ]]; then
    __neg_sign=""
  else
    __neg_sign="-"
  fi
  __dybatpho_math_compose __neg_out "${__neg_sign}" "${__neg_int}" "${__neg_frac}"
}

#######################################
# @description Add two numbers, sign included.
# @arg $1 string Name of the variable receiving the sum
# @arg $2 string First value
# @arg $3 string Second value
# @set The named variable
# @exitcode 1 Stop the script when either value is not a number
# @internal
#######################################
function __dybatpho_math_add2 {
  local __add2_out_name __add2_a __add2_b
  dybatpho::expect_args __add2_out_name __add2_a __add2_b -- "$@"
  local -n __add2_out="${__add2_out_name}"
  local __add2_short_a __add2_short_b __add2_short_scale
  if __dybatpho_math_short_pair_into __add2_short_a __add2_short_b __add2_short_scale "${__add2_a}" "${__add2_b}"; then
    __dybatpho_math_unshort_into __add2_out "$((__add2_short_a + __add2_short_b))" "${__add2_short_scale}"
    return 0
  fi
  local __add2_sign_a __add2_int_a __add2_frac_a
  local __add2_sign_b __add2_int_b __add2_frac_b
  __dybatpho_math_parse "${__add2_a}" __add2_sign_a __add2_int_a __add2_frac_a
  __dybatpho_math_parse "${__add2_b}" __add2_sign_b __add2_int_b __add2_frac_b

  local __add2_digits_a __add2_digits_b __add2_scale __add2_total __add2_sign __add2_cmp
  __dybatpho_math_align __add2_digits_a __add2_digits_b __add2_scale \
    "${__add2_int_a}" "${__add2_frac_a}" "${__add2_int_b}" "${__add2_frac_b}"

  if [[ "${__add2_sign_a}" == "${__add2_sign_b}" ]]; then
    __dybatpho_math_add_abs __add2_total "${__add2_digits_a}" "${__add2_digits_b}"
    __add2_sign="${__add2_sign_a}"
  else
    __dybatpho_math_cmp_abs __add2_cmp "${__add2_digits_a}" "${__add2_digits_b}"
    if ((__add2_cmp >= 0)); then
      __dybatpho_math_sub_abs __add2_total "${__add2_digits_a}" "${__add2_digits_b}"
      __add2_sign="${__add2_sign_a}"
    else
      __dybatpho_math_sub_abs __add2_total "${__add2_digits_b}" "${__add2_digits_a}"
      __add2_sign="${__add2_sign_b}"
    fi
  fi

  local __add2_int __add2_frac
  __dybatpho_math_unscale __add2_int __add2_frac "${__add2_total}" "${__add2_scale}"
  __dybatpho_math_compose __add2_out "${__add2_sign}" "${__add2_int}" "${__add2_frac}"
}

#######################################
# @description Multiply two numbers, sign included.
# @arg $1 string Name of the variable receiving the product
# @arg $2 string First value
# @arg $3 string Second value
# @set The named variable
# @exitcode 1 Stop the script when either value is not a number
# @internal
#######################################
function __dybatpho_math_mul2 {
  local __mul2_out_name __mul2_a __mul2_b
  dybatpho::expect_args __mul2_out_name __mul2_a __mul2_b -- "$@"
  local -n __mul2_out="${__mul2_out_name}"
  local __mul2_short_a __mul2_short_b __mul2_scale_a __mul2_scale_b __mul2_width_a __mul2_width_b
  # Two values of at most eighteen significant digits between them multiply
  # below 10^18, inside Bash arithmetic.
  if __dybatpho_math_short_into __mul2_short_a __mul2_scale_a __mul2_width_a "${__mul2_a}" \
    && __dybatpho_math_short_into __mul2_short_b __mul2_scale_b __mul2_width_b "${__mul2_b}" \
    && ((__mul2_width_a + __mul2_scale_a + __mul2_width_b + __mul2_scale_b <= 18)); then
    __dybatpho_math_unshort_into __mul2_out "$((__mul2_short_a * __mul2_short_b))" \
      "$((__mul2_scale_a + __mul2_scale_b))"
    return 0
  fi
  local __mul2_sign_a __mul2_int_a __mul2_frac_a
  local __mul2_sign_b __mul2_int_b __mul2_frac_b
  __dybatpho_math_parse "${__mul2_a}" __mul2_sign_a __mul2_int_a __mul2_frac_a
  __dybatpho_math_parse "${__mul2_b}" __mul2_sign_b __mul2_int_b __mul2_frac_b

  local __mul2_product __mul2_sign="" __mul2_int __mul2_frac
  __dybatpho_math_mul_abs __mul2_product \
    "${__mul2_int_a}${__mul2_frac_a}" "${__mul2_int_b}${__mul2_frac_b}"
  [[ "${__mul2_sign_a}" != "${__mul2_sign_b}" ]] && __mul2_sign="-"
  __dybatpho_math_unscale __mul2_int __mul2_frac "${__mul2_product}" \
    "$((${#__mul2_frac_a} + ${#__mul2_frac_b}))"
  __dybatpho_math_compose __mul2_out "${__mul2_sign}" "${__mul2_int}" "${__mul2_frac}"
}

#######################################
# @description Divide two numbers to a requested number of fraction digits,
#   rounding half away from zero.
# @arg $1 string Name of the variable receiving the quotient
# @arg $2 string Dividend
# @arg $3 string Divisor
# @arg $4 number Fraction digits to keep
# @set The named variable
# @exitcode 1 Stop the script on a bad value, a bad scale, or a zero divisor
# @internal
#######################################
function __dybatpho_math_div2 {
  local __div2_out_name __div2_a __div2_b __div2_scale
  dybatpho::expect_args __div2_out_name __div2_a __div2_b __div2_scale -- "$@"
  local -n __div2_out="${__div2_out_name}"
  [[ "${__div2_scale}" =~ ^[0-9]+$ ]] \
    || {
      local math_caller_detail
      math_caller_detail=$(__dybatpho_math_caller)
      dybatpho::die "${math_caller_detail}: Scale must be a non-negative integer, got '${__div2_scale}'"
    }
  # Read in base ten: `08` would otherwise be an invalid octal literal.
  __div2_scale=$((10#${__div2_scale}))
  local __div2_sign_a __div2_int_a __div2_frac_a
  local __div2_sign_b __div2_int_b __div2_frac_b
  __dybatpho_math_parse "${__div2_a}" __div2_sign_a __div2_int_a __div2_frac_a
  __dybatpho_math_parse "${__div2_b}" __div2_sign_b __div2_int_b __div2_frac_b
  [[ "${__div2_int_b}" != "0" || -n "${__div2_frac_b}" ]] \
    || {
      local math_caller_detail
      math_caller_detail=$(__dybatpho_math_caller)
      dybatpho::die "${math_caller_detail}: Division by zero"
    }

  local __div2_num="${__div2_int_a}${__div2_frac_a}"
  local __div2_den="${__div2_int_b}${__div2_frac_b}"
  # One guard digit beyond the requested scale is what the rounding step needs
  # to decide the last kept digit.
  local __div2_shift=$((${#__div2_frac_b} - ${#__div2_frac_a} + __div2_scale + 1))
  local __div2_index
  if ((__div2_shift >= 0)); then
    for ((__div2_index = 0; __div2_index < __div2_shift; __div2_index++)); do
      __div2_num="${__div2_num}0"
    done
  else
    for ((__div2_index = 0; __div2_index < -__div2_shift; __div2_index++)); do
      __div2_den="${__div2_den}0"
    done
  fi

  local __div2_quot __div2_rem __div2_int __div2_frac __div2_sign=""
  __dybatpho_math_divmod_abs __div2_quot __div2_rem "${__div2_num}" "${__div2_den}"
  [[ "${__div2_sign_a}" != "${__div2_sign_b}" ]] && __div2_sign="-"
  __dybatpho_math_unscale __div2_int __div2_frac "${__div2_quot}" "$((__div2_scale + 1))"
  __dybatpho_math_round_digits __div2_int __div2_frac "${__div2_scale}"
  __dybatpho_math_compose __div2_out "${__div2_sign}" "${__div2_int}" "${__div2_frac}"
}

#######################################
# @description Collect the values an aggregate works on, from the arguments or
#   from standard input.
# @arg $1 string Name of the array receiving the values
# @arg $@ string Values, or none to read standard input
# @set The named array
# @internal
#######################################
function __dybatpho_math_collect {
  local -n __collect_out="$1"
  shift
  __collect_out=()
  if (($#)); then
    __collect_out=("$@")
    return 0
  fi
  local -a __collect_fields=()
  # A line may hold several values, which is what `awk` or `cut` hands over.
  # `read -a` splits them without the pathname expansion an unquoted
  # expansion would add, so a `*` is a value rather than the file names here.
  # A last line without a newline makes `read` fail after filling the fields,
  # so a non-empty array still counts.
  while read -r -a __collect_fields || ((${#__collect_fields[@]})); do
    __collect_out+=(${__collect_fields[@]+"${__collect_fields[@]}"})
  done
}

#######################################
# @description Run a list aggregate through the `awk` engine, into a named
#   variable, when `DYBATPHO_MATH_ENGINE` allows it, the list is long enough
#   under `auto` to repay starting a process, and `awk` is installed.
#   Anything the engine cannot answer exactly as the Bash engine would -- a
#   value that is not a number, or one holding a line break -- returns failure
#   instead, and the caller runs the Bash engine, which reports it.
# @arg $1 string Name of the variable receiving the output
# @arg $2 string Aggregate: `sum`, `sumsq`, `min`, `max`, or `sort`
# @arg $@ string Values
# @set The named variable: one line, two for `sumsq`, one value a line for `sort`
# @exitcode 0 The engine answered
# @exitcode 1 Use the Bash engine
# @internal
#######################################
function __dybatpho_math_awk_into {
  local -n __dybatpho_math_awk_out="$1"
  local __dybatpho_math_awk_mode="$2"
  shift 2
  case "${DYBATPHO_MATH_ENGINE}" in
    bash) return 1 ;;
    awk) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
    auto) (($# >= __dybatpho_math_awk_threshold)) || return 1 ;;
    # "DYBATPHO_MATH_ENGINE picks the engine and refuses one it does not know"
    # covers this; `dybatpho::die` exits, so that test uses `run`.
    *)
      local __dybatpho_math_awk_caller                                                      # kcov(skip)
      __dybatpho_math_awk_caller="$(__dybatpho_math_caller)"                                # kcov(skip)
      __dybatpho_math_awk_caller+=": Unknown DYBATPHO_MATH_ENGINE: ${DYBATPHO_MATH_ENGINE}" # kcov(skip)
      dybatpho::die "${__dybatpho_math_awk_caller}. Use auto, awk, or bash"                 # kcov(skip)
      ;;
  esac
  (($#)) || return 1
  command -v awk &> /dev/null || return 1
  # One value a line: a value holding a line break would read as two.
  local IFS=' '
  [[ "$*" != *$'\n'* ]] || return 1
  __dybatpho_math_awk_out="$(printf '%s\n' "$@" \
    | LC_ALL=C command awk "${__dybatpho_math_awk_program}${__dybatpho_math_awk_lib}" "${__dybatpho_math_awk_mode}")"
}

#######################################
# @description Return success when a value is a plain decimal number.
#   Scientific notation, thousands separators and hexadecimal are not numbers
#   here: every other function in this module rejects them, and this is the test
#   that says so before one of them stops the script.
# @example
#   dybatpho::math_is_number "-12.5" && echo yes   # yes
#   dybatpho::math_is_number "1e3" || echo no      # no
#
# @arg $1 string Value to test
# @exitcode 0 The value is a number
# @exitcode 1 It is not
#######################################
function dybatpho::math_is_number {
  local value
  dybatpho::expect_args value -- "$@"
  [[ "${value}" =~ ${DYBATPHO_MATH_NUMBER_REGEX} ]]
}

#######################################
# @description Return success when a value is a whole number.
#   A fraction that is only zeros still counts, so `2.00` is an integer.
# @example
#   dybatpho::math_is_integer "2.00" && echo yes   # yes
#   dybatpho::math_is_integer "2.01" || echo no    # no
#
# @arg $1 string Value to test
# @exitcode 0 The value is a whole number
# @exitcode 1 It is not a number, or it has a fractional part
#######################################
function dybatpho::math_is_integer {
  local value
  dybatpho::expect_args value -- "$@"
  dybatpho::math_is_number "${value}" || return 1
  local sign integer fraction
  __dybatpho_math_parse "${value}" sign integer fraction
  [[ -z "${fraction}" ]]
}

#######################################
# @description Add numbers exactly.
# @example
#   dybatpho::math_add 0.1 0.2           # 0.3
#   dybatpho::math_add 19.99 5.01 0.5    # 25.5
#
# @arg $@ string Two or more values
# @stdout The sum
# @exitcode 1 Stop the script when a value is not a number
#######################################
function dybatpho::math_add {
  local a b
  dybatpho::expect_args a b -- "$@"
  shift 2
  local total operand
  __dybatpho_math_add2 total "${a}" "${b}"
  for operand in "$@"; do
    __dybatpho_math_add2 total "${total}" "${operand}"
  done
  printf '%s\n' "${total}"
}

#######################################
# @description Subtract the second number from the first, and any further
#   numbers from the running result.
# @example
#   dybatpho::math_sub 1 0.9         # 0.1
#   dybatpho::math_sub 100 10 5      # 85
#
# @arg $@ string Two or more values
# @stdout The difference
# @exitcode 1 Stop the script when a value is not a number
#######################################
function dybatpho::math_sub {
  local a b
  dybatpho::expect_args a b -- "$@"
  shift 2
  local total operand negated
  __dybatpho_math_negate negated "${b}"
  __dybatpho_math_add2 total "${a}" "${negated}"
  for operand in "$@"; do
    __dybatpho_math_negate negated "${operand}"
    __dybatpho_math_add2 total "${total}" "${negated}"
  done
  printf '%s\n' "${total}"
}

#######################################
# @description Multiply numbers exactly. The result keeps every digit both
#   operands contributed, so a price times a quantity is never rounded.
# @example
#   dybatpho::math_mul 19.99 3               # 59.97
#   dybatpho::math_mul 99999999999 99999999999  # 9999999999800000000001
#
# @arg $@ string Two or more values
# @stdout The product
# @exitcode 1 Stop the script when a value is not a number
#######################################
function dybatpho::math_mul {
  local a b
  dybatpho::expect_args a b -- "$@"
  shift 2
  local total operand
  __dybatpho_math_mul2 total "${a}" "${b}"
  for operand in "$@"; do
    __dybatpho_math_mul2 total "${total}" "${operand}"
  done
  printf '%s\n' "${total}"
}

#######################################
# @description Divide one number by another, rounding half away from zero.
# @example
#   dybatpho::math_div 10 4        # 2.5
#   dybatpho::math_div 2 3 5       # 0.66667
#   dybatpho::math_div 1 3 0       # 0
#
# @arg $1 string Dividend
# @arg $2 string Divisor
# @arg $3 number [default: ${DYBATPHO_MATH_SCALE}] Fraction digits to keep
# @env DYBATPHO_MATH_SCALE number Default fraction digits
# @stdout The quotient
# @exitcode 1 Stop the script on a non-number, a bad scale, or a zero divisor
# @tip Division is the one operation that cannot always be exact; every other
#   operation in this module keeps all of its digits
#######################################
function dybatpho::math_div {
  local a b
  dybatpho::expect_args a b -- "$@"
  local scale="${3-${DYBATPHO_MATH_SCALE}}"
  local quotient
  __dybatpho_math_div2 quotient "${a}" "${b}" "${scale}"
  printf '%s\n' "${quotient}"
}

#######################################
# @description Print the remainder of an integer division. The sign follows the
#   dividend, the way `%` does in Bash and in C.
# @example
#   dybatpho::math_mod 17 5     # 2
#   dybatpho::math_mod -17 5    # -2
#
# @arg $1 string Dividend, a whole number
# @arg $2 string Divisor, a whole number
# @stdout The remainder
# @exitcode 1 Stop the script on a fractional operand or a zero divisor
#######################################
function dybatpho::math_mod {
  local a b
  dybatpho::expect_args a b -- "$@"
  # shellcheck disable=SC2034 # out-param of the parse; the remainder takes the dividend's sign
  local sign_a int_a frac_a sign_b int_b frac_b
  __dybatpho_math_parse "${a}" sign_a int_a frac_a
  __dybatpho_math_parse "${b}" sign_b int_b frac_b
  [[ -z "${frac_a}" && -z "${frac_b}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected whole numbers, got '${a}' and '${b}'"
  [[ "${int_b}" != "0" ]] || dybatpho::die "${FUNCNAME[0]}: Division by zero"
  local quotient remainder result
  __dybatpho_math_divmod_abs quotient remainder "${int_a}" "${int_b}"
  __dybatpho_math_compose result "${sign_a}" "${remainder}" ""
  printf '%s\n' "${result}"
}

#######################################
# @description Raise a number to a whole power.
# @example
#   dybatpho::math_pow 2 10        # 1024
#   dybatpho::math_pow 1.05 3      # 1.157625
#   dybatpho::math_pow 2 -3        # 0.125
#
# @arg $1 string Base
# @arg $2 string Exponent, a whole number
# @arg $3 number [default: ${DYBATPHO_MATH_SCALE}] Fraction digits for a negative exponent
# @env DYBATPHO_MATH_SCALE number Default fraction digits for a negative exponent
# @env DYBATPHO_MATH_MAX_EXPONENT number Largest exponent magnitude accepted
# @stdout The power
# @exitcode 1 Stop the script on a fractional or oversized exponent, or on `0` raised to a negative power
# @note A positive exponent is exact. A negative one is a division, so it rounds
#   at the requested scale like `dybatpho::math_div`.
#######################################
function dybatpho::math_pow {
  local base exponent
  dybatpho::expect_args base exponent -- "$@"
  local scale="${3-${DYBATPHO_MATH_SCALE}}"
  [[ "${exponent}" =~ ^[+-]?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Exponent must be a whole number, got '${exponent}'"
  local magnitude="${exponent#[+-]}"
  # Measured as text first: past 64 bits `$(( ))` wraps, and an exponent of
  # 2^64 + 1 read as 1.
  magnitude="${magnitude#"${magnitude%%[!0]*}"}"
  ((${#magnitude} <= ${#DYBATPHO_MATH_MAX_EXPONENT})) || magnitude="${DYBATPHO_MATH_MAX_EXPONENT}0"
  magnitude=$((10#${magnitude:-0}))
  ((magnitude <= DYBATPHO_MATH_MAX_EXPONENT)) \
    || dybatpho::die \
      "${FUNCNAME[0]}: Exponent magnitude must be at most ${DYBATPHO_MATH_MAX_EXPONENT}, got '${exponent}'"

  local sign integer fraction
  __dybatpho_math_parse "${base}" sign integer fraction

  # Square-and-multiply keeps a large exponent to a handful of long
  # multiplications rather than one per step.
  local result="1" factor="${base}" remaining="${magnitude}"
  while ((remaining > 0)); do
    ((remaining % 2 == 1)) && __dybatpho_math_mul2 result "${result}" "${factor}"
    remaining=$((remaining / 2))
    ((remaining > 0)) && __dybatpho_math_mul2 factor "${factor}" "${factor}"
  done

  if [[ "${exponent}" == -* ]] && ((magnitude > 0)); then
    [[ "${integer}" != "0" || -n "${fraction}" ]] \
      || dybatpho::die "${FUNCNAME[0]}: Zero cannot be raised to a negative power"
    __dybatpho_math_div2 result "1" "${result}" "${scale}"
  fi
  printf '%s\n' "${result}"
}

#######################################
# @description Print a number without its sign.
# @example
#   dybatpho::math_abs -12.5    # 12.5
#
# @arg $1 string Value
# @stdout The magnitude
# @exitcode 1 Stop the script when the value is not a number
#######################################
function dybatpho::math_abs {
  local value
  dybatpho::expect_args value -- "$@"
  local sign integer fraction result
  __dybatpho_math_parse "${value}" sign integer fraction
  __dybatpho_math_compose result "" "${integer}" "${fraction}"
  printf '%s\n' "${result}"
}

#######################################
# @description Print a number with its sign flipped.
# @example
#   dybatpho::math_neg 12.5    # -12.5
#   dybatpho::math_neg -12.5   # 12.5
#   dybatpho::math_neg 0       # 0
#
# @arg $1 string Value
# @stdout The negated value
# @exitcode 1 Stop the script when the value is not a number
#######################################
function dybatpho::math_neg {
  local value
  dybatpho::expect_args value -- "$@"
  local result
  __dybatpho_math_negate result "${value}"
  printf '%s\n' "${result}"
}

#######################################
# @description Compare two numbers by value rather than as strings.
# @example
#   dybatpho::math_compare 1.10 1.9     # -1
#   dybatpho::math_compare 2.50 2.5     # 0
#   (($(dybatpho::math_compare "${used}" "${quota}") > 0)) && dybatpho::warn "Over quota"
#
# @arg $1 string First value
# @arg $2 string Second value
# @stdout `-1` when the first is smaller, `0` when they are equal, `1` when it is larger
# @exitcode 1 Stop the script when a value is not a number
#######################################
function dybatpho::math_compare {
  local a b
  dybatpho::expect_args a b -- "$@"
  local result
  __dybatpho_math_cmp2 result "${a}" "${b}"
  printf '%s\n' "${result}"
}

#######################################
# @description Return success when the first number is greater than the second.
# @example
#   dybatpho::math_gt "${balance}" 0 || dybatpho::die "Account is empty"
#
# @arg $1 string First value
# @arg $2 string Second value
# @exitcode 0 The first value is greater
# @exitcode 1 It is not
#######################################
function dybatpho::math_gt {
  local a b
  dybatpho::expect_args a b -- "$@"
  # In this shell, not in `$(...)`: a value that is not a number has to stop
  # the script, and from a subshell the stop would end only the subshell while
  # the caller read the empty answer as "no".
  local order
  __dybatpho_math_cmp2 order "${a}" "${b}"
  ((order > 0))
}

#######################################
# @description Return success when the first number is less than the second.
# @example
#   dybatpho::math_lt "${free_gb}" 1 && dybatpho::warn "Disk nearly full"
#
# @arg $1 string First value
# @arg $2 string Second value
# @exitcode 0 The first value is smaller
# @exitcode 1 It is not
#######################################
function dybatpho::math_lt {
  local a b
  dybatpho::expect_args a b -- "$@"
  # In this shell, not in `$(...)`: a value that is not a number has to stop
  # the script, and from a subshell the stop would end only the subshell while
  # the caller read the empty answer as "no".
  local order
  __dybatpho_math_cmp2 order "${a}" "${b}"
  ((order < 0))
}

#######################################
# @description Return success when two numbers have the same value, whatever
#   their spelling: `2.50`, `2.5` and `+2.5` are all equal.
# @example
#   dybatpho::math_eq 2.50 2.5 && echo same
#
# @arg $1 string First value
# @arg $2 string Second value
# @exitcode 0 The values are equal
# @exitcode 1 They are not
#######################################
function dybatpho::math_eq {
  local a b
  dybatpho::expect_args a b -- "$@"
  # In this shell, not in `$(...)`: a value that is not a number has to stop
  # the script, and from a subshell the stop would end only the subshell while
  # the caller read the empty answer as "no".
  local order
  __dybatpho_math_cmp2 order "${a}" "${b}"
  ((order == 0))
}

#######################################
# @description Truncate toward zero, dropping the fractional part.
# @example
#   dybatpho::math_trunc 2.9     # 2
#   dybatpho::math_trunc -2.9    # -2
#
# @arg $1 string Value
# @stdout The whole part
# @exitcode 1 Stop the script when the value is not a number
#######################################
function dybatpho::math_trunc {
  local value
  dybatpho::expect_args value -- "$@"
  local sign integer fraction result
  __dybatpho_math_parse "${value}" sign integer fraction
  __dybatpho_math_compose result "${sign}" "${integer}" ""
  printf '%s\n' "${result}"
}

#######################################
# @description Round down, toward negative infinity.
# @example
#   dybatpho::math_floor 2.9     # 2
#   dybatpho::math_floor -2.1    # -3
#
# @arg $1 string Value
# @stdout The largest whole number that is not greater than the value
# @exitcode 1 Stop the script when the value is not a number
#######################################
function dybatpho::math_floor {
  local value
  dybatpho::expect_args value -- "$@"
  local sign integer fraction result
  __dybatpho_math_parse "${value}" sign integer fraction
  if [[ -n "${sign}" && -n "${fraction}" ]]; then
    __dybatpho_math_add_abs integer "${integer}" "1"
  fi
  __dybatpho_math_compose result "${sign}" "${integer}" ""
  printf '%s\n' "${result}"
}

#######################################
# @description Round up, toward positive infinity.
# @example
#   dybatpho::math_ceil 2.1      # 3
#   dybatpho::math_ceil -2.9     # -2
#
# @arg $1 string Value
# @stdout The smallest whole number that is not less than the value
# @exitcode 1 Stop the script when the value is not a number
#######################################
function dybatpho::math_ceil {
  local value
  dybatpho::expect_args value -- "$@"
  local sign integer fraction result
  __dybatpho_math_parse "${value}" sign integer fraction
  if [[ -z "${sign}" && -n "${fraction}" ]]; then
    __dybatpho_math_add_abs integer "${integer}" "1"
  fi
  __dybatpho_math_compose result "${sign}" "${integer}" ""
  printf '%s\n' "${result}"
}

#######################################
# @description Round to a number of fraction digits, halves away from zero.
#   `printf '%.2f'` rounds binary floats to even and follows `LC_NUMERIC`, so it
#   answers `2.66` for `2.665` on one machine and `2,67` on another; this
#   rounds the decimal digits themselves and always answers `2.67`.
# @example
#   dybatpho::math_round 2.665 2    # 2.67
#   dybatpho::math_round -0.5       # -1
#   dybatpho::math_round 1.005 2    # 1.01
#
# @arg $1 string Value
# @arg $2 number [default: 0] Fraction digits to keep
# @stdout The rounded value, with trailing zeros dropped
# @exitcode 1 Stop the script when the value is not a number or the scale is not a non-negative integer
# @tip This rounds for computation. Use `dybatpho::i18n_number` when the result
#   is going to be shown, since that one keeps the digits a person expects to see
#######################################
function dybatpho::math_round {
  local value
  dybatpho::expect_args value -- "$@"
  local scale="${2-0}"
  [[ "${scale}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Scale must be a non-negative integer, got '${scale}'"
  scale=$((10#${scale}))
  local sign integer fraction result
  __dybatpho_math_parse "${value}" sign integer fraction
  __dybatpho_math_round_digits integer fraction "${scale}"
  __dybatpho_math_compose result "${sign}" "${integer}" "${fraction}"
  printf '%s\n' "${result}"
}

#######################################
# @description Add numbers exactly, into a named variable.
#   This is `dybatpho::math_add` without the `$(...)`: a loop that accumulates
#   with `total=$(dybatpho::math_add …)` starts a subshell every time round,
#   which costs more than the addition, and a value that is not a number stops
#   only that subshell. Every `_into` variant takes the variable name first
#   and the operands after it, the way the printing form takes them.
# @example
#   local total=0 price
#   for price in 19.99 5.01 0.5; do
#     dybatpho::math_add_into total "${total}" "${price}"
#   done
#   printf '%s\n' "${total}"   # 25.5
#
# @arg $1 string Name of the variable receiving the sum
# @arg $@ string Two or more values
# @set The named variable
# @exitcode 1 Stop the script when a value is not a number, or the name cannot be bound
#######################################
function dybatpho::math_add_into {
  local __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b
  dybatpho::expect_args __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b -- "$@"
  dybatpho::expect_ref "${__dybatpho_math_into_name}"
  shift 3
  local __dybatpho_math_into_total __dybatpho_math_into_operand
  __dybatpho_math_add2 __dybatpho_math_into_total "${__dybatpho_math_into_a}" "${__dybatpho_math_into_b}"
  for __dybatpho_math_into_operand in "$@"; do
    __dybatpho_math_add2 __dybatpho_math_into_total \
      "${__dybatpho_math_into_total}" "${__dybatpho_math_into_operand}"
  done
  local -n __dybatpho_math_into_ref="${__dybatpho_math_into_name}"
  __dybatpho_math_into_ref="${__dybatpho_math_into_total}"
}

#######################################
# @description Subtract numbers exactly, into a named variable: the second from
#   the first, and any further ones from the running result, as
#   `dybatpho::math_sub` does.
# @example
#   dybatpho::math_sub_into left 100 10 5   # left=85
#
# @arg $1 string Name of the variable receiving the difference
# @arg $@ string Two or more values
# @set The named variable
# @exitcode 1 Stop the script when a value is not a number, or the name cannot be bound
#######################################
function dybatpho::math_sub_into {
  local __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b
  dybatpho::expect_args __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b -- "$@"
  dybatpho::expect_ref "${__dybatpho_math_into_name}"
  shift 3
  local __dybatpho_math_into_total __dybatpho_math_into_operand __dybatpho_math_into_negated
  __dybatpho_math_negate __dybatpho_math_into_negated "${__dybatpho_math_into_b}"
  __dybatpho_math_add2 __dybatpho_math_into_total "${__dybatpho_math_into_a}" "${__dybatpho_math_into_negated}"
  for __dybatpho_math_into_operand in "$@"; do
    __dybatpho_math_negate __dybatpho_math_into_negated "${__dybatpho_math_into_operand}"
    __dybatpho_math_add2 __dybatpho_math_into_total \
      "${__dybatpho_math_into_total}" "${__dybatpho_math_into_negated}"
  done
  local -n __dybatpho_math_into_ref="${__dybatpho_math_into_name}"
  __dybatpho_math_into_ref="${__dybatpho_math_into_total}"
}

#######################################
# @description Multiply numbers exactly, into a named variable, as
#   `dybatpho::math_mul` does.
# @example
#   dybatpho::math_mul_into line_total 19.99 3   # line_total=59.97
#
# @arg $1 string Name of the variable receiving the product
# @arg $@ string Two or more values
# @set The named variable
# @exitcode 1 Stop the script when a value is not a number, or the name cannot be bound
#######################################
function dybatpho::math_mul_into {
  local __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b
  dybatpho::expect_args __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b -- "$@"
  dybatpho::expect_ref "${__dybatpho_math_into_name}"
  shift 3
  local __dybatpho_math_into_total __dybatpho_math_into_operand
  __dybatpho_math_mul2 __dybatpho_math_into_total "${__dybatpho_math_into_a}" "${__dybatpho_math_into_b}"
  for __dybatpho_math_into_operand in "$@"; do
    __dybatpho_math_mul2 __dybatpho_math_into_total \
      "${__dybatpho_math_into_total}" "${__dybatpho_math_into_operand}"
  done
  local -n __dybatpho_math_into_ref="${__dybatpho_math_into_name}"
  __dybatpho_math_into_ref="${__dybatpho_math_into_total}"
}

#######################################
# @description Divide one number by another into a named variable, rounding
#   half away from zero, as `dybatpho::math_div` does.
# @example
#   dybatpho::math_div_into share 2 3 5   # share=0.66667
#
# @arg $1 string Name of the variable receiving the quotient
# @arg $2 string Dividend
# @arg $3 string Divisor
# @arg $4 number [default: ${DYBATPHO_MATH_SCALE}] Fraction digits to keep
# @env DYBATPHO_MATH_SCALE number Default fraction digits
# @set The named variable
# @exitcode 1 Stop the script on a non-number, a bad scale, a zero divisor, or a name that cannot be bound
#######################################
function dybatpho::math_div_into {
  local __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b
  dybatpho::expect_args __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b -- "$@"
  dybatpho::expect_ref "${__dybatpho_math_into_name}"
  local __dybatpho_math_into_total
  __dybatpho_math_div2 __dybatpho_math_into_total "${__dybatpho_math_into_a}" "${__dybatpho_math_into_b}" \
    "${4-${DYBATPHO_MATH_SCALE}}"
  local -n __dybatpho_math_into_ref="${__dybatpho_math_into_name}"
  __dybatpho_math_into_ref="${__dybatpho_math_into_total}"
}

#######################################
# @description Compare two numbers by value into a named variable, as
#   `dybatpho::math_compare` does: `-1`, `0` or `1`.
# @example
#   dybatpho::math_compare_into order "${used}" "${quota}"
#   ((order > 0)) && dybatpho::warn "Over quota"
#
# @arg $1 string Name of the variable receiving `-1`, `0` or `1`
# @arg $2 string First value
# @arg $3 string Second value
# @set The named variable
# @exitcode 1 Stop the script when a value is not a number, or the name cannot be bound
#######################################
function dybatpho::math_compare_into {
  local __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b
  dybatpho::expect_args __dybatpho_math_into_name __dybatpho_math_into_a __dybatpho_math_into_b -- "$@"
  dybatpho::expect_ref "${__dybatpho_math_into_name}"
  local __dybatpho_math_into_total
  __dybatpho_math_cmp2 __dybatpho_math_into_total "${__dybatpho_math_into_a}" "${__dybatpho_math_into_b}"
  local -n __dybatpho_math_into_ref="${__dybatpho_math_into_name}"
  __dybatpho_math_into_ref="${__dybatpho_math_into_total}"
}

#######################################
# @description Round to a number of fraction digits into a named variable,
#   halves away from zero, as `dybatpho::math_round` does.
# @example
#   dybatpho::math_round_into price 2.665 2   # price=2.67
#
# @arg $1 string Name of the variable receiving the rounded value
# @arg $2 string Value
# @arg $3 number [default: 0] Fraction digits to keep
# @set The named variable
# @exitcode 1 Stop the script on a value that is not a number, a bad scale, or a name that cannot be bound
#######################################
function dybatpho::math_round_into {
  local __dybatpho_math_into_name __dybatpho_math_into_a
  dybatpho::expect_args __dybatpho_math_into_name __dybatpho_math_into_a -- "$@"
  dybatpho::expect_ref "${__dybatpho_math_into_name}"
  local __dybatpho_math_into_scale="${3-0}"
  [[ "${__dybatpho_math_into_scale}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Scale must be a non-negative integer, got '${__dybatpho_math_into_scale}'"
  __dybatpho_math_into_scale=$((10#${__dybatpho_math_into_scale}))
  local __dybatpho_math_into_sign __dybatpho_math_into_int __dybatpho_math_into_frac __dybatpho_math_into_total
  __dybatpho_math_parse "${__dybatpho_math_into_a}" \
    __dybatpho_math_into_sign __dybatpho_math_into_int __dybatpho_math_into_frac
  __dybatpho_math_round_digits __dybatpho_math_into_int __dybatpho_math_into_frac "${__dybatpho_math_into_scale}"
  __dybatpho_math_compose __dybatpho_math_into_total \
    "${__dybatpho_math_into_sign}" "${__dybatpho_math_into_int}" "${__dybatpho_math_into_frac}"
  local -n __dybatpho_math_into_ref="${__dybatpho_math_into_name}"
  __dybatpho_math_into_ref="${__dybatpho_math_into_total}"
}

#######################################
# @description Print the smallest of a list of numbers.
# @example
#   dybatpho::math_min 3 1.5 2          # 1.5
#   dybatpho::math_min < durations.txt
#
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no argument is given
# @stdout The smallest value, as it was written
# @exitcode 1 Stop the script when no value is given or one is not a number
#######################################
function dybatpho::math_min {
  local -a values=()
  __dybatpho_math_collect values "$@"
  ((${#values[@]})) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  local smallest="${values[0]}" number
  if ! __dybatpho_math_awk_into smallest min ${values[@]+"${values[@]}"}; then
    smallest="${values[0]}"
    for number in ${values[@]+"${values[@]}"}; do
      dybatpho::math_lt "${number}" "${smallest}" && smallest="${number}"
    done
  fi
  printf '%s\n' "${smallest}"
}

#######################################
# @description Print the largest of a list of numbers.
# @example
#   dybatpho::math_max 3 1.5 2          # 3
#   dybatpho::math_max < durations.txt
#
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no argument is given
# @stdout The largest value, as it was written
# @exitcode 1 Stop the script when no value is given or one is not a number
#######################################
function dybatpho::math_max {
  local -a values=()
  __dybatpho_math_collect values "$@"
  ((${#values[@]})) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  local largest="${values[0]}" number
  if ! __dybatpho_math_awk_into largest max ${values[@]+"${values[@]}"}; then
    largest="${values[0]}"
    for number in ${values[@]+"${values[@]}"}; do
      dybatpho::math_gt "${number}" "${largest}" && largest="${number}"
    done
  fi
  printf '%s\n' "${largest}"
}

#######################################
# @description Store a signed whole number as Bash arithmetic reads it in base
#   ten, whatever zeros it leads with: `08` is eight, not an invalid octal.
# @arg $1 string Name of the variable receiving the number
# @arg $2 string Whole number, optionally signed
# @set The named variable
# @internal
#######################################
function __dybatpho_math_decimal_into {
  local -n __dybatpho_math_decimal_out="$1"
  local __dybatpho_math_decimal_digits="${2#[+-]}"
  if [[ "$2" == -* ]]; then
    __dybatpho_math_decimal_out=$((-10#${__dybatpho_math_decimal_digits}))
  else
    __dybatpho_math_decimal_out=$((10#${__dybatpho_math_decimal_digits}))
  fi
}

#######################################
# @description Add up a list of numbers exactly.
# @example
#   dybatpho::math_sum 19.99 5.01 0.5           # 25.5
#   awk '{print $3}' sizes.txt | dybatpho::math_sum
#
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no argument is given
# @stdout The total, or `0` for an empty list
# @exitcode 1 Stop the script when a value is not a number
#######################################
function dybatpho::math_sum {
  local -a values=()
  __dybatpho_math_collect values "$@"
  local total="0" number
  if ! __dybatpho_math_awk_into total sum ${values[@]+"${values[@]}"}; then
    total="0"
    for number in ${values[@]+"${values[@]}"}; do
      __dybatpho_math_add2 total "${total}" "${number}"
    done
  fi
  printf '%s\n' "${total}"
}

#######################################
# @description Print the mean of a list of numbers.
# @example
#   dybatpho::math_avg 10 20 25                         # 18.3333333333
#   DYBATPHO_MATH_SCALE=2 dybatpho::math_avg 10 20 25   # 18.33
#
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no argument is given
# @env DYBATPHO_MATH_SCALE number Fraction digits kept in the result
# @stdout The mean
# @exitcode 1 Stop the script when no value is given or one is not a number
# @note Every argument is a value, so the scale is taken from
#   `DYBATPHO_MATH_SCALE` rather than from a trailing argument that could not be
#   told apart from the data
#######################################
function dybatpho::math_avg {
  local -a values=()
  __dybatpho_math_collect values "$@"
  ((${#values[@]})) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  local total="0" number mean
  if ! __dybatpho_math_awk_into total sum ${values[@]+"${values[@]}"}; then
    total="0"
    for number in ${values[@]+"${values[@]}"}; do
      __dybatpho_math_add2 total "${total}" "${number}"
    done
  fi
  __dybatpho_math_div2 mean "${total}" "${#values[@]}" "${DYBATPHO_MATH_SCALE}"
  printf '%s\n' "${mean}"
}

#######################################
# @description Compare two numbers, sign included, without a subshell.
# @arg $1 string Name of the variable receiving `-1`, `0` or `1`
# @arg $2 string First value
# @arg $3 string Second value
# @set The named variable
# @exitcode 1 Stop the script when either value is not a number
# @internal
#######################################
function __dybatpho_math_cmp2 {
  local __cmp2_out_name __cmp2_a __cmp2_b
  dybatpho::expect_args __cmp2_out_name __cmp2_a __cmp2_b -- "$@"
  local -n __cmp2_out="${__cmp2_out_name}"
  local __cmp2_short_a __cmp2_short_b __cmp2_short_scale
  if __dybatpho_math_short_pair_into __cmp2_short_a __cmp2_short_b __cmp2_short_scale "${__cmp2_a}" "${__cmp2_b}"; then
    __cmp2_out=$(((__cmp2_short_a > __cmp2_short_b) - (__cmp2_short_a < __cmp2_short_b)))
    return 0
  fi
  local __cmp2_sign_a __cmp2_int_a __cmp2_frac_a
  local __cmp2_sign_b __cmp2_int_b __cmp2_frac_b
  __dybatpho_math_parse "${__cmp2_a}" __cmp2_sign_a __cmp2_int_a __cmp2_frac_a
  __dybatpho_math_parse "${__cmp2_b}" __cmp2_sign_b __cmp2_int_b __cmp2_frac_b
  if [[ "${__cmp2_sign_a}" != "${__cmp2_sign_b}" ]]; then
    if [[ -z "${__cmp2_sign_a}" ]]; then
      __cmp2_out=1
    else
      __cmp2_out=-1
    fi
    return 0
  fi
  local __cmp2_digits_a __cmp2_digits_b __cmp2_scale
  __dybatpho_math_align __cmp2_digits_a __cmp2_digits_b __cmp2_scale \
    "${__cmp2_int_a}" "${__cmp2_frac_a}" "${__cmp2_int_b}" "${__cmp2_frac_b}"
  __dybatpho_math_cmp_abs __cmp2_out "${__cmp2_digits_a}" "${__cmp2_digits_b}"
  [[ -n "${__cmp2_sign_a}" ]] && __cmp2_out=$((-__cmp2_out))
  return 0
}

#######################################
# @description Encode a decimal number into a key whose byte order is its
#   numeric order, into a named variable.
#   A non-negative number becomes `1`, its integer digit count in five digits,
#   the integer without leading zeros, and the fraction without trailing ones,
#   so a longer integer sorts later and equal integers fall through to the
#   fraction digit by digit. A negative number becomes `0` and the same parts
#   with every digit mapped onto a letter in reverse (`9` to `a`, `0` to `j`)
#   and a closing `~`, which reverses the order and still sorts `-0.5` before
#   `-0.45`. Zero is non-negative whatever its sign.
# @arg $1 string Name of the variable receiving the key
# @arg $2 string Number, as `dybatpho::math_is_number` accepts it
# @set The named variable
# @internal
#######################################
function __dybatpho_math_sort_key_into {
  local -n __dybatpho_math_key_ref="$1"
  local __dybatpho_math_key_n="$2" __dybatpho_math_key_negative=0
  local __dybatpho_math_key_int __dybatpho_math_key_frac=""

  case "${__dybatpho_math_key_n}" in
    -*) __dybatpho_math_key_negative=1 __dybatpho_math_key_n="${__dybatpho_math_key_n#-}" ;;
    +*) __dybatpho_math_key_n="${__dybatpho_math_key_n#+}" ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac
  __dybatpho_math_key_int="${__dybatpho_math_key_n%%.*}"
  [[ "${__dybatpho_math_key_n}" != *.* ]] || __dybatpho_math_key_frac="${__dybatpho_math_key_n#*.}"

  # Strip leading zeros from the integer and trailing zeros from the fraction:
  # `007.50` and `7.5` are the same number and must get the same key.
  __dybatpho_math_key_int="${__dybatpho_math_key_int#"${__dybatpho_math_key_int%%[!0]*}"}"
  __dybatpho_math_key_frac="${__dybatpho_math_key_frac%"${__dybatpho_math_key_frac##*[!0]}"}"
  [[ -n "${__dybatpho_math_key_int}${__dybatpho_math_key_frac}" ]] || __dybatpho_math_key_negative=0

  local __dybatpho_math_key_width
  if ((__dybatpho_math_key_negative == 0)); then
    printf -v __dybatpho_math_key_width '%05d' "${#__dybatpho_math_key_int}"
    __dybatpho_math_key_ref="1${__dybatpho_math_key_width}${__dybatpho_math_key_int}.${__dybatpho_math_key_frac}"
    return 0
  fi

  printf -v __dybatpho_math_key_width '%05d' "$((99999 - ${#__dybatpho_math_key_int}))"
  local __dybatpho_math_key_digits="${__dybatpho_math_key_int}.${__dybatpho_math_key_frac}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//0/j}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//1/i}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//2/h}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//3/g}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//4/f}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//5/e}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//6/d}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//7/c}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//8/b}"
  __dybatpho_math_key_digits="${__dybatpho_math_key_digits//9/a}"
  __dybatpho_math_key_ref="0${__dybatpho_math_key_width}${__dybatpho_math_key_digits}~"
}

#######################################
# @description Sort numbers by value, smallest first, into an array.
#   A stable merge sort, so the number of comparisons stays at `n log n`
#   whatever order the values arrive in. When every value is a whole number that
#   fits in Bash's own arithmetic, the comparisons use `(( ))` instead of the
#   digit-string comparison, which is what keeps a list of millisecond timings
#   quick to sort.
# @arg $1 string Name of the array receiving the sorted values, as written
# @arg $@ string Values
# @set The named array
# @exitcode 1 Stop the script when a value is not a number
# @internal
#######################################
function __dybatpho_math_sort {
  local -n __sort_out="$1"
  shift
  local -a __sort_from=("$@")
  local __sort_value __sort_native=true
  for __sort_value in ${__sort_from[@]+"${__sort_from[@]}"}; do
    [[ "${__sort_value}" =~ ${DYBATPHO_MATH_NUMBER_REGEX} ]] \
      || {
        local math_caller_detail                     # kcov(skip)
        math_caller_detail=$(__dybatpho_math_caller) # kcov(skip)
        # kcov cannot see a die under `run`; 'math_median dies on a value that is not a number' covers it.
        dybatpho::die "${math_caller_detail}: Not a number: '${__sort_value}'" # kcov(skip)
      }
    [[ "${__sort_value}" =~ ^[+-]?[0-9]{1,18}$ ]] || __sort_native=false
  done

  if [[ "${__sort_native}" == true ]]; then
    # Each value becomes a plain integer key once, so the sort compares in
    # Bash's own arithmetic without a call per comparison. `10#` keeps a
    # leading zero from being read as octal; the sign has to sit outside it.
    local -a __sort_keys=() __sort_order=()
    local __sort_at __sort_sign __sort_digits
    for __sort_at in "${!__sort_from[@]}"; do
      __sort_digits="${__sort_from[__sort_at]}"
      __sort_sign=""
      [[ "${__sort_digits}" == [+-]* ]] && __sort_sign="${__sort_digits:0:1}" && __sort_digits="${__sort_digits:1}"
      __sort_keys[__sort_at]=$((${__sort_sign}10#${__sort_digits}))
      __sort_order+=("${__sort_at}")
    done
    __dybatpho_helpers_sort __sort_order @int-key __sort_keys
    local -a __sort_sorted=()
    for __sort_at in ${__sort_order[@]+"${__sort_order[@]}"}; do
      __sort_sorted+=("${__sort_from[__sort_at]}")
    done
    __sort_from=(${__sort_sorted[@]+"${__sort_sorted[@]}"})
  else
    # Each value is encoded once into a key whose byte order is its numeric
    # order, so the sort compares strings inline instead of aligning two
    # digit strings on every comparison.
    local -a __sort_keys=() __sort_order=()
    local __sort_at
    for __sort_at in "${!__sort_from[@]}"; do
      # Through a scalar: Bash 4.3 drops an assignment made through a nameref
      # that names an array element.
      local __sort_key
      __dybatpho_math_sort_key_into __sort_key "${__sort_from[__sort_at]}"
      __sort_keys[__sort_at]="${__sort_key}"
      __sort_order+=("${__sort_at}")
    done
    __dybatpho_helpers_sort __sort_order @bytes-key __sort_keys
    local -a __sort_sorted=()
    for __sort_at in ${__sort_order[@]+"${__sort_order[@]}"}; do
      __sort_sorted+=("${__sort_from[__sort_at]}")
    done
    __sort_from=(${__sort_sorted[@]+"${__sort_sorted[@]}"})
  fi
  __sort_out=(${__sort_from[@]+"${__sort_from[@]}"})
}

#######################################
# @description Take the integer square root of a digit string, rounded down.
#   The pencil-and-paper method: digits are brought down two at a time, and
#   each step finds the largest next digit whose trial product still fits in the
#   remainder. Every step is exact, so the result is the true floor.
# @arg $1 string Name of the variable receiving the root digits
# @arg $2 string Digit string
# @set The named variable
# @internal
#######################################
function __dybatpho_math_isqrt {
  local __isqrt_out_name __isqrt_digits
  dybatpho::expect_args __isqrt_out_name __isqrt_digits -- "$@"
  local -n __isqrt_out="${__isqrt_out_name}"
  __dybatpho_math_strip __isqrt_digits
  ((${#__isqrt_digits} % 2)) && __isqrt_digits="0${__isqrt_digits}"
  local __isqrt_root="0" __isqrt_rem="0" __isqrt_index
  local __isqrt_base __isqrt_digit __isqrt_trial __isqrt_cmp
  for ((__isqrt_index = 0; __isqrt_index < ${#__isqrt_digits}; __isqrt_index += 2)); do # kcov(skip) every root runs it
    __isqrt_rem="${__isqrt_rem}${__isqrt_digits:__isqrt_index:2}"
    __dybatpho_math_strip __isqrt_rem
    # The next digit d is the largest with (20 * root + d) * d <= remainder.
    __dybatpho_math_mul_abs __isqrt_base "${__isqrt_root}" "20"
    for ((__isqrt_digit = 9; __isqrt_digit > 0; __isqrt_digit--)); do
      __dybatpho_math_add_abs __isqrt_trial "${__isqrt_base}" "${__isqrt_digit}"
      __dybatpho_math_mul_abs __isqrt_trial "${__isqrt_trial}" "${__isqrt_digit}"
      __dybatpho_math_cmp_abs __isqrt_cmp "${__isqrt_trial}" "${__isqrt_rem}"
      ((__isqrt_cmp <= 0)) && break
    done
    if ((__isqrt_digit > 0)); then
      __dybatpho_math_sub_abs __isqrt_rem "${__isqrt_rem}" "${__isqrt_trial}"
    fi
    __isqrt_root="${__isqrt_root}${__isqrt_digit}"
    __dybatpho_math_strip __isqrt_root
  done
  __isqrt_out="${__isqrt_root}"
}

#######################################
# @description Take the square root of a non-negative number to a requested
#   number of fraction digits, rounding half away from zero.
# @arg $1 string Name of the variable receiving the root
# @arg $2 string Value, not negative
# @arg $3 number Fraction digits to keep
# @set The named variable
# @exitcode 1 Stop the script on a bad value, a negative value, or a bad scale
# @internal
#######################################
function __dybatpho_math_sqrt2 {
  local __sqrt2_out_name __sqrt2_value __sqrt2_scale
  dybatpho::expect_args __sqrt2_out_name __sqrt2_value __sqrt2_scale -- "$@"
  local -n __sqrt2_out="${__sqrt2_out_name}"
  local math_caller_detail
  [[ "${__sqrt2_scale}" =~ ^[0-9]+$ ]] \
    || {
      math_caller_detail=$(__dybatpho_math_caller) # kcov(skip)
      # kcov cannot see a die under `run`; 'math_sqrt dies on a bad scale or a non-number' covers it.
      dybatpho::die "${math_caller_detail}: Scale must be a non-negative integer, got '${__sqrt2_scale}'" # kcov(skip)
    }
  __sqrt2_scale=$((10#${__sqrt2_scale}))
  local __sqrt2_sign __sqrt2_int __sqrt2_frac
  __dybatpho_math_parse "${__sqrt2_value}" __sqrt2_sign __sqrt2_int __sqrt2_frac
  [[ -z "${__sqrt2_sign}" ]] \
    || {
      math_caller_detail=$(__dybatpho_math_caller) # kcov(skip)
      # kcov cannot see a die under `run`; 'math_sqrt dies on a negative value' covers it.
      dybatpho::die "${math_caller_detail}: No square root of a negative number: '${__sqrt2_value}'" # kcov(skip)
    }
  # Shift the value so its root carries one guard digit past the scale: the
  # radicand needs twice as many fraction digits as the root, and an odd count
  # of fraction digits gets one more zero to pair up.
  local __sqrt2_digits="${__sqrt2_int}${__sqrt2_frac}"
  local __sqrt2_pad=$((2 * (__sqrt2_scale + 1) - ${#__sqrt2_frac})) __sqrt2_index
  for ((__sqrt2_index = 0; __sqrt2_index < __sqrt2_pad; __sqrt2_index++)); do
    __sqrt2_digits="${__sqrt2_digits}0"
  done
  # A value with more fraction digits than the root needs loses the excess:
  # flooring the radicand cannot change the floor of its root.
  if ((__sqrt2_pad < 0)); then
    __sqrt2_digits="${__sqrt2_digits:0:${#__sqrt2_digits}+__sqrt2_pad}"
  fi
  local __sqrt2_root __sqrt2_rint __sqrt2_rfrac
  __dybatpho_math_isqrt __sqrt2_root "${__sqrt2_digits:-0}"
  __dybatpho_math_unscale __sqrt2_rint __sqrt2_rfrac "${__sqrt2_root}" "$((__sqrt2_scale + 1))"
  __dybatpho_math_round_digits __sqrt2_rint __sqrt2_rfrac "${__sqrt2_scale}"
  __dybatpho_math_compose __sqrt2_out "" "${__sqrt2_rint}" "${__sqrt2_rfrac}"
}

#######################################
# @description Sort numbers by value into an array, through the `awk` engine
#   when it applies and `__dybatpho_math_sort` otherwise. Both are stable, so
#   the two agree on the order of equal values written differently.
# @arg $1 string Name of the array receiving the sorted values, as written
# @arg $@ string Values
# @set The named array
# @exitcode 1 Stop the script when a value is not a number
# @internal
#######################################
function __dybatpho_math_sorted_into {
  local -n __dybatpho_math_sorted_out="$1"
  shift
  local __dybatpho_math_sorted_lines
  local -a __dybatpho_math_sorted_values=()
  if __dybatpho_math_awk_into __dybatpho_math_sorted_lines sort "$@"; then
    mapfile -t __dybatpho_math_sorted_values <<< "${__dybatpho_math_sorted_lines}"
  else
    __dybatpho_math_sort __dybatpho_math_sorted_values "$@"
  fi
  __dybatpho_math_sorted_out=(${__dybatpho_math_sorted_values[@]+"${__dybatpho_math_sorted_values[@]}"})
}

#######################################
# @description Print the median of a list of numbers.
#   The values are ordered by value; an odd count answers with the middle one
#   as it was written, an even count with the exact mean of the two middle
#   ones. Halving a decimal adds at most one digit, so the median is never
#   rounded.
# @example
#   dybatpho::math_median 7 1 3              # 3
#   dybatpho::math_median 1 2 3 10           # 2.5
#   dybatpho::math_median < durations.txt
#
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no argument is given
# @stdout The median
# @exitcode 1 Stop the script when no value is given or one is not a number
#######################################
function dybatpho::math_median {
  local -a values=() sorted=()
  __dybatpho_math_collect values "$@"
  ((${#values[@]})) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  __dybatpho_math_sorted_into sorted ${values[@]+"${values[@]}"}
  local count=${#sorted[@]} middle=$((${#sorted[@]} / 2))
  if ((count % 2)); then
    printf '%s\n' "${sorted[middle]}"
    return 0
  fi
  local total result
  __dybatpho_math_add2 total "${sorted[middle - 1]}" "${sorted[middle]}"
  __dybatpho_math_mul2 result "${total}" "0.5"
  printf '%s\n' "${result}"
}

#######################################
# @description Print a percentile of a list of numbers.
#   Percentiles are interpolated linearly between the two nearest ranks — the
#   inclusive definition that spreadsheets call `PERCENTILE.INC`, R calls type 7
#   and NumPy uses by default: the values are sorted, the rank
#   `(n - 1) * p / 100` is taken counting from zero, and a fractional rank lies
#   that far between its neighbours. `0` is the smallest value, `100` the
#   largest and `50` the median. Every step is a multiplication by a decimal, so
#   the answer is exact.
# @example
#   dybatpho::math_percentile 90 1 2 3 4 5 6 7 8 9 10    # 9.1
#   dybatpho::math_percentile 50 3 1 2                   # 2
#   dybatpho::math_percentile 99 < latencies.txt
#
# @arg $1 string Percentile, from `0` to `100`, fractions allowed
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no value argument is given
# @stdout The percentile
# @exitcode 1 Stop the script on a percentile outside `0`–`100`, an empty list, or a value that is not a number
#######################################
function dybatpho::math_percentile {
  local percentile
  dybatpho::expect_args percentile -- "$@"
  shift
  dybatpho::math_is_number "${percentile}" \
    || dybatpho::die "${FUNCNAME[0]}: Percentile must be a number from 0 to 100, got '${percentile}'"
  local below above
  __dybatpho_math_cmp2 below "${percentile}" "0"
  __dybatpho_math_cmp2 above "${percentile}" "100"
  ((below >= 0 && above <= 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Percentile must be a number from 0 to 100, got '${percentile}'"

  local -a values=() sorted=()
  __dybatpho_math_collect values "$@"
  ((${#values[@]})) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  __dybatpho_math_sorted_into sorted ${values[@]+"${values[@]}"}

  local result
  __dybatpho_math_percentile_sorted_into result "${percentile}" ${sorted[@]+"${sorted[@]}"}
  printf '%s\n' "${result}"
}

#######################################
# @description Interpolate a percentile of values that are already sorted, into
#   a named variable, the way `dybatpho::math_percentile` defines it. A caller
#   asking for several percentiles of one list sorts it once.
# @arg $1 string Name of the variable receiving the percentile
# @arg $2 string Percentile, a number from `0` to `100`
# @arg $@ string Values, sorted by value, at least one
# @set The named variable
# @internal
#######################################
function __dybatpho_math_percentile_sorted_into {
  local -n __pct_out="$1"
  local __pct_percentile="$2"
  shift 2
  local -a __pct_sorted=("$@")
  local __pct_rank __pct_sign __pct_whole __pct_part
  __dybatpho_math_mul2 __pct_rank "$((${#__pct_sorted[@]} - 1))" "${__pct_percentile}"
  __dybatpho_math_mul2 __pct_rank "${__pct_rank}" "0.01"
  __dybatpho_math_parse "${__pct_rank}" __pct_sign __pct_whole __pct_part
  if [[ -z "${__pct_part}" ]]; then
    __pct_out="${__pct_sorted[10#${__pct_whole}]}"
    return 0
  fi
  # A fractional rank is below the last index, so its upper neighbour exists.
  local __pct_lower="${__pct_sorted[10#${__pct_whole}]}" __pct_upper="${__pct_sorted[10#${__pct_whole} + 1]}"
  local __pct_gap __pct_step
  __dybatpho_math_negate __pct_gap "${__pct_lower}"
  __dybatpho_math_add2 __pct_gap "${__pct_upper}" "${__pct_gap}"
  __dybatpho_math_mul2 __pct_step "${__pct_gap}" "0.${__pct_part}"
  __dybatpho_math_add2 __pct_out "${__pct_lower}" "${__pct_step}"
}

#######################################
# @description Print the square root of a number.
#   The root is computed digit by digit on the decimal value, so it is the true
#   root rounded half away from zero at the requested width, not a binary
#   approximation.
# @example
#   dybatpho::math_sqrt 16          # 4
#   dybatpho::math_sqrt 2 5         # 1.41421
#   dybatpho::math_sqrt 0.25        # 0.5
#
# @arg $1 string Value, not negative
# @arg $2 number [default: ${DYBATPHO_MATH_SCALE}] Fraction digits to keep
# @env DYBATPHO_MATH_SCALE number Default fraction digits
# @stdout The square root
# @exitcode 1 Stop the script on a non-number, a negative value, or a bad scale
#######################################
function dybatpho::math_sqrt {
  local value
  dybatpho::expect_args value -- "$@"
  local scale="${2-${DYBATPHO_MATH_SCALE}}" result
  __dybatpho_math_sqrt2 result "${value}" "${scale}"
  printf '%s\n' "${result}"
}

#######################################
# @description Print the standard deviation of a list of numbers.
#   By default this is the population standard deviation, which describes the
#   values given and divides by their count. `--sample` gives the sample
#   standard deviation, which estimates the spread of a larger population the
#   values were drawn from and divides by one less than the count. The
#   variance is computed exactly from the sum and the sum of squares, so only
#   the final square root is rounded.
# @example
#   dybatpho::math_stddev 2 4 4 4 5 5 7 9            # 2
#   dybatpho::math_stddev --sample 2 4 4 4 5 5 7 9   # 2.1380899353
#   DYBATPHO_MATH_SCALE=3 dybatpho::math_stddev 1 2 3 4   # 1.118
#
# @option --sample Divide by `n - 1` instead of `n`
# @arg $@ string Values, or none to read them from standard input
# @stdin One or more values per line, when no value argument is given
# @env DYBATPHO_MATH_SCALE number Fraction digits kept in the result
# @stdout The standard deviation
# @exitcode 1 Stop the script on an empty list, a single value with `--sample`, or a value that is not a number
#######################################
function dybatpho::math_stddev {
  local sample=false
  if [[ "${1-}" == "--sample" ]]; then
    sample=true
    shift
  fi
  local -a values=()
  __dybatpho_math_collect values "$@"
  local count=${#values[@]}
  ((count)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one value"
  if [[ "${sample}" == true ]] && ((count < 2)); then
    # kcov cannot see a die under `run`; 'math_stddev dies on an empty list or a lone sample' covers it.
    dybatpho::die "${FUNCNAME[0]}: A sample standard deviation needs at least two values" # kcov(skip)
  fi

  # variance = (n * sum(x^2) - sum(x)^2) / (n * d), with d = n or n - 1. The
  # numerator is exact and never negative, so the only rounding is the root's.
  local total="0" squares="0" number square sums
  if __dybatpho_math_awk_into sums sumsq ${values[@]+"${values[@]}"}; then
    total="${sums%%$'\n'*}"
    squares="${sums#*$'\n'}"
  else
    for number in ${values[@]+"${values[@]}"}; do
      __dybatpho_math_add2 total "${total}" "${number}"
      __dybatpho_math_mul2 square "${number}" "${number}"
      __dybatpho_math_add2 squares "${squares}" "${square}"
    done
  fi
  local spread total_squared divisor=${count}
  [[ "${sample}" == true ]] && divisor=$((count - 1))
  __dybatpho_math_mul2 spread "${squares}" "${count}"
  __dybatpho_math_mul2 total_squared "${total}" "${total}"
  __dybatpho_math_negate total_squared "${total_squared}"
  __dybatpho_math_add2 spread "${spread}" "${total_squared}"

  # Divide with enough digits that the root keeps its own guard digit, then
  # take the root: flooring the radicand cannot change the floor of its root,
  # so the division is truncated rather than rounded.
  local scale="${DYBATPHO_MATH_SCALE}" variance quotient remainder sign integer fraction
  [[ "${scale}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Scale must be a non-negative integer, got '${scale}'"
  scale=$((10#${scale}))
  __dybatpho_math_parse "${spread}" sign integer fraction
  local numerator="${integer}${fraction}" index
  for ((index = 0; index < 2 * (scale + 1); index++)); do
    numerator="${numerator}0"
  done
  local denominator
  __dybatpho_math_mul_abs denominator "$((count * divisor))" "1"
  for ((index = 0; index < ${#fraction}; index++)); do
    denominator="${denominator}0"
  done
  __dybatpho_math_divmod_abs quotient remainder "${numerator}" "${denominator}"
  __dybatpho_math_unscale integer fraction "${quotient}" "$((2 * (scale + 1)))"
  __dybatpho_math_compose variance "" "${integer}" "${fraction}"
  local result
  __dybatpho_math_sqrt2 result "${variance}" "${scale}"
  printf '%s\n' "${result}"
}

#######################################
# @description Hold a number inside a range.
# @example
#   dybatpho::math_clamp 42 0 10      # 10
#   dybatpho::math_clamp -3 0 10      # 0
#   dybatpho::math_clamp 7.5 0 10     # 7.5
#
# @arg $1 string Value
# @arg $2 string Lower bound
# @arg $3 string Upper bound
# @stdout The value, or whichever bound it crossed
# @exitcode 1 Stop the script on a non-number or a lower bound above the upper one
#######################################
function dybatpho::math_clamp {
  local value lower upper
  dybatpho::expect_args value lower upper -- "$@"
  dybatpho::math_gt "${lower}" "${upper}" \
    && dybatpho::die "${FUNCNAME[0]}: Lower bound '${lower}' is above upper bound '${upper}'"
  if dybatpho::math_lt "${value}" "${lower}"; then
    printf '%s\n' "${lower}"
  elif dybatpho::math_gt "${value}" "${upper}"; then
    printf '%s\n' "${upper}"
  else
    printf '%s\n' "${value}"
  fi
}

#######################################
# @description Print what percentage one number is of another.
# @example
#   dybatpho::math_percent 42 200       # 21
#   dybatpho::math_percent 1 3 2        # 33.33
#
# @arg $1 string Part
# @arg $2 string Whole
# @arg $3 number [default: ${DYBATPHO_MATH_SCALE}] Fraction digits to keep
# @env DYBATPHO_MATH_SCALE number Default fraction digits
# @stdout The percentage, without a `%` sign
# @exitcode 1 Stop the script on a non-number, a bad scale, or a whole of zero
# @tip Pair it with `dybatpho::i18n_percent` to print the result the way the
#   reader's locale writes a percentage
#######################################
function dybatpho::math_percent {
  local part whole
  dybatpho::expect_args part whole -- "$@"
  local scale="${3-${DYBATPHO_MATH_SCALE}}"
  local scaled result
  __dybatpho_math_mul2 scaled "${part}" "100"
  __dybatpho_math_div2 result "${scaled}" "${whole}" "${scale}"
  printf '%s\n' "${result}"
}

#######################################
# @description Print the greatest common divisor of whole numbers.
# @example
#   dybatpho::math_gcd 12 18        # 6
#   dybatpho::math_gcd 24 36 60     # 12
#
# @arg $@ string Two or more whole numbers; signs are ignored
# @stdout The greatest common divisor, `0` only when every value is zero
# @exitcode 1 Stop the script on a fractional or non-numeric value
#######################################
function dybatpho::math_gcd {
  local a b
  dybatpho::expect_args a b -- "$@"
  shift 2
  local -a values=("${a}" "${b}" "$@")
  local number sign integer fraction
  local result="0" quotient remainder current
  for number in "${values[@]}"; do
    __dybatpho_math_parse "${number}" sign integer fraction
    [[ -z "${fraction}" ]] \
      || dybatpho::die "${FUNCNAME[0]}: Expected whole numbers, got '${number}'"
    current="${integer}"
    # Euclid: replace the pair by (smaller, remainder) until nothing is left.
    while [[ "${current}" != "0" ]]; do
      __dybatpho_math_divmod_abs quotient remainder "${result}" "${current}"
      result="${current}"
      current="${remainder}"
    done
  done
  printf '%s\n' "${result}"
}

#######################################
# @description Print the least common multiple of whole numbers.
# @example
#   dybatpho::math_lcm 4 6         # 12
#   dybatpho::math_lcm 2 3 5       # 30
#
# @arg $@ string Two or more whole numbers; signs are ignored
# @stdout The least common multiple, `0` when any value is zero
# @exitcode 1 Stop the script on a fractional or non-numeric value
#######################################
function dybatpho::math_lcm {
  local a b
  dybatpho::expect_args a b -- "$@"
  shift 2
  local -a values=("${a}" "${b}" "$@")
  local number sign integer fraction
  local result="1" divisor product quotient remainder
  for number in "${values[@]}"; do
    __dybatpho_math_parse "${number}" sign integer fraction
    [[ -z "${fraction}" ]] \
      || dybatpho::die "${FUNCNAME[0]}: Expected whole numbers, got '${number}'"
    if [[ "${integer}" == "0" ]]; then
      printf '0\n'
      return 0
    fi
    divisor="$(dybatpho::math_gcd "${result}" "${integer}")"
    __dybatpho_math_mul_abs product "${result}" "${integer}"
    __dybatpho_math_divmod_abs quotient remainder "${product}" "${divisor}"
    result="${quotient}"
  done
  printf '%s\n' "${result}"
}

#######################################
# @description Print a random whole number in an inclusive range.
#   `$((RANDOM % n))` is biased whenever `n` does not divide the generator's
#   range, which is most of the time: with `RANDOM % 10` the low digits come up
#   noticeably more often. This draws sixty bits and rejects the tail that would
#   cause the bias, so every value in the range is equally likely.
# @example
#   dybatpho::math_random 1 6              # a die roll
#   sleep "$(dybatpho::math_random 1 5)"   # jittered backoff
#
# @arg $1 string Lower bound, a whole number
# @arg $2 string Upper bound, a whole number, not below the lower one
# @stdout A whole number between the bounds, both included
# @exitcode 1 Stop the script on a fractional bound, a reversed range, or a range wider than the generator
# @note `RANDOM` is not a cryptographic generator. Read `/dev/urandom` for
#   anything that guards a secret
#######################################
function dybatpho::math_random {
  local lower upper
  dybatpho::expect_args lower upper -- "$@"
  local bound
  for bound in "${lower}" "${upper}"; do
    [[ "${bound}" =~ ^[+-]?[0-9]+$ ]] \
      || dybatpho::die "${FUNCNAME[0]}: Bounds must be whole numbers, got '${bound}'"
    ((${#bound} <= 18)) \
      || dybatpho::die "${FUNCNAME[0]}: Bound '${bound}' is outside the range Bash can draw from"
  done
  # A leading zero would make the arithmetic below read the bound as octal.
  __dybatpho_math_decimal_into lower "${lower}"
  __dybatpho_math_decimal_into upper "${upper}"
  ((lower <= upper)) \
    || dybatpho::die "${FUNCNAME[0]}: Lower bound '${lower}' is above upper bound '${upper}'"

  local span=$((upper - lower + 1))
  # A span that wrapped is a span this generator cannot cover uniformly.
  ((span > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Range ${lower}..${upper} is too wide to draw from"

  # `RANDOM` yields fifteen bits at a time; four draws make sixty.
  local -i modulus=1152921504606846976
  local -i limit=$((modulus / span * span))
  local -i draw
  while :; do
    draw=$(((RANDOM << 45) | (RANDOM << 30) | (RANDOM << 15) | RANDOM))
    ((draw < limit)) && break
  done
  printf '%s\n' "$((lower + draw % span))"
}
