defmodule EventStoreTest do
  use ExUnit.Case, async: true
  alias EventStore.{UserCreated, UserUpdated}

  @data %{"some" => "data"}

  describe "dispatch/1" do
    test "dispatches the event to all subscribers" do
      EventStore.subscribe()

      {:ok, event} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
          data: @data
        })

      refute is_nil(event.aggregate_version)

      assert_received %UserCreated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        data: @data
      }
    end

    test "increments aggregate_version" do
      EventStore.subscribe()

      aggregate_id = Ecto.UUID.generate()

      {:ok, %{aggregate_version: 1}} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: aggregate_id,
          data: @data
        })

      {:ok, %{aggregate_version: 1}} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: Ecto.UUID.generate(),
          data: @data
        })

      {:ok, %{aggregate_version: 2}} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: aggregate_id,
          data: @data
        })
    end
  end

  describe "sync_dispatch/1" do
    test "dispatches the event to all subscribers which must acknowledge the event" do
      spawn(fn ->
        EventStore.subscribe()

        receive do
          event -> EventStore.acknowledge(event)
        end
      end)

      {:ok, event} =
        EventStore.sync_dispatch(%UserCreated{
          aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
          data: @data
        })

      refute is_nil(event.aggregate_version)
    end

    test "raises in case the event is not acknowledged" do
      assert_raise EventStore.AcknowledgementError, fn ->
        EventStore.sync_dispatch(%UserCreated{
          aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
          data: @data
        })
      end
    end
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

    refute EventStore.exists?(aggregate_id, UserCreated)

    EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, data: @data})
    assert EventStore.exists?(aggregate_id, UserCreated)
  end
end
