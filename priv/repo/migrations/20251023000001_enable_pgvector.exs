defmodule Thunderline.Repo.Migrations.EnablePgvector do
  @moduledoc """
  Enables the pgvector extension for storing and querying vector embeddings.

  Required for RAG (Retrieval-Augmented Generation) document storage and
  semantic search capabilities.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS vector")
  end
end
