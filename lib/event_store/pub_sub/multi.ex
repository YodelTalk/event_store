defmodule EventStore.PubSub.Multi do
  @behaviour EventStore.PubSub

  @children [
    EventStore.PubSub.Postgres,
    EventStore.PubSub.Registry
  ]

  @impl true
  def subscribe(topic) when is_atom(topic) do
    Enum.each(@children, & &1.subscribe(topic))
    :ok
  end

  @impl true
  def broadcast(event) when is_struct(event) do
    Enum.flat_map(@children, & &1.broadcast(event))
  end
end
