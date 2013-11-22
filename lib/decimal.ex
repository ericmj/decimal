defmodule Decimal do
  import Kernel, except: [abs: 1, max: 2, min: 2, round: 1]

  use Decimal.Record
  import Decimal.Context
  alias Decimal.Context
  alias Decimal.Error
  alias Decimal.Util

  def abs(num, context // unlimited) do
    dec(coef: coef) = d = to_decimal(num)
    dec(d, coef: Kernel.abs(coef)) |> round(context)
  end

  def add(num1, num2, context // unlimited) do
    dec(coef: coef1, exp: exp1) = to_decimal(num1)
    dec(coef: coef2, exp: exp2) = to_decimal(num2)

    { coef1, coef2 } = add_align(coef1, exp1, coef2, exp2)
    coef = coef1 + coef2
    exp = Kernel.min(exp1, exp2)
    dec(coef: coef, exp: exp) |> round(context)
  end

  def sub(num1, num2, context // unlimited) do
    dec(coef: coef2) = d2 = to_decimal(num2)
    add(num1, dec(d2, coef: -coef2)) |> round(context)
  end

  def compare(num1, num2, context // unlimited) do
    case sub(num1, num2, context) do
      dec(coef: 0) -> 0
      dec(coef: coef) when coef > 0 -> 1
      dec(coef: coef) when coef < 0 -> -1
    end
  end

  def div(num1, num2, Context[] = context) do
    dec(coef: coef1, exp: exp1) = d1 = to_decimal(num1)
    dec(coef: coef2, exp: exp2) = to_decimal(num2)

    # TODO?
    unless context.precision > 0,
      do: raise(Error, message: "unlimited precision not supported for division")

    if coef2 == 0, do: raise(Error, message: "division by zero")

    if coef1 == 0 do
      d1
    else
      sign = div_sign(coef1, coef2)
      prec10 = Util.int_pow10(1, context.precision)

      { coef1, coef2, adjust } = div_adjust(Kernel.abs(coef1), Kernel.abs(coef2), 0)
      { coef, adjust, _rem } = div_calc(coef1, coef2, 0, adjust, prec10)
      dec(coef: sign * coef, exp: exp1 - exp2 - adjust) |> round(context)
    end
  end

  def div_int(num1, num2, Context[] = context // unlimited) do
    div_rem(num1, num2, context) |> elem(0)
  end

  def rem(num1, num2, Context[] = context // unlimited) do
    div_rem(num1, num2, context) |> elem(1)
  end

  def div_rem(num1, num2, Context[] = context // unlimited) do
    dec(coef: coef1, exp: exp1) = d1 = to_decimal(num1)
    dec(coef: coef2, exp: exp2) = d2 = to_decimal(num2)
    abs_coef1 = Kernel.abs(coef1)
    abs_coef2 = Kernel.abs(coef2)

    if compare(dec(d1, coef: abs_coef1), dec(d2, coef: abs_coef2)) == -1 do
      { dec(coef: 0, exp: 0), d1 }
    else
      div_sign = div_sign(coef1, coef2)
      rem_sign = if coef1 < 0, do: -1, else: 1
      { coef1, coef2, adjust } = div_adjust(abs_coef1, abs_coef2, 0)

      unless context.precision == 0 or -adjust < context.precision,
        do: raise(Error, message: "division requires higher precision than context allows")

      adjust2 = if adjust < 0, do: 0, else: adjust
      { coef, rem } = div_int_calc(coef1, coef2, 0, adjust)
      { coef, exp } = truncate(coef, exp1 - exp2 - adjust2)

      adjust3 = if adjust > 0, do: 0, else: adjust
      { dec(coef: div_sign * coef, exp: exp),
        dec(coef: rem_sign * Util.int_pow10(rem, adjust3), exp: 0) }
    end
  end

  def max(num1, num2, context // unlimited) do
    d1 = to_decimal(num1)
    d2 = to_decimal(num2)
    if compare(d1, d2, context) == -1,
      do: d2,
      else: d1
  end

  def min(num1, num2, context // unlimited) do
    d1 = to_decimal(num1)
    d2 = to_decimal(num2)
    if compare(d1, d2, context) == 1,
      do: d2,
      else: d1
  end

  def minus(num) do
    dec(coef: coef) = d = to_decimal(num)
    dec(d, coef: -coef)
  end

  def mult(num1, num2, context // unlimited) do
    dec(coef: coef1, exp: exp1) = d1 = to_decimal(num1)
    dec(coef: coef2, exp: exp2) = d2 = to_decimal(num2)

    dec(coef: coef1 * coef2, exp: exp1 + exp2) |> round(context)
  end

  def to_decimal(num, context // unlimited)

  def to_decimal(dec() = d, ctxt),
    do: d |> round(ctxt)
  def to_decimal(int, ctxt) when is_integer(int),
    do: dec(coef: int) |> round(ctxt)
  def to_decimal(float, ctxt) when is_float(float),
    do: to_decimal(float_to_binary(float)) |> round(ctxt)
  def to_decimal(binary, ctxt) when is_binary(binary),
    do: parse(binary) |> round(ctxt)
  def to_decimal(_, _),
    do: raise ArgumentError

  def to_string(num, type // :normal)

  def to_string(num, :normal) do
    dec(coef: coef, exp: exp) = to_decimal(num)
    list = integer_to_list(Kernel.abs(coef))

    list =
      if exp >= 0 do
        list ++ :lists.duplicate(exp, ?0)
      else
        diff = length(list) + exp
        if diff > 0 do
          List.insert_at(list, diff, ?.)
        else
          '0.' ++ :lists.duplicate(-diff, ?0) ++ list
        end
      end

    if coef < 0 do
      list = [?-|list]
    end

    String.from_char_list!(list)
  end

  def to_string(num, :scientific) do
    dec(coef: coef, exp: exp) = to_decimal(num)
    list = integer_to_list(Kernel.abs(coef))

    { list, exp_offset } = trim_coef(list)
    exp = exp + exp_offset
    length = length(list)

    if length > 1 do
      list = List.insert_at(list, 1, ?.)
      exp = exp + length - 1
    end

    list = list ++ 'e' ++ integer_to_list(exp)

    if coef < 0 do
      list = [?-|list]
    end

    String.from_char_list!(list)
  end

  ## STRINGIFY ##

  defp trim_coef('0') do
    { '0', 0 }
  end

  defp trim_coef(list) do
    num = count_trailing_zeros(list, 0)
    { Enum.drop(list, -num), num }
  end

  defp count_trailing_zeros([], count),
    do: count
  defp count_trailing_zeros([?0|tail], count),
    do: count_trailing_zeros(tail, count+1)
  defp count_trailing_zeros([_|tail], _count),
    do: count_trailing_zeros(tail, 0)

  ## ARITHMETIC ##

  defp add_align(coef1, exp1, coef2, exp2) when exp1 == exp2,
    do: { coef1, coef2 }

  defp add_align(coef1, exp1, coef2, exp2) when exp1 > exp2,
    do: { coef1 * Util.int_pow10(1, exp1 - exp2), coef2 }

  defp add_align(coef1, exp1, coef2, exp2) when exp1 < exp2,
    do: { coef1, coef2 * Util.int_pow10(1, exp2 - exp1) }

  defp div_adjust(coef1, coef2, adjust) when coef1 < coef2,
    do: div_adjust(coef1 * 10, coef2, adjust + 1)

  defp div_adjust(coef1, coef2, adjust) when coef1 >= coef2 * 10,
    do: div_adjust(coef1, coef2 * 10, adjust - 1)

  defp div_adjust(coef1, coef2, adjust),
    do: { coef1, coef2, adjust }

  defp div_calc(coef1, coef2, coef, adjust, prec10) do
    cond do
      coef1 >= coef2 ->
        div_calc(coef1 - coef2, coef2, coef + 1, adjust, prec10)
      div_complete?(coef1, coef, adjust, prec10) ->
        { coef, adjust, coef1 }
      true ->
        div_calc(coef1 * 10, coef2, coef * 10, adjust + 1, prec10)
    end
  end

  defp div_complete?(coef1, coef, adjust, prec10),
    do: (coef1 == 0 and adjust >= 0) or coef >= prec10

  defp div_sign(coef1, coef2) do
    coef1_sign = if coef1 < 0, do: -1, else: 1
    coef2_sign = if coef2 < 0, do: -1, else: 1
    coef1_sign * coef2_sign
  end

  defp div_int_calc(coef1, coef2, coef, adjust) do
    cond do
      coef1 >= coef2 ->
        div_int_calc(coef1 - coef2, coef2, coef + 1, adjust)
      adjust < 0 ->
        div_int_calc(coef1 * 10, coef2, coef * 10, adjust + 1)
      true ->
        { coef, coef1 }
    end
  end

  defp truncate(coef, exp) when exp >= 0,
    do: { coef, exp }

  defp truncate(coef, exp) when exp < 0,
    do: truncate(div(coef, 10), exp + 1)

  ## PARSING ##

  defp parse("+" <> bin) do
    parse_unsign(bin)
  end

  defp parse("-" <> bin) do
    dec(coef: coef) = d = parse_unsign(bin)
    dec(d, coef: -coef)
  end

  defp parse(bin) do
    parse_unsign(bin)
  end

  defp parse_unsign(bin) do
    { int, rest } = parse_digits(bin)
    { float, rest } = parse_float(rest)
    { exp, rest } = parse_exp(rest)

    if int == [] or rest != "", do: raise ArgumentError
    if exp == [], do: exp = '0'

    dec(coef: list_to_integer(int ++ float), exp: list_to_integer(exp) - length(float))
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
