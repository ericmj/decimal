defmodule Decimal do
  import Kernel, except: [abs: 1, div: 2, max: 2, min: 2, rem: 1, round: 1]

  use Decimal.Record
  alias Decimal.Error

  def abs(num) do
    dec(coef: coef) = d = new(num)
    dec(d, coef: Kernel.abs(coef))
  end

  def add(num1, num2) do
    dec(coef: coef1, exp: exp1) = new(num1)
    dec(coef: coef2, exp: exp2) = new(num2)

    { coef1, coef2 } = add_align(coef1, exp1, coef2, exp2)
    coef = coef1 + coef2
    exp = Kernel.min(exp1, exp2)
    dec(coef: coef, exp: exp)
  end

  def sub(num1, num2) do
    dec(coef: coef2) = d2 = new(num2)
    add(num1, dec(d2, coef: -coef2))
  end

  def compare(num1, num2) do
    case sub(num1, num2) do
      dec(coef: 0) -> 0
      dec(coef: coef) when coef > 0 -> 1
      dec(coef: coef) when coef < 0 -> -1
    end
  end

  def div(num1, num2, precision // 0) do
    dec(coef: coef1, exp: exp1) = d1 = new(num1)
    dec(coef: coef2, exp: exp2) = new(num2)

    # TODO
    # Is there a performant way to check if a decimal expansion
    # is non-terminating?
    unless precision > 0,
      do: raise(Error, message: "unlimited precision not supported for division")

    if coef2 == 0, do: raise(Error, message: "division by zero")

    if coef1 == 0 do
      d1
    else
      sign = div_sign(coef1, coef2)
      prec10 = int_pow10(1, precision-1)

      { coef1, coef2, adjust } = div_adjust(Kernel.abs(coef1), Kernel.abs(coef2), 0)
      { coef, adjust, _rem } = div_calc(coef1, coef2, 0, adjust, prec10)
      dec(coef: sign * coef, exp: exp1 - exp2 - adjust)
    end
  end

  def div_int(num1, num2) do
    div_rem(num1, num2) |> elem(0)
  end

  def rem(num1, num2) do
    div_rem(num1, num2) |> elem(1)
  end

  def div_rem(num1, num2) do
    dec(coef: coef1, exp: exp1) = d1 = new(num1)
    dec(coef: coef2, exp: exp2) = d2 = new(num2)
    abs_coef1 = Kernel.abs(coef1)
    abs_coef2 = Kernel.abs(coef2)

    if compare(dec(d1, coef: abs_coef1), dec(d2, coef: abs_coef2)) == -1 do
      { dec(coef: 0, exp: 0), d1 }
    else
      div_sign = div_sign(coef1, coef2)
      rem_sign = if coef1 < 0, do: -1, else: 1
      { coef1, coef2, adjust } = div_adjust(abs_coef1, abs_coef2, 0)

      adjust2 = if adjust < 0, do: 0, else: adjust
      { coef, rem } = div_int_calc(coef1, coef2, 0, adjust)
      { coef, exp } = truncate(coef, exp1 - exp2 - adjust2)

      adjust3 = if adjust > 0, do: 0, else: adjust
      { dec(coef: div_sign * coef, exp: exp),
        dec(coef: rem_sign * int_pow10(rem, adjust3), exp: 0) }
    end
  end

  def max(num1, num2) do
    d1 = new(num1)
    d2 = new(num2)
    if compare(d1, d2) == -1, do: d2, else: d1
  end

  def min(num1, num2) do
    d1 = new(num1)
    d2 = new(num2)
    if compare(d1, d2) == 1, do: d2, else: d1
  end

  def minus(num) do
    dec(coef: coef) = d = new(num)
    dec(d, coef: -coef)
  end

  def mult(num1, num2) do
    dec(coef: coef1, exp: exp1) = new(num1)
    dec(coef: coef2, exp: exp2) = new(num2)

    dec(coef: coef1 * coef2, exp: exp1 + exp2)
  end

  def reduce(num) do
    dec(coef: coef, exp: exp) = new(num)
    if coef == 0 do
      dec(coef: 0, exp: 0)
    else
      do_reduce(coef, exp)
    end
  end

  def precision(num, precision, rounding) do
    dec(coef: coef, exp: exp) = d = new(num)

    if precision > 0 do
      sign = if coef < 0, do: -1, else: 1
      coef = Kernel.abs(coef)
      prec10 = int_pow10(1, precision)
      do_precision(coef, exp, sign, prec10, rounding)
    else
      d
    end
  end

  def round(num, n // 0, mode // :half_up) do
    dec(coef: coef, exp: exp) = reduce(num)
    sign = if coef < 0, do: -1, else: 1
    coef = Kernel.abs(coef)
    do_round(coef, exp, sign, -n, mode)
  end

  def new(dec() = d),
    do: d
  def new(int) when is_integer(int),
    do: dec(coef: int)
  def new(float) when is_float(float),
    do: new(float_to_binary(float))
  def new(binary) when is_binary(binary),
    do: parse(binary)
  def new(_),
    do: raise ArgumentError

  def coef(num) do
    dec(coef: coef) = new(num)
    coef
  end

  def exp(num) do
    dec(exp: exp) = new(num)
    exp
  end

  def frac(num) do
    dec(coef: coef, exp: exp) = new(num)
    if exp < 0 do
      coef = calc_frac(Kernel.abs(coef), exp, 0, 1)
      dec(coef: coef, exp: exp)
    else
      dec(coef: 0, exp: 0)
    end
  end

  def to_string(num, type // :normal)

  def to_string(num, :normal) do
    dec(coef: coef, exp: exp) = new(num)
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
    dec(coef: coef, exp: exp) = new(num)
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

  def to_string(num, :simple) do
    dec(coef: coef, exp: exp) = new(num)
    str = integer_to_binary(coef)

    if exp != 0 do
      str <> "e" <> integer_to_binary(exp)
    else
      str
    end
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
    do: { coef1 * int_pow10(1, exp1 - exp2), coef2 }

  defp add_align(coef1, exp1, coef2, exp2) when exp1 < exp2,
    do: { coef1, coef2 * int_pow10(1, exp2 - exp1) }

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
    do: truncate(Kernel.div(coef, 10), exp + 1)

  defp do_reduce(0, _exp) do
    dec(coef: 0, exp: 0)
  end

  defp do_reduce(coef, exp) do
    if Kernel.rem(coef, 10) == 0 do
      do_reduce(Kernel.div(coef, 10), exp + 1)
    else
      dec(coef: coef, exp: exp)
    end
  end

  defp int_pow10(num, 0),
    do: num
  defp int_pow10(num, pow) when pow > 0,
    do: int_pow10(10 * num, pow - 1)
  defp int_pow10(num, pow) when pow < 0,
    do: int_pow10(Kernel.div(num, 10), pow + 1)

  def calc_frac(_coef, 0, frac, _fexp), do: frac

  def calc_frac(coef, exp, frac, fexp) do
    frac = frac + fexp * Kernel.rem(coef, 10)
    calc_frac(Kernel.div(coef, 10), exp + 1, frac, fexp * 10)
  end

  ## ROUNDING ##

  defp do_precision(coef, exp, sign, prec10, rounding) when coef >= prec10 do
    significant = Kernel.div(coef, 10)
    remainder = Kernel.rem(coef, 10)
    if increment?(rounding, sign, significant, remainder),
      do: significant = significant + 1

    do_precision(significant, exp + 1, sign, prec10, rounding)
  end

  defp do_precision(coef, exp, sign, _prec10, _rounding) do
    dec(coef: sign * coef, exp: exp)
  end

  defp do_round(coef, exp, sign, n, rounding) when n > exp do
    significant = Kernel.div(coef, 10)
    remainder = Kernel.rem(coef, 10)
    if increment?(rounding, sign, significant, remainder),
      do: significant = significant + 1

    do_round(significant, exp + 1, sign, n, rounding)
  end

  defp do_round(coef, exp, sign, _n, _rounding) do
    dec(coef: sign * coef, exp: exp)
  end

  defp increment?(:truncate, _, _, _),
    do: false

  defp increment?(:ceiling, sign, _, remain),
    do: sign == 1 and remain != 0

  defp increment?(:floor, sign, _, remain),
    do: sign == -1 and remain != 0

  defp increment?(:half_up, sign, _, remain),
    do: sign == 1 and remain >= 5

  defp increment?(:half_away_zero, _, _, remain),
    do: remain >= 5

  defp increment?(:half_even, _, signif, remain),
    do: remain > 5 or (remain == 5 and Kernel.rem(signif, 2) == 1)

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
