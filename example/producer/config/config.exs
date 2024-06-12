import Config

config :producer,
  ecto_repos: [EventStore.Adapter.Postgres.Repo]

config :event_store,
  adapter: EventStore.Adapter.Postgres,
  pub_sub: EventStore.PubSub.Multi,
  namespace: Consumer

config :event_store, EventStore.PubSub.Multi,
  broadcast_to: [EventStore.PubSub.Postgres, EventStore.PubSub.Registry]

config :event_store, EventStore.Adapter.Postgres.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  database: "event_store_example_app",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
