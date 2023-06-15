import Config

config :event_store,
  adapter:
    String.to_atom(System.get_env("EVENT_STORE_ADAPTER", "Elixir.EventStore.Adapter.InMemory")),
  sync_timeout: 100

config :event_store, EventStore.Adapter.Postgres.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  database: "event_store_test",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  pool: Ecto.Adapters.SQL.Sandbox
