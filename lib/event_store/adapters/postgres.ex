defmodule EventStore.Adapters.Postgres do
  @behaviour EventStore.Adapter

  import Ecto.Query
  alias EventStore.Event

  defmodule Repo do
    use Ecto.Repo, otp_app: :event_store, adapter: Ecto.Adapters.Postgres
  end

  @impl true
  def insert(changeset) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> insert!()
  end

  defp insert!(event) do
    Repo.insert_all(
      Event,
      [
        [
          # TODO: Generate the keyword list from the changeset.
          name: event.name,
          version: event.version,
          aggregate_id: event.aggregate_id,
          aggregate_version: next_aggregate_version(event),
          payload: event.payload,
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        ]
      ],
      returning: [:id, :aggregate_version],
      on_conflict: :nothing
    )
    |> case do
      {1, [%{id: id, aggregate_version: aggregate_version} | _]} ->
        {:ok, %{event | id: id, aggregate_version: aggregate_version}}

      {0, []} ->
        insert!(event)
    end
  end

  defp next_aggregate_version(%{aggregate_id: aggregate_id} = _event) do
    from(e in Event,
      where: e.aggregate_id == ^aggregate_id,
      select: %{aggregate_version: coalesce(max(e.aggregate_version) + 1, 1)}
    )
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
