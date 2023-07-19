defmodule EventStore.PubSub.Postgres.Notifications do
  @moduledoc false

  def child_spec(opts) do
    opts =
      EventStore.Adapter.Postgres.Repo.config()
      |> Keyword.merge(name: __MODULE__)
      |> Keyword.merge(auto_reconnect: true)
      |> Keyword.merge(opts)

    %{
      id: __MODULE__,
      start: {Postgrex.Notifications, :start_link, [opts]}
    }
  end
end
