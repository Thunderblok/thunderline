# Custom Postgrex type definitions for Thunderline.
#
# Registers the `vector` type from pgvector extension so that Ecto
# can properly encode/decode vector columns.
#
# Uses AshPostgres.Extensions.Vector which handles encoding/decoding
# of Ash.Vector structs to PostgreSQL vector binary format.
#
# NOTE: This file must NOT use `defmodule` - Postgrex.Types.define
# creates the module itself. See ash_postgres documentation.

Postgrex.Types.define(
  Thunderline.PostgresTypes,
  [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
