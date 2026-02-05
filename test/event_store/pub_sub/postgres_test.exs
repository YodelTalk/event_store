defmodule EventStore.PubSub.PostgresTest do
  use ExUnit.Case
  import SpawnSubscriber

  alias EventStore.PubSub.{Postgres, Registry}
  alias EventStore.{UserCreated, UserUpdated}

  @user_created %UserCreated{
    aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
    payload: %{"some" => "data"}
  }

  @user_updated %UserUpdated{
    aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
    payload: %{"some" => "data"}
  }

  setup_all do
    start_supervised!(EventStore.Adapter.Postgres.Repo)

    start_supervised!(
      {Postgrex.Notifications,
       EventStore.Adapter.Postgres.Repo.config() ++
         [name: EventStore.PubSub.Postgres.Notifications, auto_reconnect: true]}
    )

    :ok
  end

  setup do
    start_supervised!(Registry)
    start_supervised!(Postgres)
    :ok
  end

  test "subscribe/1" do
    assert Postgres.subscribe(UserCreated)
  end

  test "broadcast/1" do
    pid1 = spawn_subscriber(Postgres, UserCreated, self())
    pid2 = spawn_subscriber(Postgres, UserUpdated, self())

    user_created = EventStore.insert_with_adapter(@user_created, EventStore.Adapter.Postgres)
    assert is_list(Postgres.broadcast(user_created))

    user_created = %{
      @user_created
      | id: user_created.id,
        aggregate_version: user_created.aggregate_version,
        inserted_at: user_created.inserted_at
    }

    assert_receive {:received, ^user_created, ^pid1}
    refute_receive {:received, ^user_created, ^pid2}
  end

  test "broadcast/1 does not load unnecessary events" do
    ref = Process.monitor(Postgres)
    Postgres.subscribe(UserCreated)

    user_created = EventStore.insert_with_adapter(@user_updated, EventStore.Adapter.Postgres)

    # If deleted directly from the DB, an Ecto.NoResultsError should crash the
    # PubSub process when accessing the event. However, since the process
    # only subscribed to UserCreated events, this situation should not occur.
    EventStore.Adapter.Postgres.Repo.delete_all(EventStore.Event)

    assert is_list(Postgres.broadcast(user_created))

    # Ensure that the PubSub process did not crash.
    refute_receive {:DOWN, ^ref, _, _, _}
  end

  test "broadcast/1 works after PostgreSQL connection loss" do
    # Set up a subscriber before the connection loss
    pid = spawn_subscriber(Postgres, UserCreated, self())

    # Verify subscription works before connection loss
    user_created_before =
      EventStore.insert_with_adapter(@user_created, EventStore.Adapter.Postgres)

    Postgres.broadcast(user_created_before)

    expected_before = %{
      @user_created
      | id: user_created_before.id,
        aggregate_version: user_created_before.aggregate_version,
        inserted_at: user_created_before.inserted_at
    }

    assert_receive {:received, ^expected_before, ^pid}

    # Terminate the PostgreSQL backend connection to simulate network interruption.
    # This causes Postgrex.Notifications to lose its TCP connection while the
    # Elixir process stays alive. With auto_reconnect: true, it will reconnect
    # and automatically re-issue LISTEN commands for all registered channels.
    terminate_notifications_backend_connection()

    # Wait for reconnection (auto_reconnect is enabled)
    Process.sleep(600)

    # Set up a new subscriber after reconnection
    pid2 = spawn_subscriber(Postgres, UserCreated, self())

    # Insert and broadcast a new event after reconnection
    user_created_after =
      EventStore.insert_with_adapter(
        %UserCreated{
          aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
          payload: %{"after" => "reconnect"}
        },
        EventStore.Adapter.Postgres
      )

    Postgres.broadcast(user_created_after)

    expected_after = %UserCreated{
      id: user_created_after.id,
      aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
      aggregate_version: user_created_after.aggregate_version,
      payload: %{"after" => "reconnect"},
      inserted_at: user_created_after.inserted_at
    }

    # This should be received if the subscription was restored after reconnection
    assert_receive {:received, ^expected_after, ^pid2}, 1000
  end

  test "broadcast/1 works after Postgrex.Notifications process crashes" do
    # Set up a subscriber before the crash
    pid = spawn_subscriber(Postgres, UserCreated, self())

    # Verify subscription works before crash
    user_created_before =
      EventStore.insert_with_adapter(@user_created, EventStore.Adapter.Postgres)

    Postgres.broadcast(user_created_before)

    expected_before = %{
      @user_created
      | id: user_created_before.id,
        aggregate_version: user_created_before.aggregate_version,
        inserted_at: user_created_before.inserted_at
    }

    assert_receive {:received, ^expected_before, ^pid}

    # Kill the Postgrex.Notifications process to simulate a crash.
    # Unlike connection loss, this causes the process to lose all state
    # (including the listener_channels registry). The supervisor restarts it,
    # but without our LISTEN subscription. The PubSub.Postgres GenServer
    # must detect this and re-subscribe.
    notifications_pid = Process.whereis(EventStore.PubSub.Postgres.Notifications)
    Process.exit(notifications_pid, :kill)

    # Wait for the process to restart
    Process.sleep(100)

    # The Notifications process should be back up
    assert Process.whereis(EventStore.PubSub.Postgres.Notifications) != nil

    # Set up a new subscriber after restart
    pid2 = spawn_subscriber(Postgres, UserCreated, self())

    # Insert and broadcast a new event after restart
    user_created_after =
      EventStore.insert_with_adapter(
        %UserCreated{
          aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
          payload: %{"after" => "crash"}
        },
        EventStore.Adapter.Postgres
      )

    Postgres.broadcast(user_created_after)

    expected_after = %UserCreated{
      id: user_created_after.id,
      aggregate_id: "fedcba98-7654-3210-fedc-ba9876543210",
      aggregate_version: user_created_after.aggregate_version,
      payload: %{"after" => "crash"},
      inserted_at: user_created_after.inserted_at
    }

    # This should be received if the subscription was restored after process crash
    assert_receive {:received, ^expected_after, ^pid2}, 1000
  end

  defp terminate_notifications_backend_connection do
    # The Notifications process maintains a dedicated connection that listens
    # for NOTIFY events. We can identify it by looking for a connection that
    # has an active LISTEN command (shown in pg_stat_activity as idle with
    # the LISTEN query).
    #
    # We use a direct connection to avoid using pool connections that might
    # get terminated instead.
    {:ok, %{rows: rows}} =
      Ecto.Adapters.SQL.query(
        EventStore.Adapter.Postgres.Repo,
        """
        SELECT pid FROM pg_stat_activity
        WHERE datname = 'event_store_test'
          AND pid != pg_backend_pid()
          AND query ILIKE '%LISTEN%'
        """
      )

    case rows do
      [[backend_pid] | _] ->
        Ecto.Adapters.SQL.query(
          EventStore.Adapter.Postgres.Repo,
          "SELECT pg_terminate_backend($1)",
          [backend_pid]
        )

      [] ->
        # Fallback: terminate the oldest idle connection (likely Notifications)
        {:ok, %{rows: idle_rows}} =
          Ecto.Adapters.SQL.query(
            EventStore.Adapter.Postgres.Repo,
            """
            SELECT pid FROM pg_stat_activity
            WHERE datname = 'event_store_test'
              AND state = 'idle'
              AND pid != pg_backend_pid()
            ORDER BY backend_start ASC
            LIMIT 1
            """
          )

        case idle_rows do
          [[backend_pid]] ->
            Ecto.Adapters.SQL.query(
              EventStore.Adapter.Postgres.Repo,
              "SELECT pg_terminate_backend($1)",
              [backend_pid]
            )

          [] ->
            :ok
        end
    end
  end
end
