defmodule Notifier.Channels.TelegramTest do
  use Notifier.Case, async: false

  alias Notifier.Channels.Telegram

  doctest Telegram

  @msg %{level: :warning, title: "Disk", body: "90% full", url: nil}

  describe "deliver/1" do
    test "success posts HTML sendMessage to the bot URL" do
      stub_http(&ok_responses/2)

      assert :ok = Telegram.deliver(@msg)

      assert_received {:request, :telegram, "/botTEST-TELEGRAM-TOKEN/sendMessage", body}
      assert body["chat_id"] == "TEST-CHAT-ID"
      assert body["parse_mode"] == "HTML"
      assert body["text"] == "⚠️ <b>Disk</b>\n\n90% full"
    end

    test "4xx (e.g. chat not found) cancels" do
      stub_http(fn :telegram, _ -> {400, %{"ok" => false, "description" => "chat not found"}} end)
      assert {:cancel, {:http_error, 400, _}} = Telegram.deliver(@msg)
    end

    test "401 bad token cancels" do
      stub_http(fn :telegram, _ -> {401, %{"ok" => false}} end)
      assert {:cancel, {:http_error, 401, _}} = Telegram.deliver(@msg)
    end

    test "5xx returns a retryable error" do
      stub_http(fn :telegram, _ -> {502, %{"ok" => false}} end)
      assert {:error, {:http_error, 502, _}} = Telegram.deliver(@msg)
    end

    test "429 returns a retryable error" do
      stub_http(fn :telegram, _ -> {429, %{"ok" => false}} end)
      assert {:error, {:http_error, 429, _}} = Telegram.deliver(@msg)
    end

    test "transport errors are retryable" do
      Req.Test.stub(Notifier.HTTPStub, &Req.Test.transport_error(&1, :timeout))
      assert {:error, %Req.TransportError{reason: :timeout}} = Telegram.deliver(@msg)
    end

    test "missing config cancels without making a request" do
      Application.delete_env(:notifier, :telegram_bot_token)
      refute Telegram.configured?()
      assert {:cancel, :not_configured} = Telegram.deliver(@msg)
    end
  end

  describe "format/1 and HTML escaping" do
    test "escapes <, > and & in title and body" do
      text =
        Telegram.format(%{level: :info, title: "<script>&", body: "a<b>c & d</b>", url: nil})

      assert text == "ℹ️ <b>&lt;script&gt;&amp;</b>\n\na&lt;b&gt;c &amp; d&lt;/b&gt;"
    end

    test "does not double-escape" do
      assert Telegram.escape("&amp;") == "&amp;amp;"
    end

    test "uses an emoji per level" do
      assert Telegram.format(%{@msg | level: :info}) =~ ~r/^ℹ️ /
      assert Telegram.format(%{@msg | level: :warning}) =~ ~r/^⚠️ /
      assert Telegram.format(%{@msg | level: :critical}) =~ ~r/^🚨 /
    end

    test "includes an escaped link when url is given" do
      text = Telegram.format(%{@msg | url: ~s(https://x.test/?a=1&b="2")})

      assert text =~
               ~s(<a href="https://x.test/?a=1&amp;b=&quot;2&quot;">https://x.test/?a=1&amp;b="2"</a>)
    end

    test "omits empty body" do
      assert Telegram.format(%{@msg | body: ""}) == "⚠️ <b>Disk</b>"
    end
  end
end
