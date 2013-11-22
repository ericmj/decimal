defmodule Decimal.Util do
  @moduledoc false

  def int_pow10(num, 0), do: num
  def int_pow10(num, pow) when pow > 0, do: int_pow10(10 * num, pow - 1)
  def int_pow10(num, pow) when pow < 0, do: int_pow10(div(num, 10), pow + 1)
end
