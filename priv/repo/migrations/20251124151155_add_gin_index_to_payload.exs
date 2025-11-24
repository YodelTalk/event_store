defmodule EventStore.Adapter.Postgres.Repo.Migrations.AddGinIndexToPayload do
  use Ecto.Migration
  @disable_ddl_transaction true

  def up do
    # Using gin and trgm extension in order to perform ilike and text queries.
    # something like: `WHERE payload LIKE '%RecordingStartTime%'`
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE INDEX CONCURRENTLY IF NOT EXISTS events_payload_gin_idx ON events USING gin (payload gin_trgm_ops)")
  end

  def down do
    # No need to remove the pg_trgm extension, which may cause errors if already used somewhere else.
    execute("DROP INDEX CONCURRENTLY IF EXISTS events_payload_gin_idx")
  end
end
