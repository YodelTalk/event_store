defmodule EventStore.PubSub do
  @moduledoc """
  Defines the behavior for a publish/subscribe system in EventStore.

  The `EventStore.PubSub` module specifies the expected behavior for
  publish/subscribe systems in the EventStore. This includes functions for
  subscribing to specific event types and broadcasting events to the
  subscribers.

  Implementations of this behavior are expected to provide the mechanisms for
  handling subscriptions and broadcasting events to the subscribers.
  """

  alias EventStore.Event

  @doc """
  Subscribes the calling process to a specific event type.
  """
  @callback subscribe(name :: atom()) :: :ok

  @doc """
  Broadcasts an event to all subscribers of its type.
  """
  @callback broadcast(event :: Event.t()) :: [pid()]
end
