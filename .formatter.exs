[
  import_deps: [
    :ash_postgres,
    :ash_admin,
    :ash_graphql,
    :absinthe,
    :ash_ai,
    :ash_phoenix,
    :ash,
    :ash_cloak,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Absinthe.Formatter, Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
