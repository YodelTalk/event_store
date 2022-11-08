defmodule EventStore.PubSub.RegistryTest do
  use ExUnit.Case, async: false

  alias EventStore.PubSub.Registry
  alias EventStore.{UserCreated, UserUpdated}

  @user_created %UserCreated{
    aggregate_id: "01234567-89ab-cdef-0123-456789abcdef",
    payload: %{"some" => "data"}
  }

  test "subscribe/1" do
    assert Registry.subscribe(UserCreated)
  end

  test "broadcast/1" do
    pid1 = spawn_subscriber(UserCreated, self())
    pid2 = spawn_subscriber(UserUpdated, self())

    Registry.broadcast(@user_created)

    assert_receive {:received, @user_created, ^pid1}
    refute_receive {:received, @user_created, ^pid2}
  end

  defp spawn_subscriber(name, parent) do
    pid =
      spawn(fn ->
        Registry.subscribe(name)
        send(parent, {:subscribed, name, self()})

        receive do
          event when is_struct(event, name) ->
            send(parent, {:received, event, self()})
        end
      end)

    assert_receive {:subscribed, ^name, ^pid}

    pid
  end
end
