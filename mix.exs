defmodule ConfigApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :config_api,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {ConfigApi.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:jason, "~> 1.2"},
      {:memento, "~> 0.5.0"},
      # EventStore dependencies for CQRS migration
      {:eventstore, "~> 1.4.8"},
      {:postgrex, "~> 0.21.1"},
      # Schema validation for OpenAPI contract tests
      {:ex_json_schema, "~> 0.10", only: [:test]},
      {:yaml_elixir, "~> 2.11", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
