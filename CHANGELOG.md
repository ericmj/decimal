# CHANGELOG

## v3.2.0 (2026-10-10)

### Enhancements

* Make most operations faster. Compared with v3.1.2 on OTP 29, on decimals
  with up to 20 digits and exponents from -20 to 20, `div/2` is about 8x
  faster, `mult/2` 6x, `add/2` 5x, `round/3` 4x, `compare/2` 2.7x and
  `normalize/1` 2x. On money amounts with two decimals, `to_float/1` is about
  23x faster, `compare/3` 18x, `div/2` 15x, `rem/2` and `sqrt/1` 4x,
  `round/3` 2-3x, `add/2`, `sub/2`, `mult/2`, `div_int/2` and `compare/2`
  2-2.7x, and parsing 1.4x. `from_float/1` and `cast/1` of a float are about
  3.4x faster and `cast/1` of an integer 3x. `to_string/1` is unchanged.

* Add the `:subnormal` and `:clamped` signals from the General Decimal
  Arithmetic spec. `:subnormal` is signalled for every result whose adjusted
  exponent is below `emin`, even an exact one, and `:underflow` only when
  such a result is also inexact. A zero result's exponent is kept between
  `emin - precision + 1` and `emax`, the range of nonzero results, and
  `:clamped` is signalled when it has to move:
  `Decimal.mult("0e-3500", "0e-3500")` returns `0E-6176` instead of
  `0E-7000`. This also applies to the zero results of division by infinity,
  of `div_int/2` and `div_rem/2` with a smaller dividend, and of `sqrt/1`. A
  subnormal result that rounds to zero signals `:clamped` too.

### Bug fixes

* Fix `Decimal.div/2` rounding some inexact results the wrong way. Under
  `:half_even` and `:half_down`, a result just above a tie was rounded as a
  tie, and under `:ceiling`, `:floor` and `:up`, a result whose first
  discarded digit was 0 was treated as exact even when later digits weren't,
  so `:ceiling` and `:floor` could return a value on the wrong side of the
  true quotient. About 5% of random divisions at the default precision were
  affected. `:inexact` was also missing when the remainder was a power of
  ten.

* Fix `:up` rounding changing exact values. A result whose discarded digits
  were all zero was still rounded away from zero: with `precision: 1` and
  `rounding: :up`, `Decimal.add(0, Decimal.new("9.0"))` returned `10`
  instead of `9`, and `Decimal.round(Decimal.new(0), -1, :up)` returned
  `1E+1` instead of `0E+1`.

* Fix rounding carries leaving one digit more than the precision. Rounding
  `9.99` to precision 2 returned `10.0` instead of `10`, and
  `Decimal.div(95, 10)` at precision 1 returned `10` instead of `1E+1`. This
  affected every operation that rounds to the context precision, and the
  results now match the General Decimal Arithmetic spec and Python's
  `decimal`.

* Fix `Decimal.sqrt/1` rounding inexact roots as if the first discarded
  digit were the whole remainder. At precision 9 under `:ceiling`,
  `Decimal.sqrt(10)` returned `3.16227766` instead of `3.16227767`, and at
  precision 2 under `:half_even`, `Decimal.sqrt("1.57")` returned `1.2`
  instead of `1.3`. The default `:half_up` rounding wasn't affected. Inexact
  roots now signal `:inexact` as well as `:rounded`.

* Fix `Decimal.rem/2` and `Decimal.div_rem/2` computing the remainder from a
  product rounded to the context precision, which could cancel it out:
  `Decimal.rem("9999999999999999999999999999999999", "2.000000000000000000000000000000001")`
  returned `0` instead of `3E-33`.

* Fix `Decimal.to_float/1` returning the next float up for odd integers
  between 2^52 and 2^53, which doubles represent exactly:
  `Decimal.to_float(Decimal.new(4_503_599_627_370_497))` returned
  `4503599627370498.0`.

* Keep subnormal results instead of flushing them to zero. Since v3.0.0 set
  the default `emin` to -6143, every result with an adjusted exponent below
  it became 0 with `:underflow`, even an exact one:
  `Decimal.div("1e-6140", 10000)` returned `0` instead of `1E-6144`. Such
  results are now rounded at the exponent `emin - precision + 1` (-6176 by
  default) with the context's rounding, as IEEE 754 and the General Decimal
  Arithmetic spec specify, and signal `:subnormal`, plus `:underflow` when
  that rounding is inexact. A result that rounds to zero keeps that exponent
  (`0E-6176`). `Decimal.round/3` no longer flushes an input below `emin` to
  zero before rounding it.

* Fix `Decimal.round/3` rounding an input with more digits than the
  precision twice, first with the context's rounding instead of `mode`: at
  precision 3, `Decimal.round(Decimal.new("0.4995"), 1, :down)` returned
  `0.5` instead of `0.4`.

* Make `Decimal.round/3` signal `:rounded` when it discards digits of a
  nonzero coefficient, and `:inexact` when any of them is nonzero, as the
  quantize operation of the General Decimal Arithmetic spec does.
  `Decimal.round("1.25", 1)` returned `1.3` with no flags.

* Make `Decimal.round/3` signal `:invalid_operation` and return NaN where
  quantize does: for ±Infinity, when `-places` is outside
  `emin - precision + 1` to `emax`, and when the result would need more
  digits than the precision or an adjusted exponent above `emax`. The signal
  is trapped by default, so these calls now raise `Decimal.Error`. Before,
  the context rounded such results to an exponent other than `-places`:
  `Decimal.round(Decimal.new("1e40"), 2)` returned
  `1.000000000000000000000000000000000E+40`, and `Decimal.round("1.5", 7000)`
  returned `1.500000000000000000000000000000000`. ±Infinity was returned
  unchanged.

* Make `Decimal.compare/3` exact. It rounded `num1 ± threshold` to the
  context precision, so numbers near the threshold compared wrong:
  `Decimal.compare(1, "1.000000000000000000000000000000002", "1.5e-33")`
  returned `:eq` although they differ by `2e-33`. It no longer sets
  `:inexact` or `:rounded`, accepts `-0` as a threshold, and raises
  `Decimal.Error` instead of `CondClauseError` for a NaN when
  `:invalid_operation` isn't trapped.

* Make `Decimal.compare/2` raise `Decimal.Error` for a NaN operand even when
  `:invalid_operation` isn't trapped, instead of returning the NaN. Comparing
  a NaN with ±Infinity now raises too, instead of returning `:lt` or `:gt`.

* Make `Decimal.Context.set/1`, `Decimal.Context.with/2` and
  `Decimal.Context.update/1` raise `ArgumentError` for an invalid context: a
  precision that isn't a positive integer, an unknown rounding mode, an
  `emax` or `emin` that is neither an integer nor `:infinity`, or an `emin`
  above `emax`. A precision of 0 silently gave wrong results
  (`Decimal.add(1, 1)` returned `0E+1`), and the other cases failed with
  `FunctionClauseError` in the next operation.

* Make `Decimal.to_integer/1` raise `ArgumentError` for NaN and ±Infinity,
  like `Decimal.to_float/1`, instead of `FunctionClauseError`.

## v3.1.2 (2026-10-10)

### Security

* Fix `Decimal.round/3` building its result at the full requested scale
  before applying the context precision, so its time and memory grew with
  the `places` argument instead of with the precision. A caller controlling
  `places` could exhaust memory with one call:
  `Decimal.round(Decimal.new("1.5"), -50_000_000)` allocated about 5.5 GB,
  and positive `places` above about 1.26 million built the padding and then
  raised `SystemLimitError`. The coefficient is now padded to at most one
  digit past the context precision, and dropping more digits than the
  coefficient has no longer builds a list of zeros of that length. Results
  and flags are unchanged, except that those calls now return a value. This
  is a fix for **CVE-2026-97853** (GitHub advisory
  [GHSA-6c27-994x-c52f](https://github.com/ericmj/decimal/security/advisories/GHSA-6c27-994x-c52f)).

* Make `Decimal.to_integer/1` and `Decimal.to_float/1` return `0` and `0.0`
  for a zero coefficient without computing a power of ten the size of its
  exponent. Zeros are exempt from the exponent limits, so `Decimal.round/3`
  returns zeros such as `0E+1000000000` for large `places`, and converting
  one spent about 1.8 seconds before raising `SystemLimitError`. This is part
  of the fix for **CVE-2026-97853** (GitHub advisory
  [GHSA-6c27-994x-c52f](https://github.com/ericmj/decimal/security/advisories/GHSA-6c27-994x-c52f)).

## v3.1.1 (2026-05-27)

### Bug fixes

* Fix `Decimal.parse/2` and `Decimal.new/2` rejecting inspect output for
  values at the context's full precision with negative exponents (e.g.
  `Decimal.new("0.3162277660168379331998893544432719")`). The
  `:max_digits` limit no longer counts non-significant leading zeros.

## v3.1.0 (2026-05-08)

### Enhancements

* `Decimal.new/2` now accepts an optional `opts` keyword list and
  forwards it to `Decimal.parse/2`, allowing callers to override
  `:max_digits` and `:max_exponent` when constructing a decimal from
  a string.

### Bug fixes

* Fix infinite loop in `Decimal.to_integer/1` when the coefficient is
  zero and the exponent is negative (e.g. `Decimal.new("0.0")`). Such
  values now correctly convert to the integer `0`.

## v3.0.0 (2026-05-07)

### Note on the new defaults

The new decimal128 defaults are more than sufficient for currency and
other real-world numeric use cases. With `precision: 34` and a scale of
2 (two digits after the decimal point for cents), values from `0.00` up
to roughly `99_999_999_999_999_999_999_999_999_999_999.99` (~10³², 100
nonillion) round-trip without rounding. Most upgrades from 2.x require
no code changes.

### Security

* Make the v2.4.0 exponent amplification mitigations the default. The
  default `Decimal.Context` and the public parse, cast, and to_string
  functions now follow IEEE 754 decimal128 limits, rejecting inputs
  such as `1e1000000000` without materializing them. This is a fix for
  **CVE-2026-32686** (GitHub advisory
  [GHSA-rhv4-8758-jx7v](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)).

### Breaking changes

* `Decimal.Context` defaults change from precision `28` and unbounded
  `emax`/`emin` to decimal128 values: `precision: 34`, `emax: 6_144`,
  `emin: -6_143`. Operation results whose adjusted exponent leaves that
  band signal overflow or underflow.
* `Decimal.parse/1` and `Decimal.cast/1` reject inputs whose digit count
  exceeds `34` (decimal128 precision) or whose absolute exponent exceeds
  `6_144` (decimal128 emax). Use `parse/2` / `cast/2` with
  `max_digits: :infinity` and `max_exponent: :infinity` to restore
  unbounded behavior.
* `Decimal.parse/2` and `Decimal.cast/2` default `:max_digits` to `34`
  and `:max_exponent` to `6_144` when not specified.
* `Decimal.to_string/2` and `Decimal.to_string/3` raise `ArgumentError`
  when the rendered output would exceed `6_178` digit characters
  (precision + emax — the worst-case `:normal` width of any in-range
  decimal128 value). `Inspect`, `String.Chars`, and `JSON.Encoder`
  protocol implementations pass `max_digits: :infinity` so debug output
  always succeeds.

## v2.4.0 (2026-05-07)

### Security

* Mitigate exponent amplification. Compact inputs such as `1e1000000`
  could force multi-second expansions during arithmetic, parsing,
  normalization, comparison, or formatting. `Decimal.add/2` and
  `Decimal.sub/2` now scale operands to `precision + 2` digits with a
  sticky bit instead of materializing the full coefficient. This mitigates
  **CVE-2026-32686** (GitHub advisory
  [GHSA-rhv4-8758-jx7v](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)).

### Enhancements

* Add `:max_digits` and `:max_exponent` options to `Decimal.parse/2` and
  `Decimal.cast/2` to reject pathological inputs without expansion
* Add `:max_digits` option to `Decimal.to_string/3` to cap formatted output
  before materialization
* Add `:emax` and `:emin` fields to `Decimal.Context` for IBM General Decimal
  Arithmetic-style overflow and underflow signaling
* Optimize hot paths for large decimals: `coef_length`, `normalize`,
  `to_integer`, `integer?`, parsing, and large-coefficient string formatting

## v2.3.0 (2024-12-13)

* Implement the upcoming [`JSON.Encoder`](https://hexdocs.pm/elixir/main/JSON.Encoder.html)
  protocol

## v2.2.0 (2024-11-13)

* Add `Decimal.gte?/2` and `Decimal.lte?/2`
* Add `Decimal.compare/3` and `Decimal.eq?/3` with threshold as parameter

## v2.1.1 (2023-04-26)

Decimal v2.1 requires Elixir v1.8+.

### Bug fixes

* Fix `Decimal.compare/2` when comparing against `0`

## v2.1.0 (2023-04-26)

Decimal v2.1 requires Elixir v1.8+.

### Enhancements

* Improve error message from `Decimal.to_integer/1` during precision loss
* `Inspect` protocol implementation returns strings in the `Decimal.new(...)` format
* Add `Decimal.scale/1`
* Optimize `Decimal.compare/2` for numbers with large exponents

### Bug fixes

* Fix `Decimal.integer?/1` spec
* Fix `Decimal.integer?/1` check on 0 with >1 significant digits

## v2.0.0 (2020-09-08)

Decimal v2.0 requires Elixir v1.2+.

### Enhancements

* Add `Decimal.integer?/1`

### Breaking changes

* Change `Decimal.compare/2` to return `:lt | :eq | :gt`
* Change `Decimal.cast/1` to return `{:ok, t} | :error`
* Change `Decimal.parse/1` to return `{t, binary} | :error`
* Remove `:message` and `:result` fields from `Decimal.Error`
* Remove sNaN
* Rename qNaN to NaN
* Remove deprecated support for floats in `Decimal.new/1`
* Remove deprecated `Decimal.minus/1`
* Remove deprecated `Decimal.plus/1`
* Remove deprecated `Decimal.reduce/1`
* Remove deprecated `Decimal.with_context/2`, `Decimal.get_context/1`, `Decimal.set_context/1`,
  and `Decimal.update_context/1`
* Remove deprecated `Decimal.decimal?/1`

### Deprecations

* Deprecate `Decimal.cmp/2`

## v1.9.0 (2020-09-08)

### Enhancements

* Add `Decimal.negate/1`
* Add `Decimal.apply_context/1`
* Add `Decimal.normalize/1`
* Add `Decimal.Context.with/2`, `Decimal.Context.get/1`, `Decimal.Context.set/2`,
  and `Decimal.Context.update/1`
* Add `Decimal.is_decimal/1`

### Deprecations

* Deprecate `Decimal.minus/1` in favour of the new `Decimal.negate/1`
* Deprecate `Decimal.plus/1` in favour of the new `Decimal.apply_context/1`
* Deprecate `Decimal.reduce/1` in favour of the new `Decimal.normalize/1`
* Deprecate `Decimal.with_context/2`, `Decimal.get_context/1`, `Decimal.set_context/2`,
  and `Decimal.update_context/1` in favour of new functions on the `Decimal.Context` module
* Deprecate `Decimal.decimal?/1` in favour of the new `Decimal.is_decimal/1`

## v1.8.1 (2019-12-20)

### Bug fixes

* Fix Decimal.compare/2 with string arguments
* Set :signal on error

## v1.8.0 (2019-06-24)

### Enhancements

* Add `Decimal.cast/1`
* Add `Decimal.eq?/2`, `Decimal.gt?/2`, and `Decimal.lt?/2`
* Add guards to `Decimal.new/3` to prevent invalid Decimal numbers

## v1.7.0 (2019-02-16)

### Enhancements

* Add `Decimal.sqrt/1`

## v1.6.0 (2018-11-22)

### Enhancements

* Support for canonical XSD representation on `Decimal.to_string/2`

### Bugfixes

* Fix exponent off-by-one when converting from decimal to float
* Fix negative?/1 and positive?/1 specs

### Deprecations

* Deprecate passing float to `Decimal.new/1` in favor of `Decimal.from_float/1`

## v1.5.0 (2018-03-24)

### Enhancements

* Add `Decimal.positive?/1` and `Decimal.negative?/1`
* Accept integers and strings in arithmetic functions, e.g.: `Decimal.add(1, "2.0")`
* Add `Decimal.from_float/1`

### Soft deprecations (no warnings emitted)

* Soft deprecate passing float to `new/1` in favor of `from_float/1`

## v1.4.1 (2017-10-12)

### Bugfixes

* Include the given value as part of the error reason
* Fix `:half_even` `:lists.last` bug (empty signif)
* Fix error message for round
* Fix `:half_down` rounding error when remainder is greater than 5
* Fix `Decimal.new/1` float conversion with bigger precision than 4
* Fix precision default value

## v1.4.0 (2017-06-25)

### Bugfixes

* Fix `Decimal.to_integer/1` for large coefficients
* Fix rounding of ~0 values
* Fix errors when comparing and adding two infinities
