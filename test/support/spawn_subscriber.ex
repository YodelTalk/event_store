defmodule SpawnSubscriber do
  import ExUnit.Assertions

  def spawn_subscriber(pub_sub, name, parent) do
    pid =
      spawn(fn ->
        pub_sub.subscribe(name)
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
