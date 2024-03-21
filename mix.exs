defmodule MyProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "2024.3.20",
      elixir: "~> 1.16",
      deps: deps(),
      # docs
      name: "Brett's Dev Blog",
      docs: docs()
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    pages =
      "pages/**/*.{md,livemd}"
      |> Path.wildcard()
      |> Enum.sort_by(&Path.basename/1, :desc)

    [
      main: latest(pages),
      extras: pages,
      groups_for_extras: [
        Experiments: ~r(/experiments/),
        Legacy: ~r(/legacy/)
      ],
      api_reference: false,
      formatters: ["html"],
      # assets: "assets",
      logo: "assets/logo.jpg"
    ]
  end

  defp latest(pages) do
    pages
    |> hd()
    |> Path.basename()
    |> Path.rootname()
  end
end
