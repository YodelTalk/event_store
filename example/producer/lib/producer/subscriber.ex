defmodule Producer.Subscriber do
  use GenServer
  alias Producer.Event

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    EventStore.subscribe(Event)
    {:ok, []}
  end

  def handle_info(event, state) do
    IO.inspect(event, label: "An event was received")
    {:noreply, state}
  end
end
