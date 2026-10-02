#!/usr/bin/env bash
# @file math_ops.sh
# @brief Example showing exact decimal arithmetic
# @description Demonstrates dybatpho::math_add, math_sub, math_mul, math_div,
#   math_mod, math_pow, math_abs, math_neg, math_compare, math_gt, math_lt,
#   math_eq, math_round, math_floor, math_ceil, math_trunc, math_min, math_max,
#   math_sum, math_avg, math_median, math_percentile, math_stddev, math_sqrt,
#   math_clamp, math_percent, math_gcd, math_lcm,
#   math_random, math_is_number and math_is_integer, by pricing an invoice and
#   summarizing a batch of timings.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules math

dybatpho::register_common_handlers

# @description Run the `WHY NOT awk OR bc` section of this example.
# @noargs
function _demo_exactness {
  dybatpho::header "WHY NOT awk OR bc"
  # Binary floating point cannot hold 0.1, so `awk` answers 0.30000000000000004
  # and a total built from cents slowly drifts. Digit arithmetic does not.
  local math_add
  math_add=$(dybatpho::math_add 0.1 0.2)
  dybatpho::info "0.1 + 0.2       = ${math_add}"
  local math_sub
  math_sub=$(dybatpho::math_sub 1.1 1.0)
  dybatpho::info "1.1 - 1.0       = ${math_sub}"
  # `$(( ))` would silently wrap past 2^63 here.
  local math_pow
  math_pow=$(dybatpho::math_pow 99999999999 2)
  dybatpho::info "99999999999 ^ 2 = ${math_pow}"
  local math_eq
  math_eq=$(dybatpho::math_eq 2.50 2.5 && echo yes || echo no)
  dybatpho::info "2.50 == 2.5     : ${math_eq}"
}

# @description Run the `AN INVOICE, TO THE CENT` section of this example.
# @noargs
function _demo_invoice {
  dybatpho::header "AN INVOICE, TO THE CENT"
  local -a prices=(19.99 4.50 129.00)
  local -a quantities=(3 2 1)
  local index subtotal="0" line

  # Results are canonical, so a line worth 9.00 prints as 9. Putting the cents
  # back is display work, which is what `dybatpho::i18n_currency` is for.
  for index in "${!prices[@]}"; do
    line="$(dybatpho::math_mul "${prices[index]}" "${quantities[index]}")"
    subtotal="$(dybatpho::math_add "${subtotal}" "${line}")"
    dybatpho::print "  $(printf '%-11s' "${quantities[index]} x ${prices[index]}") = ${line}"
  done

  # A discount and a tax rate are ratios; rounding happens once, at the end,
  # where money is actually charged.
  local discount tax total
  discount="$(dybatpho::math_mul "${subtotal}" 0.10)"
  local math_sub_2
  math_sub_2=$(dybatpho::math_sub "${subtotal}" "${discount}")
  tax="$(dybatpho::math_mul "${math_sub_2}" 0.0825)"
  local math_sub
  math_sub=$(dybatpho::math_sub "${subtotal}" "${discount}")
  local math_add
  math_add=$(dybatpho::math_add "${math_sub}" "${tax}")
  total="$(dybatpho::math_round \
    "${math_add}" 2)"

  dybatpho::info "Subtotal        : ${subtotal}"
  dybatpho::info "Discount (10%)  : -${discount}"
  dybatpho::info "Tax (8.25%)     : ${tax}"
  dybatpho::success "Total charged   : ${total}"

  # The share each line takes of the bill, which is what a report shows.
  local math_mul
  math_mul=$(dybatpho::math_mul "${prices[0]}" "${quantities[0]}")
  dybatpho::info "First line is $(dybatpho::math_percent \
    "${math_mul}" "${subtotal}" 1)% of the subtotal"
}

# @description Run the `SUMMARIZING A BATCH` section of this example.
# @noargs
function _demo_statistics {
  dybatpho::header "SUMMARIZING A BATCH"
  local -a durations=(0.482 1.205 0.997 2.310 0.874)
  dybatpho::info "Samples : ${durations[*]}"
  dybatpho::info "Count   : ${#durations[@]}"
  local math_sum
  math_sum=$(dybatpho::math_sum "${durations[@]}")
  dybatpho::info "Total   : ${math_sum}"
  local math_min
  math_min=$(dybatpho::math_min "${durations[@]}")
  dybatpho::info "Fastest : ${math_min}"
  local math_max
  math_max=$(dybatpho::math_max "${durations[@]}")
  dybatpho::info "Slowest : ${math_max}"
  local DYBATPHO_MATH_SCALE_3
  DYBATPHO_MATH_SCALE_3=$(DYBATPHO_MATH_SCALE=3 dybatpho::math_avg "${durations[@]}")
  dybatpho::info "Mean    : ${DYBATPHO_MATH_SCALE_3}"

  # The mean hides the outliers; the median and the percentiles do not. A
  # percentile interpolates between the two nearest ranks, so it is exact.
  local median p90 spread root
  median="$(dybatpho::math_median "${durations[@]}")"
  dybatpho::info "Median  : ${median}"
  p90="$(dybatpho::math_percentile 90 "${durations[@]}")"
  dybatpho::info "p90     : ${p90}"
  # Population deviation by default; `--sample` divides by n - 1 instead.
  spread="$(DYBATPHO_MATH_SCALE=3 dybatpho::math_stddev --sample "${durations[@]}")"
  dybatpho::info "Std dev : ${spread} (sample)"
  root="$(dybatpho::math_sqrt 2 6)"
  dybatpho::info "sqrt(2) : ${root}"

  # A list arrives on a pipe as often as in an array.
  local printf
  printf=$(printf '%s\n' "${durations[@]}" | dybatpho::math_sum)
  dybatpho::info "From a pipe: ${printf}"

  local budget="1.000"
  local slowest
  slowest="$(dybatpho::math_max "${durations[@]}")"
  if dybatpho::math_gt "${slowest}" "${budget}"; then
    dybatpho::warn "Slowest sample ${slowest}s is over the ${budget}s budget"
  else
    dybatpho::success "Every sample is inside the ${budget}s budget" # kcov(skip)
  fi
}

# @description Run the `ROUNDING THAT SAYS WHAT IT DOES` section of this example.
# @noargs
function _demo_rounding {
  dybatpho::header "ROUNDING THAT SAYS WHAT IT DOES"
  local value="2.665"
  dybatpho::info "Value  : ${value}"
  local math_round_2
  math_round_2=$(dybatpho::math_round "${value}" 2)
  dybatpho::print "  round  (2 digits): ${math_round_2}"
  local math_round
  math_round=$(dybatpho::math_round "${value}")
  dybatpho::print "  round  (0 digits): ${math_round}"
  local math_floor_2
  math_floor_2=$(dybatpho::math_floor "${value}")
  dybatpho::print "  floor            : ${math_floor_2}"
  local math_ceil
  math_ceil=$(dybatpho::math_ceil "${value}")
  dybatpho::print "  ceil             : ${math_ceil}"
  local math_trunc_2
  math_trunc_2=$(dybatpho::math_trunc "${value}")
  dybatpho::print "  trunc            : ${math_trunc_2}"
  dybatpho::print "  the same, below zero:"
  local negative="-2.665"
  local math_floor
  math_floor=$(dybatpho::math_floor "${negative}")
  local math_round_3
  math_round_3=$(dybatpho::math_round "${negative}")
  dybatpho::print "    round: ${math_round_3} floor: ${math_floor}"
  local math_trunc
  math_trunc=$(dybatpho::math_trunc "${negative}")
  local math_ceil_2
  math_ceil_2=$(dybatpho::math_ceil "${negative}")
  dybatpho::print "    ceil: ${math_ceil_2} trunc: ${math_trunc}"
  local math_neg
  math_neg=$(dybatpho::math_neg 2.665)
  local math_abs
  math_abs=$(dybatpho::math_abs "${negative}")
  dybatpho::print "  abs / neg        : ${math_abs} / ${math_neg}"
}

# @description Run the `A PROGRESS READOUT` section of this example.
# @noargs
function _demo_progress {
  dybatpho::header "A PROGRESS READOUT"
  local done_count=7 total_count=9 percent bar_width filled index bar=""
  percent="$(dybatpho::math_percent "${done_count}" "${total_count}" 1)"
  bar_width=20
  # Clamping keeps a rounding error or a miscounted job from drawing a bar that
  # is longer than the bar.
  local math_mul
  local math_mul_2
  math_mul_2=$(dybatpho::math_mul "${done_count}" "${bar_width}")
  math_mul=${math_mul_2}
  filled="$(dybatpho::math_clamp \
    "$(dybatpho::math_round "$(dybatpho::math_div \
      "${math_mul}" "${total_count}")")" \
    0 "${bar_width}")"
  for ((index = 0; index < bar_width; index++)); do
    if ((index < filled)); then
      bar="${bar}#"
    else
      bar="${bar}."
    fi
  done
  dybatpho::info "[${bar}] ${percent}% (${done_count}/${total_count})"
}

# @description Run the `WHOLE-NUMBER HELPERS` section of this example.
# @noargs
function _demo_whole_numbers {
  dybatpho::header "WHOLE-NUMBER HELPERS"
  local math_mod_2
  math_mod_2=$(dybatpho::math_mod 17 5)
  dybatpho::info "17 mod 5        : ${math_mod_2}"
  local math_mod
  math_mod=$(dybatpho::math_mod -17 5)
  dybatpho::info "-17 mod 5       : ${math_mod}"
  local math_gcd
  math_gcd=$(dybatpho::math_gcd 24 36 60)
  dybatpho::info "gcd(24, 36, 60) : ${math_gcd}"
  local math_lcm
  math_lcm=$(dybatpho::math_lcm 4 6)
  dybatpho::info "lcm(4, 6)       : ${math_lcm}"
  # An aspect ratio is a gcd: 1920x1080 reduces to 16:9.
  local width=1920 height=1080 divisor
  divisor="$(dybatpho::math_gcd "${width}" "${height}")"
  local ratio_width ratio_height
  ratio_width=$(dybatpho::math_div "${width}" "${divisor}" 0)
  ratio_height=$(dybatpho::math_div "${height}" "${divisor}" 0)
  dybatpho::info "${width}x${height} is ${ratio_width}:${ratio_height}"

  # Retry jitter, without the bias `$((RANDOM % 5))` would introduce.
  local attempt
  for attempt in 1 2 3; do
    local math_random
    math_random=$(dybatpho::math_random 1 5)
    dybatpho::print "  attempt ${attempt}: would sleep ${math_random}s"
  done
}

# @description Run the `CHECKING INPUT BEFORE COMPUTING` section of this example.
# @noargs
function _demo_validation {
  dybatpho::header "CHECKING INPUT BEFORE COMPUTING"
  local candidate
  for candidate in "42" "-3.5" "1e3" "1,5" "" "2.00"; do
    if ! dybatpho::math_is_number "${candidate}"; then
      dybatpho::warn "  '${candidate}' is not a number this module accepts"
      continue
    fi
    if dybatpho::math_is_integer "${candidate}"; then
      dybatpho::print "  '${candidate}' is a whole number"
    else
      dybatpho::print "  '${candidate}' is a decimal"
    fi
  done

  # The shape a real guard takes: validate, then compute.
  local reported="12.75"
  dybatpho::math_is_number "${reported}" \
    || dybatpho::die "Refusing to bill against '${reported}'"
  local math_compare
  math_compare=$(dybatpho::math_compare "${reported}" 12.8)
  dybatpho::success "Ranked by value: ${math_compare} means ${reported} < 12.8"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_exactness
  _demo_invoice
  _demo_statistics
  _demo_rounding
  _demo_progress
  _demo_whole_numbers
  _demo_validation
  dybatpho::success "Math operations demo complete"
}

_main "$@"
