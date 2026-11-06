defmodule Notifier.Case do
  @moduledoc false
  use ExUnit.CaseTemplate

  @placeholder_config [
    telegram_bot_token: "TEST-TELEGRAM-TOKEN",
    telegram_chat_id: "TEST-CHAT-ID",
    pushover_token: "TEST-PUSHOVER-TOKEN",
    pushover_user: "TEST-PUSHOVER-USER",
    req_options: [plug: {Req.Test, Notifier.HTTPStub}]
  ]

  @managed_keys @placeholder_config ++
                  [
                    oban_name: nil,
                    routes: nil,
                    mode: nil,
                    channels: nil,
                    pushover_retry: nil,
                    pushover_expire: nil
                  ]

  using do
    quote do
      import Notifier.Case
      import ExUnit.CaptureLog
    end
  end

  setup do
    previous = Map.new(@managed_keys, fn {k, _} -> {k, Application.fetch_env(:notifier, k)} end)
    Enum.each(@managed_keys, fn {k, _} -> Application.delete_env(:notifier, k) end)
    Enum.each(@placeholder_config, fn {k, v} -> Application.put_env(:notifier, k, v) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {k, {:ok, v}} -> Application.put_env(:notifier, k, v)
        {k, :error} -> Application.delete_env(:notifier, k)
      end)
    end)

    :ok
  end

  @doc """
  Installs a Req.Test stub that routes by host, records each request to the
  test process, and responds with `responder.(channel, conn)`.
  """
  def stub_http(responder) do
    test_pid = self()

    Req.Test.stub(Notifier.HTTPStub, fn conn ->
      channel =
        case conn.host do
          "api.telegram.org" -> :telegram
          "api.pushover.net" -> :pushover
        end

      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, channel, conn.request_path, decode(conn, raw)})

      case responder.(channel, conn) do
        {status, body} -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
      end
    end)
  end

  def ok_responses(:telegram, _conn), do: {200, %{"ok" => true}}
  def ok_responses(:pushover, _conn), do: {200, %{"status" => 1}}

  defp decode(conn, raw) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      ["application/json" <> _] -> Jason.decode!(raw)
      ["application/x-www-form-urlencoded" <> _] -> URI.decode_query(raw)
      _ -> raw
    end
  end
end
