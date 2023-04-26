defmodule Decimal.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "compare/2" do
    test "integer equality" do
      check all(
              first <- StreamData.integer(),
              second <- StreamData.integer()
            ) do
        assert Decimal.compare(first, second) == term_compare(first, second)
      end
    end

    test "float equality" do
      check all(
              first <- StreamData.float(),
              second <- StreamData.float()
            ) do
        assert Decimal.compare(to_dec(first), to_dec(second)) == term_compare(first, second)
      end
    end

    test "number equality" do
      check all(
              first <- stream_data_number(),
              second <- stream_data_number()
            ) do
        assert Decimal.compare(to_dec(first), to_dec(second)) == term_compare(first, second)
      end
    end
  end

  defp to_dec(float) when is_float(float), do: Decimal.from_float(float)
  defp to_dec(other), do: Decimal.new(other)

  defp term_compare(first, second) do
    cond do
      first < second -> :lt
      first > second -> :gt
      true -> :eq
    end
  end

  defp stream_data_number() do
    StreamData.one_of([StreamData.integer(), StreamData.float()])
  end
end
