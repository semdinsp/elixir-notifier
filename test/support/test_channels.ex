defmodule Notifier.TestChannel do
  @moduledoc false
  @behaviour Notifier.Channel

  @impl true
  def deliver(message) do
    send(:notifier_test_channel_sink, {:test_channel, message})
    :ok
  end
end

defmodule Notifier.RaisingChannel do
  @moduledoc false
  @behaviour Notifier.Channel

  @impl true
  def deliver(_message), do: raise("boom")
end
