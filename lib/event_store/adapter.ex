defmodule EventStore.Adapter do
  @type aggregate_id :: String.t()
  @type inserted_at :: NaiNaiveDateTime.t()
  @type name :: atom()

  @callback insert(Ecto.Changeset.t()) :: {:ok, %EventStore.Event{}}
  @callback stream(aggregate_id() | name(), inserted_at()) :: [%EventStore.Event{}]
  @callback exists?(aggregate_id(), name()) :: boolean()
end
