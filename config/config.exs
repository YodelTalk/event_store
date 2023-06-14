import Config

config :event_store,
  adapter: EventStore.Adapter.Postgres,
  ecto_repos: [EventStore.Adapter.Postgres.Repo]

config :event_store, EventStore.Adapter.Postgres.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  database: "event_store_dev",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
