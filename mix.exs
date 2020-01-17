defmodule Decimal.Mixfile do
  use Mix.Project

  @version "2.0.0-dev"

  def project() do
    [
      app: :decimal,
      version: @version,
      elixir: "~> 1.2",
      deps: deps(),
      name: "Decimal",
      source_url: "https://github.com/ericmj/decimal",
      docs: [source_ref: "v#{@version}", main: "readme", extras: ["README.md"]],
      description: description(),
      package: package()
    ]
  end

  def application() do
    []
  end

  defp deps() do
    [
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description() do
    "Arbitrary precision decimal arithmetic."
  end

  defp package() do
    [
      maintainers: ["Eric Meadows-Jönsson"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/ericmj/decimal"}
    ]
  end
end
