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

  defp children(EventStore.Adapters.InMemory, EventStore.PubSub.Registry) do
    [EventStore.PubSub.Registry, EventStore.Adapters.InMemory]
  end

  defp children(EventStore.Adapters.Postgres, EventStore.PubSub.Registry) do
    [EventStore.PubSub.Registry, EventStore.Adapters.Postgres.Repo]
  end

  defp children(EventStore.Adapters.Postgres, pub_sub)
       when pub_sub in [
              EventStore.PubSub.Multi,
              EventStore.PubSub.Postgres
            ] do
    repo_config = EventStore.Adapters.Postgres.Repo.config()

    [
      EventStore.Adapters.Postgres.Repo,
      {Postgrex.Notifications, repo_config ++ [name: EventStore.PubSub.Postgres.Notifications]},
      EventStore.PubSub.Registry,
      EventStore.PubSub.Postgres
    ]
  end

  defp children(adapter, pub_sub) do
    raise "Running event_store with both #{adapter} and #{pub_sub} makes no sense, please update your config"
  end
end
