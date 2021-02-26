if Version.compare(System.version(), "1.11.0") != :lt do
  if String.to_integer(System.otp_release()) > 22 do
    defmodule Decimal.Guards do
      @moduledoc since: "2.1.0"
      @moduledoc """
      Set of guards allowing validating `Decimal` values in guards.

      Use `import Decimal.Guards` to use these guards in your module.

      ## Examples

      iex> case {"1", Decimal.cast("1")} do
      ...>   {s, {:ok, d}} when is_decimal_positive(d) and not is_decimal(s) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal`; otherwise returns `false`.

      ## Examples

      iex> case Decimal.cast("1") do
      ...>   {:ok, d} when is_decimal(d) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_decimal(d) when is_map(d) and d.__struct__ == Decimal

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal` and is non-negative; otherwise returns `false`.

      ## Examples

      iex> case Decimal.cast("0") do
      ...>   {:ok, d} when is_decimal_non_negative(d) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_decimal_non_negative(d) when is_decimal(d) and d.sign == 1

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal` and is positive; otherwise returns `false`.

      ## Examples

      iex> case {Decimal.cast("1"), Decimal.cast("0")} do
      ...>   {{:ok, d1}, {:ok, d2}} when is_decimal_positive(d1) and
      ...>                               not is_decimal_positive(d2) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_decimal_positive(d) when is_decimal_non_negative(d) and d.coef != 0

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal` and is negative; otherwise returns `false`.

      ## Examples

      iex> case Decimal.cast("-1") do
      ...>   {:ok, d} when is_decimal_negative(d) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_decimal_negative(d) when is_decimal(d) and d.sign == -1

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal` and is non-negative; otherwise returns `false`.

      ## Examples

      iex> case {0, Decimal.cast("1"), "1"} do
      ...>   {i, {:ok, d}, s} when is_non_negative(d)
      ...>                         and is_non_negative(i)
      ...>                         and not is_non_negative(s) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_non_negative(d)
               when is_decimal_non_negative(d) or ((is_integer(d) or is_float(d)) and d >= 0)

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal` and is positive; otherwise returns `false`.

      ## Examples

      iex> case {0, Decimal.cast("1"), "1"} do
      ...>   {i, {:ok, d}, s} when is_positive(d)
      ...>                         and not is_positive(i)
      ...>                         and not is_positive(s) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_positive(d)
               when is_decimal_positive(d) or ((is_integer(d) or is_float(d)) and d > 0)

      @doc since: "2.1.0"
      @doc """
      Returns `true` if term is a `Decimal` and is negative; otherwise returns `false`.

      ## Examples

      iex> case {-1, Decimal.cast("-1"), "-1"} do
      ...>   {i, {:ok, d}, s} when is_negative(d)
      ...>                         and is_negative(i)
      ...>                         and not is_negative(s) -> :ok
      ...>   _ -> :error
      ...> end
      :ok
      """
      defguard is_negative(d)
               when is_decimal_negative(d) or ((is_integer(d) or is_float(d)) and d < 0)
    end
  end
end
