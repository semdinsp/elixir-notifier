defmodule Notifier.Channels.TwilioTest do
  use Notifier.Case, async: false

  test "stub returns {:cancel, :not_implemented}" do
    assert {:cancel, :not_implemented} =
             Notifier.Channels.Twilio.deliver(%{level: :info, title: "t", body: "b"})
  end
end
