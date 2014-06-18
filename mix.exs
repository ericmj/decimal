Code.ensure_loaded?(Hex) and Hex.start

defmodule Decimal.Mixfile do
  use Mix.Project

  def project do
    [ app: :decimal,
      version: "0.2.2",
      elixir: "== 0.13.3 or ~> 0.14.0",
      deps: deps,
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

  defp deps do
    [ { :ex_doc, github: "elixir-lang/ex_doc", only: :dev },
      { :markdown, github: "devinus/markdown", only: :dev } ]
  end

  defp description do
    """
    Arbitrary precision decimal arithmetic for Elixir.
    """
  end

  defp package do
    [ contributors: ["Eric Meadows-Jönsson"],
      licenses: ["Apache 2.0"],
      links: %{"Github" => "https://github.com/ericmj/decimal",
               "Documentation" => "http://ericmj.github.io/decimal"} ]
  end
end
