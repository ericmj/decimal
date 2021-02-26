if Version.compare(System.version(), "1.11.0") != :lt do
  if String.to_integer(apply(System, :otp_release, [])) > 22 do
    defmodule DecimalGuardsTest do
      use ExUnit.Case, async: true

      require Decimal
      import Decimal.Guards

      doctest Decimal.Guards
    end
  end
end
