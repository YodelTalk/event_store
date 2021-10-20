defmodule EventStore do
  require Logger
  alias Phoenix.PubSub

  @adapter Application.fetch_env!(:event_store, :adapter)
  @namespace Application.get_env(:event_store, :namespace, __MODULE__)

  defdelegate exists?(aggregate_id, name), to: @adapter

  @spec dispatch(%EventStore.Event{}) :: {:ok, %EventStore.Event{}}
  def dispatch(event) do
    {:ok, %{aggregate_version: aggregate_version}} =
      event
      |> event.__struct__.changeset()
      |> then(&@adapter.insert(&1))

    event = %{event | aggregate_version: aggregate_version, from: self()}

    Logger.debug("Event dispatched: #{inspect(event)}")
    PubSub.broadcast(EventStore.PubSub, "events", event)

    {:ok, event}
  end

  def subscribe() do
    PubSub.subscribe(EventStore.PubSub, "events")
  end

  def stream(aggregate_id_or_name) do
    aggregate_id_or_name
    |> @adapter.stream()
    |> Enum.map(fn event ->
      module = Module.safe_concat(@namespace, event.name)

      module
      |> struct(%{aggregate_id: event.aggregate_id})
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
