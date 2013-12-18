defmodule Decimal do
  @moduledoc """
  Decimal arithmetic on arbitrary precision floating-point numbers.

  A number is represented by a signed coefficient and exponent such that: `sign
  * coefficient * 10^exponent`. All numbers are represented and calculated
  exactly, but the result of an operation may be rounded depending on the
  context the operation is performed with, see: `Decimal.Context`. Trailing
  zeros in the coefficient are never truncated to preserve the number of
  significant digits unless explicitly done so.

  There are also special values such as NaN and (+-)Infinity. -0 and +0 are two
  distinct values.

  Exceptional conditions are grouped into signals, each signal has a flag and a
  trap enabler in the context. Whenever a signal is triggered it's flag is set
  in the context and will be set until explicitly cleared. If the signal is trap
  enabled `Decimal.Error` will be raised.

  The specifications influencing the API:
  * [IBM's General Decimal Arithmetic Specification](http://speleotrove.com/decimal/decarith.html)
  * [IEEE standard 854-1987](http://754r.ucbtest.org/standards/854.pdf)
  """

  @opaque t :: { Decimal, 1 | -1, non_neg_integer, integer }

  @type signal :: :invalid_operation |
                  :division_by_zero |
                  :rounded |
                  :inexact

  @type rounding :: :down |
                    :half_up |
                    :half_even |
                    :ceiling |
                    :floor |
                    :half_down |
                    :up

  import Kernel, except: [abs: 1, div: 2, max: 2, min: 2, rem: 1, round: 1]

  defrecordp :dec, __MODULE__, [sign: 1, coef: 0, exp: 0]

  @context_key :"$decimal_context"

  defexception Error, [:signal, :reason, :result] do
    @moduledoc """
    The exception that all Decimal operations may raise.

    ## Fields

    * `signal` - The signalled error, additional signalled errors will be found
      in the context.
    * `reason` - The reason for the error.
    * `result` - The result of the operation signalling the error.

    Rescuing the error to access the result or the other fields of the error is
    discouraged and should only be done for exceptional conditions. It is more
    pragmatic to set the appropriate traps on the context and check the flags
    after the operation if the result needs to be inspected.
    """

    record_type signal: Decimal.signal,
                reason: String.t,
                result: Decimal.t

    def message(Error[signal: signal, reason: reason]) do
      if reason do
        "#{signal}: #{reason}"
      else
        "#{signal}"
      end
    end
  end

  defrecord Context,
      precision: 9,
      rounding: :half_up,
      flags: [],
      traps: [:invalid_operation, :division_by_zero] do
    @moduledoc """
    The context is kept in the process dictionary. It can be accessed with
    `Decimal.get_context/0` and `Decimal.set_context/1`.

    ## Fields

    * `precision` - Maximum number of decimal digits in the coefficient. If an
      operation's result has more digits it will be rounded to `precision`
      digits with the rounding algorithm in `rounding`.
    * `rounding` - The rounding algorithm used when the coefficient's number of
      exceeds `precision`. Strategies explained below.
    * `flags` - A list of signals that for which the flag is sent. When an
      exceptional condition is signalled it's flag is set. The flags are sticky
      and will be set until explicitly cleared.
    * `traps` - A list of set trap enablers for signals. When a signal's trap
      enabler is set the condition causes `Decimal.Error` to be raised.

    ## Rounding algorithms

    * `:down` - Round toward zero (truncate). Discarded digits are ignored,
      result is unchanged.
    * `:half_up` - If the discarded digits is greater than or equal to half of
      the value of a one in the next left position then the coefficient will be
      incremented by one (rounded up). Otherwise, the discarded digits will be
      ignored.
    * `:half_even` - Also known as "round to nearest" or "banker's rounding". If
      the discarded digits is greater than half of the value of a one in the
      next left position then the coefficient will be incremented by one
      (rounded up). If they represent less than half discarded digits will be
      ignored. Otherwise (exactly half), the coefficient is not altered if it's
      even, or incremented by one (rounded up) if it's odd (to make an even
      number).
    * `:ceiling` - Round toward +Infinity. If all of the discarded digits are
      zero or the sign is negative the result is unchanged. Otherwise, the
      coefficient will be incremented by one (rounded up).
    * `:floor` - Round toward -Infinity. If all of the discarded digits are zero
      or the sign is positive the result is unchanged. Otherwise, the sign is
      negative and coefficient will be incremented by one.
    * `:half_down` - If the discarded digits is greater than half of the value
      of a one in the next left position then the coefficient will be
      incremented by one (rounded up). Otherwise the discarded digits are
      ignored.
    * `:up` - Round away from zero. If all discarded digits are zero the
      coefficient is not changed, otherwise it is incremented by one (rounded
      up).
    """

    record_type precision: pos_integer,
                rounding: Decimal.rounding,
                flags: [Decimal.signal],
                traps: [Decimal.signal]
  end

  defmacrop error(flags, reason, result, context // nil) do
    quote bind_quoted: binding do
      case handle_error(flags, reason, result, context) do
        { :ok, result } -> result
        { :error, error } -> raise Error, error
      end
    end
  end

  defmacro is_nan(d) do
    quote do
      dec(unquote(d), :coef) in [:sNaN, :qNaN]
    end
  end

  defmacrop is_qnan(d) do
    quote do
      dec(unquote(d), :coef) == :qNaN
    end
  end

  defmacrop is_snan(d) do
    quote do
      dec(unquote(d), :coef) == :sNaN
    end
  end

  defmacro is_inf(d) do
    quote do
      dec(unquote(d), :coef) == :inf
    end
  end

  def abs(dec(coef: :sNaN) = d) do
    error(:invalid_operation, "operation on NaN", d)
  end

  def abs(dec(coef: :qNaN) = d) do
    d
  end

  def abs(dec() = d) do
    dec(d, sign: 1) |> context
  end

  def add(dec() = d1, dec() = d2) when is_snan(d1) or is_snan(d2) do
    error(:invalid_operation, "operation on NaN", first_nan(d1, d2))
  end

  def add(dec() = d1, dec() = d2) when is_qnan(d1) or is_qnan(d2) do
    first_nan(d1, d2)
  end

  def add(dec(coef: coef1) = d1, dec(coef: coef2) = d2) when is_inf(d1) or is_inf(d2) do
    cond do
      coef1 == coef2 ->
        error(:invalid_operation, "-Infinity + Infinity", dec(coef: :NaN))
      coef1 == :inf ->
        d1
      coef2 == :inf ->
        d2
    end
  end

  def add(dec(sign: sign1, coef: coef1, exp: exp1), dec(sign: sign2, coef: coef2, exp: exp2)) do
    { coef1, coef2 } = add_align(coef1, exp1, coef2, exp2)
    coef = sign1 * coef1 + sign2 * coef2
    exp = Kernel.min(exp1, exp2)
    sign = add_sign(sign1, sign2, coef)
    dec(sign: sign, coef: Kernel.abs(coef), exp: exp) |> context
  end

  def sub(num1, dec(sign: sign) = d2) do
    add(num1, dec(d2, sign: -sign))
  end

  def compare(dec(coef: coef1) = num1, dec(coef: coef2) = num2) do
    cond do
      coef1 == :qNaN ->
        num1
      coef2 == :qNaN ->
        num2
      true ->
        case sub(num1, num2) do
          dec(coef: 0) -> dec(sign: 1)
          dec(sign: sign) -> dec(sign: sign, coef: 1)
        end
    end
  end

  def div(dec() = d1, dec() = d2) when is_snan(d1) or is_snan(d2) do
    error(:invalid_operation, "operation on NaN", first_nan(d1, d2))
  end

  def div(dec() = d1, dec() = d2) when is_qnan(d1) or is_qnan(d2) do
    first_nan(d1, d2)
  end

  def div(dec(sign: sign1, coef: coef1, exp: exp1) = d1, dec(sign: sign2, coef: coef2, exp: exp2) = d2)
      when is_inf(d1) or is_inf(d2) do
    sign = if sign1 == sign2, do: 1, else: -1

    cond do
      coef1 == coef2 ->
        error(:invalid_operation, "(+-)Infinity / (+-)Infinity", dec(coef: :NaN))
      coef1 == :inf ->
        dec(d1, sign: sign)
      coef2 == :inf ->
        # TODO: Subnormal
        # exponent?
        dec(sign: sign, coef: 0, exp: exp1 - exp2)
    end
  end

  def div(dec(coef: 0), dec(coef: 0)) do
    error(:invalid_operation, "0 / 0", dec(coef: :NaN))
  end

  def div(dec(sign: sign1, coef: coef1, exp: exp1), dec(sign: sign2, coef: coef2, exp: exp2)) do
    sign = if sign1 == sign2, do: 1, else: -1

    if coef2 == 0 do
      error(:division_by_zero, nil, dec(sign: sign, coef: :inf))
    else
      if coef1 == 0 do
        coef = 0
        adjust = 0
        signals = []
      else
        context = Context[] = get_context
        prec10 = int_pow10(1, context.precision-1)

        { coef1, coef2, adjust } = div_adjust(coef1, coef2, 0)
        { coef, adjust, _rem, signals } = div_calc(coef1, coef2, 0, adjust, prec10)
      end

      dec(sign: sign, coef: coef, exp: exp1 - exp2 - adjust) |> context(signals)
    end
  end

  def div_int(num1, num2) do
    div_rem(num1, num2) |> elem(0)
  end

  def rem(num1, num2) do
    div_rem(num1, num2) |> elem(1)
  end

  def div_rem(dec() = d1, dec() = d2) when is_snan(d1) or is_snan(d2) do
    d = first_nan(d1, d2)
    { error(:invalid_operation, "operation on NaN", d),
      error(:invalid_operation, "operation on NaN", d) }
  end

  def div_rem(dec() = d1, dec() = d2) when is_qnan(d1) or is_qnan(d2) do
    d = first_nan(d1, d2)
    { d, d }
  end

  def div_rem(dec(sign: sign1, coef: coef1, exp: exp1) = d1, dec(sign: sign2, coef: coef2, exp: exp2) = d2)
      when is_inf(d1) or is_inf(d2) do
    sign = if sign1 == sign2, do: 1, else: -1

    cond do
      coef1 == coef2 ->
        error(:invalid_operation, "(+-)Infinity / (+-)Infinity", { dec(coef: :NaN), dec(coef: :NaN) })
      coef1 == :inf ->
        { dec(d1, sign: sign), dec(sign: sign1, coef: 0) }
      coef2 == :inf ->
        # TODO: Subnormal
        # exponent?
        { dec(sign: sign, coef: 0, exp: exp1 - exp2), dec(d2, sign: sign1) }
    end
  end

  def div_rem(dec(coef: 0), dec(coef: 0)) do
    { error(:invalid_operation, "0 / 0", dec(coef: :NaN)),
      error(:invalid_operation, "0 / 0", dec(coef: :NaN)) }
  end

  def div_rem(dec(sign: sign1, coef: coef1, exp: exp1) = d1, dec(sign: sign2, coef: coef2, exp: exp2) = d2) do
    div_sign = if sign1 == sign2, do: 1, else: -1

    if compare(dec(d1, sign: 1), dec(d2, sign: 1)) == -1 do
      { dec(sign: div_sign, coef: 0, exp: exp1 - exp2), d1 }
    else
      if coef1 == 0 do
        { dec(d1, sign: div_sign) |> context,
          dec(d2, sign: sign1) |> context }
      else
        { coef1, coef2, adjust } = div_adjust(coef1, coef2, 0)

        adjust2 = if adjust < 0, do: 0, else: adjust
        { coef, rem } = div_int_calc(coef1, coef2, 0, adjust)
        { coef, exp } = truncate(coef, exp1 - exp2 - adjust2)

        div_coef = int_pow10(coef, exp)
        context = Context[] = get_context
        prec10 = int_pow10(1, context.precision-1)

        if div_coef > prec10 do
          error(:invalid_operation, "integer division impossible, quotient too large", dec(coef: :NaN))
        else
          adjust3 = if adjust > 0, do: 0, else: adjust
          { dec(sign: div_sign, coef: div_coef) |> context,
            dec(sign: sign1, coef: rem, exp: adjust3) |> context }
        end
      end
    end
  end

  def max(dec(coef: coef1) = num1, dec(coef: coef2) = num2) do
    cond do
      coef1 == :qNaN ->
        num2
      coef2 == :qNaN ->
        num1
      true ->
        context(if match?(dec(sign: -1), compare(num1, num2)), do: num2, else: num1)
    end
  end

  def min(dec(coef: coef1) = num1, dec(coef: coef2) = num2) do
    cond do
      coef1 == :qNaN ->
        num2
      coef2 == :qNaN ->
        num1
      true ->
        context(if match?(dec(sign: 1), compare(num1, num2)), do: num2, else: num1)
    end
  end

  def minus(dec(coef: :sNaN) = d) do
    error(:invalid_operation, "operation on NaN", d)
  end

  def minus(dec(coef: :qNaN) = d) do
    d
  end

  def minus(dec(sign: sign) = d) do
    dec(d, sign: -sign) |> context
  end

  def plus(dec(coef: :sNaN) = d) do
    error(:invalid_operation, "operation on NaN", d)
  end

  def plus(dec() = d) do
    context(d)
  end

  def mult(dec() = d1, dec() = d2) when is_snan(d1) or is_snan(d2) do
    error(:invalid_operation, "operation on NaN", first_nan(d1, d2))
  end

  def mult(dec() = d1, dec() = d2) when is_qnan(d1) or is_qnan(d2) do
    first_nan(d1, d2)
  end

  def mult(dec(sign: sign1, coef: coef1, exp: exp1) = d1, dec(sign: sign2, coef: coef2, exp: exp2) = d2)
      when is_inf(d1) or is_inf(d2) do

    if coef1 == 0 or coef2 == 0 do
      error(:invalid_operation, "0 * (+-)Infinity", dec(coef: :NaN))
    else
      sign = if sign1 == sign2, do: 1, else: -1
      # exponent?
      dec(sign: sign, coef: :inf, exp: exp1 + exp2)
    end
  end

  def mult(dec(sign: sign1, coef: coef1, exp: exp1), dec(sign: sign2, coef: coef2, exp: exp2)) do
    sign = if sign1 == sign2, do: 1, else: -1
    dec(sign: sign, coef: coef1 * coef2, exp: exp1 + exp2) |> context
  end

  def reduce(dec(coef: :sNaN) = d) do
    error(:invalid_operation, "operation on NaN", d)
  end

  def reduce(dec(coef: :qNaN) = d) do
    d
  end

  def reduce(dec(coef: :inf) = d) do
    # exponent?
    dec(d, exp: 0)
  end

  def reduce(dec(sign: sign, coef: coef, exp: exp)) do
    if coef == 0 do
      dec(sign: sign, coef: 0, exp: 0)
    else
      dec(do_reduce(coef, exp), sign: sign) |> context
    end
  end

  def round(dec(coef: :sNaN) = d) do
    error(:invalid_operation, "operation on NaN", d)
  end

  def round(dec(coef: :qNaN) = d) do
    d
  end

  def round(dec(coef: :inf) = d) do
    d
  end

  def round(num, n // 0, mode // :half_up) do
    dec(sign: sign, coef: coef, exp: exp) = reduce(num)
    { value, signals } = do_round(coef, exp, sign, -n, mode, [])
    context(value, signals)
  end

  def new(dec() = d),
    do: d
  def new(int) when is_integer(int),
    do: dec(sign: (if int < 0, do: -1, else: 1), coef: Kernel.abs(int))
  def new(float) when is_float(float),
    do: new(:io_lib_format.fwrite_g(float) |> iolist_to_binary)
  def new(binary) when is_binary(binary),
    do: parse(binary)

  def to_string(num, type // :scientific)

  def to_string(dec(sign: sign, coef: :qNaN), _type) do
    if sign == 1, do: "NaN", else: "-NaN"
  end

  def to_string(dec(sign: sign, coef: :sNaN), _type) do
    if sign == 1, do: "sNaN", else: "-sNaN"
  end

  def to_string(dec(sign: sign, coef: :inf), _type) do
    if sign == 1, do: "Infinity", else: "-Infinity"
  end

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
    length = length(list)
    adjusted = exp + length - 1

    cond do
      exp == 0 ->
        :ok

      exp < 0 and adjusted >= -6 ->
        abs_exp = Kernel.abs(exp)
        diff = -length + abs_exp + 1
        if diff > 0 do
          list = :lists.duplicate(diff, ?0) ++ list
          list = List.insert_at(list, 1, ?.)
        else
          list = List.insert_at(list, abs_exp + 1, ?.)
        end

      true ->
        if length > 2 do
          list = List.insert_at(list, 1, ?.)
        end
        list = list ++ 'E'
        if exp >= 0, do: list = list ++ '+'
        list = list ++ integer_to_list(adjusted)
    end

    if sign == -1 do
      list = [?-|list]
    end

    iolist_to_binary(list)
  end

  def to_string(dec(sign: sign, coef: coef, exp: exp), :raw) do
    str = integer_to_binary(coef)

    if sign == -1 do
      str = [?-|str]
    end

    if exp != 0 do
      str = [str, "E", integer_to_binary(exp)]
    end

    iolist_to_binary(str)
  end

  def with_context(Context[] = context, fun) when is_function(fun, 0) do
    old = set_context(context)
    try do
      fun.()
    after
      if old, do: set_context(old)
    end
  end

  def get_context do
    Process.get(@context_key, Context[])
  end

  def set_context(Context[] = context) do
    Process.put(@context_key, context)
  end

  def update_context(fun) when is_function(fun, 1) do
    get_context |> fun.() |> set_context
  end

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

      coef1 == 0 and adjust >= 0 ->
        { coef, adjust, coef1, [] }

      coef >= prec10 ->
        signals = [:rounded]
        unless base_10?(coef1), do: signals = [:inexact|signals]
        { coef, adjust, coef1, signals }

      true ->
        div_calc(coef1 * 10, coef2, coef * 10, adjust + 1, prec10)
    end
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

  defp base_10?(1), do: true

  defp base_10?(num) do
    if Kernel.rem(num, 10) == 0 do
      base_10?(Kernel.div(num, 10))
    else
      false
    end
  end

  defp truncate(coef, exp) when exp >= 0 do
    { coef, exp }
  end

  defp truncate(coef, exp) when exp < 0 do
    truncate(Kernel.div(coef, 10), exp + 1)
  end

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

  def calc_frac(_coef, 0, frac, _fexp), do: frac

  def calc_frac(coef, exp, frac, fexp) do
    frac = frac + fexp * Kernel.rem(coef, 10)
    calc_frac(Kernel.div(coef, 10), exp + 1, frac, fexp * 10)
  end

  ## ROUNDING ##

  defp do_round(coef, exp, sign, n, rounding, signals) when n > exp do
    significant = Kernel.div(coef, 10)
    remainder = Kernel.rem(coef, 10)
    if increment?(rounding, sign, significant, remainder),
      do: significant = significant + 1

    do_round(significant, exp + 1, sign, n, rounding, signals)
  end

  defp do_round(coef, exp, sign, _n, _rounding, signals) do
    { dec(sign: sign, coef: coef, exp: exp), signals }
  end

  defp precision(dec() = d, _precision, _rounding)
      when is_inf(d) or is_nan(d) do
    { d, [] }
  end

  defp precision(dec(sign: sign, coef: coef, exp: exp), precision, rounding) do
    prec10 = int_pow10(1, precision)
    do_precision(coef, exp, sign, prec10, rounding, [])
  end

  defp do_precision(coef, exp, sign, prec10, rounding, signals) when coef >= prec10 do
    significant = Kernel.div(coef, 10)
    remainder = Kernel.rem(coef, 10)
    if increment?(rounding, sign, significant, remainder),
      do: significant = significant + 1

    signals = put_uniq(signals, :rounded)
    if remainder != 0 do
      signals = put_uniq(signals, :inexact)
    end

    do_precision(significant, exp + 1, sign, prec10, rounding, signals)
  end

  defp do_precision(coef, exp, sign, _prec10, _rounding, signals) do
    { dec(sign: sign, coef: coef, exp: exp), signals }
  end

  defp increment?(:down, _, _, _),
    do: false

  defp increment?(:ceiling, sign, _, remain),
    do: sign == 1 and remain != 0

  defp increment?(:floor, sign, _, remain),
    do: sign == -1 and remain != 0

  defp increment?(:half_up, sign, _, remain),
    do: sign == 1 and remain >= 5

  defp increment?(:half_even, _, signif, remain),
    do: remain > 5 or (remain == 5 and Kernel.rem(signif, 2) == 1)

  defp increment?(:half_down, _, _, remain),
    do: remain >= 5

  defp increment?(:up, _, _, _),
    do: true

  ## CONTEXT ##

  defp context(num, signals // []) do
    ctxt = Context[] = get_context
    { result, prec_signals } = precision(num, ctxt.precision, ctxt.rounding)
    error(put_uniq(signals, prec_signals), nil, result, ctxt)
  end

  defp put_uniq(list, elems) when is_list(elems) do
    Enum.reduce(elems, list, &put_uniq(&2, &1))
  end

  defp put_uniq(list, elem) do
    if elem in list, do: list, else: [elem|list]
  end

  ## PARSING ##

  defp parse("+" <> bin) do
    String.downcase(bin) |> parse_unsign
  end

  defp parse("-" <> bin) do
    d = String.downcase(bin) |> parse_unsign
    dec(d, sign: -1)
  end

  defp parse(bin) do
    String.downcase(bin) |> parse_unsign
  end

  defp parse_unsign("inf") do
    dec(coef: :inf)
  end

  defp parse_unsign("infinity") do
    dec(coef: :inf)
  end

  defp parse_unsign("snan") do
    dec(coef: :sNaN)
  end

  defp parse_unsign("nan") do
    dec(coef: :qNaN)
  end

  defp parse_unsign(bin) do
    { int, rest } = parse_digits(bin)
    { float, rest } = parse_float(rest)
    { exp, rest } = parse_exp(rest)

    if rest != "" or (int == [] and float == []) do
      error(:invalid_operation, "number parsing syntax", dec(coef: :NaN))
    else
      if int == [], do: int = '0'
      if exp == [], do: exp = '0'
      dec(coef: list_to_integer(int ++ float), exp: list_to_integer(exp) - length(float))
    end
  end

  defp parse_float("." <> rest), do: parse_digits(rest)
  defp parse_float(bin), do: { [], bin }

  defp parse_exp(<< ?e, rest :: binary >>) do
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

  # Util

  defp handle_error(signals, reason, result, context) do
    context = Context[] = context || get_context
    signals = List.wrap(signals)

    Enum.reduce(signals, context.flags, &put_uniq(&2, &1))
      |> context.flags
      |> set_context

    error_signal = Enum.find(signals, &(&1 in context.traps))
    nan = if error_signal, do: :sNaN, else: :qNaN

    if match?(dec(coef: :NaN), result) do
      result = dec(result, coef: nan)
    end

    if error_signal do
      error = [signals: error_signal, reason: reason, result: result]
      { :error, error }
    else
      { :ok, result }
    end
  end

  defp first_nan(d1, d2) do
    if is_nan(d1), do: d1, else: d2
  end
end

defimpl Inspect, for: Decimal do
  def inspect(dec, _opts) do
    "#Decimal<" <> Decimal.to_string(dec) <> ">"
  end
end

defimpl String.Chars, for: Decimal do
  def to_string(dec) do
    Decimal.to_string(dec)
  end
end
