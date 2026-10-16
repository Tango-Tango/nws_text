defmodule NwsText.MixProject do
  use Mix.Project

  @version "0.0.0"
  @source_url "https://github.com/Tango-Tango/nws_text"

  def project do
    [
      app: :nws_text,
      name: "NwsText",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Parse National Weather Service text products, VTEC, UGC, polygons, narrative, and embedded CAP.",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ] ++ umbrella_config()
  end

  def cli, do: [preferred_envs: ["test.json": :test]]

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:geo, "~> 4.1"},
      {:saxy, "~> 1.6"},
      {:nimble_parsec, "~> 1.4"},
      {:jason, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_unit_json, "~> 0.6", only: :test, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "pyIEM" => "https://github.com/akrherz/pyIEM"},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md"], source_ref: "v#{@version}"]
  end

  # Inside a parent umbrella's apps/ directory, share its build, deps, lockfile, and config.
  defp umbrella_config do
    root = Path.expand("../..", __DIR__)

    if Path.basename(Path.dirname(__DIR__)) == "apps" and File.exists?(Path.join(root, "mix.lock")) do
      [
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock",
        elixirc_options: [warnings_as_errors: System.get_env("ELIXIR_WARNINGS_OK") == nil]
      ]
    else
      []
    end
  end
end
