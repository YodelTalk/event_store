import Config

config :event_store,
  adapter:
    System.get_env("EVENT_STORE_ADAPTER", "Elixir.EventStore.Adapters.InMemory")
    |> String.to_atom()
