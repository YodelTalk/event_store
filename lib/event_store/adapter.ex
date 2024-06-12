defmodule EventStore.Adapter do
  @moduledoc """
  A behaviour module that defines the contract for EventStore adapters.
  """

  @doc """
  Inserts an event changeset and returns the inserted event.
  """
  @callback insert(changeset :: Ecto.Changeset.t()) :: EventStore.Event.t()

  @doc """
  Provides a stream of all existing events.
  """
  @callback stream() :: Enum.t()

  @doc """
  Streams events filtered by a single or multiple aggregate IDs or event names.
  """
  @callback stream(
              identifier ::
                EventStore.aggregate_id()
                | [EventStore.aggregate_id()]
                | EventStore.name()
                | [EventStore.name()]
            ) :: Enum.t()

  @doc """
  Streams events filtered by a single or multiple aggregate IDs or event names,
  since a given timestamp.
  """
  @callback stream_since(
              identifier ::
                EventStore.aggregate_id()
                | [EventStore.aggregate_id()]
                | EventStore.name()
                | [EventStore.name()],
              timestamp :: NaiveDateTime.t()
            ) :: Enum.t()

  @doc """
  Runs the given function in a transaction if necessary. See
  `Ecto.Repo.transaction/2` for more details.
  """
  @callback transaction(function :: fun(), opts :: keyword()) :: any()

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
