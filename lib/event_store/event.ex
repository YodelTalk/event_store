defmodule EventStore.Event do
  @moduledoc """
  Defines the schema and behaviour for storing and handling events in the
  EventStore.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type payload :: String.t()

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t(),
          from: any(),
          version: non_neg_integer(),
          aggregate_id: String.t(),
          aggregate_version: non_neg_integer(),
          payload: payload(),
          inserted_at: NaiveDateTime.t()
        }

  defmacro __using__(_) do
    quote do
      @behaviour EventStore.Event

      use Ecto.Schema
      import Ecto.Changeset
      alias EventStore.Event

      embedded_schema do
        field :from, :any, virtual: true
        field :version, :integer, default: 1
        field :aggregate_id, :binary_id
        field :aggregate_version, :integer
        field :payload, :map
        field :inserted_at, :naive_datetime_usec
      end

      @spec changeset(EventStore.Event.t()) :: Ecto.Changeset.t()
      def changeset(event) do
        name =
          __MODULE__
          |> Module.split()
          |> List.last()

        payload =
          case event.payload do
            nil -> nil
            payload -> Jason.encode!(payload)
          end

        Event.changeset(%Event{}, %{
          aggregate_id: event.aggregate_id,
          aggregate_version: event.aggregate_version,
          name: name,
          payload: payload
        })
      end

      @spec cast_payload(Ecto.Schema.t(), EventStore.Event.payload()) :: Ecto.Changeset.t()
      def cast_payload(data, payload) do
        payload_decoded =
          case payload do
            nil -> nil
            payload -> Jason.decode!(payload)
          end

        cast(data, %{payload: payload_decoded}, [:payload])
      end
    end
  end

  @callback changeset(struct()) :: Ecto.Changeset.t()
  @callback cast_payload(Ecto.Schema.t(), EventStore.Event.payload()) :: Ecto.Changeset.t()

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "events" do
    field :name, :string
    field :from, :any, virtual: true
    field :version, :integer, default: 1
    field :aggregate_id, :string
    field :aggregate_version, :integer
    field :payload, :string
    field :inserted_at, :naive_datetime_usec
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    inserted_at = apply(Process.get(:naive_date_time, NaiveDateTime), :utc_now, [])

    event
    |> cast(attrs, [:aggregate_id, :version, :name, :payload])
    |> validate_required([:aggregate_id, :version, :name, :payload])
    |> put_change(:inserted_at, inserted_at)
  end
end
