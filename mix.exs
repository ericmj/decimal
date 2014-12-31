defmodule Decimal.Mixfile do
  use Mix.Project

  def project do
    [app: :decimal,
     version: "1.1.0",
     elixir: "~> 1.0",
     deps: deps,
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
    [{:ex_doc, only: :dev},
     {:earmark, only: :dev}]
  end

  defp description do
    """
    Arbitrary precision decimal arithmetic for Elixir.
    """
  end

  defp package do
    [contributors: ["Eric Meadows-Jönsson"],
     licenses: ["Apache 2.0"],
     links: %{"Github" => "https://github.com/ericmj/decimal"}]
  end
end
