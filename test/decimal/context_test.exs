defmodule Decimal.ContextTest do
  use ExUnit.Case, async: true

  import TestMacros
  alias Decimal.Context
  alias Decimal.Error

  @bounded_smoke_exp 10_000_000
  @bounded_smoke_max_us 5_000_000
  @bounded_smoke_timeout 15_000

  test "with_context/2: down" do
    Context.with(%Context{precision: 2, rounding: :down}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"102") == d(1, 10, 1)
      assert Decimal.add(~d"0", ~d"-102") == d(-1, 10, 1)
      assert Decimal.add(~d"0", ~d"1.1") == d(1, 11, -1)
    end)
  end

  test "with_context/2: ceiling" do
    Context.with(%Context{precision: 2, rounding: :ceiling}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"102") == d(1, 11, 1)
      assert Decimal.add(~d"0", ~d"-102") == d(-1, 10, 1)
      assert Decimal.add(~d"0", ~d"106") == d(1, 11, 1)
    end)
  end

  test "with_context/2: floor" do
    Context.with(%Context{precision: 2, rounding: :floor}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"1.10") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"-123") == d(-1, 13, 1)
    end)
  end

  test "with_context/2: half up" do
    Context.with(%Context{precision: 2, rounding: :half_up}, fn ->
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
    Context.with(%Context{precision: 2, rounding: :half_even}, fn ->
      # 9.99 rounds up to 10 at precision 2; the carry re-rounds to two
      # significant digits (d(1, 10, 0)), not the three-digit d(1, 100, -1).
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 10, 0)
      assert Decimal.add(~d"0", ~d"1.0") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"123") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"6.66") == d(1, 67, -1)
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 10, 0)
      assert Decimal.add(~d"0", ~d"-6.66") == d(-1, 67, -1)
      assert Decimal.add(~d"0", ~d"-9.99") == d(-1, 10, 0)
    end)

    Context.with(%Context{precision: 3, rounding: :half_even}, fn ->
      assert Decimal.add(~d"0", ~d"244.58") == d(1, 245, 0)
    end)
  end

  test "with_context/2: half down" do
    Context.with(%Context{precision: 2, rounding: :half_down}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"1.05") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"-1.05") == d(-1, 10, -1)
      assert Decimal.add(~d"0", ~d"123") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"125") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"-125") == d(-1, 12, 1)
    end)
  end

  test "with_context/2: up" do
    Context.with(%Context{precision: 2, rounding: :up}, fn ->
      assert Decimal.add(~d"0", ~d"1.02") == d(1, 11, -1)
      assert Decimal.add(~d"0", ~d"102") == d(1, 11, 1)
      assert Decimal.add(~d"0", ~d"-102") == d(-1, 11, 1)
      assert Decimal.add(~d"0", ~d"1.1") == d(1, 11, -1)
    end)

    # :up rounds away from zero only when a discarded digit is nonzero. An
    # exact value whose dropped digits are all zero must be left unchanged
    # (matches the General Decimal Arithmetic spec and Python's decimal).
    Context.with(%Context{precision: 1, rounding: :up}, fn ->
      assert Decimal.add(~d"0", ~d"9.0") == d(1, 9, 0)
      assert Decimal.add(~d"0", ~d"-9.0") == d(-1, 9, 0)
      assert Decimal.mult(~d"9.00", ~d"1") == d(1, 9, 0)
      # a nonzero discarded digit still rounds up
      assert Decimal.add(~d"0", ~d"3.1") == d(1, 4, 0)
    end)
  end

  test "with_context/2: rounding carry keeps exactly precision digits" do
    # When rounding overflows an all-nines coefficient (9.99 -> 10.0 at
    # precision 2, 9.5 -> 10 at precision 1), the result must be re-rounded
    # to `precision` significant digits rather than keeping the extra digit.
    # Applies to every context operation. Expected values match the General
    # Decimal Arithmetic spec and Python's decimal.
    Context.with(%Context{precision: 1, rounding: :half_even}, fn ->
      assert Decimal.div(~d"95", ~d"10") == d(1, 1, 1)
    end)

    Context.with(%Context{precision: 2, rounding: :half_even}, fn ->
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 10, 0)
      assert Decimal.mult(~d"3.33", ~d"3") == d(1, 10, 0)
      assert Decimal.sub(~d"10", ~d"0.001") == d(1, 10, 0)
    end)

    Context.with(%Context{precision: 3, rounding: :ceiling}, fn ->
      assert Decimal.div(~d"9995", ~d"1000") == d(1, 100, -1)
    end)
  end

  test "with_context/2: large exponent gap addition" do
    num = d(1, 1, 100_000)
    one = d(1, 1, 0)

    for {rounding, result} <- [
          down: d(1, 100, 99_998),
          half_up: d(1, 100, 99_998),
          half_even: d(1, 100, 99_998),
          half_down: d(1, 100, 99_998),
          up: d(1, 101, 99_998),
          floor: d(1, 100, 99_998),
          ceiling: d(1, 101, 99_998)
        ] do
      Context.with(
        %Context{precision: 3, rounding: rounding, emax: :infinity, emin: :infinity},
        fn ->
          assert Decimal.add(num, one) == result
          assert :inexact in Context.get().flags
          assert :rounded in Context.get().flags
        end
      )
    end
  end

  test "with_context/2: large exponent gap addition with zero" do
    num = d(1, 1, 100_000)

    Context.with(%Context{precision: 3, emax: :infinity, emin: :infinity}, fn ->
      assert Decimal.add(d(1, 0, -100_000), num) == d(1, 100, 99_998)
      assert Context.get().flags == [:rounded]
    end)

    Context.with(%Context{precision: 3, emax: :infinity, emin: :infinity}, fn ->
      assert Decimal.add(d(1, 0, 100_000), d(1, 1, 0)) == d(1, 1, 0)
      assert Context.get().flags == []
    end)
  end

  test "with_context/2: large exponent gap subtraction" do
    num = d(1, 1, 100_000)
    one = d(1, 1, 0)

    # Modes that round up carry 9.99e99999 to 1.00e100000; the carry
    # re-rounds to three significant digits, d(1, 100, 99_998), rather than
    # the four-digit d(1, 1000, 99_997). :down and :floor truncate (no carry).
    for {rounding, result} <- [
          down: d(1, 999, 99_997),
          half_up: d(1, 100, 99_998),
          half_even: d(1, 100, 99_998),
          half_down: d(1, 100, 99_998),
          up: d(1, 100, 99_998),
          floor: d(1, 999, 99_997),
          ceiling: d(1, 100, 99_998)
        ] do
      Context.with(
        %Context{precision: 3, rounding: rounding, emax: :infinity, emin: :infinity},
        fn ->
          assert Decimal.sub(num, one) == result
          assert :inexact in Context.get().flags
          assert :rounded in Context.get().flags
        end
      )
    end
  end

  @tag timeout: @bounded_smoke_timeout
  test "with_context/2: large exponent gap arithmetic stays bounded" do
    num = %Decimal{sign: 1, coef: 1, exp: @bounded_smoke_exp}
    one = d(1, 1, 0)

    Context.with(%Context{precision: 3, emax: :infinity, emin: :infinity}, fn ->
      assert_runs_quickly("add/2 large exponent gap", fn ->
        assert Decimal.add(num, one) == %Decimal{sign: 1, coef: 100, exp: @bounded_smoke_exp - 2}
      end)
    end)

    Context.with(%Context{precision: 3, emax: :infinity, emin: :infinity}, fn ->
      assert_runs_quickly("sub/2 large exponent gap", fn ->
        # default :half_up carries 9.99e(N-1) to 1.00eN; the carry re-rounds
        # to three significant digits (coef 100, exp N-2).
        assert Decimal.sub(num, one) == %Decimal{sign: 1, coef: 100, exp: @bounded_smoke_exp - 2}
      end)
    end)
  end

  @tag timeout: @bounded_smoke_timeout
  test "with_context/2: large exponent gap zero addition stays bounded" do
    zero = %Decimal{sign: 1, coef: 0, exp: -@bounded_smoke_exp}
    num = %Decimal{sign: 1, coef: 1, exp: @bounded_smoke_exp}

    Context.with(%Context{precision: 3, emax: :infinity, emin: :infinity}, fn ->
      assert_runs_quickly("add/2 large exponent gap with zero", fn ->
        assert Decimal.add(zero, num) == %Decimal{sign: 1, coef: 100, exp: @bounded_smoke_exp - 2}
      end)
    end)
  end

  test "with_context/2 set flags" do
    Context.with(%Context{precision: 2}, fn ->
      assert [] = Context.get().flags
      Decimal.add(~d"2", ~d"2")
      assert [] = Context.get().flags
      Decimal.add(~d"2.0000", ~d"2")
      assert [:rounded] = Context.get().flags
      Decimal.add(~d"2.0001", ~d"2")
      assert :inexact in Context.get().flags
    end)

    Context.with(%Context{precision: 111}, fn ->
      assert [] = Context.get().flags

      coef = :erlang.binary_to_integer("1" <> String.duplicate("0", 106))
      Decimal.div(Decimal.new(1, coef, 0), ~d"17")

      # 10^106 / 17 is non-terminating, so rounding it to 111 digits produces
      # an inexact result: both :rounded and :inexact must be signalled (per
      # the General Decimal Arithmetic spec; Python's decimal agrees).
      flags = Context.get().flags
      assert :rounded in flags
      assert :inexact in flags
    end)

    Context.with(%Context{precision: 2}, fn ->
      assert [] = Context.get().flags

      assert_raise Error, fn ->
        assert Decimal.mult(~d"inf", ~d"0")
      end

      assert :invalid_operation in Context.get().flags
    end)
  end

  test "with_context/2 traps" do
    Context.with(%Context{traps: []}, fn ->
      assert Decimal.mult(~d"inf", ~d"0") == d(1, :NaN, 0)
      assert Decimal.div(~d"5", ~d"0") == d(1, :inf, 0)
      assert :division_by_zero in Context.get().flags
    end)
  end

  test "with_context/2 emax overflow" do
    Context.with(%Context{precision: 3, emax: 2, traps: []}, fn ->
      assert Decimal.mult(~d"9.99e2", 10) == d(1, :inf, 0)
      assert :overflow in Context.get().flags
      assert :inexact in Context.get().flags
      assert :rounded in Context.get().flags
    end)

    Context.with(%Context{precision: 3, rounding: :down, emax: 2, traps: []}, fn ->
      assert Decimal.mult(~d"9.99e2", 10) == d(1, 999, 0)
      assert :overflow in Context.get().flags
    end)
  end

  test "with_context/2 rem signals overflow when |num1| < |num2|" do
    Context.with(%Context{precision: 3, emax: 2, traps: []}, fn ->
      result = Decimal.rem(~d"9e9", ~d"9e10")
      assert result == d(1, :inf, 0)
      assert :overflow in Context.get().flags
    end)
  end

  test "with_context/2 emin underflow" do
    Context.with(%Context{precision: 3, emin: -2, traps: []}, fn ->
      assert Decimal.div(1, 3000) == d(1, 3, -4)
      assert :underflow in Context.get().flags
      assert :inexact in Context.get().flags
      assert :rounded in Context.get().flags
    end)
  end

  # Expected values and flags of operation results match Python's decimal
  # module with the same context.
  describe "subnormal results" do
    test "keep the digits at or above etiny = emin - precision + 1" do
      Context.with(%Context{precision: 3, emin: -2, traps: []}, fn ->
        assert Decimal.div(1, 1000) == d(1, 1, -3)
        assert Context.get().flags == [:subnormal]
      end)

      Context.with(%Context{precision: 3, emin: -2, traps: []}, fn ->
        assert Decimal.apply_context(~d"1.0e-4") == d(1, 1, -4)
        assert Enum.sort(Context.get().flags) == [:rounded, :subnormal]
      end)
    end

    test "are rounded at etiny with the context rounding" do
      for {rounding, num1, num2, expected} <- [
            {:half_up, 1, 3000, d(1, 3, -4)},
            {:half_up, 1, 30000, d(1, 0, -4)},
            {:half_up, -1, 30000, d(-1, 0, -4)},
            {:ceiling, 1, 30000, d(1, 1, -4)},
            {:floor, -1, 30000, d(-1, 1, -4)},
            {:up, 1, 30000, d(1, 1, -4)},
            {:half_up, 1, 20000, d(1, 1, -4)},
            {:half_even, 1, 20000, d(1, 0, -4)},
            {:half_even, 3, 20000, d(1, 2, -4)}
          ] do
        Context.with(%Context{precision: 3, emin: -2, rounding: rounding, traps: []}, fn ->
          assert Decimal.div(num1, num2) == expected

          flags = [:inexact, :rounded, :subnormal, :underflow]
          flags = if expected.coef == 0, do: [:clamped | flags], else: flags
          assert Enum.sort(Context.get().flags) == flags
        end)
      end
    end

    test "underflow when tiny before rounding, even if rounding carries to emin" do
      for value <- [~d"0.009996", ~d"0.009950", ~d"0.00999"] do
        Context.with(%Context{precision: 3, emin: -2, traps: []}, fn ->
          assert Decimal.apply_context(value) == d(1, 100, -4)
          assert Enum.sort(Context.get().flags) == [:inexact, :rounded, :subnormal, :underflow]
        end)
      end

      Context.with(%Context{precision: 3, emin: -2, traps: []}, fn ->
        assert Decimal.apply_context(~d"0.0100") == d(1, 100, -4)
        assert Context.get().flags == []
      end)
    end

    test "with the default decimal128 context" do
      Context.with(%Context{}, fn ->
        assert Decimal.div(~d"1e-6140", 10000) == d(1, 1, -6144)
        assert Decimal.mult(~d"1e-6000", ~d"1e-150") == d(1, 1, -6150)
        assert Decimal.sub(~d"2e-6143", ~d"1.5e-6143") == d(1, 5, -6144)
        assert Decimal.add(Decimal.new(1, 1, -6144), 0) == d(1, 1, -6144)
        assert Decimal.normalize(Decimal.new(1, 100, -6146)) == d(1, 1, -6144)
        assert Context.get().flags == [:subnormal]
      end)

      Context.with(%Context{}, fn ->
        thirty_three_threes = String.to_integer(String.duplicate("3", 33))
        assert Decimal.div(1, ~d"3e6143") == d(1, thirty_three_threes, -6176)
        assert Enum.sort(Context.get().flags) == [:inexact, :rounded, :subnormal, :underflow]
      end)

      Context.with(%Context{}, fn ->
        assert Decimal.mult(~d"1e-3100", ~d"1e-3100") == d(1, 0, -6176)

        assert Enum.sort(Context.get().flags) ==
                 [:clamped, :inexact, :rounded, :subnormal, :underflow]
      end)
    end

    test "trap underflow only when inexact" do
      Context.with(%Context{precision: 3, emin: -2, traps: [:underflow]}, fn ->
        assert Decimal.div(1, 1000) == d(1, 1, -3)
      end)
    end

    test "trap subnormal for every result below emin" do
      Context.with(%Context{precision: 3, emin: -2, traps: [:subnormal]}, fn ->
        assert Decimal.div(1, 100) == d(1, 1, -2)
        assert_raise Error, "subnormal", fn -> Decimal.div(1, 1000) end
      end)
    end

    test "round/3 signals subnormal and clamped for the result, not the input" do
      tiny = Decimal.new(1, 15, -6145)

      Context.with(%Context{}, fn ->
        assert Decimal.round(tiny, 6145) == tiny
        assert Decimal.round(tiny, 6144, :half_even) == d(1, 2, -6144)
        assert Decimal.round(tiny, 6144, :down) == d(1, 1, -6144)
        assert Context.get().flags == [:subnormal]
      end)

      Context.with(%Context{}, fn ->
        assert Decimal.round(tiny, 6140) == d(1, 0, -6140)
        assert Decimal.round(Decimal.new(1, 0, 1_000_000_000), 2) == d(1, 0, -2)
        assert Decimal.round(Decimal.new(-1, 0, -1_000_000_000), 2) == d(-1, 0, -2)
        assert Context.get().flags == []
      end)

      Context.with(%Context{}, fn ->
        assert Decimal.round(Decimal.new(1, 0, -6200), 6200) == d(1, 0, -6176)
        assert Context.get().flags == [:clamped]
      end)
    end

    test "round/3 results padded below etiny keep the digits at or above it" do
      for {num, places, expected, flags} <- [
            {Decimal.new(1, 1, -6150), 7000, d(1, Integer.pow(10, 26), -6176),
             [:rounded, :subnormal]},
            {Decimal.new(1, 15, -6175), 6200, d(1, 150, -6176), [:rounded, :subnormal]},
            {Decimal.new(1, 15, -6175), 6176, d(1, 150, -6176), [:subnormal]},
            {Decimal.new(1, 15, -6175), 6174, d(1, 2, -6174), [:subnormal]},
            {Decimal.new(1, 96, -6145), 6144, d(1, 10, -6144), []},
            {Decimal.new(1, 123, -6146), 7000, d(1, 123 * Integer.pow(10, 30), -6176),
             [:rounded, :subnormal]},
            {Decimal.new(-1, 7, -6143), 6200, d(-1, 7 * Integer.pow(10, 33), -6176), [:rounded]}
          ] do
        Context.with(%Context{}, fn ->
          assert Decimal.round(num, places) == expected
          assert Enum.sort(Context.get().flags) == flags
        end)
      end
    end

    @tag timeout: @bounded_smoke_timeout
    test "far below etiny stays bounded" do
      tiny = Decimal.new(1, 1, -@bounded_smoke_exp)

      assert_runs_quickly("apply_context/1 far below etiny", fn ->
        Context.with(%Context{rounding: :ceiling}, fn ->
          assert Decimal.apply_context(tiny) == d(1, 1, -6176)
        end)

        assert Decimal.apply_context(tiny) == d(1, 0, -6176)
        assert Decimal.round(tiny, 2) == d(1, 0, -2)
        assert Decimal.mult(tiny, tiny) == d(1, 0, -6176)
      end)
    end
  end

  describe "zero results" do
    test "have their exponent clamped to between etiny and emax" do
      for {fun, expected} <- [
            {fn -> Decimal.mult(~d"0e-3500", ~d"0e-3500") end, d(1, 0, -6176)},
            {fn -> Decimal.mult(~d"0e3500", ~d"0e3500") end, d(1, 0, 6144)},
            {fn -> Decimal.mult(~d"-1e6000", ~d"0e1000") end, d(-1, 0, 6144)},
            {fn -> Decimal.add(~d"0e-3500", Decimal.new(1, 0, -7000)) end, d(1, 0, -6176)}
          ] do
        Context.with(%Context{}, fn ->
          assert fun.() == expected
          assert Context.get().flags == [:clamped]
        end)
      end

      Context.with(%Context{precision: 3, emin: -2, emax: 5}, fn ->
        assert Decimal.mult(~d"0e3", ~d"0e3") == d(1, 0, 5)
        assert Decimal.mult(~d"0e-3", ~d"0e-3") == d(1, 0, -4)
        assert Context.get().flags == [:clamped]
      end)
    end

    test "inside the limits, or without limits, are unchanged" do
      Context.with(%Context{}, fn ->
        assert Decimal.mult(~d"0e-3000", ~d"0e-3000") == d(1, 0, -6000)
        assert Decimal.mult(~d"0e3000", ~d"0e3000") == d(1, 0, 6000)
        assert Context.get().flags == []
      end)

      Context.with(%Context{emin: :infinity, emax: :infinity}, fn ->
        assert Decimal.mult(~d"0e-3500", ~d"0e-3500") == d(1, 0, -7000)
        assert Decimal.mult(~d"0e3500", ~d"0e3500") == d(1, 0, 7000)
        assert Context.get().flags == []
      end)
    end

    test "that skip rounding are clamped too" do
      Context.with(%Context{}, fn ->
        assert Decimal.div(~d"1e-6000", d(1, :inf, 1000)) == d(1, 0, -6176)
        assert Decimal.div_int(~d"1e-6000", d(1, :inf, 1000)) == d(1, 0, -6176)
        assert Decimal.div_int(~d"1e-6000", ~d"1e6000") == d(1, 0, -6176)
        assert {d(1, 0, -6176), _} = Decimal.div_rem(~d"1e-6000", d(1, :inf, 1000))
        assert Decimal.div_rem(~d"1e-6000", ~d"1e6000") == {d(1, 0, -6176), d(1, 1, -6000)}
        assert Decimal.sqrt(Decimal.new(1, 0, -13000)) == d(1, 0, -6176)
        assert Context.get().flags == [:clamped]
      end)
    end

    test "trap clamped" do
      Context.with(%Context{traps: [:clamped]}, fn ->
        assert_raise Error, "clamped", fn -> Decimal.mult(~d"0e-3500", ~d"0e-3500") end
      end)
    end
  end

  test "with_context/2 exponent limit traps" do
    assert_raise Error, "overflow", fn ->
      Context.with(%Context{precision: 3, emax: 2, traps: [:overflow]}, fn ->
        Decimal.mult(~d"9.99e2", 10)
      end)
    end

    assert_raise Error, "underflow", fn ->
      Context.with(%Context{precision: 3, emin: -2, traps: [:underflow]}, fn ->
        Decimal.div(1, 3000)
      end)
    end
  end

  describe "validation" do
    test "set/1, with/2 and update/1 reject invalid fields" do
      for {context, message} <- [
            {%Context{precision: 0}, "invalid :precision, expected a positive integer, got: 0"},
            {%Context{precision: -1}, "invalid :precision, expected a positive integer, got: -1"},
            {%Context{precision: 1.5},
             "invalid :precision, expected a positive integer, got: 1.5"},
            {%Context{rounding: :bogus},
             ~r/^invalid :rounding, expected one of \[.*\], got: :bogus$/},
            {%Context{emax: 1.0}, "invalid :emax, expected an integer or :infinity, got: 1.0"},
            {%Context{emin: nil}, "invalid :emin, expected an integer or :infinity, got: nil"},
            {%Context{emin: 10, emax: 5},
             "invalid :emin and :emax, emin must not be greater than emax, got: emin 10 and emax 5"}
          ] do
        assert_raise ArgumentError, message, fn -> Context.set(context) end
        assert_raise ArgumentError, message, fn -> Context.with(context, fn -> :ok end) end
        assert_raise ArgumentError, message, fn -> Context.update(fn _ -> context end) end
      end

      assert Context.get() == %Context{}
    end

    test "a rejected with/2 leaves the current context in place" do
      Context.with(%Context{precision: 5}, fn ->
        assert_raise ArgumentError, fn ->
          Context.with(%Context{precision: 0}, fn -> :ok end)
        end

        assert Context.get().precision == 5
      end)
    end

    test "accepts boundary values" do
      Context.with(%Context{precision: 1, emin: 0, emax: 0}, fn ->
        assert Decimal.add(1, 1) == d(1, 2, 0)
      end)

      Context.with(%Context{emin: :infinity, emax: :infinity}, fn ->
        assert Decimal.add(1, 1) == d(1, 2, 0)
      end)
    end
  end

  defp assert_runs_quickly(name, fun) do
    {elapsed_us, _result} = :timer.tc(fun)

    assert elapsed_us < @bounded_smoke_max_us,
           "#{name} took #{elapsed_us}us, expected less than #{@bounded_smoke_max_us}us"
  end
end
