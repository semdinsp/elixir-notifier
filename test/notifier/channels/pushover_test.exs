defmodule Notifier.Channels.PushoverTest do
  use Notifier.Case, async: false

  alias Notifier.Channels.Pushover

  @msg %{level: :warning, title: "Disk", body: "90% full", url: nil}

  test "success posts form params" do
    stub_http(&ok_responses/2)

    assert :ok = Pushover.deliver(%{@msg | url: "https://example.com"})

    assert_received {:request, :pushover, "/1/messages.json", params}

    assert params == %{
             "token" => "TEST-PUSHOVER-TOKEN",
             "user" => "TEST-PUSHOVER-USER",
             "title" => "Disk",
             "message" => "90% full",
             "priority" => "0",
             "url" => "https://example.com"
           }
  end

  test "critical sends priority=2 with retry and expire defaults" do
    stub_http(&ok_responses/2)

    assert :ok = Pushover.deliver(%{@msg | level: :critical})

    assert_received {:request, :pushover, _, params}
    assert params["priority"] == "2"
    assert params["retry"] == "60"
    assert params["expire"] == "3600"
  end

  test "retry/expire are configurable and clamped to Pushover's limits" do
    Application.put_env(:notifier, :pushover_retry, 5)
    Application.put_env(:notifier, :pushover_expire, 99_999)

    params = Pushover.params(%{@msg | level: :critical})
    assert params[:retry] == 30
    assert params[:expire] == 10_800
  end

  test "info is priority -1 and non-critical levels omit retry/expire" do
    params = Pushover.params(%{@msg | level: :info})
    assert params[:priority] == -1
    refute Keyword.has_key?(params, :retry)
    refute Keyword.has_key?(params, :expire)
  end

  test "empty body falls back to the title (message is required)" do
    assert Pushover.params(%{@msg | body: ""})[:message] == "Disk"
  end

  test "4xx (bad token) cancels" do
    stub_http(fn :pushover, _ ->
      {400, %{"status" => 0, "errors" => ["application token is invalid"]}}
    end)

    assert {:cancel, {:http_error, 400, _}} = Pushover.deliver(@msg)
  end

  test "5xx returns a retryable error" do
    stub_http(fn :pushover, _ -> {503, %{}} end)
    assert {:error, {:http_error, 503, _}} = Pushover.deliver(@msg)
  end

  test "missing config cancels" do
    Application.delete_env(:notifier, :pushover_user)
    refute Pushover.configured?()
    assert {:cancel, :not_configured} = Pushover.deliver(@msg)
  end
end
