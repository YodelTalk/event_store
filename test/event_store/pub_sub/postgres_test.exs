defmodule EventStore.PubSub.PostgresTest do
  use ExUnit.Case, async: false

  alias EventStore.PubSub.Postgres
  alias EventStore.{UserCreated, UserUpdated}

  import SpawnSubscriber

  @user_created %UserCreated{
    aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
    payload: %{"some" => "data"}
  }

  setup do
    repo_config = EventStore.Adapters.Postgres.Repo.config()

    for app <- [
          EventStore.Adapters.Postgres.Repo,
          {Postgrex.Notifications,
           repo_config ++ [name: EventStore.PubSub.Postgres.Notifications]},
          EventStore.PubSub.Postgres
        ],
        do: start_supervised(app)

    :ok
  end

  test "subscribe/1" do
    assert Postgres.subscribe(UserCreated)
  end

  test "broadcast/1" do
    pid1 = spawn_subscriber(Postgres, UserCreated, self())
    pid2 = spawn_subscriber(Postgres, UserUpdated, self())

    user_created = EventStore.insert_with_adapter(@user_created, EventStore.Adapters.Postgres)
    assert is_list(Postgres.broadcast(user_created))

    user_created = %{
      @user_created
      | aggregate_version: user_created.aggregate_version,
        inserted_at: user_created.inserted_at
    }

    assert_receive {:received, ^user_created, ^pid1}
    refute_receive {:received, ^user_created, ^pid2}
  end
end
