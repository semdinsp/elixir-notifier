defmodule Notifier.Channels.Pushover do
  @moduledoc """
  Delivers messages through the Pushover Messages API.

  Levels map to Pushover priorities:

  | level       | priority             |
  |-------------|----------------------|
  | `:info`     | `-1` (quiet)         |
  | `:warning`  | `0` (normal)         |
  | `:critical` | `2` (emergency)      |

  Emergency priority repeats the alert every `retry` seconds until it is
  acknowledged or `expire` seconds pass. Pushover requires `retry >= 30` and
  `expire <= 10800`; values outside those bounds are clamped.

  ## Configuration

      config :notifier,
        pushover_token: "app-token-placeholder",
        pushover_user: "user-key-placeholder",
        # optional, emergency (critical) only:
        pushover_retry: 60,
        pushover_expire: 3600
  """

  @behaviour Notifier.Channel

  @endpoint "https://api.pushover.net/1/messages.json"
  @max_title 250
  @max_message 1024

  @priorities %{info: -1, warning: 0, critical: 2}

  @impl true
  def configured? do
    present?(Application.get_env(:notifier, :pushover_token)) and
      present?(Application.get_env(:notifier, :pushover_user))
  end

  @impl true
  def deliver(message) do
    if configured?() do
      Notifier.HTTP.post(@endpoint, form: params(message))
    else
      {:cancel, :not_configured}
    end
  end

  @doc "Builds the form params sent to Pushover (credentials included)."
  @spec params(Notifier.Channel.message()) :: keyword()
  def params(%{level: level, title: title} = message) do
    priority = Map.fetch!(@priorities, level)
    body = message |> Map.get(:body, "") |> to_string()

    [
      token: Application.fetch_env!(:notifier, :pushover_token),
      user: Application.fetch_env!(:notifier, :pushover_user),
      title: String.slice(to_string(title), 0, @max_title),
      # `message` is required by Pushover, so fall back to the title.
      message: String.slice(if(body == "", do: to_string(title), else: body), 0, @max_message),
      priority: priority
    ]
    |> put_url(Map.get(message, :url))
    |> put_emergency(priority)
  end

  defp put_url(params, url) when is_binary(url) and url != "", do: params ++ [url: url]
  defp put_url(params, _), do: params

  defp put_emergency(params, 2) do
    retry = Application.get_env(:notifier, :pushover_retry, 60)
    expire = Application.get_env(:notifier, :pushover_expire, 3600)
    params ++ [retry: max(retry, 30), expire: min(expire, 10_800)]
  end

  defp put_emergency(params, _), do: params

  defp present?(value), do: value not in [nil, ""]
end
