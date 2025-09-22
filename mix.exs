defmodule Responses.MixProject do
  use Mix.Project

  def project do
    [
      app: :responses,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for the Responses API",
      package: package(),
      docs: docs(),

      # Project metadata
      name: "Responses",
      source_url: "https://github.com/vkryukov/responses"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:jaxon, "~> 2.0"},
      {:decimal, "~> 2.0"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/vkryukov/responses"},
      maintainers: ["Victor Kryukov"],
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* usage-rules.md)
    ]
  end

  defp docs do
    [
      # Set README.md as the main page
      main: "readme",

      # Include documentation files
      extras: [
        "README.md",
        "CHANGELOG.md",
        {"CHANGELOG_OLD.md", [title: "Legacy Changelog"]},
        "tutorial.livemd"
      ],

      # Group documentation sections
      groups_for_extras: [
        Guides: ["README.md", "CHANGELOG.md", "CHANGELOG_OLD.md"],
        "Interactive Tutorials": ~r/\.livemd$/
      ],

      # Organize modules in the sidebar
      groups_for_modules: [
        "Main API": [
          Responses
        ],
        "Supporting Modules": [
          Responses.Response,
          Responses.Stream,
          Responses.Schema,
          Responses.Pricing,
          Responses.Prompt
        ]
      ]
    ]
  end
end
