defmodule EventStore.UserUpdated do
  use EventStore.Event

  @primary_key false
  embedded_schema do
    field :aggregate_id, :string
    field :version, :integer, default: 1
    field :data, :map
  end

  def changeset(event) do
    attrs = %{
      aggregate_id: event.aggregate_id,
      name: __MODULE__ |> Module.split() |> List.last(),
      payload: Jason.encode!(event.data)
    }

    Event.changeset(%Event{}, attrs)
  end

  def cast_payload(data, payload) do
    cast(data, %{data: Jason.decode!(payload)}, [:data])
  end
end
