defmodule Notifier.Channels.Telegram do
  @moduledoc """
  Delivers messages through the Telegram Bot API (`sendMessage`).

  Messages are sent with `parse_mode: "HTML"`. All user-supplied text is
  HTML-escaped, so titles and bodies can contain `<`, `>` and `&` safely.

  ## Configuration

      config :notifier,
        telegram_bot_token: "123456:ABC-placeholder",
        telegram_chat_id: "-1001234567890"
  """

  @behaviour Notifier.Channel

  @api_base "https://api.telegram.org"
  # Telegram's hard limit is 4096 characters after entity parsing; leave room
  # for the title, emoji and link.
  @max_body 3500

  @emoji %{info: "ℹ️", warning: "⚠️", critical: "🚨"}

  @impl true
  def configured? do
    present?(token()) and present?(chat_id())
  end

  @impl true
  def deliver(message) do
    if configured?() do
      Notifier.HTTP.post("#{@api_base}/bot#{token()}/sendMessage",
        json: %{
          chat_id: chat_id(),
          text: format(message),
          parse_mode: "HTML",
          link_preview_options: %{is_disabled: true}
        }
      )
    else
      {:cancel, :not_configured}
    end
  end

  @doc """
  Builds the HTML text sent to Telegram.

      iex> Notifier.Channels.Telegram.format(%{level: :warning, title: "a < b", body: "x & y", url: nil})
      "⚠️ <b>a &lt; b</b>\\n\\nx &amp; y"
  """
  @spec format(Notifier.Channel.message()) :: String.t()
  def format(%{level: level, title: title} = message) do
    body = message |> Map.get(:body, "") |> to_string() |> String.slice(0, @max_body)

    [
      "#{Map.fetch!(@emoji, level)} <b>#{escape(title)}</b>",
      if(body != "", do: escape(body)),
      case Map.get(message, :url) do
        url when is_binary(url) and url != "" ->
          ~s(<a href="#{escape_attr(url)}">#{escape(url)}</a>)

        _ ->
          nil
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc """
  Escapes the three characters Telegram's HTML parse mode requires.

      iex> Notifier.Channels.Telegram.escape("<b>Tom & Jerry</b>")
      "&lt;b&gt;Tom &amp; Jerry&lt;/b&gt;"
  """
  @spec escape(String.t()) :: String.t()
  def escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(text), do: text |> escape() |> String.replace(~s("), "&quot;")

  defp token, do: Application.get_env(:notifier, :telegram_bot_token)
  defp chat_id, do: Application.get_env(:notifier, :telegram_chat_id)

  defp present?(value), do: value not in [nil, ""]
end
