defmodule Producer do
  alias Producer.Event

  def dispatch do
    EventStore.dispatch(%Event{aggregate_id: Ecto.UUID.generate()})
    :ok
  end
end
