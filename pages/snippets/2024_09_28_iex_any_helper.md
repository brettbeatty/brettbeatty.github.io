# IEx "any" Helper

When developing Phoenix apps I often find myself wanting to grab a resource from the database. Usually any instance of the schema will do.

In the past I would just write a short Ecto query that would look something like this:

    iex> Repo.one(from(User, limit: 1))

Working on [Surge](https://surgemsg.com/) I decided I do this frequently enough I would create a helper to make it even easier.

    iex> any User
    #Surge.Accounts.User<
      __meta__: #Ecto.Schema.Metadata<:loaded, "users">,
      id: "add88424-01bf-443d-b970-bd46f8adf75a",
      email: "user@example.com",
      confirmed_at: ~U[2024-09-28 03:59:53Z],
      inserted_at: ~U[2024-09-28 03:55:36Z],
      updated_at: ~U[2024-09-28 03:59:53Z],
      ...
    >

The big trick to this helper is only defining it if `Repo` exists. Then the utility is available in `iex -S mix` but doesn't cause problems if I just run `iex`.

### .iex.exs

    import_if_available(Ecto.Query)

    alias Surge.Accounts.User
    alias Surge.Repo

    defmodule IExHelpers do
      if Code.ensure_loaded?(Repo) do
        def any(query) do
          query
          |> limit(1)
          |> Repo.one()
        end
      end
    end

    import IExHelpers

