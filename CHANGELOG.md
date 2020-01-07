# CHANGELOG

## v1.9.0-rc.0 (2020-01-07)

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
