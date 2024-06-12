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
  Subscribes the calling process to a specific event type.
  """
  @impl true
  def subscribe(name) when is_atom(name) do
    Registry.register(__MODULE__, Atom.to_string(name), nil)
    :ok
  end

  @doc """
  Broadcasts an event to all subscribers.
  """
  @impl true
  def broadcast(event) when is_struct(event) do
    name = Atom.to_string(event.__struct__)

    for {pid, _} <- Registry.lookup(__MODULE__, name) do
      send(pid, event)
      pid
    end
  end
end
