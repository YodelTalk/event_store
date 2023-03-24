defmodule EventStore.Adapter do
  @type aggregate_id :: String.t()
  @type name :: atom()
  @type inserted_at :: NaiNaiveDateTime.t()

  @callback insert(Ecto.Changeset.t()) :: {:ok, %EventStore.Event{}}
  @callback stream(aggregate_id() | name(), inserted_at()) :: [%EventStore.Event{}]

  @callback exists?(aggregate_id(), name()) :: boolean()
  @callback first(aggregate_id(), name()) :: %EventStore.Event{} | nil
  @callback last(aggregate_id(), name()) :: %EventStore.Event{} | nil
end
