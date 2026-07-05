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
      assert Decimal.div(1, 1000) == d(1, 0, 0)
      assert :underflow in Context.get().flags
      assert :inexact in Context.get().flags
      assert :rounded in Context.get().flags
    end)
  end

  test "with_context/2 exponent limit traps" do
    assert_raise Error, "overflow", fn ->
      Context.with(%Context{precision: 3, emax: 2, traps: [:overflow]}, fn ->
        Decimal.mult(~d"9.99e2", 10)
      end)
    end

    assert_raise Error, "underflow", fn ->
      Context.with(%Context{precision: 3, emin: -2, traps: [:underflow]}, fn ->
        Decimal.div(1, 1000)
      end)
    end
  end

  defp assert_runs_quickly(name, fun) do
    {elapsed_us, _result} = :timer.tc(fun)

    assert elapsed_us < @bounded_smoke_max_us,
           "#{name} took #{elapsed_us}us, expected less than #{@bounded_smoke_max_us}us"
  end
end
