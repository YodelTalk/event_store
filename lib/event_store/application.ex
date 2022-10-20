defmodule EventStore.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [EventStore.PubSub] ++ extra_children(EventStore.adapter())

    opts = [strategy: :one_for_one, name: EventStore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp extra_children(EventStore.Adapters.InMemory) do
    [EventStore.Adapters.InMemory]
  end

  defp extra_children(EventStore.Adapters.Postgres) do
    [EventStore.Adapters.Postgres.Repo]
  end
end
