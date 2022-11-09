defmodule EventStore.PubSub.Postgres do
  @behaviour EventStore.PubSub

  use GenServer

  alias Postgrex.Notifications
  alias EventStore.Adapters.Postgres.Repo

  @channel "events"

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, name: name)
  end

  # PubSub API

  @impl true
  def subscribe(topic) when is_atom(topic) do
    if is_nil(Process.whereis(__MODULE__)) do
      raise "#{__MODULE__} is not running"
    end

    EventStore.PubSub.Registry.subscribe(topic)
  end

  @impl true
  def broadcast(event) when is_struct(event) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "NOTIFY #{@channel}, '#{event.id}:#{EventStore.to_name(event)}'"
    )

    # Always return an empty list because there is currently no way to get
    # informed about potential subscribers
    []
  end

  # GenServer API

  @impl true
  def init(_) do
    {:ok, _ref} = Notifications.listen(__MODULE__.Notifications, @channel)
    {:ok, []}
  end

  @impl true
  def handle_info(
        {:notification, _pid, _ref, @channel, <<id::binary-size(36), ":", _name::binary>>},
        state
      ) do
    # TODO: Filter unused events before loading them from the database!

    EventStore.Event
    |> Repo.get!(id)
    |> EventStore.cast()
    |> EventStore.PubSub.Registry.broadcast()

    {:noreply, state}
  end
end
