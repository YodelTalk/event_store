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
  def stream(aggregate_id) do
    Agent.get(__MODULE__, & &1)
    |> Enum.filter(&(&1.aggregate_id == aggregate_id))
    |> Enum.reverse()
  end

  @impl true
  def exists?(aggregate_id, name) do
    Agent.get(__MODULE__, & &1)
    |> Enum.any?(&(&1.aggregate_id == aggregate_id and &1.name == name))
  end
end
