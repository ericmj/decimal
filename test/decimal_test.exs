defmodule DecimalTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import TestMacros
  alias Decimal.Context
  alias Decimal.Error

  require Decimal

  @bounded_smoke_max_us 5_000_000
  @bounded_smoke_timeout 15_000

  elixir_json_available? = Version.match?(System.version(), ">= 1.18.0-rc")

  if elixir_json_available? do
    doctest Decimal
  else
    doctest Decimal, except: [:moduledoc]
  end

  test "parse/1" do
    assert Decimal.parse("123") == {d(1, 123, 0), ""}
    assert Decimal.parse("+123") == {d(1, 123, 0), ""}
    assert Decimal.parse("-123") == {d(-1, 123, 0), ""}
    assert Decimal.parse("-123x") == {d(-1, 123, 0), "x"}
    assert Decimal.parse("-123X") == {d(-1, 123, 0), "X"}

    assert Decimal.parse("123.0") == {d(1, 1230, -1), ""}
    assert Decimal.parse("+123.0") == {d(1, 1230, -1), ""}
    assert Decimal.parse("-123.0") == {d(-1, 1230, -1), ""}
    assert Decimal.parse("-123.0x") == {d(-1, 1230, -1), "x"}

    assert Decimal.parse("1.5") == {d(1, 15, -1), ""}
    assert Decimal.parse("+1.5") == {d(1, 15, -1), ""}
    assert Decimal.parse("-1.5") == {d(-1, 15, -1), ""}
    assert Decimal.parse("-1.5x") == {d(-1, 15, -1), "x"}

    assert Decimal.parse("0") == {d(1, 0, 0), ""}
    assert Decimal.parse("+0") == {d(1, 0, 0), ""}
    assert Decimal.parse("-0") == {d(-1, 0, 0), ""}

    assert Decimal.parse("0.") == {d(1, 0, 0), ""}
    assert Decimal.parse("0.x") == {d(1, 0, 0), "x"}
    assert Decimal.parse(".0") == {d(1, 0, -1), ""}
    assert Decimal.parse(".0x") == {d(1, 0, -1), "x"}

    assert Decimal.parse("0.0") == {d(1, 0, -1), ""}
    assert Decimal.parse("-0.0") == {d(-1, 0, -1), ""}
    assert Decimal.parse("+0.0") == {d(1, 0, -1), ""}

    assert Decimal.parse("0.0.0") == {d(1, 0, -1), ".0"}
    assert Decimal.parse("-0.0.0") == {d(-1, 0, -1), ".0"}
    assert Decimal.parse("+0.0.0") == {d(1, 0, -1), ".0"}

    assert Decimal.parse("1230e13") == {d(1, 1230, 13), ""}
    assert Decimal.parse("+1230e+2") == {d(1, 1230, 2), ""}
    assert Decimal.parse("-1230e-2") == {d(-1, 1230, -2), ""}
    assert Decimal.parse("-1230e-2x") == {d(-1, 1230, -2), "x"}

    assert Decimal.parse("1230.00e13") == {d(1, 123_000, 11), ""}
    assert Decimal.parse("+1230.1230e+5") == {d(1, 12_301_230, 1), ""}
    assert Decimal.parse("-1230.01010e-5") == {d(-1, 123_001_010, -10), ""}
    assert Decimal.parse("-1230.01010e-5x") == {d(-1, 123_001_010, -10), "x"}

    assert Decimal.parse("0e0") == {d(1, 0, 0), ""}
    assert Decimal.parse("+0e-0") == {d(1, 0, 0), ""}
    assert Decimal.parse("-0e+0") == {d(-1, 0, 0), ""}
    assert Decimal.parse("-0e+0x") == {d(-1, 0, 0), "x"}

    assert Decimal.parse("inf") == {d(1, :inf, 0), ""}
    assert Decimal.parse("infinity") == {d(1, :inf, 0), ""}
    assert Decimal.parse("INFinity") == {d(1, :inf, 0), ""}
    assert Decimal.parse("INFINITY") == {d(1, :inf, 0), ""}

    assert Decimal.parse("nan") == {d(1, :NaN, 0), ""}
    assert Decimal.parse("-NaN") == {d(-1, :NaN, 0), ""}
    assert Decimal.parse("nAn") == {d(1, :NaN, 0), ""}

    assert Decimal.parse("42.+42") == {d(1, 42, 0), "+42"}

    assert Decimal.parse("") == :error
    assert Decimal.parse("a") == :error
    assert Decimal.parse("test") == :error
    assert Decimal.parse("e0") == :error

    assert Decimal.parse("1e-d") == {d(1, 1, 0), "e-d"}
  end

  test "parse/2 with limits" do
    assert Decimal.parse("123", max_digits: 3) == {d(1, 123, 0), ""}
    assert Decimal.parse("123", max_digits: 2) == :error

    assert Decimal.parse("0.123", max_digits: 3) == {d(1, 123, -3), ""}
    assert Decimal.parse("00123", max_digits: 3) == {d(1, 123, 0), ""}
    assert Decimal.parse("0.00123", max_digits: 3) == {d(1, 123, -5), ""}
    assert Decimal.parse("123.000", max_digits: 6) == {d(1, 123_000, -3), ""}
    assert Decimal.parse("123.000", max_digits: 5) == :error

    assert Decimal.parse("1e10", max_exponent: 10) == {d(1, 1, 10), ""}
    assert Decimal.parse("1e10", max_exponent: 9) == :error

    assert Decimal.parse("1.23e2", max_exponent: 0) == {d(1, 123, 0), ""}
    assert Decimal.parse("1.23e3", max_exponent: 0) == :error
    assert Decimal.parse("1e-10", max_exponent: 9) == :error
    assert Decimal.parse("1e1000000000000000000000000", max_exponent: 9) == :error

    assert_raise ArgumentError, ~r/:max_digits/, fn ->
      Decimal.parse("1", max_digits: -1)
    end

    assert_raise ArgumentError, ~r/unknown option :unknown/, fn ->
      Decimal.parse("1", unknown: 1)
    end
  end

  @tag timeout: @bounded_smoke_timeout
  test "parse/2 rejects very large exponents without materializing them" do
    input = "1e" <> String.duplicate("9", 1_000_000)

    assert_runs_quickly("parse/2 bounded exponent rejection", fn ->
      assert Decimal.parse(input, max_exponent: 9) == :error
    end)
  end

  @tag timeout: @bounded_smoke_timeout
  test "parse/2 rejects very long digit runs without materializing them" do
    input = String.duplicate("9", 1_000_000)

    assert_runs_quickly("parse/2 bounded digit rejection", fn ->
      assert Decimal.parse(input, max_digits: 34) == :error
    end)
  end

  test "parse/2 with very long digit strings under explicit limits" do
    digits = String.duplicate("9", 50_000)
    coef = :erlang.binary_to_integer(digits)
    opts = [max_digits: :infinity, max_exponent: :infinity]

    assert Decimal.parse(digits, opts) == {%Decimal{coef: coef, exp: 0}, ""}

    assert Decimal.parse("0." <> digits, opts) == {%Decimal{coef: coef, exp: -50_000}, ""}

    int = String.duplicate("1", 30_000)
    frac = String.duplicate("5", 20_000)
    expected_coef = :erlang.binary_to_integer(int <> frac)

    assert Decimal.parse(int <> "." <> frac, opts) ==
             {%Decimal{coef: expected_coef, exp: -20_000}, ""}

    assert Decimal.parse(digits <> "x", opts) == {%Decimal{coef: coef, exp: 0}, "x"}
  end

  test "parse/2 enforces digit count on very long strings" do
    digits = String.duplicate("9", 50_000)

    assert Decimal.parse(digits, max_digits: 50_000, max_exponent: :infinity) ==
             {%Decimal{coef: :erlang.binary_to_integer(digits), exp: 0}, ""}

    assert Decimal.parse(digits, max_digits: 49_999, max_exponent: :infinity) == :error

    fractional = "0." <> digits

    assert Decimal.parse(fractional, max_digits: 50_000, max_exponent: :infinity) ==
             {%Decimal{coef: :erlang.binary_to_integer(digits), exp: -50_000}, ""}

    assert Decimal.parse(fractional, max_digits: 49_999, max_exponent: :infinity) == :error
  end

  test "parse/1 round-trips inspect output at default precision" do
    decimal = %Decimal{coef: 3_162_277_660_168_379_331_998_893_544_432_719, exp: -34}
    string = Decimal.to_string(decimal, :scientific, max_digits: :infinity)

    assert string == "0.3162277660168379331998893544432719"
    assert Decimal.parse(string) == {decimal, ""}
    assert Decimal.new(string) == decimal
  end

  test "nan?/1" do
    assert Decimal.nan?(~d"nan")
    refute Decimal.nan?(~d"0")
  end

  test "inf?/1" do
    assert Decimal.inf?(~d"inf")
    refute Decimal.inf?(~d"0")
  end

  test "is_decimal/1 expression" do
    assert Decimal.is_decimal(~d"nan")
    assert Decimal.is_decimal(~d"inf")
    assert Decimal.is_decimal(~d"0")
    refute Decimal.is_decimal(42)
    refute Decimal.is_decimal("42")
    refute Decimal.is_decimal(1..2)
  end

  if function_exported?(:erlang, :is_map_key, 2) do
    defp decimal?(struct) when Decimal.is_decimal(struct), do: true
    defp decimal?(_other), do: false

    test "is_decimal/1 guard" do
      assert decimal?(~d"nan")
      assert decimal?(~d"inf")
      assert decimal?(~d"0")
      refute decimal?(42)
      refute decimal?("42")
      refute decimal?(1..2)
    end
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

    assert Decimal.new("123.45") == d(1, 12345, -2)

    assert_raise Error, fn ->
      Decimal.new("")
    end

    assert_raise Error, fn ->
      Decimal.new("123x")
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

  test "new/2 with opts" do
    long = "1.01234567890123457890123457890123456789"

    assert Decimal.new(long, max_digits: 39) ==
             d(1, 101_234_567_890_123_457_890_123_457_890_123_456_789, -38)

    assert_raise Error, fn ->
      Decimal.new(long, max_digits: 38)
    end

    assert Decimal.new("1e10", max_exponent: 10) == d(1, 1, 10)

    assert_raise Error, fn ->
      Decimal.new("1e10", max_exponent: 9)
    end

    assert_raise ArgumentError, ~r/unknown option :unknown/, fn ->
      Decimal.new("1", unknown: 1)
    end
  end

  test "from_float/1" do
    assert Decimal.from_float(123.0) == d(1, 1230, -1)
    assert Decimal.from_float(0.1) == d(1, 1, -1)
    assert Decimal.from_float(0.000015) == d(1, 15, -6)
    assert Decimal.from_float(-1.5) == d(-1, 15, -1)
  end

  test "cast/1" do
    assert Decimal.cast(123) == {:ok, d(1, 123, 0)}
    assert Decimal.cast(123.0) == {:ok, d(1, 1230, -1)}
    assert Decimal.cast("123") == {:ok, d(1, 123, 0)}
    assert Decimal.cast(d(1, 123, 0)) == {:ok, d(1, 123, 0)}

    assert Decimal.cast("one two three") == :error
    assert Decimal.cast("e0") == :error
    assert Decimal.cast(:one_two_three) == :error
  end

  test "cast/2 with limits" do
    assert Decimal.cast(123, max_digits: 3) == {:ok, d(1, 123, 0)}
    assert Decimal.cast(123, max_digits: 2) == :error

    assert Decimal.cast("123", max_digits: 3) == {:ok, d(1, 123, 0)}
    assert Decimal.cast("123", max_digits: 2) == :error

    assert Decimal.cast(d(1, 1, 10), max_exponent: 10) == {:ok, d(1, 1, 10)}
    assert Decimal.cast(d(1, 1, 10), max_exponent: 9) == :error
    assert Decimal.cast(d(1, 123, 0), max_digits: 3) == {:ok, d(1, 123, 0)}
    assert Decimal.cast(d(1, 123, 0), max_digits: 2) == :error
    assert Decimal.cast("1e1000000000000000000000000", max_exponent: 9) == :error
  end

  test "abs/1" do
    assert Decimal.abs(~d"123") == d(1, 123, 0)
    assert Decimal.abs(~d"-123") == d(1, 123, 0)
    assert Decimal.abs(~d"-12.5e2") == d(1, 125, 1)
    assert Decimal.abs(~d"-42e-42") == d(1, 42, -42)
    assert Decimal.abs(~d"-inf") == d(1, :inf, 0)
    assert Decimal.abs(~d"nan") == d(1, :NaN, 0)
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
    assert Decimal.add(~d"5", ~d"nan") == d(1, :NaN, 0)
    assert Decimal.add(~d"inf", ~d"inf") == d(1, :inf, 0)
    assert Decimal.add(~d"-inf", ~d"-inf") == d(-1, :inf, 0)

    assert Decimal.add(d(1, :inf, 2), d(1, :inf, 5)) == d(1, :inf, 5)

    Context.with(%Context{precision: 5, rounding: :floor}, fn ->
      assert Decimal.add(~d"2", ~d"-2") == d(-1, 0, 0)
    end)

    assert Decimal.add(~d"inf", ~d"5") == d(1, :inf, 0)
    assert Decimal.add(~d"5", ~d"-inf") == d(-1, :inf, 0)

    assert_raise Error, fn ->
      Decimal.add(~d"inf", ~d"-inf")
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
    assert Decimal.add(~d"5", ~d"nan") == d(1, :NaN, 0)

    Context.with(%Context{precision: 5, rounding: :floor}, fn ->
      assert Decimal.sub(~d"2", ~d"2") == d(-1, 0, 0)
    end)

    assert Decimal.sub(~d"inf", ~d"5") == d(1, :inf, 0)
    assert Decimal.sub(~d"5", ~d"-inf") == d(1, :inf, 0)

    assert_raise Error, fn ->
      Decimal.sub(~d"inf", ~d"inf")
    end
  end

  test "compare/2" do
    assert Decimal.compare(~d"420", ~d"42e1") == :eq
    assert Decimal.compare(~d"1", ~d"0") == :gt
    assert Decimal.compare(~d"0", ~d"1") == :lt
    assert Decimal.compare(~d"0", ~d"-0") == :eq

    assert Decimal.compare(~d"-inf", ~d"inf") == :lt
    assert Decimal.compare(~d"inf", ~d"-inf") == :gt
    assert Decimal.compare(~d"inf", ~d"0") == :gt
    assert Decimal.compare(~d"-inf", ~d"0") == :lt
    assert Decimal.compare(~d"0", ~d"inf") == :lt
    assert Decimal.compare(~d"0", ~d"-inf") == :gt

    assert Decimal.compare(~d"0.123", ~d"0") == :gt
    assert Decimal.compare(~d"0.123", ~d"0.122") == :gt
    assert Decimal.compare(~d"0.123", ~d"0.123") == :eq
    assert Decimal.compare(~d"0.123", ~d"0.124") == :lt
    assert Decimal.compare(~d"0.0123", ~d"0.124") == :lt

    assert Decimal.compare("Inf", "Inf") == :eq

    assert Decimal.compare(Decimal.new(1, 5, 10_000_000_000), ~d"0") == :gt

    assert_raise Error, fn ->
      Decimal.compare(~d"nan", ~d"0")
    end

    assert_raise Error, fn ->
      Decimal.compare(~d"0", ~d"nan")
    end
  end

  test "compare/3" do
    assert Decimal.compare(~d"420.5", ~d"42e1", "0.5") == :eq
    assert Decimal.compare(~d"420.5", ~d"42e1", "0.2") == :gt

    assert_raise Error, fn ->
      Decimal.compare(~d"420.5", ~d"42e1", "-0.2")
    end

    assert Decimal.compare(~d"1", ~d"0", "0") == :gt

    assert Decimal.compare(~d"-inf", ~d"inf", "100") == :lt
    assert Decimal.compare(~d"inf", ~d"-inf", "0") == :gt
    assert Decimal.compare(~d"0", ~d"inf", "1000000") == :lt

    assert Decimal.compare(~d"0.123", ~d"0", "0") == :gt
    assert Decimal.compare(~d"0.123", ~d"0", "0.2") == :eq
  end

  test "equal?/2" do
    assert Decimal.equal?(~d"420", ~d"42e1")
    refute Decimal.equal?(~d"1", ~d"0")
    refute Decimal.equal?(~d"0", ~d"1")
    assert Decimal.equal?(~d"0", ~d"-0")
    refute Decimal.equal?(~d"nan", ~d"1")
    refute Decimal.equal?(~d"1", ~d"nan")
  end

  test "eq/2?" do
    assert Decimal.eq?(~d"420", ~d"42e1")
    refute Decimal.eq?(~d"1", ~d"0")
    refute Decimal.eq?(~d"0", ~d"1")
    assert Decimal.eq?(~d"0", ~d"-0")
    refute Decimal.eq?(~d"nan", ~d"1")
    refute Decimal.eq?(~d"1", ~d"nan")
  end

  test "eq/3?" do
    assert Decimal.eq?(~d"420", ~d"42e1", ~d"0")
    assert Decimal.eq?(~d"1", ~d"0", ~d"1")
    refute Decimal.eq?(~d"1", ~d"0", ~d"0")

    assert_raise Error, fn ->
      Decimal.eq?(~d"nan", ~d"1", ~d"1")
    end
  end

  test "gt?/2" do
    refute Decimal.gt?(~d"420", ~d"42e1")
    assert Decimal.gt?(~d"1", ~d"0")
    refute Decimal.gt?(~d"0", ~d"1")
    refute Decimal.gt?(~d"0", ~d"-0")
    refute Decimal.gt?(~d"nan", ~d"1")
    refute Decimal.gt?(~d"1", ~d"nan")
  end

  test "lt?/2" do
    refute Decimal.lt?(~d"420", ~d"42e1")
    refute Decimal.lt?(~d"1", ~d"0")
    assert Decimal.lt?(~d"0", ~d"1")
    refute Decimal.lt?(~d"0", ~d"-0")
    refute Decimal.lt?(~d"nan", ~d"1")
    refute Decimal.lt?(~d"1", ~d"nan")
  end

  test "gte?/2" do
    assert Decimal.gte?(~d"420", ~d"42e1")
    assert Decimal.gte?(~d"1", ~d"0")
    refute Decimal.gte?(~d"0", ~d"1")
    assert Decimal.gte?(~d"0", ~d"-0")
    refute Decimal.gte?(~d"nan", ~d"1")
    refute Decimal.gte?(~d"1", ~d"nan")
  end

  test "lte?/2" do
    assert Decimal.lte?(~d"420", ~d"42e1")
    refute Decimal.lte?(~d"1", ~d"0")
    assert Decimal.lte?(~d"0", ~d"1")
    assert Decimal.lte?(~d"0", ~d"-0")
    refute Decimal.lte?(~d"nan", ~d"1")
    refute Decimal.lte?(~d"1", ~d"nan")
  end

  test "div/2" do
    Context.with(%Context{precision: 5, rounding: :half_up}, fn ->
      assert Decimal.div(~d"1", ~d"3") == d(1, 33333, -5)
      assert Decimal.div(~d"42", ~d"2") == d(1, 21, 0)
      assert Decimal.div(~d"123", ~d"12345") == d(1, 99635, -7)
      assert Decimal.div(~d"123", ~d"123") == d(1, 1, 0)
      assert Decimal.div(~d"-1", ~d"5") == d(-1, 2, -1)
      assert Decimal.div(~d"-1", ~d"-1") == d(1, 1, 0)
      assert Decimal.div(~d"2", ~d"-5") == d(-1, 4, -1)
    end)

    Context.with(%Context{precision: 2, rounding: :half_up}, fn ->
      assert Decimal.div(~d"31", ~d"2") == d(1, 16, 0)
    end)

    Context.with(%Context{precision: 2, rounding: :floor}, fn ->
      assert Decimal.div(~d"31", ~d"2") == d(1, 15, 0)
    end)

    assert Decimal.div(~d"0", ~d"3") == d(1, 0, 0)
    assert Decimal.div(~d"-0", ~d"3") == d(-1, 0, 0)
    assert Decimal.div(~d"0", ~d"-3") == d(-1, 0, 0)
    assert Decimal.div(~d"nan", ~d"2") == d(1, :NaN, 0)

    assert Decimal.div(~d"-inf", ~d"-2") == d(1, :inf, 0)
    assert Decimal.div(~d"5", ~d"-inf") == d(-1, 0, 0)

    assert_raise Error, fn ->
      Decimal.div(~d"inf", ~d"inf")
    end

    assert_raise Error, "invalid_operation: 0 / 0", fn ->
      Decimal.div(~d"0", ~d"-0")
    end

    assert_raise Error, "division_by_zero", fn ->
      Decimal.div(~d"1", ~d"0")
    end
  end

  test "div/2 carries the remainder as a sticky bit when rounding" do
    # The digit past the kept digits being 5 with a nonzero tail is not an
    # exact tie and must round up; a guard digit of 0 with a nonzero tail is
    # still nonzero for the directional modes. Expected values verified
    # against the exact integer quotient and Python's decimal.

    Context.with(%Context{precision: 28, rounding: :half_even}, fn ->
      # 4.7460 / -5522 -> …1405287…: guard digit 5, nonzero tail -> rounds up
      assert Decimal.div(~d"4.7460", ~d"-5522") ==
               d(-1, 8_594_712_060_847_519_014_849_692_141, -31)
    end)

    # genuine ties still round to even
    Context.with(%Context{precision: 1, rounding: :half_even}, fn ->
      assert Decimal.div(~d"5", ~d"2") == d(1, 2, 0)
      assert Decimal.div(~d"7", ~d"2") == d(1, 4, 0)
    end)

    # :ceiling / :floor must honor the remainder (their defining guarantee):
    # 1.0000001 / 1 at precision 5 has a zero guard digit but a nonzero tail
    Context.with(%Context{precision: 5, rounding: :ceiling}, fn ->
      assert Decimal.div(~d"1.0000001", ~d"1") == d(1, 10_001, -4)
    end)

    Context.with(%Context{precision: 5, rounding: :floor}, fn ->
      assert Decimal.div(~d"-1.0000001", ~d"1") == d(-1, 10_001, -4)
    end)
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
    assert Decimal.div_int(~d"nan", ~d"2") == d(1, :NaN, 0)

    assert Decimal.div_int(~d"-inf", ~d"-2") == d(1, :inf, 0)
    assert Decimal.div_int(~d"5", ~d"-inf") == d(-1, 0, 0)

    assert_raise Error, fn ->
      Decimal.div_int(~d"inf", ~d"inf")
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
    assert Decimal.rem(~d"nan", ~d"2") == d(1, :NaN, 0)

    assert_raise Error, fn ->
      Decimal.rem(~d"inf", ~d"inf")
    end

    assert_raise Error, fn ->
      Decimal.rem(~d"0", ~d"-0")
    end
  end

  test "rem/2 and div_rem/2 compute the remainder exactly" do
    # 34-digit operands whose divisor * quotient spans 67 digits: rounding
    # that intermediate product to the context precision yields exactly the
    # dividend, cancelling the true remainder of 3E-33 down to 0.
    x = ~d"9999999999999999999999999999999999"
    y = ~d"2.000000000000000000000000000000001"

    assert Decimal.rem(x, y) == d(1, 3, -33)
    assert Decimal.rem(~d"-9999999999999999999999999999999999", y) == d(-1, 3, -33)

    {q, r} = Decimal.div_rem(x, y)
    assert q == d(1, 4_999_999_999_999_999_999_999_999_999_999_997, 0)
    assert r == d(1, 3, -33)

    # the remainder is exact, so nothing may signal from the internals
    flags = Context.get().flags
    refute :inexact in flags
    refute :rounded in flags

    # a zero remainder takes the sign of the dividend, like any nonzero
    # remainder does (and as IEEE 754 and Python's decimal define it)
    assert Decimal.rem(~d"-4", ~d"2") == d(-1, 0, 0)

    Context.with(%Context{precision: 5}, fn ->
      assert Decimal.rem(~d"99999", ~d"2.0001") == d(1, 3, -4)
    end)
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
  end

  test "negate/1" do
    assert Decimal.negate(~d"0") == d(-1, 0, 0)
    assert Decimal.negate(~d"1") == d(-1, 1, 0)
    assert Decimal.negate(~d"-1") == d(1, 1, 0)

    assert Decimal.negate(~d"inf") == d(-1, :inf, 0)
    assert Decimal.negate(~d"nan") == d(1, :NaN, 0)
  end

  test "apply_context/1" do
    Context.with(%Context{precision: 2}, fn ->
      assert Decimal.apply_context(~d"0") == d(1, 0, 0)
      assert Decimal.apply_context(~d"5") == d(1, 5, 0)
      assert Decimal.apply_context(~d"123") == d(1, 12, 1)
      assert Decimal.apply_context(~d"nan") == d(1, :NaN, 0)
    end)
  end

  test "positive?/1" do
    Context.with(%Context{precision: 2}, fn ->
      refute Decimal.positive?(~d"0")
      assert Decimal.positive?(~d"5")
      refute Decimal.positive?(~d"-5")
      assert Decimal.positive?(~d"123.0")
      refute Decimal.positive?(~d"nan")
    end)
  end

  test "negative?1" do
    Context.with(%Context{precision: 2}, fn ->
      refute Decimal.negative?(~d"0")
      assert Decimal.negative?(~d"-5")
      refute Decimal.negative?(~d"5")
      assert Decimal.negative?(~d"-123.0")
      refute Decimal.negative?(~d"nan")
    end)
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
    assert Decimal.mult(~d"nan", ~d"2") == d(1, :NaN, 0)

    assert_raise Error, fn ->
      Decimal.mult(~d"inf", ~d"0")
    end

    assert_raise Error, fn ->
      Decimal.mult(~d"0", ~d"-inf")
    end
  end

  test "normalize/1" do
    assert Decimal.normalize(~d"2.1") == d(1, 21, -1)
    assert Decimal.normalize(~d"2.10") == d(1, 21, -1)
    assert Decimal.normalize(~d"-2") == d(-1, 2, 0)
    assert Decimal.normalize(~d"-2.00") == d(-1, 2, 0)
    assert Decimal.normalize(~d"200") == d(1, 2, 2)
    assert Decimal.normalize(~d"0") == d(1, 0, 0)
    assert Decimal.normalize(~d"-0") == d(-1, 0, 0)
    assert Decimal.normalize(~d"-inf") == d(-1, :inf, 0)
    assert Decimal.normalize(~d"nan") == d(1, :NaN, 0)
  end

  test "normalize/1 with zero coefficient and non-zero exponent" do
    assert Decimal.normalize(%Decimal{sign: 1, coef: 0, exp: -5}) == d(1, 0, 0)
    assert Decimal.normalize(%Decimal{sign: -1, coef: 0, exp: -5_000}) == d(-1, 0, 0)
    assert Decimal.normalize(%Decimal{sign: 1, coef: 0, exp: 5}) == d(1, 0, 0)
  end

  test "normalize/1 strips many trailing zeros without expansion" do
    coef = :erlang.binary_to_integer("123" <> String.duplicate("0", 5_000))
    assert Decimal.normalize(%Decimal{sign: 1, coef: coef, exp: 0}) == d(1, 123, 5_000)
    assert Decimal.normalize(%Decimal{sign: 1, coef: coef, exp: -2_500}) == d(1, 123, 2_500)

    # Boundary around the 16-digit chunk size.
    coef_17 = :erlang.binary_to_integer("123" <> String.duplicate("0", 17))
    assert Decimal.normalize(%Decimal{sign: 1, coef: coef_17, exp: 0}) == d(1, 123, 17)

    coef_15 = :erlang.binary_to_integer("123" <> String.duplicate("0", 15))
    assert Decimal.normalize(%Decimal{sign: 1, coef: coef_15, exp: 0}) == d(1, 123, 15)

    coef_16 = :erlang.binary_to_integer("123" <> String.duplicate("0", 16))
    assert Decimal.normalize(%Decimal{sign: 1, coef: coef_16, exp: 0}) == d(1, 123, 16)
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

  test "to_string/3 with large coefficients under explicit max_digits" do
    digits = String.duplicate("9", 2_500)
    coef = String.to_integer(digits)

    assert Decimal.to_string(%Decimal{sign: 1, coef: coef, exp: 0}, :normal, max_digits: 2_500) ==
             digits

    assert Decimal.to_string(
             %Decimal{sign: -1, coef: coef, exp: -2_500},
             :normal,
             max_digits: 2_501
           ) == "-0." <> digits

    assert Decimal.to_string(
             %Decimal{sign: 1, coef: coef, exp: -2_499},
             :scientific,
             max_digits: 2_500
           ) == "9." <> String.duplicate("9", 2_499)

    assert Decimal.to_string(
             %Decimal{sign: 1, coef: coef, exp: -1},
             :raw,
             max_digits: 2_501
           ) == digits <> "E-1"
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

  test "to_string/3 with limits" do
    assert Decimal.to_string(~d"123", :scientific, max_digits: 3) == "123"
    assert Decimal.to_string(~d"1e2", :normal, max_digits: 3) == "100"
    assert Decimal.to_string(~d"1e2", :xsd, max_digits: 4) == "100.0"

    assert Decimal.to_string(Decimal.new(1, 1, 100_000), :scientific, max_digits: 7) ==
             "1E+100000"

    assert_raise ArgumentError, ~r/:scientific representation requires 3 digits/, fn ->
      Decimal.to_string(~d"123", :scientific, max_digits: 2)
    end

    assert_raise ArgumentError, ~r/:normal representation requires 3 digits/, fn ->
      Decimal.to_string(~d"1e2", :normal, max_digits: 2)
    end

    assert_raise ArgumentError, ~r/:xsd representation requires 4 digits/, fn ->
      Decimal.to_string(~d"1e2", :xsd, max_digits: 3)
    end

    assert_raise ArgumentError, ~r/:normal representation requires 100001 digits/, fn ->
      Decimal.to_string(Decimal.new(1, 1, 100_000), :normal, max_digits: 1_000)
    end

    assert_raise ArgumentError, ~r/:xsd representation requires 100002 digits/, fn ->
      Decimal.to_string(Decimal.new(1, 1, 100_000), :xsd, max_digits: 1_000)
    end
  end

  @tag timeout: @bounded_smoke_timeout
  test "to_string/3 rejects huge expanded output before materializing it" do
    num = %Decimal{sign: 1, coef: 1, exp: 10_000_000}

    assert_runs_quickly("to_string/3 bounded normal output rejection", fn ->
      assert_raise ArgumentError, ~r/:normal representation requires 10000001 digits/, fn ->
        Decimal.to_string(num, :normal, max_digits: 1_000)
      end
    end)

    assert_runs_quickly("to_string/3 bounded xsd output rejection", fn ->
      assert_raise ArgumentError, ~r/:xsd representation requires 10000002 digits/, fn ->
        Decimal.to_string(num, :xsd, max_digits: 1_000)
      end
    end)
  end

  test "to_integer/1" do
    Context.with(%Context{precision: 36, rounding: :floor}, fn ->
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

      assert_raise(
        ArgumentError,
        "cannot convert Decimal.new(\"10.01\") without losing precision. Use Decimal.round/3 first.",
        fn -> Decimal.to_integer(d(1, 1001, -2)) end
      )

      assert_raise FunctionClauseError, fn ->
        Decimal.to_integer(d(1, :NaN, 0))
      end
    end)
  end

  test "to_integer/1 with zero coefficient and negative exponent" do
    assert Decimal.to_integer(~d"0.0") == 0
    assert Decimal.to_integer(~d"0.000") == 0
    assert Decimal.to_integer(~d"-0.0") == 0
    assert Decimal.to_integer(%Decimal{sign: 1, coef: 0, exp: -5_000}) == 0
  end

  test "to_integer/1 with very large positive exponent" do
    assert Decimal.to_integer(%Decimal{sign: 1, coef: 7, exp: 5_000}) ==
             7 * :erlang.binary_to_integer("1" <> String.duplicate("0", 5_000))

    assert Decimal.to_integer(%Decimal{sign: -1, coef: 1, exp: 3}) == -1000
  end

  test "to_integer/1 with large negative exponent and trailing zeros" do
    coef = :erlang.binary_to_integer("1" <> String.duplicate("0", 5_000))
    assert Decimal.to_integer(%Decimal{sign: 1, coef: coef, exp: -5_000}) == 1
    assert Decimal.to_integer(%Decimal{sign: -1, coef: coef, exp: -4_999}) == -10
  end

  property "to_integer/1 round-trips any integer through trailing-zero-padded encodings" do
    check all(
            n <- integer(),
            k <- integer(0..500),
            max_runs: 100
          ) do
      sign = if n < 0, do: -1, else: 1
      coef = Kernel.abs(n) * Integer.pow(10, k)
      decimal = %Decimal{sign: sign, coef: coef, exp: -k}
      assert Decimal.to_integer(decimal) == n
    end
  end

  test "to_integer/1 raises with normalized inspect" do
    # Loss-of-precision error inspects the normalized form (1.1, not 1.10).
    decimal = %Decimal{sign: 1, coef: 110, exp: -2}

    assert_raise(
      ArgumentError,
      "cannot convert Decimal.new(\"1.1\") without losing precision. Use Decimal.round/3 first.",
      fn -> Decimal.to_integer(decimal) end
    )

    assert_raise(
      ArgumentError,
      ~r/^cannot convert Decimal\.new\("0\.1"\)/,
      fn -> Decimal.to_integer(%Decimal{sign: 1, coef: 100, exp: -3}) end
    )
  end

  test "to_float/1" do
    Context.with(%Context{precision: 36, rounding: :floor}, fn ->
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

      assert_raise ArgumentError, fn ->
        Decimal.to_float(d(1, :NaN, 0))
      end
    end)
  end

  test "to_float/1 odd integers with 53-bit significands are exact" do
    # 2^52 + 1, 2^53 - 1, and any odd integer between them are exactly
    # representable as doubles and must convert without rounding.
    assert Decimal.to_float(~d"4503599627370497") === 4_503_599_627_370_497.0
    assert Decimal.to_float(~d"-4503599627370497") === -4_503_599_627_370_497.0
    assert Decimal.to_float(~d"6004799503160661") === 6_004_799_503_160_661.0
    assert Decimal.to_float(~d"9007199254740991") === 9_007_199_254_740_991.0

    # Just above 2^53 the ULP is 2: odd values are genuine ties and must
    # keep rounding to the even significand.
    assert Decimal.to_float(~d"9007199254740993") === 9_007_199_254_740_992.0
    assert Decimal.to_float(~d"9007199254740995") === 9_007_199_254_740_996.0
  end

  test "round/3: special" do
    assert Decimal.round(~d"inf", 2, :down) == d(1, :inf, 0)
    assert Decimal.round(~d"nan", 2, :down) == d(1, :NaN, 0)
  end

  test "round/3: normalization overflow" do
    Context.with(%Context{emax: 2, traps: []}, fn ->
      for places <- [-1, 0, 1] do
        assert Decimal.round(Decimal.new(1, 1, 3), places) == d(1, :inf, 0)
      end
    end)
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
    Context.with(%Context{precision: 9, rounding: :half_even}, fn ->
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

  test "sqrt/1 inexact roots at default precision" do
    # 34-significant-digit references for well-known constants; sqrt(1e33)
    # exercises the odd-exponent scaling path.
    assert Decimal.sqrt(~d"2") == d(1, 1_414_213_562_373_095_048_801_688_724_209_698, -33)
    assert Decimal.sqrt(~d"3") == d(1, 1_732_050_807_568_877_293_527_446_341_505_872, -33)
    assert Decimal.sqrt(~d"1e33") == d(1, 3_162_277_660_168_379_331_998_893_544_432_719, -17)
  end

  test "sqrt/1 uses the power-of-ten seed above the float range" do
    # At precision 200 the scaled operand has ~400 digits, past the 10^300
    # float-seed limit, so this exercises the pow10 fallback seed. Exact
    # squares are a sharp probe: a seed below the true root would be
    # returned by sqrt_loop as-is and fail the equality. The square is
    # built with integer math because mult/2 would round it to precision.
    Context.with(%Context{precision: 200}, fn ->
      n = Integer.pow(10, 199) + 1
      assert Decimal.sqrt(Decimal.new(1, n * n, 0)) == d(1, n, 0)
      assert Decimal.sqrt(~d"4") == d(1, 2, 0)
    end)
  end

  test "sqrt/1 carries the discarded digits into rounding as a sticky bit" do
    # An inexact root lies strictly beyond its truncated coefficient, so
    # directed roundings must bump even when the guard digit is 0:
    # sqrt(10) = 3.16227766016... > 3.16227766.
    Context.with(%Context{precision: 9, rounding: :ceiling}, fn ->
      assert Decimal.sqrt(~d"10") == d(1, 316_227_767, -8)
      assert Decimal.sqrt(~d"2") == d(1, 141_421_357, -8)
    end)

    Context.with(%Context{precision: 9, rounding: :up}, fn ->
      assert Decimal.sqrt(~d"10") == d(1, 316_227_767, -8)
    end)

    # :floor truncates a positive result regardless of discarded digits.
    Context.with(%Context{precision: 9, rounding: :floor}, fn ->
      assert Decimal.sqrt(~d"10") == d(1, 316_227_766, -8)
    end)

    # A guard digit of 5 with nonzero digits beyond it is not a tie:
    # sqrt(1.57) = 1.25299... rounds up, not to the even neighbor.
    Context.with(%Context{precision: 2, rounding: :half_even}, fn ->
      assert Decimal.sqrt(~d"1.57") == d(1, 13, -1)
    end)

    # An inexact root signals :inexact, not just :rounded.
    Context.with(%Context{precision: 9, rounding: :half_even}, fn ->
      assert Decimal.sqrt(~d"10") == d(1, 316_227_766, -8)

      flags = Context.get().flags
      assert :inexact in flags
      assert :rounded in flags
    end)
  end

  test "integer?/1" do
    assert Decimal.integer?(~d"1.0000")
    assert Decimal.integer?(~d"1")
    assert Decimal.integer?(~d"-1")
    assert Decimal.integer?(%Decimal{coef: 100, exp: -2})
    assert Decimal.integer?(~d"1e100")
    assert Decimal.integer?(~d"1.23e5")
    assert Decimal.integer?(~d"10000e-3")
    assert Decimal.integer?(~d"0.0")
    assert Decimal.integer?(~d"1.0")

    refute Decimal.integer?(~d"0.1")
    refute Decimal.integer?(~d"0.10")
    refute Decimal.integer?(~d"0.1000")
    refute Decimal.integer?(~d"0.1234")
    refute Decimal.integer?(~d"-0.1234")
    refute Decimal.integer?(~d"1e-100")
    refute Decimal.integer?(~d"1.2345e3")
    refute Decimal.integer?(~d"12345e-3")
    refute Decimal.integer?(~d"123e-5")
    refute Decimal.integer?(~d"100e-5")
    refute Decimal.integer?(~d"inf")
    refute Decimal.integer?(~d"NaN")
  end

  test "integer?/1 with very large coefficients and exponents" do
    huge_coef = :erlang.binary_to_integer("1" <> String.duplicate("0", 50_000))
    assert Decimal.integer?(%Decimal{sign: 1, coef: huge_coef, exp: -50_000})
    assert Decimal.integer?(%Decimal{sign: 1, coef: huge_coef, exp: -49_999})
    refute Decimal.integer?(%Decimal{sign: 1, coef: huge_coef + 1, exp: -50_000})
    refute Decimal.integer?(%Decimal{sign: 1, coef: 123, exp: -50_000})
    assert Decimal.integer?(%Decimal{sign: 1, coef: 0, exp: -1_000_000})
    assert Decimal.integer?(%Decimal{sign: 1, coef: 1, exp: 1_000_000})
  end

  @tag timeout: @bounded_smoke_timeout
  test "compare/2 handles very large coefficients without quadratic walk" do
    a = %Decimal{sign: 1, coef: :erlang.binary_to_integer(String.duplicate("9", 30_000)), exp: 0}
    b = %Decimal{sign: 1, coef: :erlang.binary_to_integer(String.duplicate("8", 30_000)), exp: 0}

    assert_runs_quickly("compare large coefs", fn ->
      assert Decimal.compare(a, b) == :gt
      assert Decimal.compare(b, a) == :lt
      assert Decimal.compare(a, a) == :eq
    end)
  end

  @tag timeout: @bounded_smoke_timeout
  test "add/2 with huge exponent gap stays bounded" do
    high = %Decimal{sign: 1, coef: 1, exp: 1_000_000}
    low = %Decimal{sign: 1, coef: 1, exp: 0}

    assert_runs_quickly("add huge exponent gap", fn ->
      assert Decimal.add(high, low).coef != 0
      assert Decimal.sub(high, low).coef != 0
    end)
  end

  @tag timeout: @bounded_smoke_timeout
  test "add/2 with a very large coefficient at the same exponent stays bounded" do
    # Equal exponents skip the bounded path, so pin that this cannot amplify:
    # with nothing to align, the coefficient is whatever the caller already
    # built, and the result is rounded to the context precision.
    # kept under `emax` so the result is a number rather than an overflow
    digits = 5_000

    big = %Decimal{
      sign: 1,
      coef: :erlang.binary_to_integer(String.duplicate("9", digits)),
      exp: 0
    }

    small = %Decimal{sign: 1, coef: 1, exp: 0}

    assert_runs_quickly("add large coef at equal exp", fn ->
      # 5_000 nines plus one is 10^5_000, which has 5_001 digits and rounds to
      # the 34 the default context allows
      assert Decimal.add(big, small) == d(1, Integer.pow(10, 33), digits + 1 - 34)
    end)
  end

  @tag timeout: @bounded_smoke_timeout
  test "add/2 with very large coefficient and small addend" do
    big = %Decimal{
      sign: 1,
      coef: :erlang.binary_to_integer(String.duplicate("9", 20_000)),
      exp: 0
    }

    small = %Decimal{sign: 1, coef: 1, exp: -20}

    assert_runs_quickly("add large coef + small", fn ->
      result = Decimal.add(big, small)
      assert result.sign == 1
    end)
  end

  property "add/2 bounded path matches unbounded result for varied sign/exp pairs" do
    check all(
            sign1 <- one_of([constant(1), constant(-1)]),
            sign2 <- one_of([constant(1), constant(-1)]),
            coef1 <- positive_integer(),
            coef2 <- positive_integer(),
            exp1 <- integer(-50..50),
            gap <- integer(10..80),
            precision <- integer(2..7),
            max_runs: 200
          ) do
      a = %Decimal{sign: sign1, coef: coef1, exp: exp1}
      b = %Decimal{sign: sign2, coef: coef2, exp: exp1 + gap}

      bounded =
        Context.with(%Context{precision: precision, traps: []}, fn ->
          Decimal.add(a, b)
        end)

      reference_precision = precision + gap + 10

      reference =
        Context.with(%Context{precision: reference_precision, traps: []}, fn ->
          Decimal.add(a, b)
        end)

      rounded_reference =
        Context.with(%Context{precision: precision, traps: []}, fn ->
          Decimal.mult(reference, ~d"1")
        end)

      assert bounded == rounded_reference, """
      bounded path diverged from unbounded reference
        a:           #{inspect(a)}
        b:           #{inspect(b)}
        precision:   #{precision}
        bounded:     #{inspect(bounded)}
        reference:   #{inspect(rounded_reference)}
      """
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

  test "issue wrong coef or sign value" do
    assert_raise FunctionClauseError, fn ->
      Decimal.new(%Decimal{coef: -1})
    end

    assert_raise FunctionClauseError, fn ->
      Decimal.new(%Decimal{sign: -3})
    end
  end

  test "test sqrt with wrong sign via new/1" do
    assert_raise FunctionClauseError, fn ->
      Decimal.sqrt(Decimal.new(d(3, 1, -1)))
    end
  end

  test "test max_min_dbl in to_float" do
    assert Decimal.to_float(dbl_max(1)) == 1.7976931348623158e308
    assert Decimal.to_float(dbl_max(-1)) == -1.7976931348623158e308

    assert_raise Decimal.Error,
                 ": number bigger than DBL_MAX: Decimal.new(\"1.79769313486231581E+308\")",
                 fn -> Decimal.to_float(Decimal.new("1.79769313486231581e308")) end

    assert_raise Decimal.Error,
                 ": negative number smaller than DBL_MAX: Decimal.new(\"-1.79769313486231581E+308\")",
                 fn -> Decimal.to_float(Decimal.new("-1.79769313486231581e308")) end

    assert Decimal.to_float(dbl_max(1)) == 1.79769313486231579e308

    assert Decimal.to_float(dbl_max(-1)) ==
             -1.79769313486231579e+308

    assert Decimal.to_float(dbl_min(1)) == 2.2250738585072014e-308
    assert Decimal.to_float(dbl_min(-1)) == -2.2250738585072014e-308

    assert_raise Decimal.Error,
                 ": number smaller than DBL_MIN: Decimal.new(\"2.22507385850720139E-308\")",
                 fn -> Decimal.to_float(Decimal.new("2.22507385850720139e-308")) end

    assert_raise Decimal.Error,
                 ": negative number bigger than DBL_MIN: Decimal.new(\"-2.22507385850720139E-308\")",
                 fn -> Decimal.to_float(Decimal.new("-2.22507385850720139e-308")) end

    assert Decimal.to_float(Decimal.new("2.22507385850720141e-308")) == 2.22507385850720141e-308

    assert Decimal.to_float(Decimal.new("-2.22507385850720141e-308")) ==
             -2.22507385850720141e-308

    assert_raise Decimal.Error,
                 ": number bigger than DBL_MAX: Decimal.new(\"9.999999999999999999E+1000000000000000000000017\")",
                 fn ->
                   Decimal.to_float(
                     Decimal.new(1, 9_999_999_999_999_999_999, 999_999_999_999_999_999_999_999)
                   )
                 end

    assert_raise Decimal.Error,
                 ": number smaller than DBL_MIN: Decimal.new(\"9.9999999999999E-999999999999999999999986\")",
                 fn ->
                   Decimal.to_float(
                     Decimal.new(1, 99_999_999_999_999, -999_999_999_999_999_999_999_999)
                   )
                 end
  end

  if elixir_json_available? do
    test "JSON.Encoder implementation" do
      assert JSON.encode!(%{x: Decimal.new("1.0")}) == "{\"x\":\"1.0\"}"

      encoder = fn
        %Decimal{} = decimal, _encode ->
          if Decimal.inf?(decimal) or Decimal.nan?(decimal) do
            raise ArgumentError, "#{inspect(decimal)} cannot be encoded to JSON"
          end

          Decimal.to_string(decimal)

        other, encode ->
          JSON.protocol_encode(other, encode)
      end

      assert JSON.encode!(%{x: Decimal.new("1.0")}, encoder) == "{\"x\":1.0}"
    end
  end

  test "div/2 exact quotients keep the preferred exponent" do
    assert Decimal.div(~d"100", ~d"1") == d(1, 100, 0)
    assert Decimal.div(~d"20", ~d"1") == d(1, 20, 0)
    assert Decimal.div(~d"1e2", ~d"1") == d(1, 1, 2)
    assert Decimal.div(~d"2.50", ~d"2") == d(1, 125, -2)
    assert Decimal.div(~d"1", ~d"2") == d(1, 5, -1)
    assert Decimal.div(~d"1", ~d"8") == d(1, 125, -3)
    assert Decimal.div(~d"100", ~d"4") == d(1, 25, 0)
    assert Decimal.div(~d"1000", ~d"8") == d(1, 125, 0)
  end

  test "div/2 exact quotient wider than precision keeps precision digits and signals" do
    pow10 = fn n -> String.to_integer("1" <> String.duplicate("0", n)) end

    # 10^40 / 1 is exact, but the quotient cannot be represented with a
    # non-negative adjust at precision 34; the result is clamped to 34
    # significant digits with a raised exponent, and :inexact/:rounded are
    # signalled (longstanding behavior of the digit-at-a-time division loop).
    assert Decimal.div(Decimal.new(1, pow10.(40), 0), ~d"1") == d(1, pow10.(33), 7)

    flags = Context.get().flags
    assert :inexact in flags
    assert :rounded in flags
  end

  test "div_int/2 and rem/2 quotient size limit" do
    pow10 = fn n -> String.to_integer("1" <> String.duplicate("0", n)) end

    # a quotient of exactly 10^precision digits-wise is still allowed
    # (the "too large" check is strictly greater than 10^precision)
    assert Decimal.div_int(Decimal.new(1, pow10.(34), 0), ~d"1") == d(1, pow10.(34), 0)

    assert_raise Error, ~r/quotient too large/, fn ->
      Decimal.div_int(Decimal.new(1, 2 * pow10.(34), 0), ~d"1")
    end

    # large exponent gaps are rejected from digit counts alone
    assert_raise Error, ~r/quotient too large/, fn ->
      Decimal.div_int(~d"1e50", ~d"1")
    end

    assert_raise Error, ~r/quotient too large/, fn ->
      Decimal.rem(~d"1e50", ~d"1")
    end
  end

  test "round/3 rounding mode table" do
    values = ~w(5.5 2.5 1.6 1.1 1.0 -1.0 -1.1 -1.6 -2.5 -5.5)

    expected = %{
      up: ~w(6 3 2 2 1 -1 -2 -2 -3 -6),
      down: ~w(5 2 1 1 1 -1 -1 -1 -2 -5),
      ceiling: ~w(6 3 2 2 1 -1 -1 -1 -2 -5),
      floor: ~w(5 2 1 1 1 -1 -2 -2 -3 -6),
      half_up: ~w(6 3 2 1 1 -1 -1 -2 -3 -6),
      half_down: ~w(5 2 2 1 1 -1 -1 -2 -2 -5),
      half_even: ~w(6 2 2 1 1 -1 -1 -2 -2 -6)
    }

    for {mode, results} <- expected, {value, result} <- Enum.zip(values, results) do
      assert Decimal.round(Decimal.new(value), 0, mode) == Decimal.new(result),
             "round(#{value}, 0, #{mode}) expected #{result}"
    end
  end

  test "round/3 when every digit is dropped" do
    assert Decimal.round(~d"0.5", 0, :half_up) == d(1, 1, 0)
    assert Decimal.round(~d"0.5", 0, :half_down) == d(1, 0, 0)
    assert Decimal.round(~d"0.5", 0, :ceiling) == d(1, 1, 0)
    assert Decimal.round(~d"0.5", 0, :floor) == d(1, 0, 0)
    assert Decimal.round(~d"-0.5", 0, :half_up) == d(-1, 1, 0)
    assert Decimal.round(~d"-0.5", 0, :floor) == d(-1, 1, 0)
    assert Decimal.round(~d"-0.5", 0, :ceiling) == d(-1, 0, 0)
    assert Decimal.round(~d"0.49", 0, :half_up) == d(1, 0, 0)
    assert Decimal.round(~d"0.51", 0, :half_down) == d(1, 1, 0)
  end

  test "context rounding carry keeps exactly precision digits" do
    Context.with(%Context{precision: 5, rounding: :half_up}, fn ->
      assert Decimal.add(~d"99999", ~d"0.5") == d(1, 10_000, 1)
    end)

    Context.with(%Context{precision: 1, rounding: :half_up}, fn ->
      assert Decimal.add(~d"9", ~d"0.5") == d(1, 1, 1)
    end)
  end

  test "context :up rounding does not round exact values up" do
    Context.with(%Context{precision: 2, rounding: :up}, fn ->
      # discarded digits all zero: value is exact, no increment
      assert Decimal.mult(~d"20", ~d"5") == d(1, 10, 1)
      # nonzero discarded digits round away from zero
      assert Decimal.mult(~d"3", ~d"34") == d(1, 11, 1)
      # sticky remainder from division also rounds away from zero
      assert Decimal.div(~d"1", ~d"3") == d(1, 34, -2)
    end)
  end

  test "mult/2 rounds to context precision and signals" do
    Context.with(%Context{precision: 5, rounding: :half_up}, fn ->
      assert Decimal.mult(~d"12345", ~d"10001") == d(1, 12346, 4)

      flags = Context.get().flags
      assert :rounded in flags
      assert :inexact in flags
    end)
  end

  test "digit counting at the coef_length fallback boundary" do
    c18 = 999_999_999_999_999_999
    c19 = 9_999_999_999_999_999_999
    pow10 = fn n -> String.to_integer("1" <> String.duplicate("0", n)) end

    c17 = 99_999_999_999_999_999

    # 17 -> 18 digits crosses from the comparison ladder into the bit-length
    # estimate, 18 -> 19 crosses the machine word; none should be touched at
    # default precision
    assert Decimal.apply_context(Decimal.new(1, c17, 0)) == d(1, c17, 0)
    assert Decimal.apply_context(Decimal.new(1, c17 + 1, 0)) == d(1, c17 + 1, 0)
    assert Decimal.apply_context(Decimal.new(1, c18, 0)) == d(1, c18, 0)
    assert Decimal.apply_context(Decimal.new(1, c19, 0)) == d(1, c19, 0)

    # the same boundary through scaling and comparison
    assert Decimal.compare(Decimal.new(1, c17, 0), Decimal.new(1, c17 + 1, 0)) == :lt
    assert Decimal.add(Decimal.new(1, c17, 0), Decimal.new(1, 1, 0)) == d(1, c17 + 1, 0)
    assert Decimal.to_string(Decimal.new(1, c17 + 1, 0)) == "100000000000000000"

    # 34 digits fits the default precision exactly; 35 digits rounds
    assert Decimal.apply_context(Decimal.new(1, pow10.(33), 0)) == d(1, pow10.(33), 0)
    assert Decimal.apply_context(Decimal.new(1, pow10.(34), 0)) == d(1, pow10.(33), 1)

    # rounding a 19-digit coefficient to 18 digits carries across the boundary
    Context.with(%Context{precision: 18, rounding: :half_up}, fn ->
      assert Decimal.apply_context(Decimal.new(1, c19, 0)) == d(1, pow10.(17), 2)
    end)

    # equal adjusted exponents at 19 digits reach the coefficient comparison
    assert Decimal.compare(Decimal.new(1, c19, 0), Decimal.new(1, c19 - 1, 0)) == :gt
    assert Decimal.compare(Decimal.new(1, c19 - 1, 0), Decimal.new(1, c19, 0)) == :lt
  end

  test "sqrt/1 across magnitudes" do
    Context.with(%Context{precision: 9, rounding: :half_even}, fn ->
      assert Decimal.sqrt(~d"1e100") == d(1, 1, 50)
      assert Decimal.sqrt(~d"4e100") == d(1, 2, 50)
      assert Decimal.sqrt(~d"1e-100") == d(1, 1, -50)
      assert Decimal.sqrt(~d"2") == d(1, 141_421_356, -8)
      assert Decimal.sqrt(~d"1e101") == d(1, 316_227_766, 42)
    end)
  end

  test "to_string/2 :xsd expands large positive exponents" do
    assert Decimal.to_string(~d"1e120", :xsd) ==
             "1" <> String.duplicate("0", 120) <> ".0"
  end

  test "compare/2 with equal exponents" do
    assert Decimal.compare(d(1, 12_345, -2), d(1, 12_346, -2)) == :lt
    assert Decimal.compare(d(1, 12_346, -2), d(1, 12_345, -2)) == :gt
    assert Decimal.compare(d(1, 12_345, -2), d(1, 12_345, -2)) == :eq

    # a negative sign inverts the coefficient order
    assert Decimal.compare(d(-1, 12_345, -2), d(-1, 12_346, -2)) == :gt
    assert Decimal.compare(d(-1, 12_346, -2), d(-1, 12_345, -2)) == :lt

    # coefficients of different lengths at the same exponent
    assert Decimal.compare(d(1, 9, 0), d(1, 1_000, 0)) == :lt
    assert Decimal.compare(d(-1, 9, 0), d(-1, 1_000, 0)) == :gt

    # 34-digit coefficients at the same scale
    coef = 1_234_567_890_123_456_789_012_345_678_901_234
    assert Decimal.compare(d(1, coef, -5), d(1, coef + 1, -5)) == :lt
    assert Decimal.compare(d(-1, coef, -5), d(-1, coef + 1, -5)) == :gt
    assert Decimal.compare(d(1, coef, -5), d(1, coef, -5)) == :eq

    # zero and NaN are still decided before the coefficients are compared
    assert Decimal.compare(d(1, 0, -2), d(1, 0, -2)) == :eq
    assert Decimal.compare(d(1, 0, -2), d(1, 5, -2)) == :lt
    assert Decimal.compare(d(-1, 0, -2), d(-1, 5, -2)) == :gt
    assert Decimal.compare(d(1, 5, -2), d(-1, 5, -2)) == :gt

    assert_raise Error, fn -> Decimal.compare(d(1, :NaN, 0), d(1, 5, 0)) end
  end

  test "add/2 with equal exponents and a coefficient length gap over the precision" do
    # An exponent gap is what makes alignment expensive; with equal exponents
    # there is nothing to align, so the exact sum is computed and rounded.
    wide = String.to_integer("1" <> String.duplicate("0", 40))
    rounded = String.to_integer("1" <> String.duplicate("0", 33))

    Context.with(%Context{traps: []}, fn ->
      assert Decimal.add(d(1, wide, 0), d(1, 1, 0)) == d(1, rounded, 7)
      assert :inexact in Context.get().flags
      assert :rounded in Context.get().flags
    end)

    # subtractive cancellation at equal exponents
    assert Decimal.add(d(1, wide, 0), d(-1, wide, 0)) == d(1, 0, 0)
    assert Decimal.add(d(1, 12_345, -2), d(-1, 12_346, -2)) == d(-1, 1, -2)

    # in-precision sums are exact
    assert Decimal.add(d(1, 12_345, -2), d(1, 1, -2)) == d(1, 12_346, -2)
    assert Decimal.sub(d(1, 12_345, -2), d(1, 12_345, -2)) == d(1, 0, -2)
  end

  test "to_float/1 across the double range" do
    # subnormals are below DBL_MIN and rejected, as documented
    assert_raise Error, fn -> Decimal.to_float(~d"5e-324") end

    assert Decimal.to_float(~d"2.2250738585072014e-308") == 2.2250738585072014e-308
    assert Decimal.to_float(~d"1.7976931348623157e308") == 1.7976931348623157e308
    assert Decimal.to_float(~d"-1.7976931348623157e308") == -1.7976931348623157e308

    # `String.to_float/1` is correctly rounded, so it is an independent oracle
    # for the scaling `to_float/1` does with integer arithmetic
    for coef <- [1, 3, 7, 9, 15, 123, 999_999_999_999_999, 1_234_567_890_123_456],
        exp <- [-30, -17, -7, -3, -1, 0, 1, 3, 7, 17, 30] do
      decimal = Decimal.new(1, coef, exp)
      expected = String.to_float("#{coef}.0e#{exp}")

      assert Decimal.to_float(decimal) == expected
      assert Decimal.to_float(Decimal.new(-1, coef, exp)) == -expected
    end

    # every power of ten in range survives the round trip
    for exp <- -300..300 do
      float = :math.pow(10.0, exp)
      assert float |> Decimal.from_float() |> Decimal.to_float() == float
    end
  end

  test "from_float/1 drops the redundant fraction from exponent notation" do
    assert Decimal.from_float(1.0e5) == d(1, 1, 5)
    assert Decimal.from_float(100_000.0) == d(1, 1, 5)
    assert Decimal.from_float(1.0e-5) == d(1, 1, -5)
    assert Decimal.from_float(-1.0e300) == d(-1, 1, 300)
    assert Decimal.from_float(5.0e-324) == d(1, 5, -324)

    # values rendered without an exponent are untouched
    assert Decimal.from_float(1.5) == d(1, 15, -1)
    assert Decimal.from_float(0.1) == d(1, 1, -1)
    assert Decimal.from_float(-3.14) == d(-1, 314, -2)
    assert Decimal.from_float(0.0) == d(1, 0, -1)
  end

  test "parse/2 exponent digits" do
    assert Decimal.parse("1e0000") == {d(1, 1, 0), ""}
    assert Decimal.parse("1e00000000000000000000005") == {d(1, 1, 5), ""}
    assert Decimal.parse("1.5e-2x") == {d(1, 15, -3), "x"}

    # the marker is only part of the number when digits follow it
    assert Decimal.parse("1e") == {d(1, 1, 0), "e"}
    assert Decimal.parse("1e+") == {d(1, 1, 0), "e+"}
    assert Decimal.parse("1e-") == {d(1, 1, 0), "e-"}
    assert Decimal.parse("1E") == {d(1, 1, 0), "E"}

    # an exponent past the limit is rejected without being materialized
    assert Decimal.parse("1e" <> String.duplicate("9", 10_000)) == :error
    assert Decimal.parse("1e-" <> String.duplicate("9", 10_000)) == :error
    assert Decimal.parse("1e6144") == {d(1, 1, 6144), ""}
    assert Decimal.parse("1e6145") == :error

    # without a limit it is parsed in full
    digits = String.duplicate("9", 40)

    assert Decimal.parse("1e" <> digits, max_exponent: :infinity) ==
             {d(1, 1, String.to_integer(digits)), ""}
  end

  test "parse/1 coefficients around the digit accumulator boundary" do
    for length <- 15..21 do
      digits = String.duplicate("9", length)
      assert Decimal.parse(digits) == {d(1, String.to_integer(digits), 0), ""}

      with_point = String.duplicate("9", length) <> "." <> String.duplicate("7", 5)

      assert Decimal.parse(with_point) ==
               {d(1, String.to_integer(String.duplicate("9", length) <> "77777"), -5), ""}
    end

    # leading zeros are not significant digits and do not stop the accumulator
    assert Decimal.parse("0000000000000000000000000000000000000001.5") == {d(1, 15, -1), ""}
    assert Decimal.parse("0.0000000000000000000001") == {d(1, 1, -22), ""}
    assert Decimal.parse(String.duplicate("0", 40)) == {d(1, 0, 0), ""}

    # past the boundary the digits convert from the input, leading zeros and all
    nines = String.duplicate("9", 18)
    assert Decimal.parse("000" <> nines) == {d(1, String.to_integer(nines), 0), ""}

    assert Decimal.parse("000" <> nines <> ".55") ==
             {d(1, String.to_integer(nines <> "55"), -2), ""}

    assert Decimal.parse("0." <> String.duplicate("0", 21) <> nines) ==
             {d(1, String.to_integer(nines), -39), ""}

    # exponent digits go through the same scan
    assert Decimal.parse("1e" <> String.duplicate("0", 20) <> "5") == {d(1, 1, 5), ""}
  end

  test "flags accumulate across operations" do
    Context.with(%Context{traps: []}, fn ->
      assert Context.get().flags == []

      Decimal.add(~d"1", ~d"2")
      assert Context.get().flags == []

      # The order is asserted, not just the membership: operations merge their
      # own signals with the ones rounding raises, and the merge must not
      # reshuffle what is already recorded.
      Decimal.div(~d"1", ~d"3")
      assert Context.get().flags == [:rounded, :inexact]

      # re-signalling the same condition leaves the flags as they are
      Decimal.div(~d"2", ~d"7")
      Decimal.add(~d"1", ~d"2")
      assert Context.get().flags == [:rounded, :inexact]

      # a new signal is still recorded on top
      Decimal.mult(~d"1e6000", ~d"1e6000")
      flags = Context.get().flags
      assert :overflow in flags
      assert :inexact in flags
      assert :rounded in flags
    end)

    # flags are per context, so a fresh one starts clean
    Context.with(%Context{}, fn -> assert Context.get().flags == [] end)
  end

  test "round/3 dropping exactly one digit" do
    assert Decimal.round(~d"1.25", 1, :half_even) == d(1, 12, -1)
    assert Decimal.round(~d"1.35", 1, :half_even) == d(1, 14, -1)
    assert Decimal.round(~d"1.25", 1, :half_up) == d(1, 13, -1)
    assert Decimal.round(~d"-1.25", 1, :half_up) == d(-1, 13, -1)
    assert Decimal.round(~d"1.25", 1, :half_down) == d(1, 12, -1)
    assert Decimal.round(~d"1.29", 1, :down) == d(1, 12, -1)
    assert Decimal.round(~d"1.21", 1, :up) == d(1, 13, -1)
    assert Decimal.round(~d"1.21", 1, :ceiling) == d(1, 13, -1)
    assert Decimal.round(~d"1.29", 1, :floor) == d(1, 12, -1)
    assert Decimal.round(~d"-1.21", 1, :floor) == d(-1, 13, -1)
  end

  defp assert_runs_quickly(name, fun) do
    {elapsed_us, _result} = :timer.tc(fun)

    assert elapsed_us < @bounded_smoke_max_us,
           "#{name} took #{elapsed_us}us, expected less than #{@bounded_smoke_max_us}us"
  end
end
