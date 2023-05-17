defmodule EventStore.PubSub.Multi do
  @behaviour EventStore.PubSub

  @subscribe_to Application.compile_env(:event_store, :subscribe_to, [EventStore.PubSub.Registry])
  @broadcast_to Application.compile_env(:event_store, :broadcast_to, [EventStore.PubSub.Registry])

  @impl true
  def subscribe(topic) when is_atom(topic) do
    Enum.each(@subscribe_to, & &1.subscribe(topic))

    :ok
  end

  @impl true
  def broadcast(event) when is_struct(event) do
    Enum.flat_map(@broadcast_to, & &1.broadcast(event))
  end
end
