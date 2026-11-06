defmodule Notifier.HTTP do
  @moduledoc false

  # Shared Req plumbing for HTTP channels.
  #
  # Req's built-in retry is disabled by default: Oban owns retries in `:oban`
  # mode, and `:sync`/`:direct` callers shouldn't block on hidden retry loops.
  # Host apps (and tests) can override anything via `config :notifier, req_options: [...]`.

  @default_options [retry: false, receive_timeout: 15_000]

  @spec post(String.t(), keyword()) :: Notifier.Channel.result()
  def post(url, request_options) do
    options =
      @default_options
      |> Keyword.merge(Application.get_env(:notifier, :req_options, []))
      |> Keyword.merge(request_options)

    url
    |> Req.post(options)
    |> classify()
  end

  @doc false
  def classify({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  def classify({:ok, %Req.Response{status: status, body: body}})
      when status == 429 or status >= 500,
      do: {:error, {:http_error, status, body}}

  def classify({:ok, %Req.Response{status: status, body: body}}),
    do: {:cancel, {:http_error, status, body}}

  def classify({:error, exception}), do: {:error, exception}
end
