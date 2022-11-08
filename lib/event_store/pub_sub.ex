defmodule EventStore.PubSub do
  @moduledoc false
  alias EventStore.Event

  @callback subscribe(atom()) :: :ok
  @callback broadcast(Event.t()) :: [pid()]
end
