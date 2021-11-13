defmodule EventStore.AcknowledgementError do
  defexception [:message]

  @impl true
  def exception({pid, event}) do
    message = "Dispatched event #{inspect(event)} was never acknowledged by #{inspect(pid)}"
    %__MODULE__{message: message}
  end
end
