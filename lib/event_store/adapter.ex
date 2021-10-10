defmodule EventStore.Adapter do
  @type aggregate_id :: String.t()
  @type name :: String.t()

  @callback insert(Ecto.Changeset.t()) :: {:ok, %EventStore.Event{}}
  @callback stream(aggregate_id()) :: [%EventStore.Event{}]
  @callback exists?(aggregate_id(), name()) :: boolean()
end
