defmodule MockNaiveDateTime do
  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(
      fn ->
        Keyword.get(opts, :utc_now, NaiveDateTime.utc_now())
      end,
      name: __MODULE__
    )
  end

  def utc_now(_ \\ nil) do
    Agent.get(__MODULE__, & &1) || NaiveDateTime.utc_now()
  end

  def set(utc_now) do
    Agent.update(__MODULE__, fn _ -> utc_now end)
  end

  def delete() do
    Agent.update(__MODULE__, fn _ -> nil end)
  end
end
