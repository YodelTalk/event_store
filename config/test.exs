import Config

config :event_store,
  adapter:
    String.to_atom(System.get_env("EVENT_STORE_ADAPTER", "Elixir.EventStore.Adapters.InMemory")),
  sync_timeout: 100
