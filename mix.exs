Code.ensure_loaded?(Hex) and Hex.start

defmodule Decimal.Mixfile do
  use Mix.Project

  def project do
    [ app: :decimal,
      version: "0.1.2",
      elixir: "~> 0.13.0",
      deps: deps(Mix.env),
      build_per_environment: false,
      name: "Decimal",
      source_url: "https://github.com/ericmj/decimal",
      docs: fn -> [
        source_ref: System.cmd("git rev-parse --verify --quiet HEAD"),
        readme: true ]
      end,
      description: description,
      package: package ]
  end

  def application do
    []
  end

  defp deps(:dev) do
    [ { :ex_doc, github: "elixir-lang/ex_doc" } ]
  end

  defp deps(_), do: []

  defp description do
    """
    Arbitrary precision decimal arithmetic for Elixir.
    """
  end

  defp package do
    [ contributors: ["Eric Meadows-Jönsson"],
      licenses: ["Apache 2.0"],
      links: [ { "Github", "https://github.com/ericmj/decimal" },
               { "Documentation", "http://ericmj.github.io/decimal" } ] ]
  end
end
