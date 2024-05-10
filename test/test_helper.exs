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
