defmodule Decimal do
  import Kernel, except: [abs: 1, div: 2, max: 2, min: 2, rem: 1, round: 1]

  defexception Error, [:message]
  defrecord Context, [:precision, :rounding]

  defrecordp :dec, __MODULE__, [sign: 1, coef: 0, exp: 0]

  @context_key :"$decimal_context"

  def abs(dec() = d) do
    dec(d, sign: 1) |> context
  end

  def add(dec(sign: sign1, coef: coef1, exp: exp1), dec(sign: sign2, coef: coef2, exp: exp2)) do
    { coef1, coef2 } = add_align(coef1, exp1, coef2, exp2)
    coef = sign1 * coef1 + sign2 * coef2
    exp = Kernel.min(exp1, exp2)
    sign = add_sign(sign1, sign2, coef)
    dec(sign: sign, coef: Kernel.abs(coef), exp: exp) |> context
  end

  def sub(num1, dec(coef: coef2) = d2) do
    add(num1, dec(d2, coef: -coef2))
  end

  def compare(num1, num2) do
    case sub(num1, num2) do
      dec(coef: 0) -> 0
      dec(sign: sign) -> sign
    end
  end

  def div(dec(sign: sign1, coef: coef1, exp: exp1) = d1, dec(sign: sign2, coef: coef2, exp: exp2)) do
    if coef2 == 0, do: raise(Error, message: "division by zero")

    if coef1 == 0 do
      d1 |> context
    else
      sign = if sign1 == sign2, do: 1, else: -1
      context = Context[] = get_context
      prec10 = int_pow10(1, context.precision-1)

      { coef1, coef2, adjust } = div_adjust(coef1, coef2, 0)
      { coef, adjust, _rem } = div_calc(coef1, coef2, 0, adjust, prec10)
      dec(sign: sign, coef: coef, exp: exp1 - exp2 - adjust) |> context
    end
  end

  def div_int(num1, num2) do
    div_rem(num1, num2) |> elem(0)
  end

  def rem(num1, num2) do
    div_rem(num1, num2) |> elem(1)
  end

  def div_rem(dec(sign: sign1, coef: coef1, exp: exp1) = d1, dec(sign: sign2, coef: coef2, exp: exp2) = d2) do
    if compare(dec(d1, sign: 1), dec(d2, sign: 1)) == -1 do
      { dec(sign: 1, coef: 0, exp: 0), d1 }
    else
      div_sign = if sign1 == sign2, do: 1, else: -1
      { coef1, coef2, adjust } = div_adjust(coef1, coef2, 0)

      adjust2 = if adjust < 0, do: 0, else: adjust
      { coef, rem } = div_int_calc(coef1, coef2, 0, adjust)
      { coef, exp } = truncate(coef, exp1 - exp2 - adjust2)

      adjust3 = if adjust > 0, do: 0, else: adjust
      { dec(sign: div_sign, coef: coef, exp: exp) |> context,
        dec(sign: sign1, coef: int_pow10(rem, adjust3), exp: 0) |> context }
    end
  end

  def max(num1, num2) do
    context(if compare(num1, num2) == -1, do: num2, else: num1)
  end

  def min(num1, num2) do
    context(if compare(num1, num2) == 1, do: num2, else: num1)
  end

  def minus(dec(sign: sign) = d) do
    dec(d, sign: -sign) |> context
  end

  def mult(dec(sign: sign1, coef: coef1, exp: exp1), dec(sign: sign2, coef: coef2, exp: exp2)) do
    sign = if sign1 == sign2, do: 1, else: -1
    dec(sign: sign, coef: coef1 * coef2, exp: exp1 + exp2) |> context
  end

  def reduce(dec(sign: sign, coef: coef, exp: exp)) do
    if coef == 0 do
      dec(coef: 0, exp: 0)
    else
      dec(do_reduce(coef, exp), sign: sign) |> context
    end
  end

  def round(num, n // 0, mode // :half_up) do
    dec(sign: sign, coef: coef, exp: exp) = reduce(num)
    do_round(coef, exp, sign, -n, mode) |> context
  end

  def new(dec() = d),
    do: d
  def new(int) when is_integer(int),
    do: dec(sign: (if int < 0, do: -1, else: 1), coef: Kernel.abs(int))
  def new(float) when is_float(float),
    do: new(:io_lib_format.fwrite_g(float) |> iolist_to_binary)
  def new(binary) when is_binary(binary),
    do: parse(binary)
  def new(_),
    do: raise ArgumentError

  def frac(dec(coef: coef, exp: exp) = d) do
    if exp < 0 do
      coef = calc_frac(coef, exp, 0, 1)
      dec(d, sign: 1, coef: coef) |> context
    else
      dec(sign: 1, coef: 0, exp: 0)
    end
  end

  def to_string(num, type // :normal)

  def to_string(dec(sign: sign, coef: coef, exp: exp), :normal) do
    list = integer_to_list(coef)

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

    if sign == -1 do
      list = [?-|list]
    end

    iolist_to_binary(list)
  end

  def to_string(dec(sign: sign, coef: coef, exp: exp), :scientific) do
    list = integer_to_list(coef)

    { list, exp_offset } = trim_coef(list)
    exp = exp + exp_offset
    length = length(list)

    if length > 1 do
      list = List.insert_at(list, 1, ?.)
      exp = exp + length - 1
    end

    list = list ++ 'e' ++ integer_to_list(exp)

    if sign == -1 do
      list = [?-|list]
    end

    iolist_to_binary(list)
  end

  def to_string(dec(sign: sign, coef: coef, exp: exp), :simple) do
    str = integer_to_binary(sign * coef)

    if exp != 0 do
      str <> "e" <> integer_to_binary(exp)
    else
      str
    end
  end

  def with_context(Context[] = context, fun) when is_function(fun, 0) do
    old = set_context(context)
    try do
      fun.()
    after
      set_context(old)
    end
  end

  def get_context do
    Process.get(@context_key, default_context)
  end

  def set_context(context) do
    Process.put(@context_key, context)
  end

  def default_context do
    Context[precision: 9, rounding: :half_up]
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

  defp add_sign(sign1, sign2, coef) do
    cond do
      coef > 0 -> 1
      coef < 0 -> -1
      sign1 == -1 and sign2 == -1 -> -1
      sign1 != sign2 and (Context[] = get_context).rounding == :floor -> -1
      true -> 1
    end
  end

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

  defp do_round(coef, exp, sign, n, rounding) when n > exp do
    significant = Kernel.div(coef, 10)
    remainder = Kernel.rem(coef, 10)
    if increment?(rounding, sign, significant, remainder),
      do: significant = significant + 1

    do_round(significant, exp + 1, sign, n, rounding)
  end

  defp do_round(coef, exp, sign, _n, _rounding) do
    dec(sign: sign, coef: coef, exp: exp)
  end

  defp precision(dec(sign: sign, coef: coef, exp: exp), precision, rounding) do
    prec10 = int_pow10(1, precision)
    do_precision(coef, exp, sign, prec10, rounding)
  end

  defp do_precision(coef, exp, sign, prec10, rounding) when coef >= prec10 do
    significant = Kernel.div(coef, 10)
    remainder = Kernel.rem(coef, 10)
    if increment?(rounding, sign, significant, remainder),
      do: significant = significant + 1

    do_precision(significant, exp + 1, sign, prec10, rounding)
  end

  defp do_precision(coef, exp, sign, _prec10, _rounding) do
    dec(sign: sign, coef: coef, exp: exp)
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

  ## CONTEXT ##

  defp context(num) do
    ctxt = Context[] = get_context
    precision(num, ctxt.precision, ctxt.rounding)
  end

  ## PARSING ##

  defp parse("+" <> bin) do
    parse_unsign(bin)
  end

  defp parse("-" <> bin) do
    d = parse_unsign(bin)
    dec(d, sign: -1)
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

defimpl Inspect, for: Decimal do
  def inspect(dec, _opts) do
    "#Decimal<" <> Decimal.to_string(dec, :simple) <> ">"
  end
end

defimpl String.Chars, for: Decimal do
  def to_string(dec) do
    Decimal.to_string(dec)
  end
end
