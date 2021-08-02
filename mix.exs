defmodule JSONAPI.Mixfile do
  use Mix.Project

  def project do
    [
      app: :jsonapi,
      version: "1.3.0",
      package: package(),
      compilers: compilers(Mix.env()),
      description: description(),
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/jeregrine/jsonapi",
      deps: deps(),
      dialyzer: dialyzer(),
      docs: [
        extras: [
          "README.md"
        ],
        main: "readme"
      ]
    ]
  end

  # Use Phoenix compiler depending on environment.
  defp compilers(:test), do: [:phoenix] ++ Mix.compilers()
  defp compilers(_), do: Mix.compilers()

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp dialyzer do
    [
      plt_add_deps: :app_tree
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, "~> 0.20", only: :dev},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.0", only: :test},
      {:plug, "~> 1.0"}
    ]
  end

  defp package do
    [
      maintainers: [
        "Jason Stiebs",
        "Mitchell Henke",
        "Jake Robers",
        "Sean Callan",
        "James Herdman"
      ],
      licenses: ["MIT"],
      links: %{github: "https://github.com/jeregrine/jsonapi", docs: "http://hexdocs.pm/jsonapi/"}
    ]
  end

  defp description do
    """
    Fully functional JSONAPI V1 Serializer as well as a QueryParser for Plug based projects and applications.
    """
  end
end
