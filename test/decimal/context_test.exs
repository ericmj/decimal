defmodule Decimal.ContextTest do
  use ExUnit.Case, async: true
  use Decimal.Record
  alias Decimal.Context
  import Kernel, except: [round: 1]

  defmacrop round(num) do
    quote do
      Decimal.to_decimal(unquote(num))
      |> Context.round(var!(context))
    end
  end

  test "truncate" do
    context = Context[precision: 2, rounding: :truncate]
    assert round("1.02") == dec(coef: 10, exp: -1)
    assert round("102") == dec(coef: 10, exp: 1)
    assert round("1.1") == dec(coef: 11, exp: -1)
  end

  test "ceiling" do
    context = Context[precision: 2, rounding: :ceiling]
    assert round("1.02") == dec(coef: 11, exp: -1)
    assert round("102") == dec(coef: 11, exp: 1)
    assert round("-102") == dec(coef: -10, exp: 1)
    assert round("106") == dec(coef: 11, exp: 1)
  end

  test "floor" do
    context = Context[precision: 2, rounding: :floor]
    assert round("1.02") == dec(coef: 10, exp: -1)
    assert round("1.10") == dec(coef: 11, exp: -1)
    assert round("-123") == dec(coef: -13, exp: 1)
  end

  test "half away zero" do
    context = Context[precision: 2, rounding: :half_away_zero]
    assert round("1.02") == dec(coef: 10, exp: -1)
    assert round("1.05") == dec(coef: 11, exp: -1)
    assert round("-1.05") == dec(coef: -11, exp: -1)
    assert round("123") == dec(coef: 12, exp: 1)
    assert round("125") == dec(coef: 13, exp: 1)
    assert round("-125") == dec(coef: -13, exp: 1)
  end

  test "half up" do
    context = Context[precision: 2, rounding: :half_up]
    assert round("1.02") == dec(coef: 10, exp: -1)
    assert round("1.05") == dec(coef: 11, exp: -1)
    assert round("-1.05") == dec(coef: -10, exp: -1)
    assert round("123") == dec(coef: 12, exp: 1)
    assert round("-123") == dec(coef: -12, exp: 1)
    assert round("125") == dec(coef: 13, exp: 1)
    assert round("-125") == dec(coef: -12, exp: 1)
  end

  test "half even" do
    context = Context[precision: 2, rounding: :half_even]
    assert round("1.0") == dec(coef: 10, exp: -1)
    assert round("123") == dec(coef: 12, exp: 1)
    assert round("6.66") == dec(coef: 67, exp: -1)
    assert round("9.99") == dec(coef: 10, exp: 0)
    assert round("-6.66") == dec(coef: -67, exp: -1)
    assert round("-9.99") == dec(coef: -10, exp: 0)
  end
end
