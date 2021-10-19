defmodule EventStore.Event do
  use Ecto.Schema
  import Ecto.Changeset

  defmacro __using__(_) do
    quote do
      @behaviour EventStore.Event

      use Ecto.Schema
      import Ecto.Changeset
      alias EventStore.Event
    end
  end

  @callback changeset(struct()) :: Ecto.Changeset.t()
  @callback cast_payload(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()

  schema "events" do
    field :name, :string
    field :version, :integer, default: 1
    field :aggregate_id, :string
    field :aggregate_version, :integer, default: 0
    field :payload, :string

    timestamps updated_at: false
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:aggregate_id, :version, :name, :payload])
    |> validate_required([:aggregate_id, :version, :name, :payload])
  end
end
