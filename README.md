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

## License

[MIT License](LICENSE)
