defmodule EventStore.PubSub.MultiTest do
  use ExUnit.Case
  import SpawnSubscriber

  alias EventStore.PubSub.{Multi, Postgres, Registry}
  alias EventStore.{UserCreated, UserUpdated}

  @user_created %UserCreated{
    aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
    payload: %{"some" => "data"}
  }

  setup_all do
    start_supervised!(EventStore.Adapters.Postgres.Repo)

    start_supervised!(
      {Postgrex.Notifications,
       EventStore.Adapters.Postgres.Repo.config() ++
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
    assert Multi.subscribe(UserCreated)
  end

  test "broadcast/1" do
    pid1 = spawn_subscriber(Postgres, UserCreated, self())
    pid2 = spawn_subscriber(Registry, UserCreated, self())
    pid3 = spawn_subscriber(Postgres, UserUpdated, self())

    user_created = EventStore.insert_with_adapter(@user_created, EventStore.Adapters.Postgres)
    assert is_list(Multi.broadcast(user_created))

    user_created = %{
      @user_created
      | aggregate_version: user_created.aggregate_version,
        from: self(),
        id: user_created.id,
        inserted_at: user_created.inserted_at
    }

    assert_receive {:received, ^user_created, ^pid1}
    assert_receive {:received, ^user_created, ^pid2}
    refute_receive {:received, ^user_created, ^pid3}
  end
end
