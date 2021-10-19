defmodule EventStore.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :name, :string, null: false
      add :version, :integer, null: false
      add :aggregate_id, :string, null: false
      add :aggregate_version, :integer, null: false
      add :payload, :text

      timestamps updated_at: false, null: false
    end
  end
end
