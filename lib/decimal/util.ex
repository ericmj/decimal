defmodule Decimal.Util do
  @moduledoc false

  def int_pow10(x) when x >= 0, do: int_pow10(x, 1)
  def int_pow10(0, acc), do: acc
  def int_pow10(x, acc), do: int_pow10(x-1, 10*acc)
end
