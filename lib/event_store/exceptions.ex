defmodule EventStore.AcknowledgementError do
  defexception [:message]

  @impl true
  def exception(event) do
    message = "Dispatched event #{inspect(event)} was never acknowledged"
    %__MODULE__{message: message}
  end
end
