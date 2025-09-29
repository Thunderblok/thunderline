defmodule ThunderlineWeb.GraphqlSchema do
  use Absinthe.Schema

  use AshGraphql,
    domains: [
      Thunderline.Thunderlink.Domain,
      Thunderline.Thundergrid.Domain,
      Thunderline.Thunderbolt.Domain
    ]

  import_types Absinthe.Plug.Types

  query do
    @desc "Simple health probe for GraphQL wiring"
    field :graphql_ready, :boolean do
      resolve fn _, _, _ ->
        {:ok, true}
      end
    end
  end

  mutation do
    # Custom Absinthe mutations can be placed here
  end

  subscription do
    # Custom Absinthe subscriptions can be placed here
  end

  # Add proper error handling middleware
  def middleware(middleware, _field, %{identifier: :mutation}) do
    middleware ++ [AshGraphql.DefaultErrorHandler]
  end

  def middleware(middleware, _field, _object) do
    middleware
  end
end
