defmodule EventStore.Adapter.InMemory do
  @moduledoc """
  An in-memory event store adapter.

  This adapter can speed up your test suite by omitting database interactions.
  To use it, configure ﻿`config/test.exs` as follows:

      config :event_store,
        adapter: EventStore.Adapter.InMemory

  > #### Avoid using this adapter in production! {: .error}
  >
  > This adapter is not optimized and is intended solely for testing and
  > demonstration purposes. Be aware that:
  > - It should NOT be used in production.
  > - Restarting the application will result in the LOSS of ALL previously
  >   stored events.
  """

  @behaviour EventStore.Adapter

  use Agent
  import EventStore.Guards

  def start_link(_) do
    # TODO: Change the internal storage to something more performant than a list.
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @impl true
  def insert(changeset) do
    # TODO: Improve the performance of the next_aggregate_version.
    next_aggregate_version =
      changeset.changes.aggregate_id
      |> stream_since(NaiveDateTime.new!(2000, 1, 1, 0, 0, 0))
      |> Enum.count()
      |> then(&(&1 + 1))

    event =
      changeset
      |> Ecto.Changeset.put_change(:id, Ecto.UUID.generate())
      |> Ecto.Changeset.put_change(:aggregate_version, next_aggregate_version)
      |> Ecto.Changeset.apply_changes()

    Agent.update(__MODULE__, &[event | &1])

    event
  end

  defp filter(fun) do
    Agent.get(__MODULE__, & &1)
    |> Enum.reverse()
    |> Stream.filter(fun)
  end

  @impl true
  def stream do
    Agent.get(__MODULE__, & &1)
    |> Enum.reverse()
    |> Stream.map(& &1)
  end

  # stream/1

  @impl true
  def stream(aggregate_id) when is_uuid(aggregate_id) do
    stream([aggregate_id])
  end

  @impl true
  def stream(aggregate_ids) when is_uuids(aggregate_ids) do
    filter(&(&1.aggregate_id in aggregate_ids))
  end

  @impl true
  def stream(name) when is_atom(name) do
    stream([name])
  end

  @impl true
  def stream(names) when is_atoms(names) do
    names = Enum.map(names, &EventStore.to_name/1)
    filter(&(&1.name in names))
  end

  # stream/2

  @impl true
  def stream(aggregate_id, name) when is_uuid(aggregate_id) and is_atom(name) do
    stream([aggregate_id], [name])
  end

  @impl true
  def stream(aggregate_ids, name) when is_uuids(aggregate_ids) and is_atom(name) do
    stream(aggregate_ids, [name])
  end

  @impl true
  def stream(aggregate_id, names) when is_uuid(aggregate_id) and is_atoms(names) do
    stream([aggregate_id], names)
  end

  @impl true
  def stream(aggregate_ids, names) when is_uuids(aggregate_ids) and is_atoms(names) do
    names = Enum.map(names, &EventStore.to_name/1)
    filter(&(&1.aggregate_id in aggregate_ids && &1.name in names))
  end

  # stream_since/2

  @impl true
  def stream_since(aggregate_id, timestamp)
      when is_uuid(aggregate_id) and is_struct(timestamp, NaiveDateTime) do
    stream_since([aggregate_id], timestamp)
  end

  @impl true
  def stream_since(aggregate_ids, timestamp)
      when is_uuids(aggregate_ids) and is_struct(timestamp, NaiveDateTime) do
    filter(
      &(&1.aggregate_id in aggregate_ids &&
          NaiveDateTime.compare(&1.inserted_at, timestamp) in [:gt, :eq])
    )
  end

  @impl true
  def stream_since(name, timestamp)
      when is_atom(name) and is_struct(timestamp, NaiveDateTime) do
    stream_since([name], timestamp)
  end

  @impl true
  def stream_since(names, timestamp)
      when is_atoms(names) and is_struct(timestamp, NaiveDateTime) do
    names = Enum.map(names, &EventStore.to_name/1)
    filter(&(&1.name in names && NaiveDateTime.compare(&1.inserted_at, timestamp) in [:gt, :eq]))
  end

  # stream_since/3

  @impl true
  def stream_since(aggregate_id, name, timestamp) when is_uuid(aggregate_id) and is_atom(name) do
    stream_since([aggregate_id], [name], timestamp)
  end

  @impl true
  def stream_since(aggregate_ids, name, timestamp)
      when is_uuids(aggregate_ids) and is_atom(name) do
    stream_since(aggregate_ids, [name], timestamp)
  end

  @impl true
  def stream_since(aggregate_id, names, timestamp)
      when is_uuid(aggregate_id) and is_atoms(names) do
    stream_since([aggregate_id], names, timestamp)
  end

  @impl true
  def stream_since(aggregate_ids, names, timestamp)
      when is_uuids(aggregate_ids) and is_atoms(names) do
    names = Enum.map(names, &EventStore.to_name/1)

    filter(
      &(&1.aggregate_id in aggregate_ids &&
          &1.name in names &&
          NaiveDateTime.compare(&1.inserted_at, timestamp) in [:gt, :eq])
    )
  end

  @impl true
  defmacro transaction(fun, _opts \\ []) do
    quote do
      unquote(fun).()
    end
  end

  @impl true
  def exists?(aggregate_id, event) when is_atom(event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.any?(&(&1.aggregate_id == aggregate_id and &1.name == name))
  end

  @impl true
  def first(aggregate_id, event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.reverse()
    |> Enum.find(&(&1.aggregate_id == aggregate_id and &1.name == name))
    |> EventStore.cast()
  end

  @impl true
  def last(aggregate_id, event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.find(&(&1.aggregate_id == aggregate_id and &1.name == name))
    |> EventStore.cast()
  end
end
