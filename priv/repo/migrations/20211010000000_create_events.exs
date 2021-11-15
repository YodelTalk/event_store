defmodule EventStore.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :name, :string, null: false
      add :version, :integer, null: false
      add :aggregate_id, :string, null: false
      add :aggregate_version, :bigint, null: false
      add :payload, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end
  end
end
