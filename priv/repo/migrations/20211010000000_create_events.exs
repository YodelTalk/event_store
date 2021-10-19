defmodule EventStore.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :name, :string
      add :version, :integer
      add :aggregate_id, :string
      add :aggregate_version, :integer, default: 1
      add :payload, :text

      timestamps updated_at: false
    end
  end
end
