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

    Registry.register(__MODULE__.Registry, Atom.to_string(topic), nil)

    :ok
  end

  @impl true
  def broadcast(event) when is_struct(event) do
    payload = %{
      id: event.id,
      name: EventStore.to_name(event),
      version: event.version
    }

    Ecto.Adapters.SQL.query!(Repo, "NOTIFY #{@channel}, '#{Jason.encode!(payload)}'")

    # Always return an empty list because there is currently no way to get
    # informed about potential subscribers
    []
  end

  # GenServer API

  @impl true
  def init(_) do
    {:ok, ref} = Notifications.listen(__MODULE__.Notifications, @channel)
    {:ok, ref}
  end

  @impl true
  def handle_info({:notification, _pid, _ref, @channel, payload}, state) do
    %{"id" => id, "name" => name} = Jason.decode!(payload)

    topic = Atom.to_string(Module.safe_concat(EventStore.namespace(), name))
    event = EventStore.Event |> Repo.get!(id) |> EventStore.cast()

    for {pid, _} <- Registry.lookup(__MODULE__.Registry, topic) do
      send(pid, event)
      pid
    end

    {:noreply, state}
  end
end
