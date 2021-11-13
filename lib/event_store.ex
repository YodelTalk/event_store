defmodule EventStore do
  require Logger
  alias EventStore.{AcknowledgementError, PubSub}

  @adapter Application.fetch_env!(:event_store, :adapter)
  @namespace Application.get_env(:event_store, :namespace, __MODULE__)
  @sync_timeout Application.get_env(:event_store, :sync_timeout, 5000)

  defdelegate exists?(aggregate_id, name), to: @adapter

  @spec dispatch(%EventStore.Event{}) :: {:ok, %EventStore.Event{}}
  def dispatch(event) do
    {event, _} = dispatch_and_return_subscribers(event)
    {:ok, event}
  end

  @spec sync_dispatch(%EventStore.Event{}) :: {:ok, %EventStore.Event{}}
  def sync_dispatch(event) do
    {
      %{aggregate_id: aggregate_id, aggregate_version: aggregate_version} = event,
      subscribers
    } = dispatch_and_return_subscribers(event)

    for subscriber <- subscribers do
      receive do
        {^subscriber, ^aggregate_id, ^aggregate_version} -> nil
      after
        @sync_timeout -> raise AcknowledgementError, {subscriber, event}
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

  @spec acknowledge(%EventStore.Event{}) :: :ok
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

  def stream(aggregate_id_or_name) do
    aggregate_id_or_name
    |> @adapter.stream()
    |> Enum.map(fn event ->
      module = Module.safe_concat(@namespace, event.name)

      module
      |> struct(%{aggregate_id: event.aggregate_id, inserted_at: event.inserted_at})
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
end
