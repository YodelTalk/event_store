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
         [name: EventStore.PubSub.Postgres.Notifications]}
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
      | aggregate_version: user_created.aggregate_version,
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
end
