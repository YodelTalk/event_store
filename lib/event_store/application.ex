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

  defp children(EventStore.Adapter.InMemory, EventStore.PubSub.Registry) do
    [EventStore.PubSub.Registry, EventStore.Adapter.InMemory]
  end

  defp children(EventStore.Adapter.Postgres, EventStore.PubSub.Registry) do
    [EventStore.PubSub.Registry, EventStore.Adapter.Postgres.Repo]
  end

  defp children(EventStore.Adapter.Postgres, pub_sub)
       when pub_sub in [
              EventStore.PubSub.Multi,
              EventStore.PubSub.Postgres
            ] do
    repo_config = EventStore.Adapter.Postgres.Repo.config()

    [
      EventStore.Adapter.Postgres.Repo,
      {Postgrex.Notifications, repo_config ++ [name: EventStore.PubSub.Postgres.Notifications]},
      EventStore.PubSub.Registry,
      EventStore.PubSub.Postgres
    ]
  end

  defp children(adapter, pub_sub) do
    raise ArgumentError, """
    Configuration error: The event_store is currently configured to use both #{inspect(adapter)} as an adapter and #{inspect(pub_sub)} as a pub_sub module.
    This combination is invalid. Please review your configuration settings and choose appropriate options for adapter and pub_sub.
    """
  end
end
