defmodule EventStore.Adapters.InMemory do
  @behaviour EventStore.Adapter

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def insert(changeset) do
    event =
      changeset
      |> Ecto.Changeset.put_change(:id, Ecto.UUID.generate())
      |> Ecto.Changeset.apply_changes()

    GenServer.call(__MODULE__, {:dispatch, event})
  end

  @impl true
  def stream(aggregate_id) do
    GenServer.call(__MODULE__, {:stream, aggregate_id})
  end

  @impl true
  def exists?(aggregate_id, name) do
    GenServer.call(__MODULE__, {:exists, aggregate_id, name})
  end

  # GenServer API

  @impl true
  def init(events) do
    {:ok, events}
  end

  @impl true
  def handle_call({:dispatch, event}, _from, events) do
    {:reply, {:ok, event}, [{event.aggregate_id, event} | events]}
  end

  @impl true
  def handle_call({:stream, aggregate_id}, _from, events) do
    stream =
      for {event_aggregate_id, event} <- events, event_aggregate_id == aggregate_id, do: event

    {:reply, Enum.reverse(stream), events}
  end

  @impl true
  def handle_call({:exists, aggregate_id, name}, _from, events) do
    result =
      Enum.any?(events, fn {_, event} ->
        event.aggregate_id == aggregate_id and event.name == name
      end)

    {:reply, result, events}
  end
end
