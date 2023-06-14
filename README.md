# event_store [![CI](https://github.com/YodelTalk/event_store/actions/workflows/test.yml/badge.svg)](https://github.com/YodelTalk/event_store/actions/workflows/test.yml)

A central store for managing and dispatching domain events.

ChatGPT's perspective why event storing/sourcing rocks:

> An event-sourced app written in Elixir leverages the language's inherent concurrency and fault-tolerance features to handle high-throughput event streams, while projections allow for flexible and efficient querying of this event data, enabling robust and scalable systems.
>

This library represents our take on an event store. Used in production for multiple apps in the wild.

## Installation

```elixir
def deps do
  [
    {:event_store, github: "YodelTalk/event_store"}
  ]
end
```

## Troubleshooting common errors

* When encountering the `(RuntimeError) cannot reduce stream outside of transaction` error, even though `EventStore.stream/2` is correctly placed inside a `Repo.transaction/1` call, it is important to verify that the correct `Ecto.Repo` is being referenced:

  The following example will lead to the aforementioned error:

  ```elixir
  alias MyApp.Repo

  last_update = Repo.one(from(model in Model, select: max(model.inserted_at))) ||
    NaiveDateTime.new!(2000, 1, 1, 0, 0, 0)

  Repo.transaction(fn ->
    EventStore.stream(MyApp.SomeEvent, last_update)
  end)
  ```

  Contrastingly, this example makes use of the appropriate `Ecto.Repo` and will not result in an error:

  ```elixir
  alias MyApp.Repo
  alias EventStore.Adapter.Postgres.Repo, as: EventStoreRepo

  last_update = Repo.one(from(model in Model, select: max(model.inserted_at))) ||
    NaiveDateTime.new!(2000, 1, 1, 0, 0, 0)

  EventStoreRepo.transaction(fn ->
    EventStore.stream(MyApp.SomeEvent, last_update)
  end)
  ```

## License

[MIT License](LICENSE)
