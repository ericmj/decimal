defmodule Decimal.Record do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      defrecordp :dec, unquote(__MODULE__), [coef: 0, exp: 0]
    end
  end
end

defimpl Inspect, for: Decimal.Record do
  def inspect(dec, _opts) do
    "#Decimal<" <> Decimal.to_string(dec, :simple) <> ">"
  end
end

defimpl String.Chars, for: Decimal.Record do
  def to_string(dec, _opts) do
    Decimal.to_string(dec)
  end
end
