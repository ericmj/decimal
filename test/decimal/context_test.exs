defmodule Decimal.ContextTest do
  use ExUnit.Case, async: true

  import TestMacros
  alias Decimal.Context
  alias Decimal.Error

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
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 100, -1)
      assert Decimal.add(~d"0", ~d"1.0") == d(1, 10, -1)
      assert Decimal.add(~d"0", ~d"123") == d(1, 12, 1)
      assert Decimal.add(~d"0", ~d"6.66") == d(1, 67, -1)
      assert Decimal.add(~d"0", ~d"9.99") == d(1, 100, -1)
      assert Decimal.add(~d"0", ~d"-6.66") == d(-1, 67, -1)
      assert Decimal.add(~d"0", ~d"-9.99") == d(-1, 100, -1)
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

      Decimal.div(
        ~d"10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        ~d"17"
      )

      assert [:rounded] = Context.get().flags
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
end
