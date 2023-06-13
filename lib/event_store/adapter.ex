defmodule EventStore.Adapter do
  @moduledoc """
  A behaviour module that defines the contract for EventStore adapters.
  """

  @type aggregate_id :: String.t()
  @type name :: atom()
  @type inserted_at :: NaiveDateTime.t()

  @doc """
  Inserts an event changeset and returns the inserted event.
  """
  @callback insert(Ecto.Changeset.t()) :: {:ok, %EventStore.Event{}}

  @doc """
  Streams events for a specific aggregate ID or event name.
  """
  @callback stream(aggregate_id() | name()) :: [%EventStore.Event{}]

  @doc """
  Streams events for a specific aggregate ID or event name, since a given
  timestamp.
  """
  @callback stream(aggregate_id() | name(), inserted_at()) :: [%EventStore.Event{}]

  @doc """
  Checks if an event with a specific aggregate ID and name exists.
  """
  @callback exists?(aggregate_id(), name()) :: boolean()

  @doc """
  Retrieves the first event with a specific aggregate ID and name.
  """
  @callback first(aggregate_id(), name()) :: %EventStore.Event{} | nil

  @doc """
  Retrieves the last event with a specific aggregate ID and name.
  """
  @callback last(aggregate_id(), name()) :: %EventStore.Event{} | nil
end
