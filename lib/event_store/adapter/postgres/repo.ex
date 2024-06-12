defmodule EventStore.Adapter.Postgres.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :event_store, adapter: Ecto.Adapters.Postgres
end
