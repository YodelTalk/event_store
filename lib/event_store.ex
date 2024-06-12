defmodule EventStore do
  @moduledoc """
  A central store for managing and dispatching domain events.

  EventStore is a core component for an event sourcing architecture, providing
  functionalities to store, dispatch, and query events. It is designed to be
  highly extensible with support for pluggable adapters.

  ## Key Features

  - **Dispatching Events:** Events can be dispatched to the store and
    optionally, the dispatch process can be synchronous to ensure that
    subscribers have acknowledged receipt.

  - **Subscribing to Events:** Processes can subscribe to specific events,
    allowing them to receive notifications when these events occur.

  - **Querying Events:** It provides facilities to check the existence of
    specific events and to retrieve the first or last event for specific
    criteria.

  - **Streaming Events:** Supports streaming events from the store which can be
    used in projections and other read models.

  - **Pluggable Adapters:** EventStore can be configured with different storage
    adapters (e.g., in-memory, PostgreSQL) which allows for flexibility in storage
    backends.

  ## Configuration

  - `:adapter` - Specifies the adapter to be used for the event store. Defaults
    to `EventStore.Adapter.Postgres`.

  - `:namespace` - Defines the namespace for the events.

  - `:pubsub` - Specifies the PubSub adapter to be used for the event store. Defaults
    to `EventStore.Adapter.PubSub.Registry`.

  - `:sync_timeout` - Specifies the timeout for synchronous dispatches.
  """

  require Logger
  require EventStore.Adapter.InMemory

  import EventStore.Guards
  alias EventStore.AcknowledgementError

  @namespace Application.compile_env(:event_store, :namespace, __MODULE__)
  @sync_timeout Application.compile_env(:event_store, :sync_timeout, 5000)

  @typedoc """
  The unique identifier for an aggregate as an UUID `t:String.t/0`.
  """
  @type aggregate_id :: String.t()

  @typedoc """
  One or more `t:EventStore.aggregate_id/0`s.
  """
  @type aggregate_ids :: aggregate_id() | [aggregate_ids()]

  @typedoc """
  The name used to identify an event as `t:module/0`.
  """
  @type name :: module()

  @typedoc """
  One or more `t:EventStore.name/0`s.
  """
  @type names :: name | [name()]

  @doc """
  Returns the configured namespace for the events.
  """
  def namespace, do: @namespace

  @adapter Application.compile_env(:event_store, :adapter, EventStore.Adapter.Postgres)

  @doc """
  Returns the configured adapter for the EventStore.
  """
  def adapter, do: @adapter

  @doc """
  Checks if an event with a specific aggregate ID and name exists.
  """
  defdelegate exists?(aggregate_id, name), to: @adapter

  @doc """
  Retrieves the first event with a specific aggregate ID and name.
  """
  defdelegate first(aggregate_id, name), to: @adapter

  @doc """
  Retrieves the last event with a specific aggregate ID and name.
  """
  defdelegate last(aggregate_id, name), to: @adapter

  @pub_sub Application.compile_env(:event_store, :pub_sub, EventStore.PubSub.Registry)

  @doc """
  Returns the configured PubSub adapter for the EventStore.
  """
  def pub_sub, do: @pub_sub

  @doc """
  Dispatches an event to the EventStore.
  """
  @spec dispatch(EventStore.Event.t()) :: {:ok, EventStore.Event.t()}
  def dispatch(event) do
    {event, _} = dispatch_and_return_subscribers(event)
    {:ok, event}
  end

  @doc """
  Dispatches an event to the EventStore and waits for acknowledgement from
  subscribers.
  """
  @spec sync_dispatch(EventStore.Event.t()) :: {:ok, EventStore.Event.t()}
  def sync_dispatch(event) do
    {
      %{aggregate_id: aggregate_id, aggregate_version: aggregate_version} = event,
      subscribers
    } = dispatch_and_return_subscribers(event)

    for subscriber <- subscribers do
      receive do
        {^subscriber, ^aggregate_id, ^aggregate_version} -> nil
      after
        @sync_timeout ->
          if Process.alive?(subscriber) do
            raise AcknowledgementError, {subscriber, event}
          end
      end
    end

    {:ok, event}
  end

  defp dispatch_and_return_subscribers(event) do
    event = insert_with_adapter(event, adapter())
    subscribers = @pub_sub.broadcast(event)

    Logger.debug("Dispatched #{inspect(event)} to #{inspect(subscribers, limit: :infinity)}")

    {event, subscribers}
  end

  @doc false
  @spec insert_with_adapter(EventStore.Event.t(), module()) :: EventStore.Event.t()
  def insert_with_adapter(event, adapter) do
    %{id: id, aggregate_version: aggregate_version, inserted_at: inserted_at} =
      event
      |> event.__struct__.changeset()
      |> then(&adapter.insert(&1))

    %{
      event
      | id: id,
        aggregate_version: aggregate_version,
        inserted_at: inserted_at,
        from: self()
    }
  end

  @doc """
  Acknowledges the receipt of an event.
  """
  @spec acknowledge(EventStore.Event.t()) :: :ok
  def acknowledge(event) do
    Logger.debug("Subscriber #{inspect(self())} acknowledged #{inspect(event)}")
    send(event.from, {self(), event.aggregate_id, event.aggregate_version})
    :ok
  end

  @doc """
  Subscribes the calling process to one or more events.
  """
  @spec subscribe(names()) :: any()
  def subscribe(names) when is_atom(names), do: subscribe([names])

  def subscribe(names) when is_list(names) do
    for name <- names, do: @pub_sub.subscribe(name)
  end

  @doc """
  Provides a stream of all existing events.
  """
  @spec stream() :: Enum.t()
  def stream do
    handle_stream(@adapter.stream())
  end

  @doc """
  Streams events filtered by one or more aggregate IDs or event names.
  """
  @spec stream(aggregate_ids() | names()) :: Enum.t()
  def stream(aggregate_ids_or_names)
      when is_one_or_more_uuids(aggregate_ids_or_names) or
             is_one_or_more_atoms(aggregate_ids_or_names) do
    handle_stream(@adapter.stream(aggregate_ids_or_names))
  end

  @doc """
  Streams events filtered by one or more aggregate IDs and one or more event
  names.
  """
  @spec stream(aggregate_ids(), names()) :: Enum.t()
  def stream(aggregate_ids, names)
      when is_one_or_more_uuids(aggregate_ids) or is_one_or_more_atoms(names) do
    handle_stream(@adapter.stream(aggregate_ids, names))
  end

  def stream(aggregate_ids_or_names, %NaiveDateTime{} = timestamp)
      when is_one_or_more_uuids(aggregate_ids_or_names) or
             is_one_or_more_atoms(aggregate_ids_or_names) do
    IO.warn("calling stream/2 with a timestamp is deprecated, please use stream_since/2 instead")
    stream_since(aggregate_ids_or_names, timestamp)
  end

  @doc """
  Streams events filtered by one or more aggregate IDs or event names,,
  since a given timestamp.
  """
  @doc since: "0.2.0"
  @spec stream_since(aggregate_ids() | names(), NaiveDateTime.t()) :: Enum.t()
  def stream_since(aggregate_ids_or_names, %NaiveDateTime{} = timestamp)
      when is_one_or_more_uuids(aggregate_ids_or_names) or
             is_one_or_more_atoms(aggregate_ids_or_names) do
    handle_stream(@adapter.stream_since(aggregate_ids_or_names, timestamp))
  end

  @doc """
  Streams events filtered by one or more aggregate IDs and one or more event
  names, since a given timestamp.
  """
  @doc since: "0.2.0"
  @spec stream_since(aggregate_ids(), names(), NaiveDateTime.t()) :: Enum.t()
  def stream_since(aggregate_ids, names, %NaiveDateTime{} = timestamp)
      when is_one_or_more_uuids(aggregate_ids) or is_one_or_more_atoms(names) do
    handle_stream(@adapter.stream_since(aggregate_ids, names, timestamp))
  end

  defp handle_stream(stream) do
    Stream.map(stream, fn record ->
      record
      |> cast()
      |> tap(&Logger.debug("Event #{record.name} loaded: #{inspect(&1)}"))
    end)
  end

  defdelegate transaction(fun, _opts \\ []), to: @adapter

  @doc """
  Casts a raw record from the store into a structured event.

  This function takes a raw record, resolves the appropriate module based on the
  event name, and casts it into an event struct, including applying the payload.

  This is an internal function and should not be called directly.
  """
  @spec cast(map()) :: any()
  def cast(nil), do: nil

  def cast(%{inserted_at: inserted_at} = record) when is_struct(inserted_at, NaiveDateTime) do
    module = Module.safe_concat(namespace(), record.name)

    module
    |> struct!(%{
      id: record.id,
      aggregate_id: record.aggregate_id,
      aggregate_version: record.aggregate_version,
      inserted_at: record.inserted_at
    })
    |> then(&module.cast_payload(&1, record.payload))
    |> Ecto.Changeset.apply_changes()
  end

  @doc false
  def to_name(event) when is_struct(event), do: to_name(event.__struct__)

  def to_name(event) when is_atom(event) do
    event
    |> Atom.to_string()
    |> to_name()
  end

  def to_name(event) when is_binary(event) do
    String.replace_prefix(event, "#{namespace()}.", "")
  end
end
