defmodule EventStore.Adapters.Postgres.Repo.Migrations.AddIndices do
  use Ecto.Migration

  def change do
    create index("events", [:name])
    create index("events", [:aggregate_id])
    create index("events", [:name, :aggregate_id])
  end
end
