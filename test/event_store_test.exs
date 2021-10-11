defmodule EventStoreTest do
  use ExUnit.Case, async: true
  alias EventStore.{UserCreated, UserUpdated}

  @data %{"some" => "data"}

  test "dispatch/1" do
    EventStore.subscribe()

    EventStore.dispatch(%UserCreated{
      aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
      data: @data
    })

    assert_received %UserCreated{
      aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
      data: @data
    }
  end

  describe "stream/1" do
    test "returns only events for the given aggregate ID" do
      aggregate_id = Ecto.UUID.generate()

      EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, data: @data})

      EventStore.dispatch(%UserCreated{
        aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
        data: @data
      })

      EventStore.dispatch(%UserUpdated{
        aggregate_id: aggregate_id,
        data: @data
      })

      assert [first, second] = EventStore.stream(aggregate_id)
      assert %UserCreated{aggregate_id: ^aggregate_id} = first
      assert %UserUpdated{aggregate_id: ^aggregate_id} = second
    end

    test "returns only events for the given event name" do
      aggregate_id = Ecto.UUID.generate()

      EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, data: @data})

      EventStore.dispatch(%UserCreated{
        aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
        data: @data
      })

      EventStore.dispatch(%UserUpdated{
        aggregate_id: aggregate_id,
        data: @data
      })

      assert events = EventStore.stream(UserCreated)
      assert Enum.all?(events, &assert(%UserCreated{} = &1))
    end
  end

  test "exists?/1 checks whether the given event with the specified aggregate_id exists" do
    aggregate_id = Ecto.UUID.generate()

    refute EventStore.exists?(aggregate_id, "UserCreated")

    EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, data: @data})
    assert EventStore.exists?(aggregate_id, "UserCreated")
  end
end
