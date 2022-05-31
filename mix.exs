defmodule DryStruct.MixProject do
  use Mix.Project

  def project do
    [
      app: :dry_struct,
      version: "0.1.0",
      elixir: "~> 1.11",
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      flags: ~w[error_handling underspecs unknown unmatched_returns]a
    ]
  end
end
