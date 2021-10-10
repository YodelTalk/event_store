defmodule EventStore do
  require Logger
  alias Phoenix.PubSub

  @adapter Application.fetch_env!(:event_store, :adapter)
  @namespace Application.get_env(:event_store, :namespace, __MODULE__)

  defdelegate exists?(aggregate_id, name), to: @adapter

  def dispatch(event) do
    {:ok, dispatched_event} =
      event
      |> event.__struct__.changeset()
      |> then(&@adapter.insert(&1))

    Logger.debug("Event #{dispatched_event.name} dispatched: #{inspect(dispatched_event)}")

    PubSub.broadcast(EventStore.PubSub, "events", event)
  end

  def subscribe() do
    PubSub.subscribe(EventStore.PubSub, "events")
  end

  def stream(aggregate_id) do
    @adapter.stream(aggregate_id)
    |> Enum.map(fn event ->
      module = Module.safe_concat(@namespace, event.name)

      module
      |> struct(%{aggregate_id: event.aggregate_id})
      |> then(&module.cast_payload(&1, event.payload))
      |> Ecto.Changeset.apply_changes()
      |> tap(&Logger.debug("Event #{event.name} loaded: #{inspect(&1)}"))
    end)
  end
end
