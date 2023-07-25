defmodule EventStore.PubSub.Registry do
  @moduledoc """
  An `EventStore.PubSub` implementation that uses an Elixir `Registry` for
  subscriptions and event broadcasting.
  """

  @behaviour EventStore.PubSub

  @doc """
  Returns a specification to start this module under a supervisor.
  """
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :duplicate, name: __MODULE__]]}
    }
  end

  @doc """
  Subscribes the calling process to a given topic.
  """
  @impl true
  def subscribe(topic) when is_atom(topic) do
    Registry.register(__MODULE__, Atom.to_string(topic), nil)
    :ok
  end

  @doc """
  Broadcasts an event to all processes subscribed to the event's topic.
  """
  @impl true
  def broadcast(event) when is_struct(event) do
    topic = Atom.to_string(event.__struct__)

    for {pid, _} <- Registry.lookup(__MODULE__, topic) do
      send(pid, event)
      pid
    end
  end
end
