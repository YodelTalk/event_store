defmodule EventStore.PubSub.Registry do
  @behaviour EventStore.PubSub

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :duplicate, name: __MODULE__]]}
    }
  end

  @impl true
  def subscribe(topic) do
    Registry.register(__MODULE__, topic, nil)
  end

  @impl true
  def broadcast(event) do
    topic = Atom.to_string(event.__struct__)

    for {pid, _} <- Registry.lookup(__MODULE__, topic) do
      send(pid, event)
      pid
    end
  end
end
