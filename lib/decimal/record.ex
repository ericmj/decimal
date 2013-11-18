defmodule Decimal.Record do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      defrecordp :dec, unquote(__MODULE__), [coef: 0, exp: 0]
    end
  end
end
