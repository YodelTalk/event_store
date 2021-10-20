defmodule EventStore.UserUpdated do
  use EventStore.Event

  @primary_key false
  embedded_schema do
    field :from, :any, virtual: true
    field :aggregate_id, :string
    field :aggregate_version, :integer
    field :version, :integer, default: 1
    field :data, :map
  end

  def changeset(event) do
    attrs = %{
      aggregate_id: event.aggregate_id,
      aggregate_version: event.aggregate_version,
      name: __MODULE__ |> Module.split() |> List.last(),
      payload: Jason.encode!(event.data)
    }

    Event.changeset(%Event{}, attrs)
  end

  def cast_payload(data, payload) do
    cast(data, %{data: Jason.decode!(payload)}, [:data])
  end
end
