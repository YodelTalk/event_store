defmodule EventStore.Adapter do
  @type aggregate_id :: String.t()
  @type name :: atom()

  @callback insert(Ecto.Changeset.t()) :: {:ok, %EventStore.Event{}}
  @callback stream(aggregate_id() | name()) :: [%EventStore.Event{}]
  @callback exists?(aggregate_id(), name()) :: boolean()
end
