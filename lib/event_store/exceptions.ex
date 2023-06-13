defmodule EventStore.AcknowledgementError do
  @moduledoc """
  Defines an exception to be raised when a dispatched event is not acknowledged.
  """

  defexception [:message]

  @doc false
  @impl true
  def exception({pid, event}) do
    message = "Dispatched event #{inspect(event)} was never acknowledged by #{inspect(pid)}"
    %__MODULE__{message: message}
  end
end
