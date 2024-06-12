defmodule EventStore.PubSub.Postgres do
  @moduledoc """
  An `EventStore.PubSub` adapter using PostgreSQL's `LISTEN` and `NOTIFY` to
  broadcast events. `EventStore.PubSub.Postgres` connects to a PostgreSQL
  channel and alerts subscribers of new events.
  """

  @behaviour EventStore.PubSub

  use GenServer
  require Logger

  alias EventStore.Adapter.Postgres.Repo
  alias Postgrex.Notifications

  @channel "events"

  @doc """
  Starts the PubSub server process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, name: name)
  end

  @doc """
  Subscribes the calling process to a specific event type using PostgreSQL notifications.
  """
  @impl true
  def subscribe(name) when is_atom(name) do
    GenServer.cast(__MODULE__, {:subscribe, EventStore.to_name(name)})
    EventStore.PubSub.Registry.subscribe(name)
  end

  @doc """
  Broadcasts an event to all subscribers through PostgreSQL notifications.
  """
  @impl true
  def broadcast(event) when is_struct(event) do
    payload = "#{event.id}:#{EventStore.to_name(event)}"

    Ecto.Adapters.SQL.query!(Repo, "NOTIFY #{@channel}, '#{payload}'")
    Logger.debug("Send #{inspect(payload)} on channel #{@channel}")

    # Return an empty list because there is currently no way to get
    # the list of subscribers.
    []
  end

  # GenServer API

  @impl true
  def init(_) do
    Notifications.listen(__MODULE__.Notifications, @channel)
    {:ok, []}
  end

  @impl true
  def handle_cast({:subscribe, name}, names) do
    {:noreply, Enum.uniq([name | names])}
  end

  @impl true
  def handle_info(
        {:notification, _pid, _ref, @channel,
         <<id::binary-size(36), ":", name::binary>> = payload},
        names
      ) do
    Logger.debug("Received #{inspect(payload)} on channel #{@channel}")

    if EventStore.to_name(name) in names do
      EventStore.Event
      |> Repo.get!(id)
      |> EventStore.cast()
      |> EventStore.PubSub.Registry.broadcast()
    end

    {:noreply, names}
  end
end
