# Sends a real test notification to your phone.
#
#     export TELEGRAM_BOT_TOKEN="123456789:AA-your-bot-token-here"
#     export TELEGRAM_CHAT_ID="your-chat-id"
#     mix run scripts/send_test_message.exs [info|warning|critical]
#
# PUSHOVER_TOKEN / PUSHOVER_USER are optional. When set, :warning and
# :critical also go to Pushover (critical = emergency priority, which repeats
# until acknowledged). Exits non-zero if any channel fails.

defmodule Notifier.SendTestMessage do
  @env %{
    telegram_bot_token: "TELEGRAM_BOT_TOKEN",
    telegram_chat_id: "TELEGRAM_CHAT_ID",
    pushover_token: "PUSHOVER_TOKEN",
    pushover_user: "PUSHOVER_USER"
  }

  @levels %{"info" => :info, "warning" => :warning, "critical" => :critical}

  def run(argv) do
    level = parse_level(argv)

    missing =
      for var <- ["TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID"], blank?(System.get_env(var)), do: var

    if missing != [] do
      abort("Missing environment variable(s): #{Enum.join(missing, ", ")}")
    end

    for {key, var} <- @env, value = System.get_env(var), not blank?(value) do
      Application.put_env(:notifier, key, value)
    end

    host = :inet.gethostname() |> elem(1) |> to_string()
    time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    IO.puts("Sending #{level} test notification...")

    {:ok, results} =
      Notifier.notify(
        level,
        "Notifier test (#{level})",
        "If you can read this, Notifier is working.\nSent from #{host} at #{time}.",
        mode: :sync,
        url: "https://github.com/semdinsp/elixir-notifier"
      )

    if results == [], do: fail("No channels were configured for #{level}; nothing sent.")

    for {channel, result} <- results do
      IO.puts("  #{channel}: #{if result == :ok, do: "ok", else: inspect(result)}")
    end

    if Enum.all?(results, fn {_, result} -> result == :ok end) do
      IO.puts("Done. Check your phone.")
    else
      fail("One or more channels failed (see above).")
    end
  end

  defp parse_level([]), do: :info

  defp parse_level([arg | _]) do
    case Map.fetch(@levels, arg) do
      {:ok, level} -> level
      :error -> abort("Unknown level #{inspect(arg)}. Use info, warning or critical.")
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp fail(message) do
    IO.puts(:stderr, "error: " <> message)
    System.halt(1)
  end

  defp abort(message) do
    IO.puts(:stderr, "error: " <> message)

    IO.puts(:stderr, """

    Usage:
      export TELEGRAM_BOT_TOKEN="..."
      export TELEGRAM_CHAT_ID="..."
      mix run scripts/send_test_message.exs [info|warning|critical]
    """)

    System.halt(1)
  end
end

Notifier.SendTestMessage.run(System.argv())
