defmodule EventStore.Adapters.Postgres do
  @behaviour EventStore.Adapter

  import Ecto.Query

  alias EventStore.Event
  alias EventStore.Adapters.Postgres.Repo

  @impl true
  defdelegate insert(changeset), to: Repo

  @impl true
  def stream(aggregate_id) do
    from(e in Event, where: e.aggregate_id == ^aggregate_id, order_by: :id)
    |> Repo.all()
  end

  @impl true
  def exists?(aggregate_id, name) do
    from(e in Event, where: e.aggregate_id == ^aggregate_id and e.name == ^name)
    |> Repo.exists?()
  end
end
