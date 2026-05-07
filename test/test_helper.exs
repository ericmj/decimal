ExUnit.start()

defmodule TestMacros do
  defmacro d(sign, coef, exp) do
    quote do
      %Decimal{sign: unquote(sign), coef: unquote(coef), exp: unquote(exp)}
    end
  end

  defmacro sigil_d(str, _opts) do
    quote do
      Decimal.new(unquote(str))
    end
  end

  defmacro dbl_min(sign) do
    quote do
      %Decimal{sign: unquote(sign), coef: 22_250_738_585_072_014, exp: -324}
    end
  end

  defmacro zero(sign) do
    quote do
      %Decimal{sign: unquote(sign), coef: 0, exp: 0}
    end
  end

  defmacro dbl_max(sign) do
    quote do
      %Decimal{sign: unquote(sign), coef: 17_976_931_348_623_158, exp: 292}
    end
  end
end

defmodule DecimalGenerators do
  @moduledoc """
  StreamData generators for `%Decimal{}` values.

  Defaults stay well inside the decimal128 context bounds so arithmetic
  operations don't trigger overflow/underflow signals during property runs.
  Tune `coef_max` / `exp_min` / `exp_max` per property when a wider or
  narrower domain is needed.
  """

  @default_coef_max 10_000_000_000_000_000
  @default_exp_min -100
  @default_exp_max 100

  def decimal(opts \\ []) do
    build(0, opts)
  end

  def non_zero_decimal(opts \\ []) do
    build(1, opts)
  end

  def non_negative_decimal(opts \\ []) do
    build(0, Keyword.put(opts, :signs, [1]))
  end

  def positive_decimal(opts \\ []) do
    build(1, Keyword.put(opts, :signs, [1]))
  end

  defp build(coef_min, opts) do
    coef_max = Keyword.get(opts, :coef_max, @default_coef_max)
    exp_min = Keyword.get(opts, :exp_min, @default_exp_min)
    exp_max = Keyword.get(opts, :exp_max, @default_exp_max)
    signs = Keyword.get(opts, :signs, [1, -1])

    {StreamData.member_of(signs), StreamData.integer(coef_min..coef_max),
     StreamData.integer(exp_min..exp_max)}
    |> StreamData.tuple()
    |> StreamData.map(fn {sign, coef, exp} ->
      %Decimal{sign: sign, coef: coef, exp: exp}
    end)
  end
end
