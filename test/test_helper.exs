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
end
