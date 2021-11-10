defmodule EventStore.Adapter do
  @type aggregate_id :: String.t()
  @type event_id :: Integer.t()
  @type name :: atom()

  @callback insert(Ecto.Changeset.t()) :: {:ok, %EventStore.Event{}}
  @callback stream(aggregate_id() | name()) :: [%EventStore.Event{}]
  @callback stream(aggregate_id() | name(), event_id()) :: [%EventStore.Event{}]
  @callback exists?(aggregate_id(), name()) :: boolean()
end
