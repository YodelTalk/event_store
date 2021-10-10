defmodule EventStoreTest do
  use ExUnit.Case, async: true
  alias EventStore.TestEvent

  @data %{"some" => "data"}

  test "dispatch/1" do
    EventStore.subscribe()

    EventStore.dispatch(%TestEvent{
      aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
      data: @data
    })

    assert_received %TestEvent{
      aggregate_id: "01234567-89ab-cdef-0123-456789abcdef"
    }
  end

  test "stream/1 returns only events for the given aggregate ID" do
    aggregate_id = Ecto.UUID.generate()

    EventStore.dispatch(%TestEvent{aggregate_id: aggregate_id, data: @data})

    EventStore.dispatch(%TestEvent{
      aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
      data: @data
    })

    EventStore.dispatch(%TestEvent{
      aggregate_id: aggregate_id,
      data: @data
    })

    assert [first, second] = EventStore.stream(aggregate_id)
    assert %TestEvent{aggregate_id: ^aggregate_id} = first
    assert %TestEvent{aggregate_id: ^aggregate_id} = second
  end
end
