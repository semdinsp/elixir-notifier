defmodule Notifier.Delivery do
  @moduledoc false

  # Single choke point for every delivery attempt, regardless of mode, so
  # telemetry and logging behave identically for :oban, :direct and :sync.

  require Logger

  @spec deliver(atom(), module(), Notifier.Channel.message()) :: Notifier.Channel.result()
  def deliver(name, module, message) do
    metadata = %{channel: name, level: message.level}

    result =
      try do
        :telemetry.span([:notifier, :deliver], metadata, fn ->
          result = module.deliver(message)
          {result, Map.put(metadata, :result, result)}
        end)
      rescue
        exception -> {:error, exception}
      end

    log_failure(name, result)
    result
  end

  defp log_failure(_name, :ok), do: :ok

  defp log_failure(name, {kind, reason}) when kind in [:error, :cancel] do
    Logger.warning("[Notifier] #{name} delivery failed (#{kind}): #{inspect(reason)}")
  end

  defp log_failure(name, other) do
    Logger.warning("[Notifier] #{name} returned unexpected result: #{inspect(other)}")
  end
end
