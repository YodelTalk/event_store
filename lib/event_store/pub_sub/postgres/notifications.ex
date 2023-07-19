defmodule EventStore.PubSub.Postgres.Notifications do
  def child_spec(opts) do
    opts =
      EventStore.Adapter.Postgres.Repo.config()
      |> Keyword.merge(name: __MODULE__)
      |> Keyword.merge(opts)

    %{
      id: __MODULE__,
      start: {Postgrex.Notifications, :start_link, [opts]}
    }
  end
end
