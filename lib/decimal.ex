defmodule Decimal do
  @moduledoc """
  Decimal arithmetic on arbitrary precision floating-point numbers.

  A number is represented by a signed coefficient and exponent such that: `sign
  * coefficient * 10 ^ exponent`. All numbers are represented and calculated
  exactly, but the result of an operation may be rounded depending on the
  context the operation is performed with, see: `Decimal.Context`. Trailing
  zeros in the coefficient are never truncated to preserve the number of
  significant digits unless explicitly done so.

  There are also special values such as NaN (not a number) and ±Infinity.
  -0 and +0 are two distinct values.
  Some operation results are not defined and will return NaN.
  This kind of NaN is quiet, any operation returning a number will return
  NaN when given a quiet NaN (the NaN value will flow through all operations).

  Exceptional conditions are grouped into signals, each signal has a flag and a
  trap enabler in the context. Whenever a signal is triggered it's flag is set
  in the context and will be set until explicitly cleared. If the signal is trap
  enabled `Decimal.Error` will be raised.

  ## Specifications

    * [IBM's General Decimal Arithmetic Specification](http://speleotrove.com/decimal/decarith.html)
    * [IEEE standard 854-1987](http://web.archive.org/web/20150908012941/http://754r.ucbtest.org/standards/854.pdf)

  This library follows the above specifications for reference of arithmetic
  operation implementations, but the public APIs may differ to provide a
  more idiomatic Elixir interface.

  The specification models the sign of the number as 1, for a negative number,
  and 0 for a positive number. Internally this implementation models the sign as
  1 or -1 such that the complete number will be `sign * coefficient *
  10 ^ exponent` and will refer to the sign in documentation as either *positive*
  or *negative*.

  The default `Decimal.Context` follows IEEE 754 decimal128: `precision` is
  34, `emax` is 6 144, and `emin` is -6 143. Operation results whose adjusted
  exponent leaves that band signal overflow or underflow. Clamped is still
  not signalled.

  ## Large exponents and untrusted input

  Decimal can represent compact values with very large exponents, such as
  `1e1000000`. These values are valid decimals, but some APIs may need memory
  or CPU proportional to the expanded size of the number.

  `parse/1`, `parse/2`, `cast/1`, `cast/2`, `to_string/2`, and `to_string/3`
  apply IEEE 754 decimal128 limits by default: `:max_digits` of 34,
  `:max_exponent` of 6 144, and a `:max_digits` for output of 6 178
  (precision + emax — large enough to render any in-range decimal128 in any
  format). These defaults reject the pathological inputs described in
  CVE-2026-32686 without materializing them. Pass options on the explicit
  arities to override; pass `:infinity` to disable a limit entirely.

  ## Protocol Implementations

  `Decimal` implements the following protocols:

  ### `Inspect`

      iex> inspect(Decimal.new("1.00"))
      "Decimal.new(\\"1.00\\")"

  ### `String.Chars`

      iex> to_string(Decimal.new("1.00"))
      "1.00"

  ### `JSON.Encoder`

  _(If running Elixir 1.18+.)_

  By default, decimals are encoded as strings to preserve precision:

      iex> JSON.encode!(Decimal.new("1.00"))
      "\\"1.00\\""

  To change that, pass a custom encoder to `JSON.encode!/2`. The following encodes
  decimals as floats:

      iex> encoder = fn
      ...>   %Decimal{} = decimal, _encoder ->
      ...>     if Decimal.inf?(decimal) or Decimal.nan?(decimal) do
      ...>       raise ArgumentError, "\#{inspect(decimal)} cannot be encoded to JSON"
      ...>     end
      ...>
      ...>     Decimal.to_string(decimal)
      ...>
      ...>   other, encoder ->
      ...>     JSON.protocol_encode(other, encoder)
      ...> end
      ...>
      iex> JSON.encode!(%{x: Decimal.new("1.00")}, encoder)
      "{\\"x\\":1.00}"

  """

  import Bitwise
  import Kernel, except: [abs: 1, div: 2, max: 2, min: 2, rem: 2, round: 1]
  import Decimal.Macros
  alias Decimal.Context
  alias Decimal.Error

  @power_of_2_to_52 4_503_599_627_370_496

  @typedoc """
  The coefficient of the power of `10`. Non-negative because the sign is stored separately in `sign`.

    * `non_neg_integer` - when the `t` represents a number, instead of one of the special values below.
    * `:NaN` - Not a Number.
    * `:inf` - Infinity.

  """
  @type coefficient :: non_neg_integer | :NaN | :inf

  @typedoc """
  The exponent to which `10` is raised.
  """
  @type exponent :: integer

  @typedoc """

    * `1` for positive
    * `-1` for negative

  """
  @type sign :: 1 | -1

  @type signal ::
          :invalid_operation
          | :division_by_zero
          | :rounded
          | :inexact
          | :overflow
          | :underflow

  @type compare_result ::
          :lt | :gt | :eq

  @typedoc """
  Rounding algorithm.

  See `Decimal.Context` for more information.
  """
  @type rounding ::
          :down
          | :half_up
          | :half_even
          | :ceiling
          | :floor
          | :half_down
          | :up

  @type parse_option ::
          {:max_digits, non_neg_integer | :infinity}
          | {:max_exponent, non_neg_integer | :infinity}

  @type to_string_option ::
          {:max_digits, non_neg_integer | :infinity}

  # IEEE 754 decimal128 defaults: precision = 34, emax = 6_144, emin = -6_143.
  # The to_string default is precision + emax (34 + 6_144), which is the
  # worst-case `:normal` digit-character count for any in-range decimal128
  # value.
  @default_max_digits 34
  @default_max_exponent 6_144
  @default_to_string_max_digits 6_178

  # Below 10^2000 the BIF `:erlang.integer_to_binary/1` is fast enough; for
  # larger integers `integer_to_decimal_iodata/3` recursively splits on a
  # power of 10 (down to chunks of `@decimal_conversion_leaf_digits` digits)
  # to avoid the quadratic cost of the BIF on very large bignums.
  @decimal_conversion_direct_limit :erlang.binary_to_integer("1" <> String.duplicate("0", 2_000))
  @decimal_conversion_leaf_digits 1_024

  # Rational approximation of log10(2) used by `integer_decimal_digit_count/1`
  # to estimate decimal digit count from bit length:
  #
  #     log10(2) ≈ 0.30102999566398119521...
  #     @log10_2_num = round(log10(2) * 2^48) = 84_732_411_018_728
  #     @log10_2_den = 2^48                   = 281_474_976_710_656
  #
  # 2^48 keeps both constants below 2^47/2^48 so `(bits - 1) * @log10_2_num`
  # stays a cheap small-bignum multiply, while the approximation is exact
  # enough that `digits = div((bits - 1) * num, den) + 1` is off by at most
  # one for any bit length we care about; the caller then nudges by ±1.
  @log10_2_num 84_732_411_018_728
  @log10_2_den 281_474_976_710_656
  @normalize_chunk 16
  @normalize_chunk_pow 10_000_000_000_000_000

  @typedoc """
  This implementation models the `sign` as `1` or `-1` such that the complete number will be: `sign * coef * 10 ^ exp`.

    * `coef` - the coefficient of the power of `10`.
    * `exp` - the exponent of the power of `10`.
    * `sign` - `1` for positive, `-1` for negative.

  """
  @type t :: %__MODULE__{
          sign: sign,
          coef: coefficient,
          exp: exponent
        }

  @type decimal :: t | integer | String.t()

  defstruct sign: 1, coef: 0, exp: 0

  defmacrop error(flags, reason, result, context \\ nil) do
    quote bind_quoted: binding() do
      case handle_error(flags, reason, result, context) do
        {:ok, result} -> result
        {:error, error} -> raise Error, error
      end
    end
  end

  @doc """
  Returns `true` if number is NaN, otherwise `false`.

  ## Examples

      iex> Decimal.nan?(Decimal.new("NaN"))
      true

      iex> Decimal.nan?(Decimal.new(42))
      false

  """
  @spec nan?(t) :: boolean
  def nan?(%Decimal{coef: :NaN}), do: true
  def nan?(%Decimal{}), do: false

  @doc """
  Returns `true` if number is ±Infinity, otherwise `false`.

  ## Examples

      iex> Decimal.inf?(Decimal.new("+Infinity"))
      true

      iex> Decimal.inf?(Decimal.new("-Infinity"))
      true

      iex> Decimal.inf?(Decimal.new("1.5"))
      false

  """
  @spec inf?(t) :: boolean
  def inf?(%Decimal{coef: :inf}), do: true
  def inf?(%Decimal{}), do: false

  @doc """
  Returns `true` if argument is a decimal number, otherwise `false`.

  ## Examples

      iex> Decimal.is_decimal(Decimal.new(42))
      true

      iex> Decimal.is_decimal(42)
      false

  Allowed in guard tests on OTP 21+.
  """
  doc_since("1.9.0")
  defmacro is_decimal(term)

  if function_exported?(:erlang, :is_map_key, 2) do
    defmacro is_decimal(term) do
      case __CALLER__.context do
        nil ->
          quote do
            case unquote(term) do
              %Decimal{} -> true
              _ -> false
            end
          end

        :match ->
          raise ArgumentError,
                "invalid expression in match, is_decimal is not allowed in patterns " <>
                  "such as function clauses, case clauses or on the left side of the = operator"

        :guard ->
          quote do
            is_map(unquote(term)) and :erlang.is_map_key(:__struct__, unquote(term)) and
              :erlang.map_get(:__struct__, unquote(term)) == Decimal
          end
      end
    end
  else
    # TODO: remove when we require Elixir v1.10
    defmacro is_decimal(term) do
      quote do
        case unquote(term) do
          %Decimal{} -> true
          _ -> false
        end
      end
    end
  end

  @doc """
  The absolute value of given number. Sets the number's sign to positive.

  ## Examples

      iex> Decimal.abs(Decimal.new("1"))
      Decimal.new("1")

      iex> Decimal.abs(Decimal.new("-1"))
      Decimal.new("1")

      iex> Decimal.abs(Decimal.new("NaN"))
      Decimal.new("NaN")

  """
  @spec abs(t) :: t
  def abs(%Decimal{coef: :NaN} = num), do: %{num | sign: 1}
  def abs(%Decimal{} = num), do: context(%{num | sign: 1})

  @doc """
  Adds two numbers together.

  ## Exceptional conditions

    * If one number is -Infinity and the other +Infinity, `:invalid_operation` will
      be signalled.

  ## Examples

      iex> Decimal.add(1, "1.1")
      Decimal.new("2.1")

      iex> Decimal.add(1, "Inf")
      Decimal.new("Infinity")

  """
  @spec add(decimal, decimal) :: t
  def add(%Decimal{coef: :NaN} = num1, %Decimal{}), do: num1

  def add(%Decimal{}, %Decimal{coef: :NaN} = num2), do: num2

  def add(%Decimal{coef: :inf, sign: sign} = num1, %Decimal{coef: :inf, sign: sign} = num2) do
    if num1.exp > num2.exp do
      num1
    else
      num2
    end
  end

  def add(%Decimal{coef: :inf}, %Decimal{coef: :inf}),
    do: error(:invalid_operation, "adding +Infinity and -Infinity", %Decimal{coef: :NaN})

  def add(%Decimal{coef: :inf} = num1, %Decimal{}), do: num1

  def add(%Decimal{}, %Decimal{coef: :inf} = num2), do: num2

  def add(%Decimal{} = num1, %Decimal{} = num2) do
    %Decimal{sign: sign1, coef: coef1, exp: exp1} = num1
    %Decimal{sign: sign2, coef: coef2, exp: exp2} = num2

    cond do
      coef1 == 0 and coef2 == 0 ->
        sign = add_sign(sign1, sign2, 0)
        context(%Decimal{sign: sign, coef: 0, exp: Kernel.min(exp1, exp2)})

      coef1 == 0 ->
        add_zero(num1, num2)

      coef2 == 0 ->
        add_zero(num2, num1)

      add_bounded?(num1, num2) ->
        add_bounded(num1, num2)

      true ->
        {coef1, coef2} = add_align(coef1, exp1, coef2, exp2)
        coef = sign1 * coef1 + sign2 * coef2
        exp = Kernel.min(exp1, exp2)
        sign = add_sign(sign1, sign2, coef)
        context(%Decimal{sign: sign, coef: Kernel.abs(coef), exp: exp})
    end
  end

  def add(num1, num2), do: add(decimal(num1), decimal(num2))

  @doc """
  Subtracts second number from the first. Equivalent to `Decimal.add/2` when the
  second number's sign is negated.

  ## Exceptional conditions

    * If one number is -Infinity and the other +Infinity `:invalid_operation` will
      be signalled.

  ## Examples

      iex> Decimal.sub(1, "0.1")
      Decimal.new("0.9")

      iex> Decimal.sub(1, "Inf")
      Decimal.new("-Infinity")

  """
  @spec sub(decimal, decimal) :: t
  def sub(%Decimal{} = num1, %Decimal{sign: sign} = num2) do
    add(num1, %{num2 | sign: -sign})
  end

  def sub(num1, num2) do
    sub(decimal(num1), decimal(num2))
  end

  @doc """
  Compares two numbers numerically using a threshold. If the first number added
  to the threshold is greater than the second number, and the first number
  subtracted by the threshold is smaller than the second number, then the two
  numbers are considered equal.

  ## Examples

      iex> Decimal.compare("1.1", 1, "0.2")
      :eq

      iex> Decimal.compare("1.2", 1, "0.1")
      :gt

      iex> Decimal.compare("1.0", "1.2", "0.1")
      :lt
  """
  @spec compare(decimal :: decimal(), decimal :: decimal(), threshold :: decimal()) ::
          compare_result()

  def compare(_, _, %Decimal{sign: -1}), do: raise(Error, reason: "threshold cannot be negative")

  def compare(%Decimal{} = n1, %Decimal{} = n2, %Decimal{} = threshold) do
    add_threshold = n1 |> Decimal.add(threshold)
    sub_threshold = n1 |> Decimal.sub(threshold)
    case1 = compare(add_threshold, n2)
    case2 = compare(sub_threshold, n2)

    cond do
      (case1 == :gt or case1 == :eq) and (case2 == :lt or case2 == :eq) -> :eq
      case1 == :gt -> :gt
      case2 == :lt -> :lt
    end
  end

  def compare(n1, n2, threshold), do: compare(decimal(n1), decimal(n2), decimal(threshold))

  @doc """
  Compares two numbers numerically. If the first number is greater than the second
  `:gt` is returned, if less than `:lt` is returned, if both numbers are equal
  `:eq` is returned.

  Neither number can be a NaN.

  ## Examples

      iex> Decimal.compare("1.0", 1)
      :eq

      iex> Decimal.compare("Inf", -1)
      :gt

  """
  @spec compare(decimal, decimal) :: compare_result()
  def compare(%Decimal{coef: :inf, sign: sign}, %Decimal{coef: :inf, sign: sign}),
    do: :eq

  def compare(%Decimal{coef: :inf, sign: sign1}, %Decimal{coef: :inf, sign: sign2})
      when sign1 < sign2,
      do: :lt

  def compare(%Decimal{coef: :inf, sign: sign1}, %Decimal{coef: :inf, sign: sign2})
      when sign1 > sign2,
      do: :gt

  def compare(%Decimal{coef: :inf, sign: 1}, _num2), do: :gt
  def compare(%Decimal{coef: :inf, sign: -1}, _num2), do: :lt

  def compare(_num1, %Decimal{coef: :inf, sign: 1}), do: :lt
  def compare(_num1, %Decimal{coef: :inf, sign: -1}), do: :gt

  def compare(%Decimal{coef: :NaN} = num1, _num2),
    do: error(:invalid_operation, "operation on NaN", num1)

  def compare(_num1, %Decimal{coef: :NaN} = num2),
    do: error(:invalid_operation, "operation on NaN", num2)

  def compare(%Decimal{coef: 0}, %Decimal{coef: 0}), do: :eq

  def compare(%Decimal{sign: 1}, %Decimal{coef: 0}), do: :gt
  def compare(%Decimal{coef: 0}, %Decimal{sign: 1}), do: :lt
  def compare(%Decimal{sign: -1}, %Decimal{coef: 0}), do: :lt
  def compare(%Decimal{coef: 0}, %Decimal{sign: -1}), do: :gt

  def compare(%Decimal{sign: 1}, %Decimal{sign: -1}), do: :gt
  def compare(%Decimal{sign: -1}, %Decimal{sign: 1}), do: :lt

  def compare(%Decimal{} = num1, %Decimal{} = num2) do
    adjusted_exp1 = adjust_exp(num1)
    adjusted_exp2 = adjust_exp(num2)

    sign =
      cond do
        adjusted_exp1 == adjusted_exp2 ->
          padded_num1 = pad_num(num1, num1.exp - num2.exp)
          padded_num2 = pad_num(num2, num2.exp - num1.exp)

          cond do
            padded_num1 == padded_num2 -> 0
            padded_num1 < padded_num2 -> -num1.sign
            true -> num1.sign
          end

        adjusted_exp1 < adjusted_exp2 ->
          -num1.sign

        true ->
          num1.sign
      end

    case sign do
      0 -> :eq
      1 -> :gt
      -1 -> :lt
    end
  end

  def compare(num1, num2) do
    compare(decimal(num1), decimal(num2))
  end

  defp adjust_exp(%Decimal{coef: coef, exp: exp}) do
    coef_adjustment = coef_length(coef)
    exp + coef_adjustment - 1
  end

  defp coef_length(0), do: 1
  defp coef_length(coef) when coef < 10, do: 1
  defp coef_length(coef) when coef < 100, do: 2
  defp coef_length(coef) when coef < 1_000, do: 3
  defp coef_length(coef) when coef < 10_000, do: 4
  defp coef_length(coef) when coef < 100_000, do: 5
  defp coef_length(coef) when coef < 1_000_000, do: 6
  defp coef_length(coef) when coef < 10_000_000, do: 7
  defp coef_length(coef) when coef < 100_000_000, do: 8
  defp coef_length(coef) when coef < 1_000_000_000, do: 9
  defp coef_length(coef) when coef < 10_000_000_000, do: 10
  defp coef_length(coef) when coef < 100_000_000_000, do: 11
  defp coef_length(coef) when coef < 1_000_000_000_000, do: 12
  defp coef_length(coef) when coef < 10_000_000_000_000, do: 13
  defp coef_length(coef) when coef < 100_000_000_000_000, do: 14
  defp coef_length(coef) when coef < 1_000_000_000_000_000, do: 15
  defp coef_length(coef) when coef < 10_000_000_000_000_000, do: 16
  defp coef_length(coef) when coef < 100_000_000_000_000_000, do: 17
  defp coef_length(coef) when coef < 1_000_000_000_000_000_000, do: 18
  defp coef_length(coef), do: integer_decimal_digit_count(coef)

  defp pad_num(%Decimal{coef: coef}, n) do
    coef * pow10(Kernel.max(n, 0) + 1)
  end

  @deprecated "Use compare/2 instead"
  @spec cmp(decimal, decimal) :: :lt | :eq | :gt
  def cmp(num1, num2) do
    compare(num1, num2)
  end

  @doc """
  Compares two numbers numerically and returns `true` if they are equal,
  otherwise `false`. If one of the operands is a quiet NaN this operation
  will always return `false`.

  ## Examples

      iex> Decimal.equal?("1.0", 1)
      true

      iex> Decimal.equal?(1, -1)
      false

  """
  @spec equal?(decimal, decimal) :: boolean
  def equal?(num1, num2) do
    eq?(num1, num2)
  end

  @doc """
  Compares two numbers numerically and returns `true` if they are equal,
  otherwise `false`. If one of the operands is a quiet NaN this operation
  will always return `false`.

  ## Examples

      iex> Decimal.eq?("1.0", 1)
      true

      iex> Decimal.eq?(1, -1)
      false

  """
  doc_since("1.8.0")
  @spec eq?(decimal, decimal) :: boolean
  def eq?(%Decimal{coef: :NaN}, _num2), do: false
  def eq?(_num1, %Decimal{coef: :NaN}), do: false
  def eq?(num1, num2), do: compare(num1, num2) == :eq

  @doc """
  It compares the equality of two numbers. If the second number is within
  the range of first - threshold and first + threshold, it returns true;
  otherwise, it returns false.

  ## Examples

      iex> Decimal.eq?("1.0", 1, "0")
      true

      iex> Decimal.eq?("1.2", 1, "0.1")
      false

      iex> Decimal.eq?("1.2", 1, "0.2")
      true

      iex> Decimal.eq?(1, -1, "0.0")
      false

  """
  doc_since("2.2.0")
  @spec eq?(decimal :: decimal(), decimal :: decimal(), threshold :: decimal()) :: boolean()
  def eq?(num1, num2, threshold), do: compare(num1, num2, threshold) == :eq

  @doc """
  Compares two numbers numerically and returns `true` if the first argument
  is greater than the second, otherwise `false`. If one the operands is a
  quiet NaN this operation will always return `false`.

  ## Examples

      iex> Decimal.gt?("1.3", "1.2")
      true

      iex> Decimal.gt?("1.2", "1.3")
      false

  """
  doc_since("1.8.0")
  @spec gt?(decimal, decimal) :: boolean
  def gt?(%Decimal{coef: :NaN}, _num2), do: false
  def gt?(_num1, %Decimal{coef: :NaN}), do: false
  def gt?(num1, num2), do: compare(num1, num2) == :gt

  @doc """
  Compares two numbers numerically and returns `true` if the first number is
  less than the second number, otherwise `false`. If one of the operands is a
  quiet NaN this operation will always return `false`.

  ## Examples

      iex> Decimal.lt?("1.1", "1.2")
      true

      iex> Decimal.lt?("1.4", "1.2")
      false

  """
  doc_since("1.8.0")
  @spec lt?(decimal, decimal) :: boolean
  def lt?(%Decimal{coef: :NaN}, _num2), do: false
  def lt?(_num1, %Decimal{coef: :NaN}), do: false
  def lt?(num1, num2), do: compare(num1, num2) == :lt

  @doc """
  Compares two numbers numerically and returns `true` if
  the first argument is greater than or equal the second,
  otherwise `false`.

  If one the operands is a quiet NaN this operation
  will always return `false`.

  ## Examples

      iex> Decimal.gte?("1.3", "1.3")
      true

      iex> Decimal.gte?("1.3", "1.2")
      true

      iex> Decimal.gte?("1.2", "1.3")
      false

  """
  doc_since("2.2.0")
  @spec gte?(decimal, decimal) :: boolean

  def gte?(%Decimal{coef: :NaN}, _num2), do: false
  def gte?(_num1, %Decimal{coef: :NaN}), do: false

  def gte?(num1, num2) do
    case compare(num1, num2) do
      :gt -> true
      :eq -> true
      _ -> false
    end
  end

  @doc """
  Compares two numbers numerically and returns `true` if
  the first number is less than or equal the second number,
  otherwise `false`.

  If one of the operands is a quiet NaN this operation
  will always return `false`.

  ## Examples

      iex> Decimal.lte?("1.1", "1.1")
      true

      iex> Decimal.lte?("1.1", "1.2")
      true

      iex> Decimal.lte?("1.4", "1.2")
      false

  """
  doc_since("2.2.0")
  @spec lte?(decimal, decimal) :: boolean

  def lte?(%Decimal{coef: :NaN}, _num2), do: false
  def lte?(_num1, %Decimal{coef: :NaN}), do: false

  def lte?(num1, num2) do
    case compare(num1, num2) do
      :lt -> true
      :eq -> true
      _ -> false
    end
  end

  @doc """
  Divides two numbers.

  ## Exceptional conditions

    * If both numbers are ±Infinity `:invalid_operation` is signalled.
    * If both numbers are ±0 `:invalid_operation` is signalled.
    * If second number (denominator) is ±0 `:division_by_zero` is signalled.

  ## Examples

      iex> Decimal.div(3, 4)
      Decimal.new("0.75")

      iex> Decimal.div("Inf", -1)
      Decimal.new("-Infinity")

  """
  @spec div(decimal, decimal) :: t
  def div(%Decimal{coef: :NaN} = num1, %Decimal{}), do: num1

  def div(%Decimal{}, %Decimal{coef: :NaN} = num2), do: num2

  def div(%Decimal{coef: :inf}, %Decimal{coef: :inf}),
    do: error(:invalid_operation, "±Infinity / ±Infinity", %Decimal{coef: :NaN})

  def div(%Decimal{sign: sign1, coef: :inf} = num1, %Decimal{sign: sign2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    %{num1 | sign: sign}
  end

  def div(%Decimal{sign: sign1, exp: exp1}, %Decimal{sign: sign2, coef: :inf, exp: exp2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    # TODO: Subnormal
    # exponent?
    %Decimal{sign: sign, coef: 0, exp: exp1 - exp2}
  end

  def div(%Decimal{coef: 0}, %Decimal{coef: 0}),
    do: error(:invalid_operation, "0 / 0", %Decimal{coef: :NaN})

  def div(%Decimal{sign: sign1}, %Decimal{sign: sign2, coef: 0}) do
    sign = if sign1 == sign2, do: 1, else: -1
    error(:division_by_zero, nil, %Decimal{sign: sign, coef: :inf})
  end

  def div(%Decimal{} = num1, %Decimal{} = num2) do
    %Decimal{sign: sign1, coef: coef1, exp: exp1} = num1
    %Decimal{sign: sign2, coef: coef2, exp: exp2} = num2
    sign = if sign1 == sign2, do: 1, else: -1

    if coef1 == 0 do
      context(%Decimal{sign: sign, coef: 0, exp: exp1 - exp2}, [])
    else
      prec10 = pow10(Context.get().precision)
      {coef1, coef2, adjust} = div_adjust(coef1, coef2, 0)
      {coef, adjust, _rem, signals} = div_calc(coef1, coef2, 0, adjust, prec10)

      context(%Decimal{sign: sign, coef: coef, exp: exp1 - exp2 - adjust}, signals)
    end
  end

  def div(num1, num2) do
    div(decimal(num1), decimal(num2))
  end

  @doc """
  Divides two numbers and returns the integer part.

  ## Exceptional conditions

    * If both numbers are ±Infinity `:invalid_operation` is signalled.
    * If both numbers are ±0 `:invalid_operation` is signalled.
    * If second number (denominator) is ±0 `:division_by_zero` is signalled.

  ## Examples

      iex> Decimal.div_int(5, 2)
      Decimal.new("2")

      iex> Decimal.div_int("Inf", -1)
      Decimal.new("-Infinity")

  """
  @spec div_int(decimal, decimal) :: t
  def div_int(%Decimal{coef: :NaN} = num1, %Decimal{}), do: num1

  def div_int(%Decimal{}, %Decimal{coef: :NaN} = num2), do: num2

  def div_int(%Decimal{coef: :inf}, %Decimal{coef: :inf}),
    do: error(:invalid_operation, "±Infinity / ±Infinity", %Decimal{coef: :NaN})

  def div_int(%Decimal{sign: sign1, coef: :inf} = num1, %Decimal{sign: sign2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    %{num1 | sign: sign}
  end

  def div_int(%Decimal{sign: sign1, exp: exp1}, %Decimal{sign: sign2, coef: :inf, exp: exp2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    # TODO: Subnormal
    # exponent?
    %Decimal{sign: sign, coef: 0, exp: exp1 - exp2}
  end

  def div_int(%Decimal{coef: 0}, %Decimal{coef: 0}),
    do: error(:invalid_operation, "0 / 0", %Decimal{coef: :NaN})

  def div_int(%Decimal{sign: sign1}, %Decimal{sign: sign2, coef: 0}) do
    div_sign = if sign1 == sign2, do: 1, else: -1
    error(:division_by_zero, nil, %Decimal{sign: div_sign, coef: :inf})
  end

  def div_int(%Decimal{} = num1, %Decimal{} = num2) do
    %Decimal{sign: sign1, coef: coef1, exp: exp1} = num1
    %Decimal{sign: sign2, coef: coef2, exp: exp2} = num2
    div_sign = if sign1 == sign2, do: 1, else: -1

    cond do
      compare(%{num1 | sign: 1}, %{num2 | sign: 1}) == :lt ->
        %Decimal{sign: div_sign, coef: 0, exp: exp1 - exp2}

      coef1 == 0 ->
        context(%{num1 | sign: div_sign})

      true ->
        case integer_division(div_sign, coef1, exp1, coef2, exp2) do
          {:ok, result} ->
            result

          {:error, error, reason, num} ->
            error(error, reason, num)
        end
    end
  end

  def div_int(num1, num2) do
    div_int(decimal(num1), decimal(num2))
  end

  @doc """
  Remainder of integer division of two numbers. The result will have the sign of
  the first number.

  ## Exceptional conditions

    * If both numbers are ±Infinity `:invalid_operation` is signalled.
    * If both numbers are ±0 `:invalid_operation` is signalled.
    * If second number (denominator) is ±0 `:division_by_zero` is signalled.

  ## Examples

      iex> Decimal.rem(5, 2)
      Decimal.new("1")

  """
  @spec rem(decimal, decimal) :: t
  def rem(%Decimal{coef: :NaN} = num1, %Decimal{}), do: num1

  def rem(%Decimal{}, %Decimal{coef: :NaN} = num2), do: num2

  def rem(%Decimal{coef: :inf}, %Decimal{coef: :inf}),
    do: error(:invalid_operation, "±Infinity / ±Infinity", %Decimal{coef: :NaN})

  def rem(%Decimal{sign: sign1, coef: :inf}, %Decimal{}), do: %Decimal{sign: sign1, coef: 0}

  def rem(%Decimal{sign: sign1}, %Decimal{coef: :inf} = num2) do
    # TODO: Subnormal
    # exponent?
    %{num2 | sign: sign1}
  end

  def rem(%Decimal{coef: 0}, %Decimal{coef: 0}),
    do: error(:invalid_operation, "0 / 0", %Decimal{coef: :NaN})

  def rem(%Decimal{sign: sign1}, %Decimal{coef: 0}),
    do: error(:division_by_zero, nil, %Decimal{sign: sign1, coef: 0})

  def rem(%Decimal{} = num1, %Decimal{} = num2) do
    %Decimal{sign: sign1, coef: coef1, exp: exp1} = num1
    %Decimal{sign: sign2, coef: coef2, exp: exp2} = num2

    cond do
      compare(%{num1 | sign: 1}, %{num2 | sign: 1}) == :lt ->
        context(%{num1 | sign: sign1})

      coef1 == 0 ->
        context(%{num2 | sign: sign1})

      true ->
        div_sign = if sign1 == sign2, do: 1, else: -1

        case integer_division(div_sign, coef1, exp1, coef2, exp2) do
          {:ok, result} ->
            sub(num1, mult(num2, result))

          {:error, error, reason, num} ->
            error(error, reason, num)
        end
    end
  end

  def rem(num1, num2) do
    rem(decimal(num1), decimal(num2))
  end

  @doc """
  Integer division of two numbers and the remainder. Should be used when both
  `div_int/2` and `rem/2` is needed. Equivalent to: `{Decimal.div_int(x, y),
  Decimal.rem(x, y)}`.

  ## Exceptional conditions

    * If both numbers are ±Infinity `:invalid_operation` is signalled.
    * If both numbers are ±0 `:invalid_operation` is signalled.
    * If second number (denominator) is ±0 `:division_by_zero` is signalled.

  ## Examples

      iex> Decimal.div_rem(5, 2)
      {Decimal.new(2), Decimal.new(1)}

  """
  @spec div_rem(decimal, decimal) :: {t, t}
  def div_rem(%Decimal{coef: :NaN} = num1, %Decimal{}), do: {num1, num1}

  def div_rem(%Decimal{}, %Decimal{coef: :NaN} = num2), do: {num2, num2}

  def div_rem(%Decimal{coef: :inf}, %Decimal{coef: :inf}) do
    numbers = {%Decimal{coef: :NaN}, %Decimal{coef: :NaN}}
    error(:invalid_operation, "±Infinity / ±Infinity", numbers)
  end

  def div_rem(%Decimal{sign: sign1, coef: :inf} = num1, %Decimal{sign: sign2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    {%{num1 | sign: sign}, %Decimal{sign: sign1, coef: 0}}
  end

  def div_rem(%Decimal{} = num1, %Decimal{coef: :inf} = num2) do
    %Decimal{sign: sign1, exp: exp1} = num1
    %Decimal{sign: sign2, exp: exp2} = num2

    sign = if sign1 == sign2, do: 1, else: -1
    # TODO: Subnormal
    # exponent?
    {%Decimal{sign: sign, coef: 0, exp: exp1 - exp2}, %{num2 | sign: sign1}}
  end

  def div_rem(%Decimal{coef: 0}, %Decimal{coef: 0}) do
    error = error(:invalid_operation, "0 / 0", %Decimal{coef: :NaN})
    {error, error}
  end

  def div_rem(%Decimal{sign: sign1}, %Decimal{sign: sign2, coef: 0}) do
    div_sign = if sign1 == sign2, do: 1, else: -1
    div_error = error(:division_by_zero, nil, %Decimal{sign: div_sign, coef: :inf})
    rem_error = error(:division_by_zero, nil, %Decimal{sign: sign1, coef: 0})
    {div_error, rem_error}
  end

  def div_rem(%Decimal{} = num1, %Decimal{} = num2) do
    %Decimal{sign: sign1, coef: coef1, exp: exp1} = num1
    %Decimal{sign: sign2, coef: coef2, exp: exp2} = num2
    div_sign = if sign1 == sign2, do: 1, else: -1

    cond do
      compare(%{num1 | sign: 1}, %{num2 | sign: 1}) == :lt ->
        {%Decimal{sign: div_sign, coef: 0, exp: exp1 - exp2}, %{num1 | sign: sign1}}

      coef1 == 0 ->
        {context(%{num1 | sign: div_sign}), context(%{num2 | sign: sign1})}

      true ->
        case integer_division(div_sign, coef1, exp1, coef2, exp2) do
          {:ok, result} ->
            {result, sub(num1, mult(num2, result))}

          {:error, error, reason, num} ->
            error(error, reason, {num, num})
        end
    end
  end

  def div_rem(num1, num2) do
    div_rem(decimal(num1), decimal(num2))
  end

  @doc """
  Compares two values numerically and returns the maximum. Unlike most other
  functions in `Decimal` if a number is NaN the result will be the other number.
  Only if both numbers are NaN will NaN be returned.

  ## Examples

      iex> Decimal.max(1, "2.0")
      Decimal.new("2.0")

      iex> Decimal.max(1, "NaN")
      Decimal.new("1")

      iex> Decimal.max("NaN", "NaN")
      Decimal.new("NaN")

  """
  @spec max(decimal, decimal) :: t
  def max(%Decimal{coef: :NaN}, %Decimal{} = num2), do: num2

  def max(%Decimal{} = num1, %Decimal{coef: :NaN}), do: num1

  def max(%Decimal{sign: sign1, exp: exp1} = num1, %Decimal{sign: sign2, exp: exp2} = num2) do
    case compare(num1, num2) do
      :lt ->
        num2

      :gt ->
        num1

      :eq ->
        cond do
          sign1 != sign2 ->
            if sign1 == 1, do: num1, else: num2

          sign1 == 1 ->
            if exp1 > exp2, do: num1, else: num2

          sign1 == -1 ->
            if exp1 < exp2, do: num1, else: num2
        end
    end
    |> context()
  end

  def max(num1, num2) do
    max(decimal(num1), decimal(num2))
  end

  @doc """
  Compares two values numerically and returns the minimum. Unlike most other
  functions in `Decimal` if a number is NaN the result will be the other number.
  Only if both numbers are NaN will NaN be returned.

  ## Examples

      iex> Decimal.min(1, "2.0")
      Decimal.new("1")

      iex> Decimal.min(1, "NaN")
      Decimal.new("1")

      iex> Decimal.min("NaN", "NaN")
      Decimal.new("NaN")

  """
  @spec min(decimal, decimal) :: t
  def min(%Decimal{coef: :NaN}, %Decimal{} = num2), do: num2

  def min(%Decimal{} = num1, %Decimal{coef: :NaN}), do: num1

  def min(%Decimal{sign: sign1, exp: exp1} = num1, %Decimal{sign: sign2, exp: exp2} = num2) do
    case compare(num1, num2) do
      :lt ->
        num1

      :gt ->
        num2

      :eq ->
        cond do
          sign1 != sign2 ->
            if sign1 == -1, do: num1, else: num2

          sign1 == 1 ->
            if exp1 < exp2, do: num1, else: num2

          sign1 == -1 ->
            if exp1 > exp2, do: num1, else: num2
        end
    end
    |> context()
  end

  def min(num1, num2) do
    min(decimal(num1), decimal(num2))
  end

  @doc """
  Negates the given number.

  ## Examples

      iex> Decimal.negate(1)
      Decimal.new("-1")

      iex> Decimal.negate("-Inf")
      Decimal.new("Infinity")

  """
  doc_since("1.9.0")
  @spec negate(decimal) :: t
  def negate(%Decimal{coef: :NaN} = num), do: num
  def negate(%Decimal{sign: sign} = num), do: context(%{num | sign: -sign})
  def negate(num), do: negate(decimal(num))

  @doc """
  Applies the context to the given number rounding it to specified precision.
  """
  doc_since("1.9.0")
  @spec apply_context(t) :: t
  def apply_context(%Decimal{} = num), do: context(num)

  @doc """
  Returns `true` if given number is positive, otherwise `false`.

  ## Examples

      iex> Decimal.positive?(Decimal.new("42"))
      true

      iex> Decimal.positive?(Decimal.new("-42"))
      false

      iex> Decimal.positive?(Decimal.new("0"))
      false

      iex> Decimal.positive?(Decimal.new("NaN"))
      false

  """
  doc_since("1.5.0")
  @spec positive?(t) :: boolean
  def positive?(%Decimal{coef: :NaN}), do: false
  def positive?(%Decimal{coef: 0}), do: false
  def positive?(%Decimal{sign: -1}), do: false
  def positive?(%Decimal{sign: 1}), do: true

  @doc """
  Returns `true` if given number is negative, otherwise `false`.

  ## Examples

      iex> Decimal.negative?(Decimal.new("-42"))
      true

      iex> Decimal.negative?(Decimal.new("42"))
      false

      iex> Decimal.negative?(Decimal.new("0"))
      false

      iex> Decimal.negative?(Decimal.new("NaN"))
      false

  """
  doc_since("1.5.0")
  @spec negative?(t) :: boolean
  def negative?(%Decimal{coef: :NaN}), do: false
  def negative?(%Decimal{coef: 0}), do: false
  def negative?(%Decimal{sign: 1}), do: false
  def negative?(%Decimal{sign: -1}), do: true

  @doc """
  Multiplies two numbers.

  ## Exceptional conditions

    * If one number is ±0 and the other is ±Infinity `:invalid_operation` is
      signalled.

  ## Examples

      iex> Decimal.mult("0.5", 3)
      Decimal.new("1.5")

      iex> Decimal.mult("Inf", -1)
      Decimal.new("-Infinity")

  """
  @spec mult(decimal, decimal) :: t
  def mult(%Decimal{coef: :NaN} = num1, %Decimal{}), do: num1

  def mult(%Decimal{}, %Decimal{coef: :NaN} = num2), do: num2

  def mult(%Decimal{coef: 0}, %Decimal{coef: :inf}),
    do: error(:invalid_operation, "0 * ±Infinity", %Decimal{coef: :NaN})

  def mult(%Decimal{coef: :inf}, %Decimal{coef: 0}),
    do: error(:invalid_operation, "0 * ±Infinity", %Decimal{coef: :NaN})

  def mult(%Decimal{sign: sign1, coef: :inf, exp: exp1}, %Decimal{sign: sign2, exp: exp2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    # exponent?
    %Decimal{sign: sign, coef: :inf, exp: exp1 + exp2}
  end

  def mult(%Decimal{sign: sign1, exp: exp1}, %Decimal{sign: sign2, coef: :inf, exp: exp2}) do
    sign = if sign1 == sign2, do: 1, else: -1
    # exponent?
    %Decimal{sign: sign, coef: :inf, exp: exp1 + exp2}
  end

  def mult(%Decimal{} = num1, %Decimal{} = num2) do
    %Decimal{sign: sign1, coef: coef1, exp: exp1} = num1
    %Decimal{sign: sign2, coef: coef2, exp: exp2} = num2
    sign = if sign1 == sign2, do: 1, else: -1
    %Decimal{sign: sign, coef: coef1 * coef2, exp: exp1 + exp2} |> context()
  end

  def mult(num1, num2) do
    mult(decimal(num1), decimal(num2))
  end

  @doc """
  Normalizes the given decimal: removes trailing zeros from coefficient while
  keeping the number numerically equivalent by increasing the exponent.

  ## Examples

      iex> Decimal.normalize(Decimal.new("1.00"))
      Decimal.new("1")

      iex> Decimal.normalize(Decimal.new("1.01"))
      Decimal.new("1.01")

  """
  doc_since("1.9.0")
  @spec normalize(t) :: t
  def normalize(%Decimal{coef: :NaN} = num), do: num

  def normalize(%Decimal{coef: :inf} = num) do
    # exponent?
    %{num | exp: 0}
  end

  def normalize(%Decimal{sign: sign, coef: coef, exp: exp}) do
    if coef == 0 do
      %Decimal{sign: sign, coef: 0, exp: 0}
    else
      %{do_normalize(coef, exp) | sign: sign} |> context
    end
  end

  @doc """
  Rounds the given number to specified decimal places with the given strategy
  (default is to round to nearest one). If places is negative, at least that
  many digits to the left of the decimal point will be zero.

  See `Decimal.Context` for more information about rounding algorithms.

  ## Examples

      iex> Decimal.round("1.234")
      Decimal.new("1")

      iex> Decimal.round("1.234", 1)
      Decimal.new("1.2")

  """
  @spec round(decimal, integer, rounding) :: t
  def round(num, places \\ 0, mode \\ :half_up)

  def round(%Decimal{coef: :NaN} = num, _, _), do: num

  def round(%Decimal{coef: :inf} = num, _, _), do: num

  def round(%Decimal{} = num, n, mode) do
    %Decimal{sign: sign, coef: coef, exp: exp} = normalize(num)
    digits = :erlang.integer_to_list(coef)
    target_exp = -n
    value = do_round(sign, digits, exp, target_exp, mode)
    context(value, [])
  end

  def round(num, n, mode) do
    round(decimal(num), n, mode)
  end

  @doc """
  Finds the square root.

  ## Examples

      iex> Decimal.sqrt("100")
      Decimal.new("10")

  """
  doc_since("1.7.0")
  @spec sqrt(decimal) :: t
  def sqrt(%Decimal{coef: :NaN} = num),
    do: error(:invalid_operation, "operation on NaN", num)

  def sqrt(%Decimal{coef: 0, exp: exp} = num),
    do: %{num | exp: exp >>> 1}

  def sqrt(%Decimal{sign: -1} = num),
    do: error(:invalid_operation, "less than zero", num)

  def sqrt(%Decimal{sign: 1, coef: :inf} = num),
    do: num

  def sqrt(%Decimal{sign: 1, coef: coef, exp: exp}) do
    precision = Context.get().precision + 1
    digits = :erlang.integer_to_list(coef)
    num_digits = length(digits)

    # Since the root is calculated from integer operations only, it must be
    # large enough to contain the desired precision. Calculate the amount of
    # `shift` required (powers of 10).
    case exp &&& 1 do
      0 ->
        # To get the desired `shift`, subtract the precision of `coef`'s square
        # root from the desired precision.
        #
        # If `coef` is 10_000, the root is 100 (3 digits of precision).
        # If `coef` is 100, the root is 10 (2 digits of precision).
        shift = precision - ((num_digits + 1) >>> 1)
        sqrt(coef, shift, exp)

      _ ->
        # If `exp` is odd, multiply `coef` by 10 and reduce shift by 1/2. `exp`
        # must be even so the root's exponent is an integer.
        shift = precision - ((num_digits >>> 1) + 1)
        sqrt(coef * 10, shift, exp)
    end
  end

  def sqrt(num) do
    sqrt(decimal(num))
  end

  defp sqrt(coef, shift, exp) do
    if shift >= 0 do
      # shift `coef` up by `shift * 2` digits
      sqrt(coef * pow10(shift <<< 1), shift, exp, true)
    else
      # shift `coef` down by `shift * 2` digits
      operand = pow10(-shift <<< 1)
      sqrt(Kernel.div(coef, operand), shift, exp, Kernel.rem(coef, operand) === 0)
    end
  end

  defp sqrt(shifted_coef, shift, exp, exact) do
    # the preferred exponent is `exp / 2` as per IEEE 754
    exp = exp >>> 1
    # guess a root 10x higher than desired precision
    guess = pow10(Context.get().precision + 1)
    root = sqrt_loop(shifted_coef, guess)

    if exact and root * root === shifted_coef do
      # if the root is exact, use preferred `exp` and shift `coef` to match
      coef =
        if shift >= 0,
          do: Kernel.div(root, pow10(shift)),
          else: root * pow10(-shift)

      context(%Decimal{sign: 1, coef: coef, exp: exp})
    else
      # otherwise the calculated root is inexact (but still meets precision),
      # so use the root as `coef` and get the final exponent by shifting `exp`
      context(%Decimal{sign: 1, coef: root, exp: exp - shift})
    end
  end

  # Babylonion method
  defp sqrt_loop(coef, guess) do
    quotient = Kernel.div(coef, guess)

    if guess <= quotient do
      guess
    else
      sqrt_loop(coef, (guess + quotient) >>> 1)
    end
  end

  @doc """
  Creates a new decimal number from an integer or a string representation.

  A decimal number will always be created exactly as specified with all digits
  kept - it will not be rounded with the context.

  ## Backus–Naur form

      sign           ::=  "+" | "-"
      digit          ::=  "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
      indicator      ::=  "e" | "E"
      digits         ::=  digit [digit]...
      decimal-part   ::=  digits "." [digits] | ["."] digits
      exponent-part  ::=  indicator [sign] digits
      infinity       ::=  "Infinity" | "Inf"
      nan            ::=  "NaN" [digits]
      numeric-value  ::=  decimal-part [exponent-part] | infinity
      numeric-string ::=  [sign] numeric-value | [sign] nan

  ## Floats

  See also `from_float/1`.

  ## Examples

      iex> Decimal.new(1)
      Decimal.new("1")

      iex> Decimal.new("3.14")
      Decimal.new("3.14")

      iex> Decimal.new("1.79769313486231581e308")
      Decimal.new("1.79769313486231581e308")

      iex> Decimal.new("2.22507385850720139e-308")
      Decimal.new("2.22507385850720139e-308")

      iex> Decimal.new("1.01234567890123457890123457890123456789", max_digits: 39)
      Decimal.new("1.01234567890123457890123457890123456789", max_digits: 39)
  """
  @spec new(decimal) :: t
  def new(%Decimal{sign: sign, coef: coef, exp: exp} = num)
      when sign in [1, -1] and ((is_integer(coef) and coef >= 0) or coef in [:NaN, :inf]) and
             is_integer(exp),
      do: num

  def new(int) when is_integer(int),
    do: %Decimal{sign: if(int < 0, do: -1, else: 1), coef: Kernel.abs(int)}

  def new(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case parse(binary, opts) do
      {decimal, ""} -> decimal
      _ -> raise Error, reason: "number parsing syntax: #{inspect(binary)}"
    end
  end

  @doc """
  Creates a new decimal number from the sign, coefficient and exponent such that
  the number will be: `sign * coefficient * 10 ^ exponent`.

  A decimal number will always be created exactly as specified with all digits
  kept - it will not be rounded with the context.

  ## Examples

      iex> Decimal.new(1, 42, 0)
      Decimal.new("42")

  """
  @spec new(sign :: 1 | -1, coef :: non_neg_integer | :NaN | :inf, exp :: integer) :: t
  def new(sign, coef, exp)
      when sign in [1, -1] and ((is_integer(coef) and coef >= 0) or coef in [:NaN, :inf]) and
             is_integer(exp),
      do: %Decimal{sign: sign, coef: coef, exp: exp}

  @doc """
  Creates a new decimal number from a floating point number.

  Floating point numbers use a fixed number of binary digits to represent
  a decimal number which has inherent inaccuracy as some decimal numbers cannot
  be represented exactly in limited precision binary.

  Floating point numbers will be converted to decimal numbers with
  `:io_lib_format.fwrite_g/1`. Since this conversion is not exact and
  because of inherent inaccuracy mentioned above, we may run into counter-intuitive results:

      iex> Enum.reduce([0.1, 0.1, 0.1], &+/2)
      0.30000000000000004

      iex> Enum.reduce([Decimal.new("0.1"), Decimal.new("0.1"), Decimal.new("0.1")], &Decimal.add/2)
      Decimal.new("0.3")

  For this reason, it's recommended to build decimals with `new/1`, which is always precise, instead.

  ## Examples

      iex> Decimal.from_float(3.14)
      Decimal.new("3.14")

  """
  doc_since("1.5.0")
  @spec from_float(float) :: t
  def from_float(float) when is_float(float) do
    float
    |> :io_lib_format.fwrite_g()
    |> fix_float_exp()
    |> IO.iodata_to_binary()
    |> new()
  end

  @doc """
  Creates a new decimal number from an integer, string, float, or existing decimal number.

  Because conversion from a floating point number is not exact, it's recommended
  to instead use `new/1` or `from_float/1` when the argument's type is certain.
  See `from_float/1`.

  ## Examples

      iex> {:ok, decimal} = Decimal.cast(3)
      iex> decimal
      Decimal.new("3")

      iex> Decimal.cast("bad")
      :error

  """
  @spec cast(term) :: {:ok, t} | :error
  def cast(term), do: cast_with_limits(term, default_parse_limits())

  @doc """
  Creates a new decimal number from an integer, string, float, or existing decimal
  number with parsing limits.

  Options are the same as `parse/2`.
  """
  doc_since("2.4.0")
  @spec cast(term, [parse_option]) :: {:ok, t} | :error
  def cast(term, opts) when is_list(opts) do
    cast_with_limits(term, parse_limits!(opts))
  end

  defp cast_with_limits(term, limits) do
    cond do
      is_integer(term) ->
        decimal = Decimal.new(term)
        if decimal_within_limits?(decimal, limits), do: {:ok, decimal}, else: :error

      match?(%Decimal{}, term) ->
        if decimal_within_limits?(term, limits), do: {:ok, term}, else: :error

      is_float(term) ->
        decimal = from_float(term)
        if decimal_within_limits?(decimal, limits), do: {:ok, decimal}, else: :error

      is_binary(term) ->
        case parse_with_limits(term, limits) do
          {decimal, ""} -> {:ok, decimal}
          _ -> :error
        end

      true ->
        :error
    end
  end

  @doc """
  Parses a binary into a decimal.

  If successful, returns a tuple in the form of `{decimal, remainder_of_binary}`,
  otherwise `:error`.

  Inputs whose digit count or exponent magnitude exceed the default limits
  (`#{@default_max_digits}` digits, `#{@default_max_exponent}` absolute
  exponent) return `:error`. Use `parse/2` to override the limits.

  ## Examples

      iex> Decimal.parse("3.14")
      {%Decimal{coef: 314, exp: -2, sign: 1}, ""}

      iex> Decimal.parse("3.14.15")
      {%Decimal{coef: 314, exp: -2, sign: 1}, ".15"}

      iex> Decimal.parse("-1.1e3")
      {%Decimal{coef: 11, exp: 2, sign: -1}, ""}

      iex> Decimal.parse("bad")
      :error

  """
  @spec parse(binary()) :: {t(), binary()} | :error
  def parse(binary) when is_binary(binary) do
    parse_with_limits(binary, default_parse_limits())
  end

  @doc """
  Parses a binary into a decimal with explicit limits.

  The following options are supported:

    * `:max_digits` - maximum number of significant decimal digits in the parsed
      coefficient. Leading zeros are not counted, but trailing zeros are. Defaults
      to `#{@default_max_digits}`. Pass `:infinity` to disable.
    * `:max_exponent` - maximum absolute value of the parsed decimal exponent,
      after fractional digits are accounted for. Defaults to
      `#{@default_max_exponent}`. Pass `:infinity` to disable.

  Returns `:error` when a parsed number exceeds the configured limits.
  """
  doc_since("2.4.0")
  @spec parse(binary(), [parse_option]) :: {t(), binary()} | :error
  def parse(binary, opts) when is_binary(binary) and is_list(opts) do
    parse_with_limits(binary, parse_limits!(opts))
  end

  defp parse_with_limits(binary, limits) do
    case binary do
      "+" <> rest ->
        parse_unsign(rest, limits)

      "-" <> rest ->
        case parse_unsign(rest, limits) do
          {%Decimal{} = num, rest} -> {%{num | sign: -1}, rest}
          :error -> :error
        end

      binary ->
        parse_unsign(binary, limits)
    end
  end

  @doc """
  Converts given number to its string representation.

  Output is bounded to `#{@default_to_string_max_digits}` digit characters by
  default; pass options via `to_string/3` to override. `:scientific` is compact
  for large positive exponents and rarely hits the limit; `:normal` and `:xsd`
  expand proportional to the exponent and will raise `ArgumentError` when the
  limit would be exceeded.

  ## Options

    * `:scientific` - number converted to scientific notation.
    * `:normal` - number converted without a exponent.
    * `:xsd` - number converted to the [canonical XSD representation](https://www.w3.org/TR/xmlschema-2/#decimal).
    * `:raw` - number converted to its raw, internal format.

  ## Examples

      iex> Decimal.to_string(Decimal.new("1.00"))
      "1.00"

      iex> Decimal.to_string(Decimal.new("123e1"), :scientific)
      "1.23E+3"

      iex> Decimal.to_string(Decimal.new("42.42"), :normal)
      "42.42"

      iex> Decimal.to_string(Decimal.new("1.00"), :xsd)
      "1.0"

      iex> Decimal.to_string(Decimal.new("4321.768"), :raw)
      "4321768E-3"

  """
  @spec to_string(t, :scientific | :normal | :xsd | :raw) :: String.t()
  def to_string(num, type \\ :scientific)

  def to_string(%Decimal{} = num, type)
      when type in [:scientific, :normal, :xsd, :raw] do
    check_to_string_max_digits!(num, type, @default_to_string_max_digits)
    do_to_string(num, type)
  end

  defp do_to_string(%Decimal{sign: sign, coef: :NaN}, _type) do
    if sign == 1, do: "NaN", else: "-NaN"
  end

  defp do_to_string(%Decimal{sign: sign, coef: :inf}, _type) do
    if sign == 1, do: "Infinity", else: "-Infinity"
  end

  defp do_to_string(%Decimal{sign: sign, coef: coef, exp: exp}, :normal) do
    digits = integer_to_decimal_binary(coef)
    length = byte_size(digits)

    iodata =
      if exp >= 0 do
        [digits, zeroes(exp)]
      else
        diff = length + exp

        if diff > 0 do
          [binary_part(digits, 0, diff), ?., binary_part(digits, diff, length - diff)]
        else
          ["0.", zeroes(-diff), digits]
        end
      end

    iodata = if sign == -1, do: [?-, iodata], else: iodata
    IO.iodata_to_binary(iodata)
  end

  defp do_to_string(%Decimal{sign: sign, coef: coef, exp: exp}, :scientific) do
    digits = integer_to_decimal_binary(coef)
    length = byte_size(digits)
    adjusted = exp + length - 1

    iodata =
      cond do
        exp == 0 ->
          digits

        exp < 0 and adjusted >= -6 ->
          abs_exp = Kernel.abs(exp)
          diff = -length + abs_exp + 1

          if diff > 0 do
            ["0.", zeroes(diff - 1), digits]
          else
            split = length + exp
            [binary_part(digits, 0, split), ?., binary_part(digits, split, length - split)]
          end

        true ->
          mantissa =
            if length > 1 do
              [binary_part(digits, 0, 1), ?., binary_part(digits, 1, length - 1)]
            else
              digits
            end

          exp_sign = if exp >= 0, do: ?+, else: []
          [mantissa, ?E, exp_sign, :erlang.integer_to_binary(adjusted)]
      end

    iodata = if sign == -1, do: [?-, iodata], else: iodata
    IO.iodata_to_binary(iodata)
  end

  defp do_to_string(%Decimal{sign: sign, coef: coef, exp: exp}, :raw) do
    str = integer_to_decimal_binary(coef)
    str = if sign == -1, do: [?- | str], else: str
    str = if exp != 0, do: [str, "E", :erlang.integer_to_binary(exp)], else: str

    IO.iodata_to_binary(str)
  end

  defp do_to_string(%Decimal{} = decimal, :xsd) do
    decimal |> canonical_xsd() |> do_to_string(:normal)
  end

  defp zeroes(0), do: ""
  defp zeroes(count), do: :binary.copy("0", count)

  defp integer_to_decimal_binary(int) when int < @decimal_conversion_direct_limit do
    :erlang.integer_to_binary(int)
  end

  defp integer_to_decimal_binary(int) do
    digits = integer_decimal_digit_count(int)
    int |> integer_to_decimal_iodata(digits, false) |> IO.iodata_to_binary()
  end

  defp integer_to_decimal_iodata(int, digits, pad?)
       when digits <= @decimal_conversion_leaf_digits do
    binary = :erlang.integer_to_binary(int)

    if pad? do
      [zeroes(digits - byte_size(binary)), binary]
    else
      binary
    end
  end

  defp integer_to_decimal_iodata(int, digits, pad?) do
    low_digits = Kernel.div(digits, 2)
    high_digits = digits - low_digits
    base = decimal_power10(low_digits)
    high = Kernel.div(int, base)
    low = Kernel.rem(int, base)

    [
      integer_to_decimal_iodata(high, high_digits, pad?),
      integer_to_decimal_iodata(low, low_digits, true)
    ]
  end

  defp integer_decimal_digit_count(int) do
    bits = int |> :binary.encode_unsigned() |> bit_length()
    digits = Kernel.div((bits - 1) * @log10_2_num, @log10_2_den) + 1
    integer_decimal_digit_count(int, digits)
  end

  defp integer_decimal_digit_count(int, digits) do
    cond do
      int >= decimal_power10(digits) ->
        integer_decimal_digit_count(int, digits + 1)

      digits > 1 and int < decimal_power10(digits - 1) ->
        integer_decimal_digit_count(int, digits - 1)

      true ->
        digits
    end
  end

  defp decimal_power10(digits), do: :erlang.binary_to_integer("1" <> zeroes(digits))

  defp bit_length(<<byte, rest::binary>>) do
    byte_size(rest) * 8 + byte_bit_length(byte)
  end

  defp byte_bit_length(byte) when byte >= 128, do: 8
  defp byte_bit_length(byte) when byte >= 64, do: 7
  defp byte_bit_length(byte) when byte >= 32, do: 6
  defp byte_bit_length(byte) when byte >= 16, do: 5
  defp byte_bit_length(byte) when byte >= 8, do: 4
  defp byte_bit_length(byte) when byte >= 4, do: 3
  defp byte_bit_length(byte) when byte >= 2, do: 2
  defp byte_bit_length(_byte), do: 1

  @doc """
  Converts given number to its string representation with explicit limits.

  The following options are supported:

    * `:max_digits` - maximum number of digit characters in the output. Sign,
      decimal point, and exponent markers are not counted. Defaults to
      `#{@default_to_string_max_digits}`. Pass `:infinity` to disable.

  Raises `ArgumentError` when the configured limit would be exceeded.
  """
  doc_since("2.4.0")
  @spec to_string(t, :scientific | :normal | :xsd | :raw, [to_string_option]) :: String.t()
  def to_string(%Decimal{} = num, type, opts)
      when is_list(opts) and type in [:scientific, :normal, :xsd, :raw] do
    max_digits =
      limit!(:max_digits, Keyword.get(opts, :max_digits, @default_to_string_max_digits))

    check_to_string_max_digits!(num, type, max_digits)
    do_to_string(num, type)
  end

  defp canonical_xsd(%Decimal{coef: 0} = decimal), do: %{decimal | exp: -1}

  defp canonical_xsd(%Decimal{coef: coef, exp: exp} = decimal)
       when exp < 0 and Kernel.rem(coef, 10) != 0 do
    decimal
  end

  defp canonical_xsd(%Decimal{coef: coef, exp: exp} = decimal) do
    %Decimal{coef: coef, exp: exp} = do_normalize(coef, exp)

    if exp >= 0 do
      %{decimal | coef: coef * decimal_power10(exp + 1), exp: -1}
    else
      %{decimal | coef: coef, exp: exp}
    end
  end

  defp check_to_string_max_digits!(_num, _type, :infinity), do: :ok

  defp check_to_string_max_digits!(num, type, max_digits) do
    digits = to_string_digit_count(num, type)

    if digits > max_digits do
      raise ArgumentError,
            "#{inspect(type)} representation requires #{digits} digits, " <>
              "but the configured maximum is #{max_digits}"
    end
  end

  defp to_string_digit_count(%Decimal{coef: coef}, _type) when coef in [:NaN, :inf], do: 0

  defp to_string_digit_count(%Decimal{coef: coef, exp: exp}, :normal),
    do: normal_digit_count(coef, exp)

  defp to_string_digit_count(%Decimal{coef: coef, exp: exp}, :xsd),
    do: xsd_digit_count(coef, exp)

  defp to_string_digit_count(%Decimal{coef: coef, exp: exp}, :raw) do
    digits = coef_length(coef)
    if exp == 0, do: digits, else: digits + integer_digit_count(exp)
  end

  defp to_string_digit_count(%Decimal{coef: coef, exp: exp}, :scientific) do
    digits = coef_length(coef)
    adjusted = exp + digits - 1

    cond do
      exp == 0 -> digits
      exp < 0 and adjusted >= -6 -> normal_digit_count(coef, exp)
      true -> digits + integer_digit_count(adjusted)
    end
  end

  defp normal_digit_count(coef, exp) do
    digits = coef_length(coef)

    if exp >= 0 do
      digits + exp
    else
      diff = digits + exp

      if diff > 0 do
        digits
      else
        1 - diff + digits
      end
    end
  end

  defp xsd_digit_count(0, _exp), do: 2

  defp xsd_digit_count(coef, exp) do
    %Decimal{coef: coef, exp: exp} = do_normalize(coef, exp)

    if exp >= 0 do
      coef_length(coef) + exp + 1
    else
      normal_digit_count(coef, exp)
    end
  end

  defp integer_digit_count(int), do: int |> Kernel.abs() |> coef_length()

  @doc """
  Returns the decimal represented as an integer.

  Raises when loss of precision will occur.

  ## Examples

      iex> Decimal.to_integer(Decimal.new("42"))
      42

      iex> Decimal.to_integer(Decimal.new("1.00"))
      1

      iex> Decimal.to_integer(Decimal.new("1.10"))
      ** (ArgumentError) cannot convert Decimal.new("1.1") without losing precision. Use Decimal.round/3 first.

  """
  @spec to_integer(t) :: integer
  def to_integer(%Decimal{sign: sign, coef: coef, exp: 0})
      when is_integer(coef),
      do: sign * coef

  def to_integer(%Decimal{sign: sign, coef: coef, exp: exp})
      when is_integer(coef) and exp > 0,
      do: sign * coef * pow10(exp)

  def to_integer(%Decimal{sign: sign, coef: coef, exp: exp})
      when is_integer(coef) and exp < 0 do
    {coef, exp} = strip_trailing_zeros(coef, exp)

    if exp >= 0 do
      sign * coef * pow10(exp)
    else
      normalized = %Decimal{sign: sign, coef: coef, exp: exp}

      raise ArgumentError,
            "cannot convert #{inspect(normalized)} without losing precision. Use Decimal.round/3 first."
    end
  end

  @doc """
  Returns the decimal converted to a float.

  The returned float may have lower precision than the decimal.

  Raises if the decimal cannot be converted to a float.

  ## Examples

      iex> Decimal.to_float(Decimal.new("1.5"))
      1.5

      iex> Decimal.to_float(Decimal.new("-1.79769313486231581e308"))
      ** (Decimal.Error) : negative number smaller than DBL_MAX: Decimal.new("-1.79769313486231581E+308")

      iex> Decimal.to_float(Decimal.new("-1.79769313486231581e308"))
      ** (Decimal.Error) : negative number smaller than DBL_MAX: Decimal.new("-1.79769313486231581E+308")

      iex> Decimal.to_float(Decimal.new("2.22507385850720139e-308"))
      ** (Decimal.Error) : number smaller than DBL_MIN: Decimal.new("2.22507385850720139E-308")

      iex> Decimal.to_float(Decimal.new("-2.22507385850720139e-308"))
      ** (Decimal.Error): negative number bigger than DBL_MIN: Decimal.new(\"-2.22507385850720139E-308\")

      iex> Decimal.to_float(Decimal.new("inf"))
      ** (ArgumentError) Decimal.new("Infinity") cannot be converted to float

  """
  @spec to_float(t) :: float
  def to_float(%Decimal{coef: coef} = decimal) when is_integer(coef) do
    %Decimal{sign: sign, coef: coef, exp: exp} = check_dbl_min_max(decimal)
    # Convert back to float without loss
    # http://www.exploringbinary.com/correct-decimal-to-floating-point-using-big-integers/
    {num, den} = ratio(coef, exp)

    boundary = den <<< 52

    cond do
      num == 0 ->
        0.0

      num >= boundary ->
        {den, exp} = scale_down(num, boundary, 52)
        decimal_to_float(sign, num, den, exp)

      true ->
        {num, exp} = scale_up(num, boundary, 52)
        decimal_to_float(sign, num, den, exp)
    end
  end

  def to_float(%Decimal{} = decimal) do
    raise ArgumentError, "#{inspect(decimal)} cannot be converted to float"
  end

  @doc """
  Returns the scale of the decimal.

  A decimal's scale is the number of digits after the decimal point. This
  includes trailing zeros; see `normalize/1` to remove them.

  ## Examples

      iex> Decimal.scale(Decimal.new("42"))
      0

      iex> Decimal.scale(Decimal.new(1, 2, 26))
      0

      iex> Decimal.scale(Decimal.new("99.12345"))
      5

      iex> Decimal.scale(Decimal.new("1.50"))
      2
  """
  @spec scale(t) :: non_neg_integer()
  def scale(%Decimal{exp: exp}), do: Kernel.max(0, -exp)

  defp scale_up(num, den, exp) when num >= den, do: {num, exp}
  defp scale_up(num, den, exp), do: scale_up(num <<< 1, den, exp - 1)

  defp scale_down(num, den, exp) do
    new_den = den <<< 1

    if num < new_den do
      {den >>> 52, exp}
    else
      scale_down(num, new_den, exp + 1)
    end
  end

  defp decimal_to_float(sign, num, den, exp) do
    quo = Kernel.div(num, den)
    rem = num - quo * den

    tmp =
      case den >>> 1 do
        den when rem > den -> quo + 1
        den when rem < den -> quo
        _ when (quo &&& 1) === 1 -> quo + 1
        _ -> quo
      end

    sign = if sign == -1, do: 1, else: 0
    tmp = tmp - @power_of_2_to_52
    exp = if tmp < @power_of_2_to_52, do: exp, else: exp + 1
    <<tmp::float>> = <<sign::size(1), exp + 1023::size(11), tmp::size(52)>>
    tmp
  end

  @doc """
  Returns `true` when the given `decimal` has no significant digits after the decimal point.

  ## Examples

      iex> Decimal.integer?("1.00")
      true

      iex> Decimal.integer?("1.10")
      false

  """
  doc_since("2.0.0")
  @spec integer?(decimal()) :: boolean
  def integer?(%Decimal{coef: :NaN}), do: false
  def integer?(%Decimal{coef: :inf}), do: false
  def integer?(%Decimal{coef: 0}), do: true
  def integer?(%Decimal{exp: exp}) when exp >= 0, do: true
  def integer?(%Decimal{coef: coef, exp: exp}), do: trailing_zeros_at_least?(coef, -exp)
  def integer?(num), do: integer?(decimal(num))

  defp trailing_zeros_at_least?(_coef, 0), do: true

  defp trailing_zeros_at_least?(coef, n) when n >= @normalize_chunk do
    case Kernel.rem(coef, @normalize_chunk_pow) do
      0 ->
        trailing_zeros_at_least?(Kernel.div(coef, @normalize_chunk_pow), n - @normalize_chunk)

      _ ->
        false
    end
  end

  defp trailing_zeros_at_least?(coef, n) do
    Kernel.rem(coef, pow10(n)) == 0
  end

  ## ARITHMETIC ##

  defp add_align(coef1, exp1, coef2, exp2) when exp1 == exp2, do: {coef1, coef2}

  defp add_align(coef1, exp1, coef2, exp2) when exp1 > exp2,
    do: {coef1 * pow10(exp1 - exp2), coef2}

  defp add_align(coef1, exp1, coef2, exp2) when exp1 < exp2,
    do: {coef1, coef2 * pow10(exp2 - exp1)}

  defp add_zero(%Decimal{coef: 0, exp: zero_exp}, %Decimal{} = num) do
    %Decimal{sign: sign, coef: coef, exp: exp} = num

    cond do
      zero_exp >= exp ->
        context(num)

      exp - zero_exp > Context.get().precision + 2 ->
        add_bounded_zero(num)

      true ->
        context(%Decimal{sign: sign, coef: coef * pow10(exp - zero_exp), exp: zero_exp})
    end
  end

  defp add_bounded_zero(%Decimal{} = num) do
    work_digits = Context.get().precision + 2
    base_exp = Kernel.min(num.exp, adjust_exp(num) - work_digits + 1)
    {coef, false} = add_scale_to_base(num.coef, num.exp, base_exp)
    context(%Decimal{sign: num.sign, coef: coef, exp: base_exp})
  end

  defp add_bounded?(%Decimal{} = num1, %Decimal{} = num2) do
    precision = Context.get().precision
    Kernel.abs(adjust_exp(num1) - adjust_exp(num2)) > precision + 2
  end

  # Bounded addition for operands whose exponent gap exceeds `precision + 2`.
  # Aligning at the smaller exponent would materialize coefficients with
  # `gap` extra digits, which is unbounded for hostile input.
  #
  # Instead, scale both operands to a shared `base_exp` chosen `precision + 2`
  # digits below the larger operand's adjusted exponent. Digits below
  # `base_exp` are dropped, and any non-zero digits dropped from the smaller
  # operand are remembered as a sticky bit. `precision/4` then sees the same
  # guard, round, and sticky information it would have seen from the
  # full-precision sum, so rounding (including half-even tie-breaking and
  # subtractive cancellation toward zero in `add_sticky/3`) matches the
  # unbounded result.
  defp add_bounded(%Decimal{} = num1, %Decimal{} = num2) do
    {high, low} = add_bounded_order(num1, num2)

    work_digits = Context.get().precision + 2
    base_exp = Kernel.min(high.exp, adjust_exp(high) - work_digits + 1)

    {high_coef, false} = add_scale_to_base(high.coef, high.exp, base_exp)
    {low_coef, low_sticky?} = add_scale_to_base(low.coef, low.exp, base_exp)

    sum = high.sign * high_coef + low.sign * low_coef
    {sum, sticky?} = add_sticky(sum, low.sign, low_sticky?)
    sign = add_sign(num1.sign, num2.sign, sum)

    context(%Decimal{sign: sign, coef: Kernel.abs(sum), exp: base_exp}, [], sticky?)
  end

  defp add_bounded_order(%Decimal{coef: 0} = num1, %Decimal{} = num2), do: {num2, num1}
  defp add_bounded_order(%Decimal{} = num1, %Decimal{coef: 0} = num2), do: {num1, num2}

  defp add_bounded_order(%Decimal{} = num1, %Decimal{} = num2) do
    if adjust_exp(num1) >= adjust_exp(num2) do
      {num1, num2}
    else
      {num2, num1}
    end
  end

  defp add_scale_to_base(0, _exp, _base_exp), do: {0, false}

  defp add_scale_to_base(coef, exp, base_exp) when exp >= base_exp do
    {coef * pow10(exp - base_exp), false}
  end

  defp add_scale_to_base(coef, exp, base_exp) do
    drop = base_exp - exp

    if drop >= coef_length(coef) do
      {0, true}
    else
      divisor = pow10(drop)
      {Kernel.div(coef, divisor), Kernel.rem(coef, divisor) != 0}
    end
  end

  defp add_sticky(sum, _tail_sign, false), do: {sum, false}

  defp add_sticky(sum, tail_sign, true) do
    sum_sign = integer_sign(sum)

    cond do
      sum_sign == 0 -> {tail_sign, true}
      sum_sign == tail_sign -> {sum, true}
      true -> {sum - sum_sign, true}
    end
  end

  defp integer_sign(int) when int > 0, do: 1
  defp integer_sign(int) when int < 0, do: -1
  defp integer_sign(_int), do: 0

  defp add_sign(sign1, sign2, coef) do
    cond do
      coef > 0 -> 1
      coef < 0 -> -1
      sign1 == -1 and sign2 == -1 -> -1
      sign1 != sign2 and Context.get().rounding == :floor -> -1
      true -> 1
    end
  end

  defp div_adjust(coef1, coef2, adjust) when coef1 < coef2,
    do: div_adjust(coef1 * 10, coef2, adjust + 1)

  defp div_adjust(coef1, coef2, adjust) when coef1 >= coef2 * 10,
    do: div_adjust(coef1, coef2 * 10, adjust - 1)

  defp div_adjust(coef1, coef2, adjust), do: {coef1, coef2, adjust}

  defp div_calc(coef1, coef2, coef, adjust, prec10) do
    cond do
      coef1 >= coef2 ->
        div_calc(coef1 - coef2, coef2, coef + 1, adjust, prec10)

      coef1 == 0 and adjust >= 0 ->
        {coef, adjust, coef1, []}

      coef >= prec10 ->
        signals = [:rounded]
        signals = if base10?(coef1), do: signals, else: [:inexact | signals]
        {coef, adjust, coef1, signals}

      true ->
        div_calc(coef1 * 10, coef2, coef * 10, adjust + 1, prec10)
    end
  end

  defp div_int_calc(coef1, coef2, coef, adjust, precision) do
    cond do
      coef1 >= coef2 ->
        div_int_calc(coef1 - coef2, coef2, coef + 1, adjust, precision)

      adjust != precision ->
        div_int_calc(coef1 * 10, coef2, coef * 10, adjust + 1, precision)

      true ->
        {coef, coef1}
    end
  end

  defp integer_division(div_sign, coef1, exp1, coef2, exp2) do
    precision = exp1 - exp2
    {coef1, coef2, adjust} = div_adjust(coef1, coef2, 0)

    {coef, _rem} = div_int_calc(coef1, coef2, 0, adjust, precision)

    prec10 = pow10(Context.get().precision)

    if coef > prec10 do
      {
        :error,
        :invalid_operation,
        "integer division impossible, quotient too large",
        %Decimal{coef: :NaN}
      }
    else
      {:ok, %Decimal{sign: div_sign, coef: coef, exp: 0}}
    end
  end

  defp do_normalize(coef, exp) when coef >= @normalize_chunk_pow do
    case Kernel.rem(coef, @normalize_chunk_pow) do
      0 ->
        do_normalize(Kernel.div(coef, @normalize_chunk_pow), exp + @normalize_chunk)

      _ ->
        do_normalize_one(coef, exp)
    end
  end

  defp do_normalize(coef, exp), do: do_normalize_one(coef, exp)

  defp do_normalize_one(0, _exp), do: %Decimal{coef: 0, exp: 0}

  defp do_normalize_one(coef, exp) when Kernel.rem(coef, 10) == 0 do
    do_normalize_one(Kernel.div(coef, 10), exp + 1)
  end

  defp do_normalize_one(coef, exp), do: %Decimal{coef: coef, exp: exp}

  defp strip_trailing_zeros(coef, exp) when coef >= @normalize_chunk_pow do
    case Kernel.rem(coef, @normalize_chunk_pow) do
      0 ->
        strip_trailing_zeros(Kernel.div(coef, @normalize_chunk_pow), exp + @normalize_chunk)

      _ ->
        strip_trailing_zeros_one(coef, exp)
    end
  end

  defp strip_trailing_zeros(coef, exp), do: strip_trailing_zeros_one(coef, exp)

  defp strip_trailing_zeros_one(0, _exp), do: {0, 0}

  defp strip_trailing_zeros_one(coef, exp) when Kernel.rem(coef, 10) == 0 do
    strip_trailing_zeros_one(Kernel.div(coef, 10), exp + 1)
  end

  defp strip_trailing_zeros_one(coef, exp), do: {coef, exp}

  defp ratio(coef, exp) when exp >= 0, do: {coef * pow10(exp), 1}
  defp ratio(coef, exp) when exp < 0, do: {coef, pow10(-exp)}

  pow10_max =
    Enum.reduce(0..104, 1, fn int, acc ->
      defp pow10(unquote(int)), do: unquote(acc)
      defp base10?(unquote(acc)), do: true
      acc * 10
    end)

  defp pow10(num) when num > 104, do: pow10(104) * pow10(num - 104)

  defp base10?(num) when num >= unquote(pow10_max) do
    if Kernel.rem(num, unquote(pow10_max)) == 0 do
      base10?(Kernel.div(num, unquote(pow10_max)))
    else
      false
    end
  end

  defp base10?(_num), do: false

  ## ROUNDING ##

  defp do_round(sign, digits, exp, target_exp, rounding) do
    num_digits = length(digits)
    precision = num_digits - (target_exp - exp)

    cond do
      exp == target_exp ->
        %Decimal{sign: sign, coef: digits_to_integer(digits), exp: exp}

      exp < target_exp and precision < 0 ->
        zeros = :lists.duplicate(target_exp - exp, ?0)
        digits = zeros ++ digits
        {signif, remain} = :lists.split(1, digits)

        signif =
          if increment?(rounding, sign, signif, remain),
            do: digits_increment(signif),
            else: signif

        coef = digits_to_integer(signif)
        %Decimal{sign: sign, coef: coef, exp: target_exp}

      exp < target_exp and precision >= 0 ->
        {signif, remain} = :lists.split(precision, digits)

        signif =
          if increment?(rounding, sign, signif, remain),
            do: digits_increment(signif),
            else: signif

        coef = digits_to_integer(signif)
        %Decimal{sign: sign, coef: coef, exp: target_exp}

      exp > target_exp ->
        digits = digits ++ Enum.map(1..(exp - target_exp), fn _ -> ?0 end)
        coef = digits_to_integer(digits)
        %Decimal{sign: sign, coef: coef, exp: target_exp}
    end
  end

  defp digits_to_integer([]), do: 0
  defp digits_to_integer(digits), do: :erlang.list_to_integer(digits)

  defp precision(%Decimal{coef: :NaN} = num, _precision, _rounding, _sticky?) do
    {num, []}
  end

  defp precision(%Decimal{coef: :inf} = num, _precision, _rounding, _sticky?) do
    {num, []}
  end

  defp precision(%Decimal{sign: sign, coef: coef, exp: exp} = num, precision, rounding, sticky?) do
    digits = :erlang.integer_to_list(coef)
    num_digits = length(digits)

    cond do
      num_digits > precision ->
        do_precision(sign, digits, num_digits, exp, precision, rounding, sticky?)

      sticky? ->
        do_precision(sign, digits, num_digits, exp, num_digits, rounding, sticky?)

      true ->
        {num, []}
    end
  end

  defp do_precision(sign, digits, num_digits, exp, precision, rounding, sticky?) do
    precision = Kernel.min(num_digits, precision)
    {signif, remain} = :lists.split(precision, digits)

    signif =
      if increment?(rounding, sign, signif, remain, sticky?),
        do: digits_increment(signif),
        else: signif

    signals = if any_nonzero?(remain, sticky?), do: [:inexact, :rounded], else: [:rounded]

    exp = exp + (num_digits - precision)
    coef = digits_to_integer(signif)
    dec = %Decimal{sign: sign, coef: coef, exp: exp}
    {dec, signals}
  end

  defp increment?(rounding, sign, signif, remain),
    do: increment?(rounding, sign, signif, remain, false)

  defp increment?(_, _, _, [], false), do: false

  defp increment?(:down, _, _, _, _), do: false

  defp increment?(:up, _, _, _, _), do: true

  defp increment?(:ceiling, sign, _, remain, sticky?),
    do: sign == 1 and any_nonzero?(remain, sticky?)

  defp increment?(:floor, sign, _, remain, sticky?),
    do: sign == -1 and any_nonzero?(remain, sticky?)

  defp increment?(:half_up, _, _, [], _sticky?), do: false

  defp increment?(:half_up, _, _, [digit | _], _sticky?), do: digit >= ?5

  defp increment?(:half_even, _, _, [], _sticky?), do: false

  defp increment?(:half_even, _, [], [?5 | rest], sticky?), do: any_nonzero?(rest, sticky?)

  defp increment?(:half_even, _, signif, [?5 | rest], sticky?),
    do: any_nonzero?(rest, sticky?) or Kernel.rem(:lists.last(signif), 2) == 1

  defp increment?(:half_even, _, _, [digit | _], _sticky?), do: digit > ?5

  defp increment?(:half_down, _, _, [], _sticky?), do: false

  defp increment?(:half_down, _, _, [digit | rest], sticky?),
    do: digit > ?5 or (digit == ?5 and any_nonzero?(rest, sticky?))

  defp any_nonzero(digits), do: :lists.any(fn digit -> digit != ?0 end, digits)

  defp any_nonzero?(digits, sticky?), do: sticky? or any_nonzero(digits)

  defp digits_increment(digits), do: digits_increment(:lists.reverse(digits), [])

  defp digits_increment([?9 | rest], acc), do: digits_increment(rest, [?0 | acc])

  defp digits_increment([head | rest], acc), do: :lists.reverse(rest, [head + 1 | acc])

  defp digits_increment([], acc), do: [?1 | acc]

  ## CONTEXT ##

  defp context(num, signals \\ []), do: context(num, signals, false)

  defp context(num, signals, sticky?) do
    context = Context.get()
    {result, prec_signals} = precision(num, context.precision, context.rounding, sticky?)
    {result, exp_signals} = exponent_limits(result, context)
    signals = signals |> put_uniq(prec_signals) |> put_uniq(exp_signals)
    error(signals, nil, result, context)
  end

  defp exponent_limits(%Decimal{coef: coef} = num, _context) when coef in [:NaN, :inf, 0],
    do: {num, []}

  defp exponent_limits(%Decimal{} = num, %Context{} = context) do
    adjusted_exp = adjust_exp(num)

    cond do
      above_emax?(adjusted_exp, context.emax) ->
        {overflow_result(num, context), [:overflow, :inexact, :rounded]}

      below_emin?(adjusted_exp, context.emin) ->
        {%{num | coef: 0, exp: 0}, [:underflow, :inexact, :rounded]}

      true ->
        {num, []}
    end
  end

  defp above_emax?(_adjusted_exp, :infinity), do: false
  defp above_emax?(adjusted_exp, emax), do: adjusted_exp > emax

  defp below_emin?(_adjusted_exp, :infinity), do: false
  defp below_emin?(adjusted_exp, emin), do: adjusted_exp < emin

  defp overflow_result(%Decimal{sign: sign}, %Context{rounding: rounding} = context) do
    if overflow_to_infinity?(rounding, sign) do
      %Decimal{sign: sign, coef: :inf}
    else
      %Decimal{
        sign: sign,
        coef: pow10(context.precision) - 1,
        exp: context.emax - context.precision + 1
      }
    end
  end

  defp overflow_to_infinity?(:down, _sign), do: false
  defp overflow_to_infinity?(:floor, sign), do: sign == -1
  defp overflow_to_infinity?(:ceiling, sign), do: sign == 1
  defp overflow_to_infinity?(_rounding, _sign), do: true

  defp put_uniq(list, elems) when is_list(elems) do
    Enum.reduce(elems, list, &put_uniq(&2, &1))
  end

  defp put_uniq(list, elem) do
    if elem in list, do: list, else: [elem | list]
  end

  ## PARSING ##

  defp parse_limits!(opts) do
    Enum.reduce(
      opts,
      %{max_digits: @default_max_digits, max_exponent: @default_max_exponent},
      fn
        {:max_digits, value}, acc ->
          %{acc | max_digits: limit!(:max_digits, value)}

        {:max_exponent, value}, acc ->
          %{acc | max_exponent: limit!(:max_exponent, value)}

        {key, _value}, _acc ->
          raise ArgumentError, "unknown option #{inspect(key)}"
      end
    )
  end

  defp default_parse_limits do
    %{max_digits: @default_max_digits, max_exponent: @default_max_exponent}
  end

  defp limit!(_key, :infinity), do: :infinity

  defp limit!(_key, value) when is_integer(value) and value >= 0, do: value

  defp limit!(key, value) do
    raise ArgumentError,
          "#{inspect(key)} must be a non-negative integer or :infinity, got: #{inspect(value)}"
  end

  defp parse_digits_count(<<?0, rest::binary>>, acc, count, leading_zeros)
       when count == leading_zeros do
    parse_digits_count(rest, acc, count + 1, leading_zeros + 1)
  end

  defp parse_digits_count(<<digit, rest::binary>>, acc, count, leading_zeros)
       when digit in ?0..?9 do
    parse_digits_count(rest, [digit | acc], count + 1, leading_zeros)
  end

  defp parse_digits_count(rest, acc, count, leading_zeros) do
    {acc, count, leading_zeros, rest}
  end

  defp digits_acc_to_integer([], _size), do: 0
  defp digits_acc_to_integer(acc, _size), do: :erlang.list_to_integer(:lists.reverse(acc))

  defp parse_exp(<<e, sign, digit, rest::binary>>)
       when e in [?e, ?E] and sign in [?+, ?-] and digit in ?0..?9 do
    {digits, rest} = parse_digits(rest)
    {[sign, digit | digits], rest}
  end

  defp parse_exp(<<e, digit, rest::binary>>) when e in [?e, ?E] and digit in ?0..?9 do
    {digits, rest} = parse_digits(rest)
    {[digit | digits], rest}
  end

  defp parse_exp(bin) do
    {[], bin}
  end

  defp parse_unsign(<<first, remainder::size(7)-binary, rest::binary>>, _limits)
       when first in [?i, ?I] do
    if String.downcase(remainder) == "nfinity" do
      {%Decimal{coef: :inf}, rest}
    else
      :error
    end
  end

  defp parse_unsign(<<first, remainder::size(2)-binary, rest::binary>>, _limits)
       when first in [?i, ?I] do
    if String.downcase(remainder) == "nf" do
      {%Decimal{coef: :inf}, rest}
    else
      :error
    end
  end

  defp parse_unsign(<<first, remainder::size(2)-binary, rest::binary>>, _limits)
       when first in [?n, ?N] do
    if String.downcase(remainder) == "an" do
      {%Decimal{coef: :NaN}, rest}
    else
      :error
    end
  end

  defp parse_unsign(bin, limits) do
    {int_rev, int_size, leading_zeros, after_int} = parse_digits_count(bin, [], 0, 0)

    {coef_rev, total_size, leading_zeros, after_float} =
      case after_int do
        <<?., after_dot::binary>> ->
          parse_digits_count(after_dot, int_rev, int_size, leading_zeros)

        _ ->
          {int_rev, int_size, leading_zeros, after_int}
      end

    cond do
      total_size == 0 ->
        :error

      exceeds_limit?(total_size - leading_zeros, limits.max_digits) ->
        :error

      true ->
        {exp, rest} = parse_exp(after_float)
        exp_chars = if exp == [], do: ~c"0", else: exp
        float_size = total_size - int_size

        case bounded_exponent(exp_chars, float_size, limits.max_exponent) do
          {:ok, exp_int} ->
            coef = digits_acc_to_integer(coef_rev, total_size)
            {%Decimal{coef: coef, exp: exp_int}, rest}

          :error ->
            :error
        end
    end
  end

  defp decimal_within_limits?(%Decimal{coef: coef, exp: exp}, limits) do
    not exceeds_limit?(decimal_digit_count(coef), limits.max_digits) and
      within_exponent_limit?(exp, limits.max_exponent)
  end

  defp decimal_digit_count(coef) when coef in [:NaN, :inf], do: 0
  defp decimal_digit_count(coef), do: coef_length(coef)

  defp exceeds_limit?(_value, :infinity), do: false
  defp exceeds_limit?(value, limit), do: value > limit

  defp within_exponent_limit?(_exp, :infinity), do: true
  defp within_exponent_limit?(exp, max_exponent), do: Kernel.abs(exp) <= max_exponent

  defp bounded_exponent(chars, float_digits, :infinity) do
    {:ok, List.to_integer(chars) - float_digits}
  end

  defp bounded_exponent(chars, float_digits, max_exponent) do
    with {:ok, exp} <- bounded_integer(chars, max_exponent + float_digits) do
      exp = exp - float_digits
      if within_exponent_limit?(exp, max_exponent), do: {:ok, exp}, else: :error
    end
  end

  defp bounded_integer([?- | digits], bound) do
    with {:ok, int} <- bounded_non_neg_integer(digits, bound), do: {:ok, -int}
  end

  defp bounded_integer([?+ | digits], bound), do: bounded_non_neg_integer(digits, bound)
  defp bounded_integer(digits, bound), do: bounded_non_neg_integer(digits, bound)

  defp bounded_non_neg_integer(digits, bound) do
    digits = trim_leading_zeroes(digits)
    bound_digits = integer_to_charlist(bound)
    digits_length = length(digits)
    bound_length = length(bound_digits)

    cond do
      digits == [] ->
        {:ok, 0}

      digits_length > bound_length ->
        :error

      digits_length == bound_length and digits_gt?(digits, bound_digits) ->
        :error

      true ->
        {:ok, List.to_integer(digits)}
    end
  end

  defp trim_leading_zeroes([?0 | rest]), do: trim_leading_zeroes(rest)
  defp trim_leading_zeroes(digits), do: digits

  defp digits_gt?([digit | rest1], [digit | rest2]), do: digits_gt?(rest1, rest2)
  defp digits_gt?([digit1 | _], [digit2 | _]), do: digit1 > digit2
  defp digits_gt?([], []), do: false

  defp parse_digits(bin), do: parse_digits(bin, [])

  defp parse_digits(<<digit, rest::binary>>, acc) when digit in ?0..?9 do
    parse_digits(rest, [digit | acc])
  end

  defp parse_digits(rest, acc) do
    {:lists.reverse(acc), rest}
  end

  # Util

  defp decimal(%Decimal{} = num), do: num
  defp decimal(num) when is_integer(num), do: new(num)
  defp decimal(num) when is_binary(num), do: new(num)

  defp decimal(other) when is_float(other) do
    raise ArgumentError,
          "implicit conversion of #{inspect(other)} to Decimal is not allowed. Use Decimal.from_float/1"
  end

  defp handle_error(signals, reason, result, context) do
    context = context || Context.get()
    signals = List.wrap(signals)

    flags = Enum.reduce(signals, context.flags, &put_uniq(&2, &1))
    Context.set(%{context | flags: flags})
    error_signal = Enum.find(signals, &(&1 in context.traps))

    if error_signal do
      error = [signal: error_signal, reason: reason]
      {:error, error}
    else
      {:ok, result}
    end
  end

  defp fix_float_exp(digits) do
    fix_float_exp(digits, [])
  end

  defp fix_float_exp([?e | rest], [?0 | [?. | result]]) do
    fix_float_exp(rest, [?e | result])
  end

  defp fix_float_exp([digit | rest], result) do
    fix_float_exp(rest, [digit | result])
  end

  defp fix_float_exp([], result), do: :lists.reverse(result)

  defp check_dbl_min_max(%Decimal{sign: 1} = num) do
    cond do
      Decimal.gt?(num, dbl_max(1)) ->
        raise Error, reason: "number bigger than DBL_MAX: #{inspect(num)}"

      Decimal.gt?(num, zero(1)) and Decimal.lt?(num, dbl_min(1)) ->
        raise Error, reason: "number smaller than DBL_MIN: #{inspect(num)}"

      true ->
        num
    end
  end

  defp check_dbl_min_max(num) do
    cond do
      Decimal.lt?(num, dbl_max(-1)) ->
        raise Error, reason: "negative number smaller than DBL_MAX: #{inspect(num)}"

      Decimal.lt?(num, zero(-1)) and Decimal.gt?(num, dbl_min(-1)) ->
        raise Error, reason: "negative number bigger than DBL_MIN: #{inspect(num)}"

      true ->
        num
    end
  end

  defp dbl_min(sign), do: %Decimal{sign: sign, coef: 22_250_738_585_072_014, exp: -324}
  defp zero(sign), do: %Decimal{sign: sign, coef: 0, exp: 0}
  defp dbl_max(sign), do: %Decimal{sign: sign, coef: 17_976_931_348_623_158, exp: 292}

  if Version.compare(System.version(), "1.3.0") == :lt do
    defp integer_to_charlist(string), do: Integer.to_char_list(string)
  else
    defp integer_to_charlist(string), do: Integer.to_charlist(string)
  end
end

defimpl Inspect, for: Decimal do
  def inspect(dec, _opts) do
    "Decimal.new(\"" <> Decimal.to_string(dec, :scientific, max_digits: :infinity) <> "\")"
  end
end

defimpl String.Chars, for: Decimal do
  def to_string(dec) do
    Decimal.to_string(dec, :scientific, max_digits: :infinity)
  end
end

# TODO: remove when we require Elixir 1.18
if Code.ensure_loaded?(JSON.Encoder) and function_exported?(JSON.Encoder, :encode, 2) do
  defimpl JSON.Encoder, for: Decimal do
    def encode(decimal, _encoder) do
      [?", Decimal.to_string(decimal, :scientific, max_digits: :infinity), ?"]
    end
  end
end
