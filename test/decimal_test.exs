defmodule DecimalTest do
  use ExUnit.Case, async: true
  use Decimal.Record

  test "basic conversion" do
    assert Decimal.to_decimal(dec(coef: 0, exp: 0)) == dec(coef: 0, exp: 0)
    assert Decimal.to_decimal(123)                  == dec(coef: 123, exp: 0)
  end

  test "float conversion" do
    assert Decimal.to_decimal(123.0) == dec(coef: 123000000000000000000, exp: -18)
    assert Decimal.to_decimal(1.5)   == dec(coef: 150000000000000000000, exp: -20)
  end

  test "string conversion" do
    assert Decimal.to_decimal("123")  == dec(coef: 123, exp: 0)
    assert Decimal.to_decimal("+123") == dec(coef: 123, exp: 0)
    assert Decimal.to_decimal("-123") == dec(coef: -123, exp: 0)

    assert Decimal.to_decimal("123.0")  == dec(coef: 1230, exp: -1)
    assert Decimal.to_decimal("+123.0") == dec(coef: 1230, exp: -1)
    assert Decimal.to_decimal("-123.0") == dec(coef: -1230, exp: -1)

    assert Decimal.to_decimal("1.5")  == dec(coef: 15, exp: -1)
    assert Decimal.to_decimal("+1.5") == dec(coef: 15, exp: -1)
    assert Decimal.to_decimal("-1.5") == dec(coef: -15, exp: -1)

    assert Decimal.to_decimal("0")  == dec(coef: 0, exp: 0)
    assert Decimal.to_decimal("+0") == dec(coef: 0, exp: 0)
    assert Decimal.to_decimal("-0") == dec(coef: 0, exp: 0)

    assert Decimal.to_decimal("1230e13")  == dec(coef: 1230, exp: 13)
    assert Decimal.to_decimal("+1230e+2") == dec(coef: 1230, exp: 2)
    assert Decimal.to_decimal("-1230e-2") == dec(coef: -1230, exp: -2)


    assert Decimal.to_decimal("1230.00e13")     == dec(coef: 123000, exp: 11)
    assert Decimal.to_decimal("+1230.1230e+5")  == dec(coef: 12301230, exp: 1)
    assert Decimal.to_decimal("-1230.01010e-5") == dec(coef: -123001010, exp: -10)

    assert Decimal.to_decimal("0e0")   == dec(coef: 0, exp: 0)
    assert Decimal.to_decimal("+0e-0") == dec(coef: 0, exp: 0)
    assert Decimal.to_decimal("-0e+0") == dec(coef: 0, exp: 0)
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

  test "abs" do
    assert Decimal.abs("123")                    == dec(coef: 123, exp: 0)
    assert Decimal.abs("-123")                   == dec(coef: 123, exp: 0)
    assert Decimal.abs("-12.5e2")                == dec(coef: 125, exp: 1)
    assert Decimal.abs(dec(coef: -42, exp: -42)) == dec(coef: 42, exp: -42)
  end

  test "add" do
    assert Decimal.add("0", "0")         == dec(coef: 0, exp: 0)
    assert Decimal.add("1", "1")         == dec(coef: 2, exp: 0)
    assert Decimal.add("1.3e3", "2.4e2") == dec(coef: 154, exp: 1)
    assert Decimal.add("0.42", "-1.5")   == dec(coef: -108, exp: -2)
    assert Decimal.add("-2e-2", "-2e-2") == dec(coef: -4, exp: -2)
  end

  test "sub" do
    assert Decimal.sub("0", "0")         == dec(coef: 0, exp: 0)
    assert Decimal.sub("1", "1")         == dec(coef: 0, exp: 0)
    assert Decimal.sub("1.3e3", "2.4e2") == dec(coef: 106, exp: 1)
    assert Decimal.sub("0.42", "-1.5")   == dec(coef: 192, exp: -2)
    assert Decimal.sub("2e-2", "-2e-2")  == dec(coef: 4, exp: -2)
  end

  test "compare" do
    assert Decimal.compare("420", "42e1") == 0
    assert Decimal.compare("1", "0")      == 1
    assert Decimal.compare("0", "1")      == -1
  end

  test "div" do
    assert Decimal.div("1", "3", 5)       == dec(coef: 33333, exp: -5)
    assert Decimal.div("42", "2", 5)      == dec(coef: 21, exp: 0)
    assert Decimal.div("123", "12345", 5) == dec(coef: 99635, exp: -7)
    assert Decimal.div("123", "123", 5)   == dec(coef: 1, exp: 0)
    assert Decimal.div("-1", "5", 5)      == dec(coef: -2, exp: -1)
    assert Decimal.div("-1", "-1", 5)     == dec(coef: 1, exp: 0)
    assert Decimal.div("2", "-5", 5)      == dec(coef: -4, exp: -1)
  end

  test "div_int" do
    assert Decimal.div_int("1", "3")      == dec(coef: 0, exp: 0)
    assert Decimal.div_int("42", "2")     == dec(coef: 21, exp: 0)
    assert Decimal.div_int("123", "23")   == dec(coef: 5, exp: 0)
    assert Decimal.div_int("123", "-23")  == dec(coef: -5, exp: 0)
    assert Decimal.div_int("-123", "23")  == dec(coef: -5, exp: 0)
    assert Decimal.div_int("-123", "-23") == dec(coef: 5, exp: 0)
    assert Decimal.div_int("1", "0.3")    == dec(coef: 3, exp: 0)
  end

  test "rem" do
    assert Decimal.rem("1", "3")      == dec(coef: 1, exp: 0)
    assert Decimal.rem("42", "2")     == dec(coef: 0, exp: 0)
    assert Decimal.rem("123", "23")   == dec(coef: 8, exp: 0)
    assert Decimal.rem("123", "-23")  == dec(coef: 8, exp: 0)
    assert Decimal.rem("-123", "23")  == dec(coef: -8, exp: 0)
    assert Decimal.rem("-123", "-23") == dec(coef: -8, exp: 0)
    assert Decimal.rem("1", "0.3")    == dec(coef: 1, exp: 0)
  end

  test "max" do
    assert Decimal.max("0", "0")     == dec(coef: 0, exp: 0)
    assert Decimal.max("1", "0")     == dec(coef: 1, exp: 0)
    assert Decimal.max("0", "1")     == dec(coef: 1, exp: 0)
    assert Decimal.max("-1", "1")    == dec(coef: 1, exp: 0)
    assert Decimal.max("1", "-1")    == dec(coef: 1, exp: 0)
    assert Decimal.max("-30", "-40") == dec(coef: -30, exp: 0)
  end

  test "min" do
    assert Decimal.min("0", "0")     == dec(coef: 0, exp: 0)
    assert Decimal.min("-1", "0")    == dec(coef: -1, exp: 0)
    assert Decimal.min("0", "-1")    == dec(coef: -1, exp: 0)
    assert Decimal.min("-1", "1")    == dec(coef: -1, exp: 0)
    assert Decimal.min("1", "0")     == dec(coef: 0, exp: 0)
    assert Decimal.min("-30", "-40") == dec(coef: -40, exp: 0)
  end

  test "minus" do
    assert Decimal.minus("0")  == dec(coef: 0, exp: 0)
    assert Decimal.minus("1")  == dec(coef: -1, exp: 0)
    assert Decimal.minus("-1") == dec(coef: 1, exp: 0)
  end

  test "mult" do
    assert Decimal.mult("0", "0")      == dec(coef: 0, exp: 0)
    assert Decimal.mult("42", "0")     == dec(coef: 0, exp: 0)
    assert Decimal.mult("0", "42")     == dec(coef: 0, exp: 0)
    assert Decimal.mult("5", "5")      == dec(coef: 25, exp: 0)
    assert Decimal.mult("-5", "5")     == dec(coef: -25, exp: 0)
    assert Decimal.mult("5", "-5")     == dec(coef: -25, exp: 0)
    assert Decimal.mult("-5", "-5")    == dec(coef: 25, exp: 0)
    assert Decimal.mult("42", "0.42")  == dec(coef: 1764, exp: -2)
    assert Decimal.mult("0.03", "0.3") == dec(coef: 9, exp: -3)
  end

  test "to_string normal" do
    assert Decimal.to_string("0")       == "0"
    assert Decimal.to_string("42")      == "42"
    assert Decimal.to_string("42.42")   == "42.42"
    assert Decimal.to_string("0.42")    == "0.42"
    assert Decimal.to_string("0.0042")  == "0.0042"
    assert Decimal.to_string("-1")      == "-1"
    assert Decimal.to_string("-1.23")   == "-1.23"
    assert Decimal.to_string("-0.0123") == "-0.0123"
  end

  test "to_string scientific" do
    assert Decimal.to_string("2", :scientific)        == "2e0"
    assert Decimal.to_string("300", :scientific)      == "3e2"
    assert Decimal.to_string("4321.768", :scientific) == "4.321768e3"
    assert Decimal.to_string("-53000", :scientific)   == "-5.3e4"
    assert Decimal.to_string("0.0042", :scientific)   == "4.2e-3"
    assert Decimal.to_string("0.2", :scientific)      == "2e-1"
    assert Decimal.to_string("-0.0003", :scientific)  == "-3e-4"
  end

  test "to_string simple" do
    assert Decimal.to_string("2", :simple)        == "2"
    assert Decimal.to_string("300", :simple)      == "300"
    assert Decimal.to_string("4321.768", :simple) == "4321768e-3"
    assert Decimal.to_string("-53000", :simple)   == "-53000"
    assert Decimal.to_string("0.0042", :simple)   == "42e-4"
    assert Decimal.to_string("0.2", :simple)      == "2e-1"
    assert Decimal.to_string("-0.0003", :simple)  == "-3e-4"
  end

  test "precision truncate" do
    precision = &Decimal.precision(&1, 2, :truncate)
    assert precision.("1.02") == dec(coef: 10, exp: -1)
    assert precision.("102")  == dec(coef: 10, exp: 1)
    assert precision.("1.1")  == dec(coef: 11, exp: -1)
  end

  test "precision ceiling" do
    precision = &Decimal.precision(&1, 2, :ceiling)
    assert precision.("1.02") == dec(coef: 11, exp: -1)
    assert precision.("102")  == dec(coef: 11, exp: 1)
    assert precision.("-102") == dec(coef: -10, exp: 1)
    assert precision.("106")  == dec(coef: 11, exp: 1)
  end

  test "precision floor" do
    precision = &Decimal.precision(&1, 2, :floor)
    assert precision.("1.02") == dec(coef: 10, exp: -1)
    assert precision.("1.10") == dec(coef: 11, exp: -1)
    assert precision.("-123") == dec(coef: -13, exp: 1)
  end

  test "precision half away zero" do
    precision = &Decimal.precision(&1, 2, :half_away_zero)
    assert precision.("1.02")  == dec(coef: 10, exp: -1)
    assert precision.("1.05")  == dec(coef: 11, exp: -1)
    assert precision.("-1.05") == dec(coef: -11, exp: -1)
    assert precision.("123")   == dec(coef: 12, exp: 1)
    assert precision.("125")   == dec(coef: 13, exp: 1)
    assert precision.("-125")  == dec(coef: -13, exp: 1)
  end

  test "precision half up" do
    precision = &Decimal.precision(&1, 2, :half_up)
    assert precision.("1.02")  == dec(coef: 10, exp: -1)
    assert precision.("1.05")  == dec(coef: 11, exp: -1)
    assert precision.("-1.05") == dec(coef: -10, exp: -1)
    assert precision.("123")   == dec(coef: 12, exp: 1)
    assert precision.("-123")  == dec(coef: -12, exp: 1)
    assert precision.("125")   == dec(coef: 13, exp: 1)
    assert precision.("-125")  == dec(coef: -12, exp: 1)
  end

  test "precision half even" do
    precision = &Decimal.precision(&1, 2, :half_even)
    assert precision.("1.0")   == dec(coef: 10, exp: -1)
    assert precision.("123")   == dec(coef: 12, exp: 1)
    assert precision.("6.66")  == dec(coef: 67, exp: -1)
    assert precision.("9.99")  == dec(coef: 10, exp: 0)
    assert precision.("-6.66") == dec(coef: -67, exp: -1)
    assert precision.("-9.99") == dec(coef: -10, exp: 0)
  end
end
