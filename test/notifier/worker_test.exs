defmodule Notifier.WorkerTest do
  use Notifier.Case, async: false
  # perform_job/3 builds and validates the job in-process; it never touches
  # the repo. The Isolated notifier avoids the default Postgres notifier.
  use Oban.Testing,
    repo: Notifier.Test.FakeRepo,
    notifier: Oban.Notifiers.Isolated,
    testing: :manual

  alias Notifier.Worker

  @args %{"channel" => "telegram", "level" => "warning", "title" => "t", "body" => "b"}

  defp perform(args), do: perform_job(Worker, args)

  test "delivers via the channel named in args" do
    stub_http(&ok_responses/2)
    assert :ok = perform(@args)
    assert_received {:request, :telegram, _, %{"text" => "⚠️ <b>t</b>\n\nb"}}
  end

  test "passes url through" do
    stub_http(&ok_responses/2)
    assert :ok = perform(Map.put(@args, "url", "https://example.com"))
    assert_received {:request, :telegram, _, %{"text" => text}}
    assert text =~ ~s(<a href="https://example.com">)
  end

  test "dispatches critical to pushover with emergency priority" do
    stub_http(&ok_responses/2)
    assert :ok = perform(%{@args | "channel" => "pushover", "level" => "critical"})

    assert_received {:request, :pushover, _,
                     %{"priority" => "2", "retry" => "60", "expire" => "3600"}}
  end

  test "4xx -> {:cancel, _}" do
    stub_http(fn _, _ -> {400, %{"ok" => false}} end)
    assert {:cancel, {:http_error, 400, _}} = perform(@args)
  end

  test "5xx -> {:error, _} (retried)" do
    stub_http(fn _, _ -> {500, %{"ok" => false}} end)
    assert {:error, {:http_error, 500, _}} = perform(@args)
  end

  test "channel unconfigured at perform time -> {:cancel, :not_configured}" do
    Application.delete_env(:notifier, :telegram_bot_token)
    assert {:cancel, :not_configured} = perform(@args)
  end

  test "unknown channel or level cancels" do
    assert {:cancel, {:unknown_channel, "fax"}} = perform(%{@args | "channel" => "fax"})
    assert {:cancel, {:invalid_level, "debug"}} = perform(%{@args | "level" => "debug"})
  end

  test "worker defaults" do
    job = Worker.new(@args)
    assert job.changes.queue == "notifications"
    assert job.changes.max_attempts == 5
  end
end
