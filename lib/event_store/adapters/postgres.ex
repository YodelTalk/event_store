defmodule EventStore.Adapters.Postgres do
  @behaviour EventStore.Adapter

  import Ecto.Query
  import Ecto.Changeset

  alias EventStore.Event

  defmodule Repo do
    use Ecto.Repo, otp_app: :event_store, adapter: Ecto.Adapters.Postgres
  end

  @impl true
  def insert(changeset) do
    changeset
    |> assign_aggregate_version()
    |> Repo.insert()
  end

  defp assign_aggregate_version(changeset) do
    query =
      from e in "events",
        where: e.aggregate_id == ^get_field(changeset, :aggregate_id),
        select: max(e.aggregate_version)

    next_aggregate_version =
      case Repo.one(query) do
        nil -> 0
        current_version -> current_version + 1
      end

    changeset
    |> force_change(:aggregate_version, next_aggregate_version)
  end

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
