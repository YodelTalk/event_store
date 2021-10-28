defmodule EventStore.Event do
  use Ecto.Schema
  import Ecto.Changeset

  defmacro __using__(_) do
    quote do
      @behaviour EventStore.Event

      use Ecto.Schema
      import Ecto.Changeset
      alias EventStore.Event

      @primary_key false
      embedded_schema do
        field :from, :any, virtual: true
        field :aggregate_id, :string
        field :aggregate_version, :integer
        field :version, :integer, default: 1
        field :payload, :map
      end

      def changeset(event) do
        attrs = %{
          aggregate_id: event.aggregate_id,
          aggregate_version: event.aggregate_version,
          name: __MODULE__ |> Module.split() |> List.last(),
          payload: Jason.encode!(event.payload)
        }

        Event.changeset(%Event{}, attrs)
      end

      def cast_payload(data, payload) do
        cast(data, %{payload: Jason.decode!(payload)}, [:payload])
      end
    end
  end

  @callback changeset(struct()) :: Ecto.Changeset.t()
  @callback cast_payload(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()

  schema "events" do
    field :name, :string
    field :version, :integer, default: 1
    field :aggregate_id, :string
    field :aggregate_version, :integer
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
