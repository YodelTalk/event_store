defmodule EventStoreTest do
  use ExUnit.Case, async: true
  alias EventStore.{UserCreated, UserUpdated}

  @unix_time ~N[1970-01-01 00:00:00.000000]
  @data %{"some" => "data"}

  setup do
    start_supervised!(MockNaiveDateTime)
    Process.put(:naive_date_time, MockNaiveDateTime)
    on_exit(fn -> Process.delete(:naive_date_time) end)
  end

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
    setup do
      {:ok, started_at: NaiveDateTime.utc_now()}
    end

    test "returns only recent events for the given aggregate ID", %{started_at: started_at} do
      aggregate_id = Ecto.UUID.generate()

      MockNaiveDateTime.set(@unix_time)
      {:ok, old} = EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})
      MockNaiveDateTime.reset()

      EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})
      EventStore.dispatch(%UserCreated{aggregate_id: Ecto.UUID.generate(), payload: @data})
      EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})

      transaction(fn ->
        events = Enum.to_list(EventStore.stream(aggregate_id, started_at))

        assert old not in events
        assert Enum.all?(events, &assert(&1.aggregate_id == aggregate_id))
      end)
    end

    test "returns only recent events for the given event name", %{started_at: started_at} do
      aggregate_id = Ecto.UUID.generate()

      MockNaiveDateTime.set(@unix_time)
      {:ok, old} = EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})
      MockNaiveDateTime.reset()

      EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})
      EventStore.dispatch(%UserCreated{aggregate_id: Ecto.UUID.generate(), payload: @data})
      EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})

      transaction(fn ->
        events = Enum.to_list(EventStore.stream(UserCreated, started_at))

        assert old not in events
        assert Enum.all?(events, &assert(is_struct(&1, UserCreated)))
      end)
    end

    test "raises an error when an invalid aggregate ID is given" do
      assert_raise FunctionClauseError, fn ->
        EventStore.stream("DefinitelyNotAnUUID", NaiveDateTime.utc_now())
      end
    end
  end

  test "exists?/2 checks whether an event of the specified type and aggregate_id exists" do
    aggregate_id = Ecto.UUID.generate()
    refute EventStore.exists?(aggregate_id, UserCreated)

    EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})
    assert EventStore.exists?(aggregate_id, UserCreated)
  end

  test "first/2 returns the first event of the specified type and aggregate_id" do
    aggregate_id = Ecto.UUID.generate()
    refute EventStore.first(aggregate_id, UserCreated)

    EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})
    EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})
    EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})

    assert %UserCreated{aggregate_version: 1} = EventStore.first(aggregate_id, UserCreated)
    assert %UserUpdated{aggregate_version: 2} = EventStore.first(aggregate_id, UserUpdated)
  end

  test "last/2 returns the last event of the specified type and aggregate_id" do
    aggregate_id = Ecto.UUID.generate()
    refute EventStore.last(aggregate_id, UserCreated)

    EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})
    EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})
    EventStore.dispatch(%UserUpdated{aggregate_id: aggregate_id, payload: @data})

    assert %UserCreated{aggregate_version: 1} = EventStore.last(aggregate_id, UserCreated)
    assert %UserUpdated{aggregate_version: 3} = EventStore.last(aggregate_id, UserUpdated)
  end

  test "supports mocking of NaiveDateTime.utc_now/1" do
    utc_now = ~N[2022-01-01 00:00:00.000000]
    MockNaiveDateTime.set(utc_now)

    EventStore.subscribe([UserCreated, UserUpdated])

    aggregate_id = Ecto.UUID.generate()
    {:ok, _} = EventStore.dispatch(%UserCreated{aggregate_id: aggregate_id, payload: @data})

    assert_received %UserCreated{
      aggregate_id: ^aggregate_id,
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
