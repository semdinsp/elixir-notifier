defmodule Notifier.Worker do
  @moduledoc """
  Oban worker that delivers one notification to one channel.

  Jobs are inserted by `Notifier.notify/4` (in `mode: :oban`) into the host
  application's Oban instance. The host must run a `:notifications` queue (or
  whatever queue is passed via the `:queue` option).

  Return values follow Oban semantics: `{:error, reason}` for transient
  failures (retried, up to 5 attempts) and `{:cancel, reason}` for permanent
  ones such as a bad token or unknown chat.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 5

  @levels %{"info" => :info, "warning" => :warning, "critical" => :critical}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel" => channel} = args}) do
    with {:ok, name, module} <- Notifier.lookup_channel(channel),
         {:ok, message} <- message(args) do
      Notifier.Delivery.deliver(name, module, message)
    end
  end

  def perform(%Oban.Job{args: args}), do: {:cancel, {:invalid_args, args}}

  defp message(%{"level" => level, "title" => title} = args) do
    case Map.fetch(@levels, level) do
      {:ok, level} ->
        {:ok, %{level: level, title: title, body: Map.get(args, "body", ""), url: args["url"]}}

      :error ->
        {:cancel, {:invalid_level, level}}
    end
  end

  defp message(args), do: {:cancel, {:invalid_args, args}}
end
