import Config

config :event_store,
  adapter:
    System.get_env("EVENT_STORE_ADAPTER", "Elixir.EventStore.Adapters.InMemory")
    |> String.to_atom(),
  pub_sub:
    System.get_env("EVENT_STORE_PUB_SUB", "Elixir.EventStore.PubSub.Registry")
    |> String.to_atom(),
  sync_timeout: 100
