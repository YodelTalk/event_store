defmodule EventStore.Adapter do
  @moduledoc """
  A behaviour module that defines the contract for EventStore adapters.
  """

  @doc """
  Inserts an event changeset and returns the inserted event.
  """
  @callback insert(Ecto.Changeset.t()) :: {:ok, EventStore.Event.t()}

  @doc """
  Streams events filtered by a single or multiple aggregate IDs or event names.
  """
  @callback stream(
              EventStore.aggregate_id()
              | [EventStore.aggregate_id()]
              | EventStore.name()
              | [EventStore.name()]
            ) :: [EventStore.Event.t()]

  @doc """
  Streams events filtered by a single or multiple aggregate IDs or event names,
  since a given timestamp.
  """
  @callback stream(
              EventStore.aggregate_id()
              | [EventStore.aggregate_id()]
              | EventStore.name()
              | [EventStore.name()],
              NaiveDateTime.t()
            ) :: [EventStore.Event.t()]

  @doc """
  Checks if an event with a specific aggregate ID and name exists.
  """
  @callback exists?(EventStore.aggregate_id(), EventStore.name()) :: boolean()

  @doc """
  Retrieves the first event with a specific aggregate ID and name.
  """
  @callback first(EventStore.aggregate_id(), EventStore.name()) :: EventStore.Event.t() | nil

  @doc """
  Retrieves the last event with a specific aggregate ID and name.
  """
  @callback last(EventStore.aggregate_id(), EventStore.name()) :: EventStore.Event.t() | nil
end
