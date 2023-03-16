defmodule EventStoreTest do
  use ExUnit.Case, async: true
  alias EventStore.{UserCreated, UserUpdated}

  @data %{"some" => "data"}

  describe "dispatch/1" do
    test "dispatches the event to all subscribers" do
      EventStore.subscribe(UserCreated)

      {:ok, event} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
          payload: @data
        })

      assert_event_structure(event)

      assert_received %UserCreated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      }
    end

    test "does not dispatch events which are not subscribed" do
      EventStore.subscribe(UserCreated)

      EventStore.dispatch(%UserCreated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      })

      EventStore.dispatch(%UserUpdated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      })

      assert_received %UserCreated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      }

      refute_received %UserUpdated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      }
    end

    test "increments aggregate_version" do
      EventStore.subscribe(UserCreated)

      aggregate_id = Ecto.UUID.generate()

      {:ok, %{aggregate_version: 1}} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: aggregate_id,
          payload: @data
        })

      {:ok, %{aggregate_version: 1}} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: Ecto.UUID.generate(),
          payload: @data
        })

      {:ok, %{aggregate_version: 2}} =
        EventStore.dispatch(%UserCreated{
          aggregate_id: aggregate_id,
          payload: @data
        })
    end
  end

  describe "sync_dispatch/1" do
    test "dispatches the event to all subscribers which all must acknowledge the event" do
      myself = self()

      spawn(fn ->
        EventStore.subscribe(UserCreated)
        send(myself, :ready)

        receive do
          event -> EventStore.acknowledge(event)
        end

        send(myself, :acknowledged)
      end)

      spawn(fn ->
        EventStore.subscribe(UserCreated)
        send(myself, :ready_too)

        receive do
          event -> EventStore.acknowledge(event)
        end

        send(myself, :acknowledged_too)
      end)

      assert_receive :ready
      assert_receive :ready_too

      {:ok, event} =
        EventStore.sync_dispatch(%UserCreated{
          aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
          payload: @data
        })

      assert_event_structure(event)

      assert_receive :acknowledged
      assert_receive :acknowledged_too
    end

    test "raises in case the event is not acknowledged" do
      EventStore.subscribe(UserCreated)

      assert_raise EventStore.AcknowledgementError, fn ->
        EventStore.sync_dispatch(%UserCreated{
          aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
          payload: @data
        })
      end
    end

    test "does not raise in case a subscriber is not alive anymore" do
      myself = self()

      pid =
        spawn(fn ->
          EventStore.subscribe(UserCreated)
          send(myself, :ready)
          :timer.sleep(:infinity)
        end)

      assert_receive :ready

      Process.exit(pid, :kill)

      EventStore.sync_dispatch(%UserCreated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      })
    end
  end

  describe "stream/2" do
    test "returns only events for the given aggregate ID" do
      aggregate_id = Ecto.UUID.generate()

      EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})

      EventStore.dispatch(%UserCreated{
        aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
        payload: @data
      })

      EventStore.dispatch(%UserUpdated{
        aggregate_id: aggregate_id,
        payload: @data
      })

      assert {:ok, [first, second]} =
               transaction(fn ->
                 aggregate_id
                 |> EventStore.stream()
                 |> Enum.to_list()
               end)

      assert %UserCreated{aggregate_id: ^aggregate_id} = first
      assert %UserUpdated{aggregate_id: ^aggregate_id} = second

      assert_event_structure(first)
      assert_event_structure(second)
    end

    test "returns only events for the given event name" do
      aggregate_id = Ecto.UUID.generate()

      EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})

      EventStore.dispatch(%UserCreated{
        aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
        payload: @data
      })

      EventStore.dispatch(%UserUpdated{
        aggregate_id: aggregate_id,
        payload: @data
      })

      transaction(fn ->
        assert UserCreated
               |> EventStore.stream()
               |> Enum.all?(&assert(%UserCreated{} = &1))
      end)
    end

    test "only accepts either an event name or an UUID" do
      assert_raise FunctionClauseError, fn ->
        EventStore.stream("DefinitelyNotAnUUID")
      end
    end

    test "returns only events after certain time" do
      EventStore.dispatch(%UserCreated{aggregate_id: Ecto.UUID.generate(), payload: @data})

      {:ok, %UserCreated{inserted_at: start_time}} =
        EventStore.dispatch(%UserCreated{aggregate_id: Ecto.UUID.generate(), payload: @data})

      EventStore.dispatch(%UserCreated{aggregate_id: Ecto.UUID.generate(), payload: @data})
      EventStore.dispatch(%UserCreated{aggregate_id: Ecto.UUID.generate(), payload: @data})

      transaction(fn ->
        all_events = UserCreated |> EventStore.stream() |> Enum.to_list()
        limited_events = UserCreated |> EventStore.stream(start_time) |> Enum.to_list()

        assert length(all_events) > length(limited_events)
      end)
    end
  end

  test "exists?/1 checks whether the given event with the specified aggregate_id exists" do
    aggregate_id = Ecto.UUID.generate()

    refute EventStore.exists?(aggregate_id, UserCreated)

    EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})
    assert EventStore.exists?(aggregate_id, UserCreated)
  end

  test "supports mocking of NaiveDateTime.utc_now/1" do
    utc_now = ~N[2022-01-01 00:00:00.000000]

    start_supervised!(MockNaiveDateTime)
    MockNaiveDateTime.set(utc_now)
    Process.put(:naive_date_time, MockNaiveDateTime)

    EventStore.subscribe([UserCreated, UserUpdated])

    {:ok, _} =
      EventStore.dispatch(%UserCreated{
        aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
        payload: @data
      })

    assert_received %UserCreated{
      aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
      payload: @data,
      inserted_at: ^utc_now
    }
  end

  defp assert_event_structure(event) do
    refute is_nil(event.aggregate_id)
    refute is_nil(event.aggregate_version)
    assert %{} = event.payload
    refute is_nil(event.inserted_at)
  end

  defp transaction(fun) do
    case EventStore.adapter() do
      EventStore.Adapters.InMemory -> {:ok, fun.()}
      EventStore.Adapters.Postgres -> EventStore.Adapters.Postgres.Repo.transaction(fun)
    end
  end
end
