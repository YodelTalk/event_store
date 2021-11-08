defmodule EventStore do
  require Logger

  alias Phoenix.PubSub
  alias EventStore.AcknowledgementError

  @adapter Application.fetch_env!(:event_store, :adapter)
  @namespace Application.get_env(:event_store, :namespace, __MODULE__)
  @sync_timeout Application.get_env(:event_store, :sync_timeout, 5000)

  defdelegate exists?(aggregate_id, name), to: @adapter

  @spec dispatch(%EventStore.Event{}) :: {:ok, %EventStore.Event{}}
  def dispatch(event) do
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

    Logger.debug("Event dispatched: #{inspect(event)}")
    PubSub.broadcast(EventStore.PubSub, Atom.to_string(event.__struct__), event)

    {:ok, event}
  end

  @spec dispatch(%EventStore.Event{}) :: {:ok, %EventStore.Event{}}
  def sync_dispatch(event) do
    {:ok, %{aggregate_version: aggregate_version} = event} = dispatch(event)

    receive do
      ^aggregate_version -> {:ok, event}
    after
      @sync_timeout -> raise AcknowledgementError, event
    end
  end

  @spec acknowledge(%EventStore.Event{}) :: :ok
  def acknowledge(event) do
    send(event.from, event.aggregate_version)
    :ok
  end

  def subscribe(events) when is_list(events) do
    for topic <- Enum.map(events, &Atom.to_string/1) do
      PubSub.subscribe(EventStore.PubSub, topic)
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
