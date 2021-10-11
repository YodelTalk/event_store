defmodule EventStore.Adapters.Postgres do
  @behaviour EventStore.Adapter

  import Ecto.Query
  alias EventStore.Event

  defmodule Repo do
    use Ecto.Repo, otp_app: :event_store, adapter: Ecto.Adapters.Postgres
  end

  @impl true
  defdelegate insert(changeset), to: Repo

  @namespace Application.get_env(:event_store, :namespace, EventStore)
             |> Atom.to_string()
             |> Kernel.<>(".")

  @impl true
  def stream(aggregate_id) when is_binary(aggregate_id) do
    from(e in Event, where: e.aggregate_id == ^aggregate_id, order_by: :id)
    |> Repo.all()
  end

  def stream(name) when is_atom(name) do
    name =
      name
      |> Atom.to_string()
      |> String.replace_prefix(@namespace, "")

    from(e in Event, where: e.name == ^name, order_by: :id)
    |> Repo.all()
  end

  @impl true
  def exists?(aggregate_id, name) do
    from(e in Event, where: e.aggregate_id == ^aggregate_id and e.name == ^name)
    |> Repo.exists?()
  end
end
