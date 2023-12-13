defmodule EventStore.Adapter.Postgres do
  @moduledoc """
  An EventStore adapter for using a PostgreSQL database.

  This adapter provides implementations for storing and retrieving events in a
  PostgreSQL database using Ecto. It supports storing events with metadata such
  as aggregate identifiers, versions, and timestamps. Streaming of events is
  also supported, with optional filtering by aggregate ID or timestamp.

  Note that the events are stored in a denormalized format to optimize for
  append-only and read-heavy use cases typical in event sourcing.
  """

  @behaviour EventStore.Adapter

  import Ecto.Query
  import EventStore.Guards

  alias EventStore.Event

  defmodule Repo do
    @moduledoc false
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
          inserted_at: event.inserted_at
        ]
      ],
      returning: [:id, :aggregate_version],
      on_conflict: :nothing
    )
    |> case do
      {1, [%{id: id, aggregate_version: aggregate_version} | _]} ->
        %{event | id: id, aggregate_version: aggregate_version}

      {0, []} ->
        insert!(event)
    end
  end

  defp next_aggregate_version(%{aggregate_id: aggregate_id} = _event)
       when not is_nil(aggregate_id) do
    Event
    |> by_aggregate_id(aggregate_id)
    |> select([e], %{aggregate_version: coalesce(max(e.aggregate_version) + 1, 1)})
  end

  defp by_aggregate_id(query, aggregate_ids) when is_list(aggregate_ids) do
    where(query, [e], e.aggregate_id in ^aggregate_ids)
  end

  defp by_aggregate_id(query, aggregate_id) do
    where(query, aggregate_id: ^aggregate_id)
  end

  defp by_event_name(query, events) when is_list(events) do
    names = Enum.map(events, &EventStore.to_name/1)
    where(query, [e], e.name in ^names)
  end

  defp by_event_name(query, event) do
    where(query, name: ^EventStore.to_name(event))
  end

  defp inserted_after(query, timestamp) do
    where(query, [e], e.inserted_at >= ^timestamp)
  end

  @impl true
  def stream do
    Event
    |> order_by(:inserted_at)
    |> Repo.stream()
  end

  @impl true
  def stream(aggregate_id) when is_one_or_more_uuids(aggregate_id) do
    Event
    |> by_aggregate_id(aggregate_id)
    |> order_by(:inserted_at)
    |> Repo.stream()
  end

  @impl true
  def stream(event) when is_one_or_more_atoms(event) do
    Event
    |> by_event_name(event)
    |> order_by(:inserted_at)
    |> Repo.stream()
  end

  @impl true
  def stream(aggregate_id, timestamp) when is_one_or_more_uuids(aggregate_id) do
    Event
    |> by_aggregate_id(aggregate_id)
    |> inserted_after(timestamp)
    |> order_by(:inserted_at)
    |> Repo.stream()
  end

  @impl true
  def stream(event, timestamp) when is_one_or_more_atoms(event) do
    Event
    |> by_event_name(event)
    |> inserted_after(timestamp)
    |> order_by(:inserted_at)
    |> Repo.stream()
  end

  @impl true
  defdelegate transaction(fun, opts \\ []), to: Repo

  @impl true
  def exists?(aggregate_id, event) when is_atom(event) do
    Event
    |> by_aggregate_id(aggregate_id)
    |> by_event_name(event)
    |> Repo.exists?()
  end

  @impl true
  def first(aggregate_id, event) do
    Event
    |> by_aggregate_id(aggregate_id)
    |> by_event_name(event)
    |> order_by(asc: :aggregate_version)
    |> limit(1)
    |> Repo.one()
    |> EventStore.cast()
  end

  @impl true
  def last(aggregate_id, event) do
    Event
    |> by_aggregate_id(aggregate_id)
    |> by_event_name(event)
    |> order_by(desc: :aggregate_version)
    |> limit(1)
    |> Repo.one()
    |> EventStore.cast()
  end
end
