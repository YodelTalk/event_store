defmodule EventStore.Application do
  @moduledoc false
  use Application

  @doc false
  @impl true
  def start(_type, _args) do
    children = children(EventStore.adapter(), EventStore.pub_sub())

    opts = [strategy: :one_for_one, name: EventStore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp children(EventStore.Adapters.InMemory, _) do
    [
      EventStore.Adapters.InMemory,
      EventStore.PubSub.Registry
    ]
  end

  defp children(EventStore.Adapters.Postgres, EventStore.PubSub.Registry) do
    [
      EventStore.Adapters.Postgres.Repo,
      EventStore.PubSub.Registry
    ]
  end

  defp children(EventStore.Adapters.Postgres, EventStore.PubSub.Postgres) do
    repo_config = EventStore.Adapters.Postgres.Repo.config()

    [
      EventStore.Adapters.Postgres.Repo,
      {Registry, keys: :duplicate, name: EventStore.PubSub.Postgres.Registry},
      {Postgrex.Notifications, repo_config ++ [name: EventStore.PubSub.Postgres.Notifications]},
      EventStore.PubSub.Postgres
    ]
  end
end
