defmodule Notifier do
  @moduledoc """
  Send alerts to your phone from any Elixir app.

      Notifier.notify(:critical, "Payments down", "Stripe webhook failing", url: "https://example.com/admin")

  Each level is routed to a list of channels (see "Routing" below). Delivery
  happens in one of three modes:

    * `:oban` (default) - insert one `Notifier.Worker` job per channel into the
      host app's Oban instance. Retries and uniqueness are handled by Oban.
    * `:direct` - fire-and-forget delivery under `Notifier.TaskSupervisor`.
      No Oban, no retries.
    * `:sync` - deliver inline and return each channel's result.

  ## Configuration

  All configuration lives in the host application's `:notifier` env, usually
  in `config/runtime.exs`:

      config :notifier,
        telegram_bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
        telegram_chat_id: System.get_env("TELEGRAM_CHAT_ID"),
        pushover_token: System.get_env("PUSHOVER_TOKEN"),
        pushover_user: System.get_env("PUSHOVER_USER")

  Optional keys:

    * `:mode` - default delivery mode (`:oban`)
    * `:oban_name` - name of the host's Oban instance (`Oban`)
    * `:routes` - map of level => channel list, merged over the defaults
    * `:channels` - map of extra channel name => module implementing `Notifier.Channel`
    * `:req_options` - extra options merged into every `Req` request
    * `:pushover_retry` / `:pushover_expire` - emergency priority settings (60 / 3600)

  ## Routing

  Default routes:

      %{
        info: [:telegram],
        warning: [:telegram, :pushover],
        critical: [:telegram, :pushover]  # Pushover at emergency priority
      }

  Channels in a route that aren't configured (missing credentials) are skipped
  with a logged warning.
  """

  require Logger

  @type level :: :info | :warning | :critical
  @type mode :: :oban | :direct | :sync

  @levels [:info, :warning, :critical]

  @default_routes %{
    info: [:telegram],
    warning: [:telegram, :pushover],
    critical: [:telegram, :pushover]
  }

  @builtin_channels %{
    telegram: Notifier.Channels.Telegram,
    pushover: Notifier.Channels.Pushover,
    twilio: Notifier.Channels.Twilio
  }

  @default_unique [period: 300, fields: [:args]]

  @doc """
  Sends a notification.

  ## Options

    * `:url` - a link included in the message
    * `:mode` - `:oban`, `:direct` or `:sync` (defaults to `config :notifier, mode:`, then `:oban`)
    * `:channels` - override the configured route for this call, e.g. `[:pushover]`
    * `:unique` - Oban uniqueness, default `#{inspect(@default_unique)}`; `false` disables
    * `:queue` - Oban queue (default `:notifications`)
    * `:priority` - Oban job priority (0-9)

  ## Return values

    * `:oban` - `{:ok, [%Oban.Job{}]}` or `{:error, reason}`
    * `:direct` - `{:ok, [pid]}`
    * `:sync` - `{:ok, [{channel, :ok | {:error, term} | {:cancel, term}}]}`

  Skipped (unconfigured) channels are omitted from the results.
  """
  @spec notify(level(), String.t(), String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def notify(level, title, body, opts \\ []) when level in @levels and is_list(opts) do
    channels = resolve_channels(level, opts)
    message = message(level, title, body, opts)

    case Keyword.get(opts, :mode, config(:mode, :oban)) do
      :oban ->
        enqueue(level, title, body, channels, opts)

      :direct ->
        deliver_direct(channels, message)

      :sync ->
        {:ok, Enum.map(channels, fn {name, mod} -> {name, deliver(name, mod, message)} end)}

      other ->
        raise ArgumentError, "unknown Notifier mode: #{inspect(other)}"
    end
  end

  @doc """
  Builds the `Oban.Job` changesets that `notify/4` would insert in `:oban` mode,
  without inserting them.

  Useful for inserting notifications atomically alongside other work, e.g.
  with `Oban.insert/3` inside an `Ecto.Multi`. Accepts the same options as
  `notify/4` (`:mode` is ignored).
  """
  @spec new_jobs(level(), String.t(), String.t(), keyword()) :: [Ecto.Changeset.t()]
  def new_jobs(level, title, body, opts \\ []) when level in @levels do
    build_jobs(level, title, body, resolve_channels(level, opts), opts)
  end

  @doc "Returns the effective level => channels routing table."
  @spec routes() :: %{level() => [atom()]}
  def routes do
    Map.merge(@default_routes, Map.new(config(:routes, %{})))
  end

  @doc false
  # Maps a channel name (atom or string from job args) to its module without
  # creating atoms from untrusted input.
  @spec lookup_channel(atom() | String.t()) :: {:ok, atom(), module()} | {:cancel, term()}
  def lookup_channel(name) do
    found =
      Enum.find(channels(), fn {key, _mod} ->
        key == name or Atom.to_string(key) == name
      end)

    case found do
      {key, mod} -> {:ok, key, mod}
      nil -> {:cancel, {:unknown_channel, name}}
    end
  end

  # -- internals --------------------------------------------------------------

  defp channels, do: Map.merge(@builtin_channels, Map.new(config(:channels, %{})))

  defp config(key, default), do: Application.get_env(:notifier, key, default)

  defp message(level, title, body, opts) do
    %{level: level, title: to_string(title), body: to_string(body || ""), url: opts[:url]}
  end

  defp deliver(name, mod, message), do: Notifier.Delivery.deliver(name, mod, message)

  defp resolve_channels(level, opts) do
    opts
    |> Keyword.get_lazy(:channels, fn -> Map.get(routes(), level, []) end)
    |> Enum.uniq()
    |> Enum.flat_map(fn name ->
      with {:ok, key, mod} <- lookup_channel(name),
           true <- configured?(mod) do
        [{key, mod}]
      else
        {:cancel, {:unknown_channel, _}} ->
          Logger.warning("[Notifier] unknown channel #{inspect(name)}; skipping")
          []

        false ->
          Logger.warning("[Notifier] channel #{inspect(name)} is not configured; skipping")
          []
      end
    end)
  end

  defp configured?(mod) do
    Code.ensure_loaded(mod)
    not function_exported?(mod, :configured?, 0) or mod.configured?()
  end

  defp enqueue(level, title, body, channels, opts) do
    oban = config(:oban_name, Oban)

    level
    |> build_jobs(title, body, channels, opts)
    |> Enum.reduce_while({:ok, []}, fn changeset, {:ok, jobs} ->
      case Oban.insert(oban, changeset) do
        {:ok, job} -> {:cont, {:ok, [job | jobs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, jobs} -> {:ok, Enum.reverse(jobs)}
      error -> error
    end
  end

  defp build_jobs(level, title, body, channels, opts) do
    job_opts = job_opts(opts)

    for {name, _mod} <- channels do
      %{
        "channel" => Atom.to_string(name),
        "level" => Atom.to_string(level),
        "title" => to_string(title),
        "body" => to_string(body || "")
      }
      |> put_url(opts[:url])
      |> Notifier.Worker.new(job_opts)
    end
  end

  defp put_url(args, url) when is_binary(url) and url != "", do: Map.put(args, "url", url)
  defp put_url(args, _), do: args

  defp job_opts(opts) do
    unique =
      case Keyword.get(opts, :unique, @default_unique) do
        falsy when falsy in [false, nil] -> []
        unique -> [unique: unique]
      end

    unique ++ Keyword.take(opts, [:queue, :priority])
  end

  defp deliver_direct(channels, message) do
    pids =
      for {name, mod} <- channels do
        {:ok, pid} =
          Task.Supervisor.start_child(Notifier.TaskSupervisor, fn ->
            deliver(name, mod, message)
          end)

        pid
      end

    {:ok, pids}
  end
end
