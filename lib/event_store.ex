defmodule EventStore do
  @moduledoc """
  A central store for managing and dispatching domain events.
  """

  require Logger
  import EventStore.Guards
  alias EventStore.{AcknowledgementError, Event, PubSub}

  @adapter Application.compile_env(:event_store, :adapter, EventStore.Adapters.InMemory)
  @namespace Application.compile_env(:event_store, :namespace, __MODULE__)
  @sync_timeout Application.compile_env(:event_store, :sync_timeout, 5000)

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
    {:ok, %{aggregate_version: aggregate_version, inserted_at: inserted_at}} =
      event
      |> event.__struct__.changeset()
      |> then(&@adapter.insert(&1))

    event = %{
      event
      | aggregate_version: aggregate_version,
        inserted_at: inserted_at,
        from: self()
    }

    subscribers = pub_sub().broadcast(event)
    Logger.debug("Dispatched #{inspect(event)} to #{inspect(subscribers, limit: :infinity)}")

    {event, subscribers}
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
  Subscribes to one or more events.
  """
  def subscribe(event) when is_atom(event), do: subscribe([event])

  def subscribe(events) when is_list(events) do
    for topic <- Enum.map(events, &Atom.to_string/1) do
      pub_sub().subscribe(topic)
    end
  end

  @doc """
  Streams events for a specific aggregate ID or event name.
  """
  def stream(aggregate_id_or_name)
      when is_uuid(aggregate_id_or_name) or is_atom(aggregate_id_or_name) do
    handle_stream(@adapter.stream(aggregate_id_or_name))
  end

  @doc """
  Streams events for a specific aggregate ID or event name, since a given
  timestamp.
  """
  def stream(aggregate_id_or_name, timestamp)
      when is_uuid(aggregate_id_or_name) or is_atom(aggregate_id_or_name) do
    handle_stream(@adapter.stream(aggregate_id_or_name, timestamp))
  end

  defp handle_stream(stream) do
    Stream.map(stream, fn event ->
      module = Module.safe_concat(@namespace, event.name)

      module
      |> struct!(%{
        aggregate_id: event.aggregate_id,
        aggregate_version: event.aggregate_version,
        inserted_at: event.inserted_at
      })
      |> then(&module.cast_payload(&1, event.payload))
      |> Ecto.Changeset.apply_changes()
      |> tap(&Logger.debug("Event #{event.name} loaded: #{inspect(&1)}"))
    end)
  end

  def to_name(event) when is_atom(event) do
    event
    |> Atom.to_string()
    |> String.replace_prefix("#{@namespace}.", "")
  end

  def to_event(nil), do: nil

  def to_event(%Event{name: name} = event) do
    %{event | __struct__: Module.safe_concat(@namespace, name)}
  end

  @doc """
  Returns the configured adapter for the EventStore.
  """
  def adapter(), do: @adapter

  def pub_sub(), do: EventStore.PubSub.Registry
end
