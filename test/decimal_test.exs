defmodule DecimalTest do
  use ExUnit.Case, async: true

  alias Decimal.Context
  alias Decimal.Error

  require Decimal

  doctest Decimal

  defmacrop d(sign, coef, exp) do
    quote do
      %Decimal{sign: unquote(sign), coef: unquote(coef), exp: unquote(exp)}
    end
  end

  defmacrop sigil_d(str, _opts) do
    quote do
      Decimal.new(unquote(str))
    end
  end

  test "nan?/1" do
    assert Decimal.nan?(~d"nan")
    refute Decimal.nan?(~d"0")
  end

  test "inf?/1" do
    assert Decimal.inf?(~d"inf")
    refute Decimal.inf?(~d"0")
  end

  test "decimal?/1" do
    assert Decimal.decimal?(~d"nan")
    assert Decimal.decimal?(~d"inf")
    assert Decimal.decimal?(~d"0")
    refute Decimal.decimal?(42)
    refute Decimal.decimal?("42")
  end

  test "new/1 conversion" do
    assert Decimal.new(d(-1, 3, 2)) == d(-1, 3, 2)
    assert Decimal.new(123) == d(1, 123, 0)

    assert_raise FunctionClauseError, fn ->
      Decimal.new(:atom)
    end
  end

  test "new/1 parsing" do
    assert Decimal.new("123") == d(1, 123, 0)
    assert Decimal.new("+123") == d(1, 123, 0)
    assert Decimal.new("-123") == d(-1, 123, 0)

    assert Decimal.new("123.0") == d(1, 1230, -1)
    assert Decimal.new("+123.0") == d(1, 1230, -1)
    assert Decimal.new("-123.0") == d(-1, 1230, -1)

    assert Decimal.new("1.5") == d(1, 15, -1)
    assert Decimal.new("+1.5") == d(1, 15, -1)
    assert Decimal.new("-1.5") == d(-1, 15, -1)

    assert Decimal.new(".0") == d(1, 0, -1)
    assert Decimal.new("0.") == d(1, 0, 0)

    assert Decimal.new("0") == d(1, 0, 0)
    assert Decimal.new("+0") == d(1, 0, 0)
    assert Decimal.new("-0") == d(-1, 0, 0)

    assert Decimal.new("1230e13") == d(1, 1230, 13)
    assert Decimal.new("+1230e+2") == d(1, 1230, 2)
    assert Decimal.new("-1230e-2") == d(-1, 1230, -2)

    assert Decimal.new("1230.00e13") == d(1, 123_000, 11)
    assert Decimal.new("+1230.1230e+5") == d(1, 12_301_230, 1)
    assert Decimal.new("-1230.01010e-5") == d(-1, 123_001_010, -10)

    assert Decimal.new("0e0") == d(1, 0, 0)
    assert Decimal.new("+0e-0") == d(1, 0, 0)
    assert Decimal.new("-0e+0") == d(-1, 0, 0)

    assert Decimal.new("inf") == d(1, :inf, 0)
    assert Decimal.new("infinity") == d(1, :inf, 0)
    assert Decimal.new("-InfInitY") == d(-1, :inf, 0)

    assert Decimal.new("nAn") == d(1, :qNaN, 0)
    assert Decimal.new("-NaN") == d(-1, :qNaN, 0)

    assert Decimal.new("snAn") == d(1, :sNaN, 0)
    assert Decimal.new("-sNaN") == d(-1, :sNaN, 0)

    assert_raise Error, fn ->
      Decimal.new("")
    end

    assert_raise Error, fn ->
      Decimal.new("test")
    end

    assert_raise Error, fn ->
      Decimal.new("e0")
    end

    assert_raise Error, fn ->
      Decimal.new("42.+42")
    end

    assert_raise Error, fn ->
      Decimal.new("42e0.0")
    end
  end

  test "from_float/1" do
    assert Decimal.from_float(123.0) == d(1, 1230, -1)
    assert Decimal.from_float(0.1) == d(1, 1, -1)
    assert Decimal.from_float(0.000015) == d(1, 15, -6)
    assert Decimal.from_float(-1.5) == d(-1, 15, -1)
  end

  test "cast/1" do
    assert Decimal.cast(123) == d(1, 123, 0)
    assert Decimal.cast(123.0) == d(1, 1230, -1)
    assert Decimal.cast("123") == d(1, 123, 0)
    assert Decimal.cast("123.0") == d(1, 1230, -1)
    assert Decimal.new(123) |> Decimal.cast() == Decimal.new(123)

    assert_raise Error, fn ->
      Decimal.cast("one two three")
    end

    assert_raise Error, fn ->
      Decimal.cast("e0")
    end

    assert_raise FunctionClauseError, fn ->
      Decimal.cast(:one_two_three)
    end
  end

  test "abs/1" do
    assert Decimal.abs(~d"123") == d(1, 123, 0)
    assert Decimal.abs(~d"-123") == d(1, 123, 0)
    assert Decimal.abs(~d"-12.5e2") == d(1, 125, 1)
    assert Decimal.abs(~d"-42e-42") == d(1, 42, -42)
    assert Decimal.abs(~d"-inf") == d(1, :inf, 0)
    assert Decimal.abs(~d"nan") == d(1, :qNaN, 0)

    assert_raise Error, fn ->
      Decimal.abs(~d"snan")
    end
  end

  test "add/2" do
    assert Decimal.add(~d"0", ~d"0") == d(1, 0, 0)
    assert Decimal.add(~d"1", ~d"1") == d(1, 2, 0)
    assert Decimal.add(~d"1.3e3", ~d"2.4e2") == d(1, 154, 1)
    assert Decimal.add(~d"0.42", ~d"-1.5") == d(-1, 108, -2)
    assert Decimal.add(~d"-2e-2", ~d"-2e-2") == d(-1, 4, -2)
    assert Decimal.add(~d"-0", ~d"0") == d(1, 0, 0)
    assert Decimal.add(~d"-0", ~d"-0") == d(-1, 0, 0)
    assert Decimal.add(~d"2", ~d"-2") == d(1, 0, 0)
    assert Decimal.add(~d"5", ~d"nan") == d(1, :qNaN, 0)
    assert Decimal.add(~d"inf", ~d"inf") == d(1, :inf, 0)
    assert Decimal.add(~d"-inf", ~d"-inf") == d(-1, :inf, 0)

    assert Decimal.add(d(1, :inf, 2), d(1, :inf, 5)) == d(1, :inf, 5)

    Decimal.with_context(%Context{precision: 5, rounding: :floor}, fn ->
      Decimal.add(~d"2", ~d"-2") == d(-1, 0, 0)
    end)

    assert Decimal.add(~d"inf", ~d"5") == d(1, :inf, 0)
    assert Decimal.add(~d"5", ~d"-inf") == d(-1, :inf, 0)

    assert_raise Error, fn ->
      Decimal.add(~d"inf", ~d"-inf")
    end

    assert_raise Error, fn ->
      Decimal.add(~d"snan", ~d"0")
    end

    assert_raise ArgumentError, ~r/implicit conversion of 2.0 to Decimal is not allowed/, fn ->
      Decimal.add(1, 2.0)
    end
  end

  test "sub/2" do
    assert Decimal.sub(~d"0", ~d"0") == d(1, 0, 0)
    assert Decimal.sub(~d"1", ~d"2") == d(-1, 1, 0)
    assert Decimal.sub(~d"1.3e3", ~d"2.4e2") == d(1, 106, 1)
    assert Decimal.sub(~d"0.42", ~d"-1.5") == d(1, 192, -2)
    assert Decimal.sub(~d"2e-2", ~d"-2e-2") == d(1, 4, -2)
    assert Decimal.sub(~d"-0", ~d"0") == d(-1, 0, 0)
    assert Decimal.sub(~d"-0", ~d"-0") == d(1, 0, 0)
    assert Decimal.add(~d"5", ~d"nan") == d(1, :qNaN, 0)

    Decimal.with_context(%Context{precision: 5, rounding: :floor}, fn ->
      Decimal.sub(~d"2", ~d"2") == d(-1, 0, 0)
    end)

    assert Decimal.sub(~d"inf", ~d"5") == d(1, :inf, 0)
    assert Decimal.sub(~d"5", ~d"-inf") == d(1, :inf, 0)

    assert_raise Error, fn ->
      Decimal.sub(~d"inf", ~d"inf")
    end

    assert_raise Error, fn ->
      Decimal.sub(~d"snan", ~d"0")
    end
  end

  test "cmp/2" do
    assert Decimal.cmp(~d"420", ~d"42e1") == :eq
    assert Decimal.cmp(~d"1", ~d"0") == :gt
    assert Decimal.cmp(~d"0", ~d"1") == :lt
    assert Decimal.cmp(~d"0", ~d"-0") == :eq

    assert Decimal.cmp(~d"-inf", ~d"inf") == :lt
    assert Decimal.cmp(~d"inf", ~d"-inf") == :gt
    assert Decimal.cmp(~d"inf", ~d"0") == :gt
    assert Decimal.cmp(~d"-inf", ~d"0") == :lt
    assert Decimal.cmp(~d"0", ~d"inf") == :lt
    assert Decimal.cmp(~d"0", ~d"-inf") == :gt

    assert Decimal.cmp("Inf", "Inf") == :eq

    assert_raise Error, fn ->
      Decimal.cmp(~d"snan", ~d"0")
    end

    assert_raise CaseClauseError, fn ->
      Decimal.cmp(~d"nan", ~d"1")
    end
  end

  test "equal?/2" do
    assert Decimal.equal?(~d"420", ~d"42e1")
    refute Decimal.equal?(~d"1", ~d"0")
    refute Decimal.equal?(~d"0", ~d"1")
    assert Decimal.equal?(~d"0", ~d"-0")
    refute Decimal.equal?(~d"nan", ~d"1")
    refute Decimal.equal?(~d"1", ~d"nan")

    assert_raise Error, fn ->
      Decimal.equal?(~d"snan", ~d"0")
    end
  end

  test "eq/2?" do
    assert Decimal.eq?(~d"420", ~d"42e1")
    refute Decimal.eq?(~d"1", ~d"0")
    refute Decimal.eq?(~d"0", ~d"1")
    assert Decimal.eq?(~d"0", ~d"-0")
    refute Decimal.eq?(~d"nan", ~d"1")
    refute Decimal.eq?(~d"1", ~d"nan")

    assert_raise Error, fn ->
      Decimal.eq?(~d"snan", ~d"0")
    end
  end

  test "gt?/2" do
    refute Decimal.gt?(~d"420", ~d"42e1")
    assert Decimal.gt?(~d"1", ~d"0")
    refute Decimal.gt?(~d"0", ~d"1")
    refute Decimal.gt?(~d"0", ~d"-0")
    refute Decimal.gt?(~d"nan", ~d"1")
    refute Decimal.gt?(~d"1", ~d"nan")

    assert_raise Error, fn ->
      Decimal.gt?(~d"snan", ~d"0")
    end
  end

  test "lt?/2" do
    refute Decimal.lt?(~d"420", ~d"42e1")
    refute Decimal.lt?(~d"1", ~d"0")
    assert Decimal.lt?(~d"0", ~d"1")
    refute Decimal.lt?(~d"0", ~d"-0")
    refute Decimal.lt?(~d"nan", ~d"1")
    refute Decimal.lt?(~d"1", ~d"nan")

    assert_raise Error, fn ->
      Decimal.lt?(~d"snan", ~d"0")
    end
  end

  test "div/2" do
    Decimal.with_context(%Context{precision: 5, rounding: :half_up}, fn ->
      assert Decimal.div(~d"1", ~d"3") == d(1, 33333, -5)
      assert Decimal.div(~d"42", ~d"2") == d(1, 21, 0)
      assert Decimal.div(~d"123", ~d"12345") == d(1, 99635, -7)
      assert Decimal.div(~d"123", ~d"123") == d(1, 1, 0)
      assert Decimal.div(~d"-1", ~d"5") == d(-1, 2, -1)
      assert Decimal.div(~d"-1", ~d"-1") == d(1, 1, 0)
      assert Decimal.div(~d"2", ~d"-5") == d(-1, 4, -1)
    end)

    Decimal.with_context(%Context{precision: 2, rounding: :half_up}, fn ->
      assert Decimal.div(~d"31", ~d"2") == d(1, 16, 0)
    end)

    Decimal.with_context(%Context{precision: 2, rounding: :floor}, fn ->
      assert Decimal.div(~d"31", ~d"2") == d(1, 15, 0)
    end)

    assert Decimal.div(~d"0", ~d"3") == d(1, 0, 0)
    assert Decimal.div(~d"-0", ~d"3") == d(-1, 0, 0)
    assert Decimal.div(~d"0", ~d"-3") == d(-1, 0, 0)
    assert Decimal.div(~d"nan", ~d"2") == d(1, :qNaN, 0)

    assert Decimal.div(~d"-inf", ~d"-2") == d(1, :inf, 0)
    assert Decimal.div(~d"5", ~d"-inf") == d(-1, 0, 0)

    assert_raise Error, fn ->
      Decimal.div(~d"inf", ~d"inf")
    end

    assert_raise Error, fn ->
      Decimal.div(~d"snan", ~d"2")
    end

    assert_raise Error, fn ->
      Decimal.div(~d"-2", ~d"-snan")
    end

    assert_raise Error, "invalid_operation: 0 / 0", fn ->
      Decimal.div(~d"0", ~d"-0")
    end

    assert_raise Error, "division_by_zero", fn ->
      Decimal.div(~d"1", ~d"0")
    end
  end

  test "div_int/2" do
    assert Decimal.div_int(~d"1", ~d"0.3") == d(1, 3, 0)
    assert Decimal.div_int(~d"2", ~d"3") == d(1, 0, 0)
    assert Decimal.div_int(~d"42", ~d"2") == d(1, 21, 0)
    assert Decimal.div_int(~d"123", ~d"23") == d(1, 5, 0)
    assert Decimal.div_int(~d"123", ~d"-23") == d(-1, 5, 0)
    assert Decimal.div_int(~d"-123", ~d"23") == d(-1, 5, 0)
    assert Decimal.div_int(~d"-123", ~d"-23") == d(1, 5, 0)
    assert Decimal.div_int(~d"1", ~d"0.3") == d(1, 3, 0)
    assert Decimal.div_int(~d"4", ~d"8") == d(1, 0, 0)

    assert Decimal.div_int(~d"0", ~d"3") == d(1, 0, 0)
    assert Decimal.div_int(~d"-0", ~d"3") == d(-1, 0, 0)
    assert Decimal.div_int(~d"0", ~d"-3") == d(-1, 0, 0)
    assert Decimal.div_int(~d"nan", ~d"2") == d(1, :qNaN, 0)

    assert Decimal.div_int(~d"-inf", ~d"-2") == d(1, :inf, 0)
    assert Decimal.div_int(~d"5", ~d"-inf") == d(-1, 0, 0)

    assert_raise Error, fn ->
      Decimal.div_int(~d"inf", ~d"inf")
    end

    assert_raise Error, fn ->
      Decimal.div_int(~d"snan", ~d"2")
    end

    assert_raise Error, fn ->
      Decimal.div_int(~d"-2", ~d"-snan")
    end

    assert_raise Error, fn ->
      Decimal.div_int(~d"0", ~d"-0")
    end
  end

  test "rem/2" do
    assert Decimal.rem(~d"1", ~d"3") == d(1, 1, 0)
    assert Decimal.rem(~d"42", ~d"2") == d(1, 0, 0)
    assert Decimal.rem(~d"123", ~d"23") == d(1, 8, 0)
    assert Decimal.rem(~d"123", ~d"-23") == d(1, 8, 0)
    assert Decimal.rem(~d"-123", ~d"23") == d(-1, 8, 0)
    assert Decimal.rem(~d"-123", ~d"-23") == d(-1, 8, 0)
    assert Decimal.rem(~d"1", ~d"0.3") == d(1, 1, -1)
    assert Decimal.rem(~d"4", ~d"8") == d(1, 4, 0)

    assert Decimal.rem(~d"2.1", ~d"3") == d(1, 21, -1)
    assert Decimal.rem(~d"10", ~d"3") == d(1, 1, 0)
    assert Decimal.rem(~d"-10", ~d"3") == d(-1, 1, 0)
    assert Decimal.rem(~d"10.2", ~d"1") == d(1, 2, -1)
    assert Decimal.rem(~d"10", ~d"0.3") == d(1, 1, -1)
    assert Decimal.rem(~d"3.6", ~d"1.3") == d(1, 10, -1)

    assert Decimal.rem(~d"-inf", ~d"-2") == d(-1, 0, 0)
    assert Decimal.rem(~d"5", ~d"-inf") == d(1, :inf, 0)
    assert Decimal.rem(~d"nan", ~d"2") == d(1, :qNaN, 0)

    assert_raise Error, fn ->
      Decimal.rem(~d"inf", ~d"inf")
    end

    assert_raise Error, fn ->
      Decimal.rem(~d"snan", ~d"2")
    end

    assert_raise Error, fn ->
      Decimal.rem(~d"-2", ~d"-snan")
    end

    assert_raise Error, fn ->
      Decimal.rem(~d"0", ~d"-0")
    end
  end

  test "max/2" do
    assert Decimal.max(~d"0", ~d"0") == d(1, 0, 0)
    assert Decimal.max(~d"1", ~d"0") == d(1, 1, 0)
    assert Decimal.max(~d"0", ~d"1") == d(1, 1, 0)
    assert Decimal.max(~d"-1", ~d"1") == d(1, 1, 0)
    assert Decimal.max(~d"1", ~d"-1") == d(1, 1, 0)
    assert Decimal.max(~d"-30", ~d"-40") == d(-1, 30, 0)

    assert Decimal.max(~d"+0", ~d"-0") == d(1, 0, 0)
    assert Decimal.max(~d"2e1", ~d"20") == d(1, 2, 1)
    assert Decimal.max(~d"-2e1", ~d"-20") == d(-1, 20, 0)

    assert Decimal.max(~d"-inf", ~d"5") == d(1, 5, 0)
    assert Decimal.max(~d"inf", ~d"5") == d(1, :inf, 0)

    assert Decimal.max(~d"nan", ~d"1") == d(1, 1, 0)
    assert Decimal.max(~d"2", ~d"nan") == d(1, 2, 0)

    assert_raise Error, fn ->
      Decimal.max(~d"snan", ~d"2")
    end
  end

  test "min/2" do
    assert Decimal.min(~d"0", ~d"0") == d(1, 0, 0)
    assert Decimal.min(~d"-1", ~d"0") == d(-1, 1, 0)
    assert Decimal.min(~d"0", ~d"-1") == d(-1, 1, 0)
    assert Decimal.min(~d"-1", ~d"1") == d(-1, 1, 0)
    assert Decimal.min(~d"1", ~d"0") == d(1, 0, 0)
    assert Decimal.min(~d"-30", ~d"-40") == d(-1, 40, 0)

    assert Decimal.min(~d"+0", ~d"-0") == d(-1, 0, 0)
    assert Decimal.min(~d"2e1", ~d"20") == d(1, 20, 0)
    assert Decimal.min(~d"-2e1", ~d"-20") == d(-1, 2, 1)

    assert Decimal.min(~d"-inf", ~d"5") == d(-1, :inf, 0)
    assert Decimal.min(~d"inf", ~d"5") == d(1, 5, 0)

    assert Decimal.min(~d"nan", ~d"1") == d(1, 1, 0)
    assert Decimal.min(~d"2", ~d"nan") == d(1, 2, 0)

    assert_raise Error, fn ->
      Decimal.min(~d"snan", ~d"2")
    end
  end

  test "negate/1" do
    assert Decimal.negate(~d"0") == d(-1, 0, 0)
    assert Decimal.negate(~d"1") == d(-1, 1, 0)
    assert Decimal.negate(~d"-1") == d(1, 1, 0)

    assert Decimal.negate(~d"inf") == d(-1, :inf, 0)
    assert Decimal.negate(~d"nan") == d(1, :qNaN, 0)

    assert_raise Error, fn ->
      Decimal.negate(~d"snan")
    end
  end

  test "apply_context/1" do
    Decimal.with_context(%Context{precision: 2}, fn ->
      assert Decimal.apply_context(~d"0") == d(1, 0, 0)
      assert Decimal.apply_context(~d"5") == d(1, 5, 0)
      assert Decimal.apply_context(~d"123") == d(1, 12, 1)
      assert Decimal.apply_context(~d"nan") == d(1, :qNaN, 0)
    end)

    assert_raise Error, fn ->
      Decimal.apply_context(~d"snan")
    end
  end

  test "positive?/1" do
    Decimal.with_context(%Context{precision: 2}, fn ->
      refute Decimal.positive?(~d"0")
      assert Decimal.positive?(~d"5")
      refute Decimal.positive?(~d"-5")
      assert Decimal.positive?(~d"123.0")
      refute Decimal.positive?(~d"nan")
    end)

    assert_raise Error, fn ->
      Decimal.positive?(~d"snan")
    end
  end

  test "negative?1" do
    Decimal.with_context(%Context{precision: 2}, fn ->
      refute Decimal.negative?(~d"0")
      assert Decimal.negative?(~d"-5")
      refute Decimal.negative?(~d"5")
      assert Decimal.negative?(~d"-123.0")
      refute Decimal.negative?(~d"nan")
    end)

    assert_raise Error, fn ->
      Decimal.negative?(~d"snan")
    end
  end

  test "mult/2" do
    assert Decimal.mult(~d"0", ~d"0") == d(1, 0, 0)
    assert Decimal.mult(~d"42", ~d"0") == d(1, 0, 0)
    assert Decimal.mult(~d"0", ~d"42") == d(1, 0, 0)
    assert Decimal.mult(~d"5", ~d"5") == d(1, 25, 0)
    assert Decimal.mult(~d"-5", ~d"5") == d(-1, 25, 0)
    assert Decimal.mult(~d"5", ~d"-5") == d(-1, 25, 0)
    assert Decimal.mult(~d"-5", ~d"-5") == d(1, 25, 0)
    assert Decimal.mult(~d"42", ~d"0.42") == d(1, 1764, -2)
    assert Decimal.mult(~d"0.03", ~d"0.3") == d(1, 9, -3)

    assert Decimal.mult(~d"0", ~d"-0") == d(-1, 0, 0)
    assert Decimal.mult(~d"0", ~d"3") == d(1, 0, 0)
    assert Decimal.mult(~d"-0", ~d"3") == d(-1, 0, 0)
    assert Decimal.mult(~d"0", ~d"-3") == d(-1, 0, 0)

    assert Decimal.mult(~d"inf", ~d"-3") == d(-1, :inf, 0)
    assert Decimal.mult(~d"nan", ~d"2") == d(1, :qNaN, 0)

    assert_raise Error, fn ->
      Decimal.mult(~d"snan", ~d"2")
    end

    assert_raise Error, fn ->
      Decimal.mult(~d"-2", ~d"-snan")
    end

    assert_raise Error, fn ->
      Decimal.mult(~d"inf", ~d"0")
    end

    assert_raise Error, fn ->
      Decimal.mult(~d"0", ~d"-inf")
    end
  end

  test "reduce/1" do
    assert Decimal.reduce(~d"2.1") == d(1, 21, -1)
    assert Decimal.reduce(~d"2.10") == d(1, 21, -1)
    assert Decimal.reduce(~d"-2") == d(-1, 2, 0)
    assert Decimal.reduce(~d"-2.00") == d(-1, 2, 0)
    assert Decimal.reduce(~d"200") == d(1, 2, 2)
    assert Decimal.reduce(~d"0") == d(1, 0, 0)
    assert Decimal.reduce(~d"-0") == d(-1, 0, 0)
    assert Decimal.reduce(~d"-inf") == d(-1, :inf, 0)
    assert Decimal.reduce(~d"nan") == d(1, :qNaN, 0)

    assert_raise Error, fn ->
      Decimal.reduce(~d"snan")
    end
  end

  test "to_string/2 normal" do
    assert Decimal.to_string(~d"0", :normal) == "0"
    assert Decimal.to_string(~d"42", :normal) == "42"
    assert Decimal.to_string(~d"42.42", :normal) == "42.42"
    assert Decimal.to_string(~d"0.42", :normal) == "0.42"
    assert Decimal.to_string(~d"0.0042", :normal) == "0.0042"
    assert Decimal.to_string(~d"-1", :normal) == "-1"
    assert Decimal.to_string(~d"-0", :normal) == "-0"
    assert Decimal.to_string(~d"-1.23", :normal) == "-1.23"
    assert Decimal.to_string(~d"-0.0123", :normal) == "-0.0123"
    assert Decimal.to_string(~d"nan", :normal) == "NaN"
    assert Decimal.to_string(~d"-nan", :normal) == "-NaN"
    assert Decimal.to_string(~d"-inf", :normal) == "-Infinity"
  end

  test "to_string/2 scientific" do
    assert Decimal.to_string(~d"123", :scientific) == "123"
    assert Decimal.to_string(~d"-123", :scientific) == "-123"
    assert Decimal.to_string(~d"123e1", :scientific) == "1.23E+3"
    assert Decimal.to_string(~d"123e3", :scientific) == "1.23E+5"
    assert Decimal.to_string(~d"123e-1", :scientific) == "12.3"
    assert Decimal.to_string(~d"123e-5", :scientific) == "0.00123"
    assert Decimal.to_string(~d"123e-10", :scientific) == "1.23E-8"
    assert Decimal.to_string(~d"-123e-12", :scientific) == "-1.23E-10"
    assert Decimal.to_string(~d"0", :scientific) == "0"
    assert Decimal.to_string(~d"0e-2", :scientific) == "0.00"
    assert Decimal.to_string(~d"0e2", :scientific) == "0E+2"
    assert Decimal.to_string(~d"-0", :scientific) == "-0"
    assert Decimal.to_string(~d"5e-6", :scientific) == "0.000005"
    assert Decimal.to_string(~d"50e-7", :scientific) == "0.0000050"
    assert Decimal.to_string(~d"5e-7", :scientific) == "5E-7"
    assert Decimal.to_string(~d"4321.768", :scientific) == "4321.768"
    assert Decimal.to_string(~d"-0", :scientific) == "-0"
    assert Decimal.to_string(~d"nan", :scientific) == "NaN"
    assert Decimal.to_string(~d"-nan", :scientific) == "-NaN"
    assert Decimal.to_string(~d"-inf", :scientific) == "-Infinity"
    assert Decimal.to_string(~d"84e-1", :scientific) == "8.4"
    assert Decimal.to_string(~d"22E+2", :scientific) == "2.2E+3"
  end

  test "to_string/2 raw" do
    assert Decimal.to_string(~d"2", :raw) == "2"
    assert Decimal.to_string(~d"300", :raw) == "300"
    assert Decimal.to_string(~d"4321.768", :raw) == "4321768E-3"
    assert Decimal.to_string(~d"-53000", :raw) == "-53000"
    assert Decimal.to_string(~d"0.0042", :raw) == "42E-4"
    assert Decimal.to_string(~d"0.2", :raw) == "2E-1"
    assert Decimal.to_string(~d"-0.0003", :raw) == "-3E-4"
    assert Decimal.to_string(~d"-0", :raw) == "-0"
    assert Decimal.to_string(~d"nan", :raw) == "NaN"
    assert Decimal.to_string(~d"-nan", :raw) == "-NaN"
    assert Decimal.to_string(~d"-inf", :raw) == "-Infinity"
  end

  test "to_string/2 xsd" do
    assert Decimal.to_string(~d"0", :xsd) == "0.0"
    assert Decimal.to_string(~d"0.0", :xsd) == "0.0"
    assert Decimal.to_string(~d"0.001", :xsd) == "0.001"
    assert Decimal.to_string(~d"-0", :xsd) == "-0.0"
    assert Decimal.to_string(~d"-1", :xsd) == "-1.0"
    assert Decimal.to_string(~d"-0.00", :xsd) == "-0.0"
    assert Decimal.to_string(~d"1.00", :xsd) == "1.0"
    assert Decimal.to_string(~d"1000", :xsd) == "1000.0"
    assert Decimal.to_string(~d"1000.000000", :xsd) == "1000.0"
    assert Decimal.to_string(~d"12345.000", :xsd) == "12345.0"
    assert Decimal.to_string(~d"42", :xsd) == "42.0"
    assert Decimal.to_string(~d"42.42", :xsd) == "42.42"
    assert Decimal.to_string(~d"0.42", :xsd) == "0.42"
    assert Decimal.to_string(~d"0.0042", :xsd) == "0.0042"
    assert Decimal.to_string(~d"010.020", :xsd) == "10.02"
    assert Decimal.to_string(~d"-1.23", :xsd) == "-1.23"
    assert Decimal.to_string(~d"-0.0123", :xsd) == "-0.0123"
    assert Decimal.to_string(~d"1E+2", :xsd) == "100.0"
    assert Decimal.to_string(~d"-42E+3", :xsd) == "-42000.0"
    assert Decimal.to_string(~d"nan", :xsd) == "NaN"
    assert Decimal.to_string(~d"-nan", :xsd) == "-NaN"
    assert Decimal.to_string(~d"-inf", :xsd) == "-Infinity"
  end

  test "to_integer/1" do
    Decimal.with_context(%Context{precision: 36, rounding: :floor}, fn ->
      assert Decimal.to_integer(~d"0") == 0
      assert Decimal.to_integer(~d"300") == 300
      assert Decimal.to_integer(~d"-53000") == -53000
      assert Decimal.to_integer(~d"-0") == 0
      assert Decimal.to_integer(d(1, 10, 2)) == 1000
      assert Decimal.to_integer(d(1, 1000, -2)) == 10
      assert Decimal.to_integer(~d"123456789123489123456789") == 123_456_789_123_489_123_456_789

      assert Decimal.to_integer(Decimal.mult(~d"123456789123489123456789", ~d"1000")) ==
               123_456_789_123_489_123_456_789_000

      assert Decimal.to_integer(d(1, 1_365_900_000_000_000_000_000, -2)) ==
               13_659_000_000_000_000_000

      assert_raise FunctionClauseError, fn ->
        Decimal.to_integer(d(1, 1001, -2))
      end

      assert_raise FunctionClauseError, fn ->
        Decimal.to_integer(d(1, :qNaN, 0))
      end
    end)
  end

  test "to_float/1" do
    Decimal.with_context(%Context{precision: 36, rounding: :floor}, fn ->
      assert Decimal.to_float(~d"0") === 0.0
      assert Decimal.to_float(~d"-0") === 0.0
      assert Decimal.to_float(~d"-0.0") === 0.0
      assert Decimal.to_float(~d"3.00") === 3.00
      assert Decimal.to_float(~d"-53.000") === -53.000
      assert Decimal.to_float(~d"53000") === 53000.0
      assert Decimal.to_float(~d"123.456") === 123.456
      assert Decimal.to_float(~d"-123.456") === -123.456
      assert Decimal.to_float(~d"123.45600") === 123.456
      assert Decimal.to_float(~d"123456.789") === 123_456.789
      assert Decimal.to_float(~d"123456789.123456789") === 123_456_789.12345679

      assert Decimal.to_float(~d"94503599627370496") === 94_503_599_627_370_496.0
      assert Decimal.to_float(~d"94503599627370496.376") === 94_503_599_627_370_496.376
      assert Decimal.to_float(~d"4503599627370496") === 4_503_599_627_370_496.0
      assert Decimal.to_float(~d"2251799813685248") === 2_251_799_813_685_248.0
      assert Decimal.to_float(~d"9007199254740992") === 9_007_199_254_740_992.0

      assert_raise FunctionClauseError, fn ->
        Decimal.to_float(d(1, :qNaN, 0))
      end
    end)
  end

  test "with_context/2: down" do
    Decimal.with_context(%Context{precision: 2, rounding: :down}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"102") == d(1, 10, 1)
      assert Decimal.add(~d"0", ~d"-102") == d(-1, 10, 1)
      assert Decimal.add(~d"0", ~d"1.1") == d(1, 11, -1)
    end)
  end

  test "with_context/2: ceiling" do
    Decimal.with_context(%Context{precision: 2, rounding: :ceiling}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"102") == d(1, 11, 1)
      assert Decimal.add(~d"0", ~d"-102") == d(-1, 10, 1)
      assert Decimal.add(~d"0", ~d"106") == d(1, 11, 1)
    end)
  end

  test "with_context/2: floor" do
    Decimal.with_context(%Context{precision: 2, rounding: :floor}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"1.10") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"-123") == d(-1, 13, 1)
    end)
  end

  test "with_context/2: half up" do
    Decimal.with_context(%Context{precision: 2, rounding: :half_up}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"1.05") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"-1.05") == d(-1, 11, -1)
      assert Decimal.add(~d"0", ~d"123") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"-123") == d(-1, 12, 1)
      assert Decimal.add(~d"0", ~d"125") == d(1, 13, 1)
      assert Decimal.add(~d"0", ~d"-125") == d(-1, 13, 1)
      assert Decimal.add(~d"0", ~d"243.48") == d(1, 24, 1)
    end)
  end

  test "with_context/2: half even" do
    Decimal.with_context(%Context{precision: 2, rounding: :half_even}, fn ->
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 100, -1)
      assert Decimal.add(~d"0", ~d"1.0") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"123") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"6.66") == d(1, 67, -1)
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 100, -1)
      assert Decimal.add(~d"0", ~d"-6.66") == d(-1, 67, -1)
      assert Decimal.add(~d"0", ~d"-9.99") == d(-1, 100, -1)
    end)

    Decimal.with_context(%Context{precision: 3, rounding: :half_even}, fn ->
      assert Decimal.add(~d"0", ~d"244.58") == d(1, 245, 0)
    end)
  end

  test "with_context/2: half down" do
    Decimal.with_context(%Context{precision: 2, rounding: :half_down}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"1.05") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"-1.05") == d(-1, 10, -1)
      assert Decimal.add(~d"0", ~d"123") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"125") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"-125") == d(-1, 12, 1)
    end)
  end

  test "with_context/2: up" do
    Decimal.with_context(%Context{precision: 2, rounding: :up}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"102") == d(1, 11, 1)
      assert Decimal.add(~d"0", ~d"-102") == d(-1, 11, 1)
      assert Decimal.add(~d"0", ~d"1.1") == d(1, 11, -1)
    end)
  end

  test "round/3: special" do
    assert Decimal.round(~d"inf", 2, :down) == d(1, :inf, 0)
    assert Decimal.round(~d"nan", 2, :down) == d(1, :qNaN, 0)

    assert_raise Error, fn ->
      Decimal.round(~d"snan", 2, :down)
    end
  end

  test "round/3: down" do
    round = &Decimal.round(&1, 2, :down)
    roundneg = &Decimal.round(&1, -2, :down)
    assert round.(~d"1.02") == d(1, 102, -2)
    assert round.(~d"1.029") == d(1, 102, -2)
    assert round.(~d"-1.029") == d(-1, 102, -2)
    assert round.(~d"102") == d(1, 10200, -2)
    assert round.(~d"0.001") == d(1, 0, -2)
    assert round.(~d"-0.001") == d(-1, 0, -2)
    assert roundneg.(~d"1.02") == d(1, 0, 2)
    assert roundneg.(~d"102") == d(1, 1, 2)
    assert roundneg.(~d"1099") == d(1, 10, 2)
  end

  test "round/3: ceiling" do
    round = &Decimal.round(&1, 2, :ceiling)
    roundneg = &Decimal.round(&1, -2, :ceiling)
    assert round.(~d"1.02") == d(1, 102, -2)
    assert round.(~d"1.021") == d(1, 103, -2)
    assert round.(~d"-1.021") == d(-1, 102, -2)
    assert round.(~d"102") == d(1, 10200, -2)
    assert roundneg.(~d"1.02") == d(1, 1, 2)
    assert roundneg.(~d"102") == d(1, 2, 2)
  end

  test "round/3: floor" do
    round = &Decimal.round(&1, 2, :floor)
    roundneg = &Decimal.round(&1, -2, :floor)
    assert round.(~d"1.02") == d(1, 102, -2)
    assert round.(~d"1.029") == d(1, 102, -2)
    assert round.(~d"-1.029") == d(-1, 103, -2)
    assert roundneg.(~d"123") == d(1, 1, 2)
    assert roundneg.(~d"-123") == d(-1, 2, 2)
  end

  test "round/3: half up" do
    round = &Decimal.round(&1, 2, :half_up)
    roundneg = &Decimal.round(&1, -2, :half_up)
    assert round.(~d"1.02") == d(1, 102, -2)
    assert round.(~d"1.025") == d(1, 103, -2)
    assert round.(~d"-1.02") == d(-1, 102, -2)
    assert round.(~d"-1.025") == d(-1, 103, -2)
    assert roundneg.(~d"120") == d(1, 1, 2)
    assert roundneg.(~d"150") == d(1, 2, 2)
    assert roundneg.(~d"-120") == d(-1, 1, 2)
    assert roundneg.(~d"-150") == d(-1, 2, 2)

    assert Decimal.round(~d"243.48", 0, :half_up) == d(1, 243, 0)
  end

  test "round/3: half even" do
    round = &Decimal.round(&1, 2, :half_even)
    roundneg = &Decimal.round(&1, -2, :half_even)
    assert round.(~d"1.03") == d(1, 103, -2)
    assert round.(~d"1.035") == d(1, 104, -2)
    assert round.(~d"1.045") == d(1, 104, -2)
    assert round.(~d"-1.035") == d(-1, 104, -2)
    assert round.(~d"-1.045") == d(-1, 104, -2)
    assert roundneg.(~d"130") == d(1, 1, 2)
    assert roundneg.(~d"150") == d(1, 2, 2)
    assert roundneg.(~d"250") == d(1, 2, 2)
    assert roundneg.(~d"-150") == d(-1, 2, 2)
    assert roundneg.(~d"-250") == d(-1, 2, 2)

    assert Decimal.round(~d"9.99", 0, :half_even) == d(1, 10, 0)
    assert Decimal.round(~d"244.58", 0, :half_even) == d(1, 245, 0)
  end

  test "round/3: half down" do
    round = &Decimal.round(&1, 2, :half_down)
    roundneg = &Decimal.round(&1, -2, :half_down)
    assert round.(~d"1.02") == d(1, 102, -2)
    assert round.(~d"1.025") == d(1, 102, -2)
    assert round.(~d"-1.02") == d(-1, 102, -2)
    assert round.(~d"-1.025") == d(-1, 102, -2)
    assert roundneg.(~d"120") == d(1, 1, 2)
    assert roundneg.(~d"150") == d(1, 1, 2)
    assert roundneg.(~d"-120") == d(-1, 1, 2)
    assert roundneg.(~d"-150") == d(-1, 1, 2)
  end

  test "round/3: up" do
    round = &Decimal.round(&1, 2, :up)
    roundneg = &Decimal.round(&1, -2, :up)
    assert round.(~d"1.02") == d(1, 102, -2)
    assert round.(~d"1.029") == d(1, 103, -2)
    assert round.(~d"-1.029") == d(-1, 103, -2)
    assert round.(~d"102") == d(1, 10200, -2)
    assert round.(~d"0.001") == d(1, 1, -2)
    assert round.(~d"-0.001") == d(-1, 1, -2)
    assert roundneg.(~d"1.02") == d(1, 1, 2)
    assert roundneg.(~d"102") == d(1, 2, 2)
    assert roundneg.(~d"1099") == d(1, 11, 2)
  end

  test "sqrt/1" do
    Decimal.with_context(%Context{precision: 9, rounding: :half_even}, fn ->
      assert Decimal.sqrt(~d"0") == d(1, 0, 0)
      assert Decimal.sqrt(~d"-0") == d(-1, 0, 0)
      assert Decimal.sqrt(~d"1") == d(1, 1, 0)
      assert Decimal.sqrt(~d"1.0") == d(1, 10, -1)
      assert Decimal.sqrt(~d"1.00") == d(1, 10, -1)
      assert Decimal.sqrt(~d"0.01") == d(1, 1, -1)
      assert Decimal.sqrt(~d"100") == d(1, 10, 0)
      assert Decimal.sqrt(~d"10") == d(1, 316_227_766, -8)
      assert Decimal.sqrt(~d"7") == d(1, 264_575_131, -8)
      assert Decimal.sqrt(~d"0.39") == d(1, 624_499_800, -9)
    end)
  end

  test "with_context/2 set flags" do
    Decimal.with_context(%Context{precision: 2}, fn ->
      assert [] = Decimal.get_context().flags
      Decimal.add(~d"2", ~d"2")
      assert [] = Decimal.get_context().flags
      Decimal.add(~d"2.0000", ~d"2")
      assert [:rounded] = Decimal.get_context().flags
      Decimal.add(~d"2.0001", ~d"2")
      assert :inexact in Decimal.get_context().flags
    end)

    Decimal.with_context(%Context{precision: 2}, fn ->
      assert [] = Decimal.get_context().flags

      assert_raise Error, fn ->
        assert Decimal.mult(~d"inf", ~d"0")
      end

      assert :invalid_operation in Decimal.get_context().flags
    end)
  end

  test "with_context/2 traps" do
    Decimal.with_context(%Context{traps: []}, fn ->
      assert Decimal.mult(~d"inf", ~d"0") == d(1, :qNaN, 0)
      assert Decimal.div(~d"5", ~d"0") == d(1, :inf, 0)
      assert :division_by_zero in Decimal.get_context().flags
    end)
  end

  test "error sets result" do
    try do
      Decimal.mult(~d"inf", ~d"0")
    rescue
      ex in [Error] ->
        assert ex.result == d(1, :sNaN, 0)
    end
  end

  test "issue #13" do
    round_down = &Decimal.round(&1, 0, :down)
    round_up = &Decimal.round(&1, 0, :up)
    assert round_down.(~d"-2.5") == d(-1, 2, 0)
    assert round_up.(~d"-2.5") == d(-1, 3, 0)
    assert round_up.(~d"2.5") == d(1, 3, 0)
    assert round_down.(~d"2.5") == d(1, 2, 0)
  end

  test "issue #35" do
    assert Decimal.round(~d"0.0001", 0, :down) == d(1, 0, 0)
    assert Decimal.round(~d"0.0001", 0, :ceiling) == d(1, 1, 0)
    assert Decimal.round(~d"0.0001", 0, :floor) == d(1, 0, 0)
    assert Decimal.round(~d"0.0001", 0, :half_up) == d(1, 0, 0)
    assert Decimal.round(~d"0.0001", 0, :half_even) == d(1, 0, 0)
    assert Decimal.round(~d"0.0001", 0, :half_down) == d(1, 0, 0)
    assert Decimal.round(~d"0.0001", 0, :up) == d(1, 1, 0)

    assert Decimal.round(~d"0.0005", 0, :down) == d(1, 0, 0)
    assert Decimal.round(~d"0.0005", 0, :ceiling) == d(1, 1, 0)
    assert Decimal.round(~d"0.0005", 0, :floor) == d(1, 0, 0)
    assert Decimal.round(~d"0.0005", 0, :half_up) == d(1, 0, 0)
    assert Decimal.round(~d"0.0005", 0, :half_even) == d(1, 0, 0)
    assert Decimal.round(~d"0.0005", 0, :half_down) == d(1, 0, 0)
    assert Decimal.round(~d"0.0005", 0, :up) == d(1, 1, 0)
  end

  test "issue #29" do
    assert Decimal.rem(~d"1.234", ~d"1") == d(1, 234, -3)
    assert Decimal.rem(~d"1.234", ~d"1.0") == d(1, 234, -3)
    assert Decimal.rem(~d"1.234", ~d"1.00") == d(1, 234, -3)
  end

  test "issue #62" do
    assert Decimal.from_float(0.0001) == d(1, 1, -4)
    assert Decimal.from_float(0.00001) == d(1, 1, -5)
    assert Decimal.from_float(0.000001) == d(1, 1, -6)
    assert Decimal.from_float(-0.0001) == d(-1, 1, -4)
    assert Decimal.from_float(-0.00001) == d(-1, 1, -5)
    assert Decimal.from_float(-0.000001) == d(-1, 1, -6)
    assert Decimal.from_float(0.00002) == d(1, 2, -5)
    assert Decimal.from_float(0.00009) == d(1, 9, -5)
  end

  test "issue #57" do
    assert Decimal.round(~d"0.5", 0, :half_even) == d(1, 0, 0)
    assert Decimal.round(~d"0.05", 1, :half_even) == d(1, 0, -1)
    assert Decimal.round(~d"0.005", 2, :half_even) == d(1, 0, -2)
    assert Decimal.round(~d"0.0005", 3, :half_even) == d(1, 0, -3)
    assert Decimal.round(~d"0.00005", 4, :half_even) == d(1, 0, -4)
    assert Decimal.round(~d"0.000005", 5, :half_even) == d(1, 0, -5)
    assert Decimal.round(~d"0.0000005", 6, :half_even) == d(1, 0, -6)
    assert Decimal.round(~d"-0.5", 0, :half_even) == d(-1, 0, 0)
    assert Decimal.round(~d"-0.05", 1, :half_even) == d(-1, 0, -1)
    assert Decimal.round(~d"-0.005", 2, :half_even) == d(-1, 0, -2)
    assert Decimal.round(~d"-0.0005", 3, :half_even) == d(-1, 0, -3)
    assert Decimal.round(~d"-0.00005", 4, :half_even) == d(-1, 0, -4)
    assert Decimal.round(~d"-0.000005", 5, :half_even) == d(-1, 0, -5)
    assert Decimal.round(~d"-0.0000005", 6, :half_even) == d(-1, 0, -6)
    assert Decimal.round(~d"0.51", 0, :half_even) == d(1, 1, 0)
    assert Decimal.round(~d"0.55", 1, :half_even) == d(1, 6, -1)
    assert Decimal.round(~d"0.6", 0, :half_even) == d(1, 1, 0)
    assert Decimal.round(~d"0.4", 0, :half_even) == d(1, 0, 0)
  end

  test "issue #60" do
    assert_raise(FunctionClauseError, "no function clause matching in Decimal.decimal/1", fn ->
      Decimal.round(nil)
    end)
  end

  test "issue #63" do
    round = &Decimal.round(&1, 2, :half_down)
    roundneg = &Decimal.round(&1, -2, :half_down)
    assert round.(~d"1.026") == d(1, 103, -2)
    assert round.(~d"1.0259") == d(1, 103, -2)
    assert round.(~d"-1.026") == d(-1, 103, -2)
    assert round.(~d"-1.0259") == d(-1, 103, -2)
    assert roundneg.(~d"155") == d(1, 2, 2)
    assert roundneg.(~d"160") == d(1, 2, 2)
    assert roundneg.(~d"-155") == d(-1, 2, 2)
    assert roundneg.(~d"-160") == d(-1, 2, 2)
  end

  test "issue #82" do
    to_float = fn binary -> Decimal.new(binary) |> Decimal.to_float() end
    assert to_float.("0.8888888888888888888888") == 0.8888888888888888888888
    assert to_float.("0.9999999999999999") == 0.9999999999999999
    assert to_float.("0.99999999999999999") == 0.99999999999999999
  end
end
