defmodule DecimalTest do
  use ExUnit.Case, async: true

  defrecordp :dec, Decimal, [coef: 0, exp: 0]
  alias Decimal.Context

  defmacrop sigil_d(str, _opts) do
    quote do
      Decimal.new(unquote(str))
    end
  end

  test "basic conversion" do
    assert Decimal.new(dec(coef: 0, exp: 0)) == dec(coef: 0, exp: 0)
    assert Decimal.new(123)                  == dec(coef: 123, exp: 0)
  end

  test "float conversion" do
    assert Decimal.new(123.0) == dec(coef: 1230, exp: -1)
    assert Decimal.new(1.5)   == dec(coef: 15, exp: -1)
  end

  test "string conversion" do
    assert Decimal.new("123")  == dec(coef: 123, exp: 0)
    assert Decimal.new("+123") == dec(coef: 123, exp: 0)
    assert Decimal.new("-123") == dec(coef: -123, exp: 0)

    assert Decimal.new("123.0")  == dec(coef: 1230, exp: -1)
    assert Decimal.new("+123.0") == dec(coef: 1230, exp: -1)
    assert Decimal.new("-123.0") == dec(coef: -1230, exp: -1)

    assert Decimal.new("1.5")  == dec(coef: 15, exp: -1)
    assert Decimal.new("+1.5") == dec(coef: 15, exp: -1)
    assert Decimal.new("-1.5") == dec(coef: -15, exp: -1)

    assert Decimal.new("0")  == dec(coef: 0, exp: 0)
    assert Decimal.new("+0") == dec(coef: 0, exp: 0)
    assert Decimal.new("-0") == dec(coef: 0, exp: 0)

    assert Decimal.new("1230e13")  == dec(coef: 1230, exp: 13)
    assert Decimal.new("+1230e+2") == dec(coef: 1230, exp: 2)
    assert Decimal.new("-1230e-2") == dec(coef: -1230, exp: -2)


    assert Decimal.new("1230.00e13")     == dec(coef: 123000, exp: 11)
    assert Decimal.new("+1230.1230e+5")  == dec(coef: 12301230, exp: 1)
    assert Decimal.new("-1230.01010e-5") == dec(coef: -123001010, exp: -10)

    assert Decimal.new("0e0")   == dec(coef: 0, exp: 0)
    assert Decimal.new("+0e-0") == dec(coef: 0, exp: 0)
    assert Decimal.new("-0e+0") == dec(coef: 0, exp: 0)
  end

  test "conversion error" do
    assert_raise ArgumentError, fn ->
      assert Decimal.new("")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.new("test")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.new(".0")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.new("e0")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.new("42.+42")
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.new(:atom)
    end

    assert_raise ArgumentError, fn ->
      assert Decimal.new("42e0.0")
    end
  end

  test "abs" do
    assert Decimal.abs(%d"123")     == dec(coef: 123, exp: 0)
    assert Decimal.abs(%d"-123")    == dec(coef: 123, exp: 0)
    assert Decimal.abs(%d"-12.5e2") == dec(coef: 125, exp: 1)
    assert Decimal.abs(%d"-42e-42") == dec(coef: 42, exp: -42)
  end

  test "add" do
    assert Decimal.add(%d"0", %d"0")         == dec(coef: 0, exp: 0)
    assert Decimal.add(%d"1", %d"1")         == dec(coef: 2, exp: 0)
    assert Decimal.add(%d"1.3e3", %d"2.4e2") == dec(coef: 154, exp: 1)
    assert Decimal.add(%d"0.42", %d"-1.5")   == dec(coef: -108, exp: -2)
    assert Decimal.add(%d"-2e-2", %d"-2e-2") == dec(coef: -4, exp: -2)
  end

  test "sub" do
    assert Decimal.sub(%d"0", %d"0")         == dec(coef: 0, exp: 0)
    assert Decimal.sub(%d"1", %d"1")         == dec(coef: 0, exp: 0)
    assert Decimal.sub(%d"1.3e3", %d"2.4e2") == dec(coef: 106, exp: 1)
    assert Decimal.sub(%d"0.42", %d"-1.5")   == dec(coef: 192, exp: -2)
    assert Decimal.sub(%d"2e-2", %d"-2e-2")  == dec(coef: 4, exp: -2)
  end

  test "compare" do
    assert Decimal.compare(%d"420", %d"42e1") == 0
    assert Decimal.compare(%d"1", %d"0")      == 1
    assert Decimal.compare(%d"0", %d"1")      == -1
  end

  test "div" do
    Decimal.with_context(Context[precision: 5, rounding: :half_up], fn ->
      assert Decimal.div(%d"1", %d"3")       == dec(coef: 33333, exp: -5)
      assert Decimal.div(%d"42", %d"2")      == dec(coef: 21, exp: 0)
      assert Decimal.div(%d"123", %d"12345") == dec(coef: 99635, exp: -7)
      assert Decimal.div(%d"123", %d"123")   == dec(coef: 1, exp: 0)
      assert Decimal.div(%d"-1", %d"5")      == dec(coef: -2, exp: -1)
      assert Decimal.div(%d"-1", %d"-1")     == dec(coef: 1, exp: 0)
      assert Decimal.div(%d"2", %d"-5")      == dec(coef: -4, exp: -1)
    end)
  end

  test "div_int" do
    assert Decimal.div_int(%d"1", %d"3")      == dec(coef: 0, exp: 0)
    assert Decimal.div_int(%d"42", %d"2")     == dec(coef: 21, exp: 0)
    assert Decimal.div_int(%d"123", %d"23")   == dec(coef: 5, exp: 0)
    assert Decimal.div_int(%d"123", %d"-23")  == dec(coef: -5, exp: 0)
    assert Decimal.div_int(%d"-123", %d"23")  == dec(coef: -5, exp: 0)
    assert Decimal.div_int(%d"-123", %d"-23") == dec(coef: 5, exp: 0)
    assert Decimal.div_int(%d"1", %d"0.3")    == dec(coef: 3, exp: 0)
  end

  test "rem" do
    assert Decimal.rem(%d"1", %d"3")      == dec(coef: 1, exp: 0)
    assert Decimal.rem(%d"42", %d"2")     == dec(coef: 0, exp: 0)
    assert Decimal.rem(%d"123", %d"23")   == dec(coef: 8, exp: 0)
    assert Decimal.rem(%d"123", %d"-23")  == dec(coef: 8, exp: 0)
    assert Decimal.rem(%d"-123", %d"23")  == dec(coef: -8, exp: 0)
    assert Decimal.rem(%d"-123", %d"-23") == dec(coef: -8, exp: 0)
    assert Decimal.rem(%d"1", %d"0.3")    == dec(coef: 1, exp: 0)
  end

  test "max" do
    assert Decimal.max(%d"0", %d"0")     == dec(coef: 0, exp: 0)
    assert Decimal.max(%d"1", %d"0")     == dec(coef: 1, exp: 0)
    assert Decimal.max(%d"0", %d"1")     == dec(coef: 1, exp: 0)
    assert Decimal.max(%d"-1", %d"1")    == dec(coef: 1, exp: 0)
    assert Decimal.max(%d"1", %d"-1")    == dec(coef: 1, exp: 0)
    assert Decimal.max(%d"-30", %d"-40") == dec(coef: -30, exp: 0)
  end

  test "min" do
    assert Decimal.min(%d"0", %d"0")     == dec(coef: 0, exp: 0)
    assert Decimal.min(%d"-1", %d"0")    == dec(coef: -1, exp: 0)
    assert Decimal.min(%d"0", %d"-1")    == dec(coef: -1, exp: 0)
    assert Decimal.min(%d"-1", %d"1")    == dec(coef: -1, exp: 0)
    assert Decimal.min(%d"1", %d"0")     == dec(coef: 0, exp: 0)
    assert Decimal.min(%d"-30", %d"-40") == dec(coef: -40, exp: 0)
  end

  test "minus" do
    assert Decimal.minus(%d"0")  == dec(coef: 0, exp: 0)
    assert Decimal.minus(%d"1")  == dec(coef: -1, exp: 0)
    assert Decimal.minus(%d"-1") == dec(coef: 1, exp: 0)
  end

  test "mult" do
    assert Decimal.mult(%d"0", %d"0")      == dec(coef: 0, exp: 0)
    assert Decimal.mult(%d"42", %d"0")     == dec(coef: 0, exp: 0)
    assert Decimal.mult(%d"0", %d"42")     == dec(coef: 0, exp: 0)
    assert Decimal.mult(%d"5", %d"5")      == dec(coef: 25, exp: 0)
    assert Decimal.mult(%d"-5", %d"5")     == dec(coef: -25, exp: 0)
    assert Decimal.mult(%d"5", %d"-5")     == dec(coef: -25, exp: 0)
    assert Decimal.mult(%d"-5", %d"-5")    == dec(coef: 25, exp: 0)
    assert Decimal.mult(%d"42", %d"0.42")  == dec(coef: 1764, exp: -2)
    assert Decimal.mult(%d"0.03", %d"0.3") == dec(coef: 9, exp: -3)
  end

  test "to_string normal" do
    assert Decimal.to_string(%d"0")       == "0"
    assert Decimal.to_string(%d"42")      == "42"
    assert Decimal.to_string(%d"42.42")   == "42.42"
    assert Decimal.to_string(%d"0.42")    == "0.42"
    assert Decimal.to_string(%d"0.0042")  == "0.0042"
    assert Decimal.to_string(%d"-1")      == "-1"
    assert Decimal.to_string(%d"-1.23")   == "-1.23"
    assert Decimal.to_string(%d"-0.0123") == "-0.0123"
  end

  test "to_string scientific" do
    assert Decimal.to_string(%d"2", :scientific)        == "2e0"
    assert Decimal.to_string(%d"300", :scientific)      == "3e2"
    assert Decimal.to_string(%d"4321.768", :scientific) == "4.321768e3"
    assert Decimal.to_string(%d"-53000", :scientific)   == "-5.3e4"
    assert Decimal.to_string(%d"0.0042", :scientific)   == "4.2e-3"
    assert Decimal.to_string(%d"0.2", :scientific)      == "2e-1"
    assert Decimal.to_string(%d"-0.0003", :scientific)  == "-3e-4"
  end

  test "to_string simple" do
    assert Decimal.to_string(%d"2", :simple)        == "2"
    assert Decimal.to_string(%d"300", :simple)      == "300"
    assert Decimal.to_string(%d"4321.768", :simple) == "4321768e-3"
    assert Decimal.to_string(%d"-53000", :simple)   == "-53000"
    assert Decimal.to_string(%d"0.0042", :simple)   == "42e-4"
    assert Decimal.to_string(%d"0.2", :simple)      == "2e-1"
    assert Decimal.to_string(%d"-0.0003", :simple)  == "-3e-4"
  end

  test "precision truncate" do
    Decimal.with_context(Context[precision: 2, rounding: :truncate], fn ->
      assert Decimal.add(%d"0", %d"1.02") == dec(coef: 10, exp: -1)
      assert Decimal.add(%d"0", %d"102")  == dec(coef: 10, exp: 1)
      assert Decimal.add(%d"0", %d"-102") == dec(coef: -10, exp: 1)
      assert Decimal.add(%d"0", %d"1.1")  == dec(coef: 11, exp: -1)
    end)
  end

  test "precision ceiling" do
    Decimal.with_context(Context[precision: 2, rounding: :ceiling], fn ->
      assert Decimal.add(%d"0", %d"1.02") == dec(coef: 11, exp: -1)
      assert Decimal.add(%d"0", %d"102")  == dec(coef: 11, exp: 1)
      assert Decimal.add(%d"0", %d"-102") == dec(coef: -10, exp: 1)
      assert Decimal.add(%d"0", %d"106")  == dec(coef: 11, exp: 1)
    end)
  end

  test "precision floor" do
    Decimal.with_context(Context[precision: 2, rounding: :floor], fn ->
      assert Decimal.add(%d"0", %d"1.02") == dec(coef: 10, exp: -1)
      assert Decimal.add(%d"0", %d"1.10") == dec(coef: 11, exp: -1)
      assert Decimal.add(%d"0", %d"-123") == dec(coef: -13, exp: 1)
    end)
  end

  test "precision half away zero" do
    Decimal.with_context(Context[precision: 2, rounding: :half_away_zero], fn ->
      assert Decimal.add(%d"0", %d"1.02")  == dec(coef: 10, exp: -1)
      assert Decimal.add(%d"0", %d"1.05")  == dec(coef: 11, exp: -1)
      assert Decimal.add(%d"0", %d"-1.05") == dec(coef: -11, exp: -1)
      assert Decimal.add(%d"0", %d"123")   == dec(coef: 12, exp: 1)
      assert Decimal.add(%d"0", %d"125")   == dec(coef: 13, exp: 1)
      assert Decimal.add(%d"0", %d"-125")  == dec(coef: -13, exp: 1)
    end)
  end

  test "precision half up" do
    Decimal.with_context(Context[precision: 2, rounding: :half_up], fn ->
      assert Decimal.add(%d"0", %d"1.02")  == dec(coef: 10, exp: -1)
      assert Decimal.add(%d"0", %d"1.05")  == dec(coef: 11, exp: -1)
      assert Decimal.add(%d"0", %d"-1.05") == dec(coef: -10, exp: -1)
      assert Decimal.add(%d"0", %d"123")   == dec(coef: 12, exp: 1)
      assert Decimal.add(%d"0", %d"-123")  == dec(coef: -12, exp: 1)
      assert Decimal.add(%d"0", %d"125")   == dec(coef: 13, exp: 1)
      assert Decimal.add(%d"0", %d"-125")  == dec(coef: -12, exp: 1)
    end)
  end

  test "precision half even" do
    Decimal.with_context(Context[precision: 2, rounding: :half_even], fn ->
      assert Decimal.add(%d"0", %d"1.0")   == dec(coef: 10, exp: -1)
      assert Decimal.add(%d"0", %d"123")   == dec(coef: 12, exp: 1)
      assert Decimal.add(%d"0", %d"6.66")  == dec(coef: 67, exp: -1)
      assert Decimal.add(%d"0", %d"9.99")  == dec(coef: 10, exp: 0)
      assert Decimal.add(%d"0", %d"-6.66") == dec(coef: -67, exp: -1)
      assert Decimal.add(%d"0", %d"-9.99") == dec(coef: -10, exp: 0)
    end)
  end

  test "round truncate" do
    round = &Decimal.round(&1, 2, :truncate)
    roundneg = &Decimal.round(&1, -2, :truncate)
    assert round.(%d"1.02")    == dec(coef: 102, exp: -2)
    assert round.(%d"1.029")   == dec(coef: 102, exp: -2)
    assert round.(%d"-1.029")  == dec(coef: -102, exp: -2)
    assert round.(%d"102")     == dec(coef: 102, exp: 0)
    assert roundneg.(%d"1.02") == dec(coef: 0, exp: 2)
    assert roundneg.(%d"102")  == dec(coef: 1, exp: 2)
    assert roundneg.(%d"1099") == dec(coef: 10, exp: 2)
  end

  test "round ceiling" do
    round = &Decimal.round(&1, 2, :ceiling)
    roundneg = &Decimal.round(&1, -2, :ceiling)
    assert round.(%d"1.02")    == dec(coef: 102, exp: -2)
    assert round.(%d"1.021")   == dec(coef: 103, exp: -2)
    assert round.(%d"-1.021")  == dec(coef: -102, exp: -2)
    assert round.(%d"102")     == dec(coef: 102, exp: 0)
    assert roundneg.(%d"1.02") == dec(coef: 1, exp: 2)
    assert roundneg.(%d"102")  == dec(coef: 2, exp: 2)
  end

  test "round floor" do
    round = &Decimal.round(&1, 2, :floor)
    roundneg = &Decimal.round(&1, -2, :floor)
    assert round.(%d"1.02")    == dec(coef: 102, exp: -2)
    assert round.(%d"1.029")   == dec(coef: 102, exp: -2)
    assert round.(%d"-1.029")  == dec(coef: -103, exp: -2)
    assert roundneg.(%d"123")  == dec(coef: 1, exp: 2)
    assert roundneg.(%d"-123") == dec(coef: -2, exp: 2)
  end

  test "round half away zero" do
    round = &Decimal.round(&1, 2, :half_away_zero)
    roundneg = &Decimal.round(&1, -2, :half_away_zero)
    assert round.(%d"1.02")    == dec(coef: 102, exp: -2)
    assert round.(%d"1.025")   == dec(coef: 103, exp: -2)
    assert round.(%d"-1.02")   == dec(coef: -102, exp: -2)
    assert round.(%d"-1.025")  == dec(coef: -103, exp: -2)
    assert roundneg.(%d"120")  == dec(coef: 1, exp: 2)
    assert roundneg.(%d"150")  == dec(coef: 2, exp: 2)
    assert roundneg.(%d"-120") == dec(coef: -1, exp: 2)
    assert roundneg.(%d"-150") == dec(coef: -2, exp: 2)
  end

  test "round half up" do
    round = &Decimal.round(&1, 2, :half_up)
    roundneg = &Decimal.round(&1, -2, :half_up)
    assert round.(%d"1.02")    == dec(coef: 102, exp: -2)
    assert round.(%d"1.025")   == dec(coef: 103, exp: -2)
    assert round.(%d"-1.02")   == dec(coef: -102, exp: -2)
    assert round.(%d"-1.025")  == dec(coef: -102, exp: -2)
    assert roundneg.(%d"120")  == dec(coef: 1, exp: 2)
    assert roundneg.(%d"150")  == dec(coef: 2, exp: 2)
    assert roundneg.(%d"-120") == dec(coef: -1, exp: 2)
    assert roundneg.(%d"-150") == dec(coef: -1, exp: 2)
  end

  test "round half even" do
    round = &Decimal.round(&1, 2, :half_even)
    roundneg = &Decimal.round(&1, -2, :half_even)
    assert round.(%d"1.03")    == dec(coef: 103, exp: -2)
    assert round.(%d"1.035")   == dec(coef: 104, exp: -2)
    assert round.(%d"1.045")   == dec(coef: 104, exp: -2)
    assert round.(%d"-1.035")  == dec(coef: -104, exp: -2)
    assert round.(%d"-1.045")  == dec(coef: -104, exp: -2)
    assert roundneg.(%d"130")  == dec(coef: 1, exp: 2)
    assert roundneg.(%d"150")  == dec(coef: 2, exp: 2)
    assert roundneg.(%d"250")  == dec(coef: 2, exp: 2)
    assert roundneg.(%d"-150") == dec(coef: -2, exp: 2)
    assert roundneg.(%d"-250") == dec(coef: -2, exp: 2)
  end

  test "coef" do
    assert Decimal.coef(%d"123")    == 123
    assert Decimal.coef(%d"0.0123") == 123
    assert Decimal.coef(%d"-1e5")   == -1
  end

  test "exp" do
    assert Decimal.exp(%d"123")    == 0
    assert Decimal.exp(%d"0.0123") == -4
    assert Decimal.exp(%d"-1e5")   == 5
  end

  test "frac" do
    assert Decimal.frac(%d"123") == dec(coef: 0, exp: 0)
    assert Decimal.frac(%d"123.123") == dec(coef: 123, exp: -3)
    assert Decimal.frac(%d"-42.42") == dec(coef: 42, exp: -2)
  end
end
