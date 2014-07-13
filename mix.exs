defmodule Decimal.Mixfile do
  use Mix.Project

  def project do
    [app: :decimal,
     version: "0.2.3-dev",
     elixir: "~> 0.14.3",
     deps: deps,
     build_per_environment: false,
     name: "Decimal",
     source_url: "https://github.com/ericmj/decimal",
     docs: fn ->
       {ref, 0} = System.cmd("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
       [source_ref: ref, readme: true]
     end,
     description: description,
     package: package]
  end

  def application do
    []
  end

  defp deps do
    [{:ex_doc, github: "elixir-lang/ex_doc", only: :dev},
     {:markdown, github: "devinus/markdown", only: :dev}]
  end

  defp description do
    """
    Arbitrary precision decimal arithmetic for Elixir.
    """
  end

  defp package do
    [contributors: ["Eric Meadows-Jönsson"],
     licenses: ["Apache 2.0"],
     links: %{"Github" => "https://github.com/ericmj/decimal",
              "Documentation" => "http://ericmj.github.io/decimal"}]
  end
end
