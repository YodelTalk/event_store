defmodule EventStore.Adapters.Postgres do
  @behaviour EventStore.Adapter

  import Ecto.Query
  alias EventStore.Event

  defmodule Repo do
    use Ecto.Repo, otp_app: :event_store, adapter: Ecto.Adapters.Postgres
  end

  @impl true
  defdelegate insert(changeset), to: Repo

  @impl true
  def stream(aggregate_id) when is_binary(aggregate_id) do
    from(e in Event, where: e.aggregate_id == ^aggregate_id, order_by: :id)
    |> Repo.all()
  end

  def stream(event) when is_atom(event) do
    name = EventStore.to_name(event)

    from(e in Event, where: e.name == ^name, order_by: :id)
    |> Repo.all()
  end

  @impl true
  @deprecated "Use exists?/2 with an atom as the second argument"
  def exists?(aggregate_id, name) when is_binary(name) do
    from(e in Event, where: e.aggregate_id == ^aggregate_id and e.name == ^name)
    |> Repo.exists?()
  end

  @impl true
  def exists?(aggregate_id, event) when is_atom(event) do
    name = EventStore.to_name(event)

    from(e in Event, where: e.aggregate_id == ^aggregate_id and e.name == ^name)
    |> Repo.exists?()
  end
end
