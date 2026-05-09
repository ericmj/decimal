defmodule Decimal.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import DecimalGenerators

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

  describe "algebraic identities" do
    property "add/2 is commutative" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.add(a, b), Decimal.add(b, a)) == :eq
      end
    end

    property "add/2 with zero is identity" do
      zero = Decimal.new(0)

      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.add(a, zero), a) == :eq
      end
    end

    property "add/2 of a and negate(a) is zero" do
      zero = Decimal.new(0)

      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.add(a, Decimal.negate(a)), zero) == :eq
      end
    end

    property "sub/2 equals add(a, negate(b))" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.sub(a, b), Decimal.add(a, Decimal.negate(b))) == :eq
      end
    end

    property "mult/2 is commutative" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.mult(a, b), Decimal.mult(b, a)) == :eq
      end
    end

    property "mult/2 with one is identity" do
      one = Decimal.new(1)

      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.mult(a, one), a) == :eq
      end
    end

    property "mult/2 with zero is zero" do
      zero = Decimal.new(0)

      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.mult(a, zero), zero) == :eq
      end
    end

    property "negate/1 is involutive" do
      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.negate(Decimal.negate(a)), a) == :eq
      end
    end

    property "abs/1 of negation equals abs" do
      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.abs(Decimal.negate(a)), Decimal.abs(a)) == :eq
      end
    end

    property "abs/1 is non-negative" do
      zero = Decimal.new(0)

      check all(a <- decimal(), max_runs: 100) do
        refute Decimal.compare(Decimal.abs(a), zero) == :lt
      end
    end
  end

  describe "comparison predicates agree with compare/2" do
    property "gt?/2" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.gt?(a, b) == (Decimal.compare(a, b) == :gt)
      end
    end

    property "lt?/2" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.lt?(a, b) == (Decimal.compare(a, b) == :lt)
      end
    end

    property "gte?/2" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        cmp = Decimal.compare(a, b)
        assert Decimal.gte?(a, b) == (cmp == :gt or cmp == :eq)
      end
    end

    property "lte?/2" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        cmp = Decimal.compare(a, b)
        assert Decimal.lte?(a, b) == (cmp == :lt or cmp == :eq)
      end
    end

    property "eq?/2" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.eq?(a, b) == (Decimal.compare(a, b) == :eq)
      end
    end

    property "equal?/2" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        assert Decimal.equal?(a, b) == (Decimal.compare(a, b) == :eq)
      end
    end
  end

  describe "min/2 and max/2" do
    property "min/2 result is not greater than either input" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        m = Decimal.min(a, b)
        refute Decimal.compare(m, a) == :gt
        refute Decimal.compare(m, b) == :gt
      end
    end

    property "max/2 result is not less than either input" do
      check all(a <- decimal(), b <- decimal(), max_runs: 100) do
        m = Decimal.max(a, b)
        refute Decimal.compare(m, a) == :lt
        refute Decimal.compare(m, b) == :lt
      end
    end
  end

  describe "normalize/1" do
    property "is idempotent" do
      check all(a <- decimal(), max_runs: 100) do
        n = Decimal.normalize(a)
        assert Decimal.normalize(n) == n
      end
    end

    property "preserves value" do
      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.compare(Decimal.normalize(a), a) == :eq
      end
    end
  end

  describe "sign predicates" do
    property "positive?/1 agrees with compare/2 against zero" do
      zero = Decimal.new(0)

      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.positive?(a) == (Decimal.compare(a, zero) == :gt)
      end
    end

    property "negative?/1 agrees with compare/2 against zero" do
      zero = Decimal.new(0)

      check all(a <- decimal(), max_runs: 100) do
        assert Decimal.negative?(a) == (Decimal.compare(a, zero) == :lt)
      end
    end
  end

  describe "round-trip" do
    property "to_string(:scientific) parses back to the same value" do
      check all(a <- decimal(), max_runs: 100) do
        s = Decimal.to_string(a, :scientific)
        assert {parsed, ""} = Decimal.parse(s, max_digits: :infinity, max_exponent: :infinity)
        assert Decimal.compare(parsed, a) == :eq
      end
    end

    property "inspect output parses back at default decimal128 limits" do
      gen =
        decimal(
          coef_max: 9_999_999_999_999_999_999_999_999_999_999_999,
          exp_min: -6144,
          exp_max: 6144
        )

      check all(a <- gen, max_runs: 200) do
        s = Decimal.to_string(a, :scientific, max_digits: :infinity)
        assert {parsed, ""} = Decimal.parse(s)
        assert parsed == a
      end
    end

    property "Decimal.new/1 of an integer round-trips through to_integer/1" do
      check all(n <- StreamData.integer(), max_runs: 100) do
        d = Decimal.new(n)
        assert Decimal.to_integer(d) == n
        assert Decimal.integer?(d)
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
