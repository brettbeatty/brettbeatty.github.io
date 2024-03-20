defmodule MyProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "2024.3.19",
      elixir: "~> 1.16",
      deps: deps(),
      # docs
      name: "Brett Beatty's Dev Blog",
      docs: [
        main: "home",
        extras:
          ["README.md": [filename: "home", title: "Home"]] ++
            Path.wildcard("pages/**/*.{md,livemd}"),
        groups_for_extras: [
          Experiments: ~r(/experiments/),
          Legacy: ~r(/legacy/)
        ],
        api_reference: false,
        formatters: ["html"]
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
