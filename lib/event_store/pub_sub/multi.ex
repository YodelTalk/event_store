defmodule EventStore.PubSub.Multi do
  @moduledoc """
  An `EventStore.PubSub` adapter for broadcasting events to multiple PubSub
  systems. It serves as a mediator, routing subscriptions and broadcast calls
  based on the configuration.
  """

  @behaviour EventStore.PubSub

  @subscribe_to Application.compile_env(:event_store, :subscribe_to, [EventStore.PubSub.Registry])
  @broadcast_to Application.compile_env(:event_store, :broadcast_to, [EventStore.PubSub.Registry])

  @doc """
  Subscribes the calling process to a specific event type across all configured PubSub systems.
  """
  @impl true
  def subscribe(name) when is_atom(name) do
    Enum.each(@subscribe_to, & &1.subscribe(name))

    :ok
  end

  @doc """
  Broadcasts an event to all subscribers across all configured PubSub systems.
  """
  @impl true
  def broadcast(event) when is_struct(event) do
    Enum.flat_map(@broadcast_to, & &1.broadcast(event))
  end
end
