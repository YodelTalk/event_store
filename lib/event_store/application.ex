defmodule EventStore.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EventStore.Adapters.InMemory,
      EventStore.Adapters.Postgres.Repo,
      EventStore.PubSub
    ]

    opts = [strategy: :one_for_one, name: EventStore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
