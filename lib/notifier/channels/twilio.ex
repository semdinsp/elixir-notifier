defmodule Notifier.Channels.Twilio do
  @moduledoc """
  Placeholder for future SMS support via Twilio. **Not implemented.**

  It satisfies the `Notifier.Channel` behaviour so it can be referenced in
  routes, but `deliver/1` only logs a warning and returns
  `{:cancel, :not_implemented}` (so Oban won't retry it). It is not part of
  the default routes.
  """

  @behaviour Notifier.Channel

  require Logger

  @impl true
  def configured?, do: true

  @impl true
  def deliver(_message) do
    Logger.warning("[Notifier] Twilio SMS channel is not implemented; message dropped")
    {:cancel, :not_implemented}
  end
end
