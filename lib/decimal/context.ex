defrecord Decimal.Context, [precision: 0, rounding: :half_up] do
  @moduledoc false

  record_type precision: non_neg_integer
  record_type rounding: :truncate | :ceiling | :floor | :half_up | :half_away_zero | :half_even

  alias __MODULE__
  alias Decimal.Util
  use Decimal.Record

  defmacro unlimited, do: quote(do: Context[precision: 0, rounding: :half_up])

  def round(dec(coef: coef, exp: exp) = d, Context[] = c) do
    if c.precision > 0 do
      sign = if coef < 0, do: -1, else: 1
      coef = abs(coef)
      prec10 = Util.int_pow10(1, c.precision)
      do_round(coef, exp, sign, prec10, c.rounding)
    else
      d
    end
  end

  defp do_round(coef, exp, sign, prec10, rounding) do
    if coef >= prec10 do
      significant = div(coef, 10)
      remainder = rem(coef, 10)
      if increment?(rounding, sign, significant, remainder),
        do: significant = significant + 1
      do_round(significant, exp + 1, sign, prec10, rounding)
    else
      dec(coef: sign * coef, exp: exp)
    end
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
    do: remain > 5 or (remain == 5 and rem(signif, 2) == 1)
end
