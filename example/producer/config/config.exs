import Config

config :producer,
  ecto_repos: [EventStore.Adapters.Postgres.Repo]

config :event_store,
  adapter: EventStore.Adapters.Postgres,
  pub_sub: EventStore.PubSub.Multi,
  namespace: Consumer,
  broadcast_to: [EventStore.PubSub.Postgres, EventStore.PubSub.Registry]

config :event_store, EventStore.Adapters.Postgres.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  database: "event_store_example_app",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
