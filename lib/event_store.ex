defmodule EventStore do
  require Logger
  alias EventStore.{AcknowledgementError, Event, PubSub}

  @adapter Application.compile_env(:event_store, :adapter, EventStore.Adapters.InMemory)
  @namespace Application.compile_env(:event_store, :namespace, __MODULE__)
  @sync_timeout Application.compile_env(:event_store, :sync_timeout, 5000)

  defdelegate exists?(aggregate_id, name), to: @adapter
  defdelegate first(aggregate_id, name), to: @adapter
  defdelegate last(aggregate_id, name), to: @adapter

  @spec dispatch(EventStore.Event.t()) :: {:ok, EventStore.Event.t()}
  def dispatch(event) do
    {event, _} = dispatch_and_return_subscribers(event)
    {:ok, event}
  end

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

    subscribers = PubSub.broadcast(event)
    Logger.debug("Dispatched #{inspect(event)} to #{inspect(subscribers, limit: :infinity)}")

    {event, subscribers}
  end

  @spec acknowledge(EventStore.Event.t()) :: :ok
  def acknowledge(event) do
    Logger.debug("Subscriber #{inspect(self())} acknowledged #{inspect(event)}")
    send(event.from, {self(), event.aggregate_id, event.aggregate_version})
    :ok
  end

  def subscribe(events) when is_list(events) do
    for topic <- Enum.map(events, &Atom.to_string/1) do
      PubSub.subscribe(topic)
    end
  end

  def subscribe(event), do: subscribe([event])

  defguardp is_uuid(value)
            when is_binary(value) and
                   byte_size(value) == 36 and
                   binary_part(value, 8, 1) == "-" and
                   binary_part(value, 13, 1) == "-" and
                   binary_part(value, 18, 1) == "-" and
                   binary_part(value, 23, 1) == "-"

  def stream(aggregate_id_or_name, timestamp \\ NaiveDateTime.new!(2000, 1, 1, 0, 0, 0))
      when is_uuid(aggregate_id_or_name) or is_atom(aggregate_id_or_name) do
    aggregate_id_or_name
    |> @adapter.stream(timestamp)
    |> Stream.map(fn event ->
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

  def adapter(), do: @adapter
end
