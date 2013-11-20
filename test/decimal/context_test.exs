defmodule Decimal.ContextTest do
  use ExUnit.Case, async: true
  use Decimal.Record
  alias Decimal.Context

  test "truncate" do
    context = Context[precision: 2, rounding: :truncate]
    assert Context.round("1.02", context) == dec(coef: 10, exp: -1)
    assert Context.round("102", context) == dec(coef: 10, exp: 1)
    assert Context.round("1.1", context) == dec(coef: 11, exp: -1)
  end

  test "ceiling" do
    context = Context[precision: 2, rounding: :ceiling]
    assert Context.round("1.02", context) == dec(coef: 11, exp: -1)
    assert Context.round("102", context) == dec(coef: 11, exp: 1)
    assert Context.round("-102", context) == dec(coef: -10, exp: 1)
    assert Context.round("106", context) == dec(coef: 11, exp: 1)
  end

  test "floor" do
    context = Context[precision: 2, rounding: :floor]
    assert Context.round("1.02", context) == dec(coef: 10, exp: -1)
    assert Context.round("1.10", context) == dec(coef: 11, exp: -1)
    assert Context.round("-123", context) == dec(coef: -13, exp: 1)
  end

  test "half away zero" do
    context = Context[precision: 2, rounding: :half_away_zero]
    assert Context.round("1.02", context) == dec(coef: 10, exp: -1)
    assert Context.round("1.05", context) == dec(coef: 11, exp: -1)
    assert Context.round("-1.05", context) == dec(coef: -11, exp: -1)
    assert Context.round("123", context) == dec(coef: 12, exp: 1)
    assert Context.round("125", context) == dec(coef: 13, exp: 1)
    assert Context.round("-125", context) == dec(coef: -13, exp: 1)
  end

  test "half up" do
    context = Context[precision: 2, rounding: :half_up]
    assert Context.round("1.02", context) == dec(coef: 10, exp: -1)
    assert Context.round("1.05", context) == dec(coef: 11, exp: -1)
    assert Context.round("-1.05", context) == dec(coef: -10, exp: -1)
    assert Context.round("123", context) == dec(coef: 12, exp: 1)
    assert Context.round("-123", context) == dec(coef: -12, exp: 1)
    assert Context.round("125", context) == dec(coef: 13, exp: 1)
    assert Context.round("-125", context) == dec(coef: -12, exp: 1)
  end

  test "half even" do
    context = Context[precision: 2, rounding: :half_even]
    assert Context.round("1.0", context) == dec(coef: 10, exp: -1)
    assert Context.round("123", context) == dec(coef: 12, exp: 1)
    assert Context.round("6.66", context) == dec(coef: 67, exp: -1)
    assert Context.round("9.99", context) == dec(coef: 10, exp: 0)
    assert Context.round("-6.66", context) == dec(coef: -67, exp: -1)
    assert Context.round("-9.99", context) == dec(coef: -10, exp: 0)
  end
end
