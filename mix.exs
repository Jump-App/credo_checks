defmodule Jump.CredoChecks.MixProject do
  use Mix.Project

  @source_url "https://github.com/Jump-App/credo_checks"

  def project do
    [
      app: :jump_credo_checks,
      version: "0.1.0",
      elixir: "~> 1.18",
      consolidate_protocols: Mix.env() != :test,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      description:
        "A collection of opinionated Credo checks aimed at improving code quality and catching common mistakes in Elixir, Oban, and LiveView",
      name: "Jump.CredoChecks",
      package: package(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      test_load_filters: [&(String.ends_with?(&1, "_test.exs") and not String.contains?(&1, "fixtures"))],
      test_ignore_filters: [&String.contains?(&1, "fixtures")],
      preferred_cli_env: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    []
  end

  def cli do
    [
      preferred_envs: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.json": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md"],
      maintainers: ["Tyler Young"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      check: [
        "clean",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test --warnings-as-errors",
        "credo"
      ],
      setup: ["deps.get"]
    ]
  end
end
