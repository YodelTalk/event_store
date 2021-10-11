defmodule EventStore.Adapters.InMemory do
  @behaviour EventStore.Adapter

  use Agent

  def start_link(_) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @impl true
  def insert(changeset) do
    event =
      changeset
      |> Ecto.Changeset.put_change(:id, Ecto.UUID.generate())
      |> Ecto.Changeset.apply_changes()

    Agent.update(__MODULE__, &[event | &1])

    {:ok, event}
  end

  @impl true
  def stream(aggregate_id) when is_binary(aggregate_id) do
    Agent.get(__MODULE__, & &1)
    |> Enum.filter(&(&1.aggregate_id == aggregate_id))
    |> Enum.reverse()
  end

  @impl true
  def stream(event) when is_atom(event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.filter(&(&1.name == name))
    |> Enum.reverse()
  end

  @impl true
  @deprecated "Use exists?/2 with an atom as the second argument"
  def exists?(aggregate_id, name) when is_binary(name) do
    Agent.get(__MODULE__, & &1)
    |> Enum.any?(&(&1.aggregate_id == aggregate_id and &1.name == name))
  end

  @impl true
  def exists?(aggregate_id, event) when is_atom(event) do
    name = EventStore.to_name(event)

    Agent.get(__MODULE__, & &1)
    |> Enum.any?(&(&1.aggregate_id == aggregate_id and &1.name == name))
  end
end
