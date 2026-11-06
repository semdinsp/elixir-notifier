defmodule Notifier.Channel do
  @moduledoc """
  Behaviour for a notification channel.

  A channel receives a normalized message map:

      %{level: :info | :warning | :critical, title: String.t(), body: String.t(), url: String.t() | nil}

  and returns:

    * `:ok` - delivered
    * `{:error, reason}` - transient failure; Oban will retry the job
    * `{:cancel, reason}` - permanent failure (bad token, unknown chat, ...); do not retry

  Channels read their own credentials from the `:notifier` application env.
  `c:configured?/0` lets `Notifier` skip channels whose credentials are missing
  instead of enqueueing jobs that can never succeed.
  """

  @type level :: :info | :warning | :critical
  @type message :: %{
          required(:level) => level(),
          required(:title) => String.t(),
          required(:body) => String.t(),
          optional(:url) => String.t() | nil
        }
  @type result :: :ok | {:error, term()} | {:cancel, term()}

  @callback deliver(message()) :: result()

  @doc "Returns `true` when the channel has the configuration it needs to deliver."
  @callback configured?() :: boolean()

  @optional_callbacks configured?: 0
end
