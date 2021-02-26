if String.to_integer(System.otp_release()) > 22 and
     Version.compare(System.version(), "1.11.0") != :lt do
  defmodule DecimalGuardsTest do
    use ExUnit.Case, async: true

    require Decimal
    import Decimal.Guards

    doctest Decimal.Guards
  end
end
