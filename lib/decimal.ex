defmodule Decimal do
  defrecordp :d, __MODULE__, [coef: 0, exp: 0]

  def to_decimal(d() = d), do: d
  def to_decimal(int) when is_integer(int), do: d(coef: int)
  def to_decimal(float) when is_float(float), do: to_decimal(float_to_binary(float))
  def to_decimal(binary) when is_binary(binary), do: parse(binary)

  defp parse("NaN") do
    d(coef: :NaN)
  end

  defp parse("+" <> bin) do
    parse_unsign(bin)
  end

  defp parse("-" <> bin) do
    d(coef: coef) = d = parse_unsign(bin)
    d(d, coef: -coef)
  end

  defp parse(bin) do
    parse_unsign(bin)
  end

  defp parse_unsign("inf") do
    d(coef: :inf)
  end

  defp parse_unsign(bin) do
    { int, rest } = parse_digits(bin)
    { float, rest } = parse_float(rest)
    { exp, rest } = parse_exp(rest)

    if int == [] or rest != "", do: raise ArgumentError
    if exp == [], do: exp = '0'

    d(coef: list_to_integer(int ++ float), exp: list_to_integer(exp) - length(float))
  end

  defp parse_float("." <> rest), do: parse_digits(rest)
  defp parse_float(bin), do: { [], bin }

  defp parse_exp(<< e, rest :: binary >>) when e in [?e, ?E] do
    case rest do
      << sign, rest :: binary >> when sign in [?+, ?-] ->
        { digits, rest } = parse_digits(rest)
        { [sign|digits], rest }
      _ ->
        parse_digits(rest)
    end
  end

  defp parse_exp(bin) do
    { [], bin }
  end

  defp parse_digits(bin), do: parse_digits(bin, [])

  defp parse_digits(<< digit, rest :: binary >>, acc) when digit in ?0..?9 do
    parse_digits(rest, [digit|acc])
  end

  defp parse_digits(rest, acc) do
    { :lists.reverse(acc), rest }
  end
end
