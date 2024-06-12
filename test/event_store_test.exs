defmodule EventStoreTest do
  use ExUnit.Case
  require Ecto.Query
  alias EventStore.{UserCreated, UserUpdated, UserDestroyed}

  @long_time_ago ~N[1970-01-01 00:00:00.000000]
  @data %{"some" => "data"}

  setup_all do
    {:ok, adapter: EventStore.adapter()}
  end

  setup :start_dependencies

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

    if EventStore.adapter() == EventStore.Adapter.Postgres do
      test "accepts empty payload" do
        aggregate_id = Ecto.UUID.generate()

        EventStore.dispatch(%UserCreated{
          aggregate_id: aggregate_id
        })

        assert %EventStore.Event{payload: nil} =
                 EventStore.Adapter.Postgres.Repo.one!(
                   Ecto.Query.where(EventStore.Event, aggregate_id: ^aggregate_id)
                 )
      end
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

  defp record_started_at(_) do
    {:ok, %{started_at: NaiveDateTime.utc_now()}}
  end

  defp dispatch_events(_) do
    [alice, bob, charlie] = for _ <- 1..3, do: Ecto.UUID.generate()

    MockNaiveDateTime.set(@long_time_ago)
    EventStore.dispatch(%UserCreated{aggregate_id: alice, payload: @data})
    MockNaiveDateTime.reset()

    EventStore.dispatch(%UserCreated{aggregate_id: bob, payload: @data})
    EventStore.dispatch(%UserCreated{aggregate_id: charlie, payload: @data})

    EventStore.dispatch(%UserUpdated{aggregate_id: alice, payload: @data})
    EventStore.dispatch(%UserUpdated{aggregate_id: bob, payload: @data})
    EventStore.dispatch(%UserUpdated{aggregate_id: charlie, payload: @data})

    EventStore.dispatch(%UserDestroyed{aggregate_id: alice, payload: @data})
    EventStore.dispatch(%UserDestroyed{aggregate_id: bob, payload: @data})
    EventStore.dispatch(%UserDestroyed{aggregate_id: charlie, payload: @data})

    %{aggregate_ids: %{alice: alice, bob: bob, charlie: charlie}}
  end

  describe "stream/0" do
    setup :dispatch_events

    test "returns all events" do
      EventStore.transaction(fn ->
        events = EventStore.stream()

        assert Enum.count(events) == 9
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end
  end

  describe "stream/1" do
    setup :dispatch_events

    test "returns events for the given aggregate ID", %{aggregate_ids: aggregate_ids} do
      EventStore.transaction(fn ->
        events = EventStore.stream(aggregate_ids.alice)

        assert Enum.all?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate IDs", %{aggregate_ids: aggregate_ids} do
      EventStore.transaction(fn ->
        events = EventStore.stream([aggregate_ids.alice, aggregate_ids.bob])

        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns only events for the given event name" do
      EventStore.transaction(fn ->
        events = EventStore.stream(UserCreated)

        assert Enum.all?(events, &is_struct(&1, UserCreated))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given event names" do
      EventStore.transaction(fn ->
        events = EventStore.stream([UserCreated, UserUpdated])

        assert Enum.any?(events, &is_struct(&1, UserCreated))
        assert Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "raises an error when an invalid aggregate ID is given" do
      assert_raise FunctionClauseError, fn ->
        EventStore.stream("DefinitelyNotAnUUID")
      end
    end
  end

  describe "stream/2" do
    setup :dispatch_events

    test "returns events for the given aggregate ID and event name", %{
      aggregate_ids: aggregate_ids
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream(aggregate_ids.alice, UserCreated)

        assert Enum.all?(events, &(&1.aggregate_id == aggregate_ids.alice))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.all?(events, &is_struct(&1, UserCreated))
        refute Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate IDs and event name", %{
      aggregate_ids: aggregate_ids
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream([aggregate_ids.alice, aggregate_ids.bob], UserCreated)

        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.all?(events, &is_struct(&1, UserCreated))
        refute Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate ID and event names", %{
      aggregate_ids: aggregate_ids
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream(aggregate_ids.alice, [UserCreated, UserUpdated])

        assert Enum.all?(events, &(&1.aggregate_id == aggregate_ids.alice))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.any?(events, &is_struct(&1, UserCreated))
        assert Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate IDs and event names", %{
      aggregate_ids: aggregate_ids
    } do
      EventStore.transaction(fn ->
        events =
          EventStore.stream([aggregate_ids.alice, aggregate_ids.bob], [UserCreated, UserUpdated])

        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.any?(events, &is_struct(&1, UserCreated))
        assert Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end
  end

  describe "stream_since/2" do
    setup [:record_started_at, :dispatch_events]

    test "return events for the given aggregate ID since the given timestamp",
         %{
           aggregate_ids: aggregate_ids,
           started_at: started_at
         } do
      EventStore.transaction(fn ->
        events = EventStore.stream_since(aggregate_ids.alice, started_at)

        assert Enum.all?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate IDs since the given timestamp", %{
      aggregate_ids: aggregate_ids,
      started_at: started_at
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream_since([aggregate_ids.alice, aggregate_ids.bob], started_at)

        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given event name since the given timestamp", %{
      started_at: started_at
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream_since(UserCreated, started_at)

        assert Enum.all?(events, &is_struct(&1, UserCreated))
        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given event names since the given timestamp", %{
      started_at: started_at
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream_since([UserCreated, UserUpdated], started_at)

        assert Enum.any?(events, &is_struct(&1, UserCreated))
        assert Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "raises an error when an invalid aggregate ID is given" do
      assert_raise FunctionClauseError, fn ->
        EventStore.stream_since("DefinitelyNotAnUUID", NaiveDateTime.utc_now())
      end
    end
  end

  describe "stream_since/3" do
    setup [:record_started_at, :dispatch_events]

    test "returns events for the given aggregate ID and event name since the given timestamp", %{
      aggregate_ids: aggregate_ids,
      started_at: started_at
    } do
      EventStore.transaction(fn ->
        events = EventStore.stream_since(aggregate_ids.alice, UserCreated, started_at)

        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.all?(events, &(&1.aggregate_id == aggregate_ids.alice))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.all?(events, &is_struct(&1, UserCreated))
        refute Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate IDs and event name since the given timestamp", %{
      aggregate_ids: aggregate_ids,
      started_at: started_at
    } do
      EventStore.transaction(fn ->
        events =
          EventStore.stream_since(
            [aggregate_ids.alice, aggregate_ids.bob],
            UserCreated,
            started_at
          )

        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        # Alice was created a long time ago
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.all?(events, &is_struct(&1, UserCreated))
        refute Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate ID and event names since the given timestamp", %{
      aggregate_ids: aggregate_ids,
      started_at: started_at
    } do
      EventStore.transaction(fn ->
        events =
          EventStore.stream_since(aggregate_ids.alice, [UserCreated, UserUpdated], started_at)

        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.all?(events, &(&1.aggregate_id == aggregate_ids.alice))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        # Alice was created a long time ago
        refute Enum.any?(events, &is_struct(&1, UserCreated))
        assert Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
    end

    test "returns events for the given aggregate IDs and event names since the given timestamp",
         %{
           aggregate_ids: aggregate_ids,
           started_at: started_at
         } do
      EventStore.transaction(fn ->
        events =
          EventStore.stream_since(
            [aggregate_ids.alice, aggregate_ids.bob],
            [UserCreated, UserUpdated],
            started_at
          )

        assert Enum.all?(events, &(NaiveDateTime.compare(&1.inserted_at, started_at) == :gt))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.alice))
        assert Enum.any?(events, &(&1.aggregate_id == aggregate_ids.bob))
        refute Enum.any?(events, &(&1.aggregate_id == aggregate_ids.charlie))
        assert Enum.any?(events, &is_struct(&1, UserCreated))
        assert Enum.any?(events, &is_struct(&1, UserUpdated))
        refute Enum.any?(events, &is_struct(&1, UserDestroyed))
        assert Enum.all?(events, &is_binary(&1.id))
      end)
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

  defp start_dependencies(%{adapter: EventStore.Adapter.InMemory}) do
    start_supervised!(EventStore.PubSub.Registry)
    start_supervised!(EventStore.Adapter.InMemory)

    :ok
  end

  defp start_dependencies(%{adapter: EventStore.Adapter.Postgres}) do
    start_supervised!(EventStore.PubSub.Registry)
    start_supervised!(EventStore.Adapter.Postgres.Repo)

    Ecto.Adapters.SQL.Sandbox.mode(EventStore.Adapter.Postgres.Repo, :manual)

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EventStore.Adapter.Postgres.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    :ok
  end
end
