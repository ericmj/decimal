defmodule Decimal.Mixfile do
  use Mix.Project

  def project do
    [ app: :decimal,
      version: "0.0.1",
      elixir: "~> 0.12.3",
      deps: deps(Mix.env),
      name: "Decimal",
      source_url: "https://github.com/ericmj/decimal",
      docs: fn -> [
        source_ref: System.cmd("git rev-parse --verify --quiet HEAD"),
        readme: true ]
      end ]
  end

  # Configuration for the OTP application
  def application do
    []
  end

  # Returns the list of dependencies in the format:
  # { :foobar, git: "https://github.com/elixir-lang/foobar.git", tag: "0.1" }
  #
  # To specify particular versions, regardless of the tag, do:
  # { :barbat, "~> 0.1", github: "elixir-lang/barbat.git" }
  defp deps(:dev) do
    [ { :ex_doc, github: "elixir-lang/ex_doc" } ]
  end

  defp deps(_), do: []
end
