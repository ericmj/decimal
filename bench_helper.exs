defmodule BenchHelper do
  @moduledoc false

  # Both bench scripts must measure the same checkout the same way, so the
  # install preamble lives here. Returns the path of the code under test.
  def install!(extra_deps \\ []) do
    decimal_path = System.get_env("DECIMAL_PATH", ".")

    Mix.install([{:decimal, path: decimal_path, override: true} | extra_deps])

    if Mix.env() != :prod do
      IO.puts(:stderr, "refusing to benchmark a #{Mix.env()} build; rerun with MIX_ENV=prod")
      System.halt(1)
    end

    decimal_path
  end

  # Values at a fixed scale with small coefficients: the shape of monetary
  # amounts. The cents are zero-padded so every value has exponent -2 and the
  # same-exponent paths of `add/2` and `compare/2` are what run.
  def money_strings do
    for i <- 1..200 do
      "#{i * 37}.#{String.pad_leading("#{Integer.mod(i * 13, 100)}", 2, "0")}"
    end
  end
end
