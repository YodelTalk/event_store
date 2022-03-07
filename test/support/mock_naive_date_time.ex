defmodule MockNaiveDateTime do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end

  def utc_now() do
    Agent.get(__MODULE__, fn
      nil -> NaiveDateTime.utc_now()
      datetime -> datetime
    end)
  end

  def set(datetime) do
    Agent.update(__MODULE__, fn _ -> datetime end)
  end

  def unset() do
    set(nil)
  end
end
