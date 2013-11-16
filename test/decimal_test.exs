defmodule DecimalTest do
  use ExUnit.Case

  defrecordp :d, Decimal, [coef: 0, exp: 0]

  test "basic conversion" do
    assert Decimal.to_decimal(d(coef: 0, exp: 0)) == d(coef: 0, exp: 0)
    assert Decimal.to_decimal(123) == d(coef: 123, exp: 0)
  end

  test "float conversion" do
    assert Decimal.to_decimal(123.0) == d(coef: 123000000000000000000, exp: -18)
    assert Decimal.to_decimal(1.5) == d(coef: 150000000000000000000, exp: -20)
  end

  test "string conversion" do
    assert Decimal.to_decimal("123") == d(coef: 123, exp: 0)
    assert Decimal.to_decimal("+123") == d(coef: 123, exp: 0)
    assert Decimal.to_decimal("-123") == d(coef: -123, exp: 0)

    assert Decimal.to_decimal("123.0") == d(coef: 1230, exp: -1)
    assert Decimal.to_decimal("+123.0") == d(coef: 1230, exp: -1)
    assert Decimal.to_decimal("-123.0") == d(coef: -1230, exp: -1)

    assert Decimal.to_decimal("1.5") == d(coef: 15, exp: -1)
    assert Decimal.to_decimal("+1.5") == d(coef: 15, exp: -1)
    assert Decimal.to_decimal("-1.5") == d(coef: -15, exp: -1)

    assert Decimal.to_decimal("0") == d(coef: 0, exp: 0)
    assert Decimal.to_decimal("+0") == d(coef: 0, exp: 0)
    assert Decimal.to_decimal("-0") == d(coef: 0, exp: 0)

    assert Decimal.to_decimal("1230e13") == d(coef: 1230, exp: 13)
    assert Decimal.to_decimal("+1230e+2") == d(coef: 1230, exp: 2)
    assert Decimal.to_decimal("-1230e-2") == d(coef: -1230, exp: -2)


    assert Decimal.to_decimal("1230.00e13") == d(coef: 123000, exp: 11)
    assert Decimal.to_decimal("+1230.1230e+5") == d(coef: 12301230, exp: 1)
    assert Decimal.to_decimal("-1230.01010e-5") == d(coef: -123001010, exp: -10)

    assert Decimal.to_decimal("0e0") == d(coef: 0, exp: 0)
    assert Decimal.to_decimal("+0e-0") == d(coef: 0, exp: 0)
    assert Decimal.to_decimal("-0e+0") == d(coef: 0, exp: 0)
  end

  test "conversion error" do
    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal("")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal("test")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal(".0")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal("e0")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal("42.+42")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal(:atom)
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.to_decimal("42e0.0")
    end
  end
end
