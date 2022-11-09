defmodule EventStore.PubSub.RegistryTest do
  use ExUnit.Case, async: false

  alias EventStore.PubSub.Registry
  alias EventStore.{UserCreated, UserUpdated}

  import SpawnSubscriber

  @user_created %UserCreated{
    aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
    payload: %{"some" => "data"}
  }

  test "subscribe/1" do
    assert Registry.subscribe(UserCreated)
  end

  test "broadcast/1" do
    pid1 = spawn_subscriber(Registry, UserCreated, self())
    pid2 = spawn_subscriber(Registry, UserUpdated, self())

    assert is_list(Registry.broadcast(@user_created))

    assert_receive {:received, @user_created, ^pid1}
    refute_receive {:received, @user_created, ^pid2}
  end
end
