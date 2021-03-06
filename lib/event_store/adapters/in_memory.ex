defmodule EventStore.Adapters.InMemory do
  @moduledoc """
  **Don't use this adapter in production!** Its currently not optimized at all. It's
  main purpose is for testing and to demonstrate how easy you can build your own
  adapter.
  """

  @behaviour EventStore.Adapter

  use Agent

  def start_link(_) do
    # TODO: Change the internal storage to something more performant than a list.
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @impl true
  def insert(changeset) do
    # TODO: Improve the performance of the next_aggregate_version.
    next_aggregate_version =
      changeset.changes.aggregate_id
      |> stream(NaiveDateTime.new!(2000, 1, 1, 0, 0, 0))
      |> Enum.count()
      |> then(&(&1 + 1))

    event =
      changeset
      |> Ecto.Changeset.put_change(:id, Ecto.UUID.generate())
      |> Ecto.Changeset.put_change(:aggregate_version, next_aggregate_version)
      |> Ecto.Changeset.apply_changes()

    Agent.update(__MODULE__, &[event | &1])

    {:ok, event}
  end

  @impl true
  def stream(aggregate_id, timestamp) when is_binary(aggregate_id) do
    Agent.get(__MODULE__, & &1)
    |> Enum.filter(&(&1.aggregate_id == aggregate_id && &1.inserted_at > timestamp))
    |> Enum.reverse()
  end

  @impl true
  def stream(event, timestamp) when is_atom(event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.filter(&(&1.name == name && &1.inserted_at > timestamp))
    |> Enum.reverse()
  end

  @impl true
  def exists?(aggregate_id, event) when is_atom(event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.any?(&(&1.aggregate_id == aggregate_id and &1.name == name))
  end
end
