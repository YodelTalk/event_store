defmodule EventStore.Event do
  @moduledoc """
  Defines the schema and behaviour for storing and handling events in the EventStore.
  """

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
        field :inserted_at, :naive_datetime_usec
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

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "events" do
    field :name, :string
    field :version, :integer, default: 1
    field :aggregate_id, :string
    field :aggregate_version, :integer
    field :payload, :string
    field :inserted_at, :naive_datetime_usec
  end

  @doc false
  def changeset(event, attrs) do
    inserted_at = apply(Process.get(:naive_date_time, NaiveDateTime), :utc_now, [])

    event
    |> cast(attrs, [:aggregate_id, :version, :name, :payload])
    |> validate_required([:aggregate_id, :version, :name, :payload])
    |> put_change(:inserted_at, inserted_at)
  end
end
