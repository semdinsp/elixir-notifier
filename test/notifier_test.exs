defmodule NotifierTest do
  use Notifier.Case, async: false

  describe "routing" do
    test "default routes" do
      assert Notifier.routes() == %{
               info: [:telegram],
               warning: [:telegram, :pushover],
               critical: [:telegram, :pushover]
             }
    end

    test "info goes to telegram only" do
      stub_http(&ok_responses/2)
      assert {:ok, [telegram: :ok]} = Notifier.notify(:info, "t", "b", mode: :sync)
    end

    test "critical goes to both telegram and pushover (emergency priority)" do
      stub_http(&ok_responses/2)

      assert {:ok, [telegram: :ok, pushover: :ok]} =
               Notifier.notify(:critical, "DB down", "boom", mode: :sync)

      assert_received {:request, :telegram, _, %{"text" => "🚨 <b>DB down</b>\n\nboom"}}
      assert_received {:request, :pushover, _, %{"priority" => "2"}}
    end

    test "configured routes merge over the defaults" do
      Application.put_env(:notifier, :routes, info: [:pushover])

      assert Notifier.routes().info == [:pushover]
      assert Notifier.routes().critical == [:telegram, :pushover]
    end

    test ":channels option overrides the route for one call" do
      stub_http(&ok_responses/2)

      assert {:ok, [pushover: :ok]} =
               Notifier.notify(:critical, "t", "b", mode: :sync, channels: [:pushover])
    end

    test "custom channels can be registered" do
      Application.put_env(:notifier, :channels, %{test: Notifier.TestChannel})
      Process.register(self(), :notifier_test_channel_sink)

      assert {:ok, [test: :ok]} = Notifier.notify(:info, "t", "b", mode: :sync, channels: [:test])
      assert_received {:test_channel, %{title: "t"}}
    end

    test "unknown channels are skipped with a warning" do
      log =
        capture_log(fn ->
          assert {:ok, []} = Notifier.notify(:info, "t", "b", mode: :sync, channels: [:nope])
        end)

      assert log =~ "unknown channel :nope"
    end

    test "rejects invalid levels" do
      assert_raise FunctionClauseError, fn -> apply(Notifier, :notify, [:debug, "t", "b"]) end
    end
  end

  describe "missing configuration" do
    test "unconfigured channels are skipped and logged, others still deliver" do
      Application.delete_env(:notifier, :pushover_token)
      stub_http(&ok_responses/2)

      log =
        capture_log(fn ->
          assert {:ok, [telegram: :ok]} = Notifier.notify(:warning, "t", "b", mode: :sync)
        end)

      assert log =~ "channel :pushover is not configured; skipping"
      refute_received {:request, :pushover, _, _}
    end

    test "nothing is enqueued for an unconfigured channel" do
      Application.delete_env(:notifier, :telegram_chat_id)

      capture_log(fn ->
        assert [changeset] = Notifier.new_jobs(:critical, "t", "b")
        assert changeset.changes.args["channel"] == "pushover"
      end)
    end
  end

  describe "mode: :oban" do
    test "builds one job per channel with default uniqueness" do
      [tg, po] = Notifier.new_jobs(:critical, "DB down", "boom", url: "https://example.com")

      assert tg.changes.worker == "Notifier.Worker"
      assert tg.changes.queue == "notifications"
      assert tg.changes.max_attempts == 5

      assert tg.changes.args == %{
               "channel" => "telegram",
               "level" => "critical",
               "title" => "DB down",
               "body" => "boom",
               "url" => "https://example.com"
             }

      assert po.changes.args["channel"] == "pushover"
      assert tg.changes.unique.period == 300
      assert tg.changes.unique.fields == [:args]
    end

    test "passes through :queue, :priority and :unique" do
      [job] =
        Notifier.new_jobs(:info, "t", "b", queue: :alerts, priority: 1, unique: [period: 60])

      assert job.changes.queue == "alerts"
      assert job.changes.priority == 1
      assert job.changes.unique.period == 60
    end

    test "unique: false disables uniqueness" do
      [job] = Notifier.new_jobs(:info, "t", "b", unique: false)
      refute Map.has_key?(job.changes, :unique)
    end

    test "inserts into the configured Oban instance" do
      # No Oban instance (and no DB) in this suite, so a failed insert into the
      # configured name proves notify/4 targets :oban_name.
      Application.put_env(:notifier, :oban_name, Notifier.MissingOban)

      assert_raise RuntimeError, ~r/Notifier.MissingOban/, fn ->
        Notifier.notify(:info, "t", "b")
      end
    end

    test "default mode can be configured" do
      Application.put_env(:notifier, :mode, :sync)
      stub_http(&ok_responses/2)
      assert {:ok, [telegram: :ok]} = Notifier.notify(:info, "t", "b")
    end
  end

  describe "mode: :direct" do
    test "delivers asynchronously under Notifier.TaskSupervisor" do
      stub_http(&ok_responses/2)

      assert {:ok, [pid]} = Notifier.notify(:info, "async", "b", mode: :direct)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert_received {:request, :telegram, _, %{"text" => "ℹ️ <b>async</b>\n\nb"}}
    end
  end

  describe "telemetry" do
    test "emits start and stop events with channel and level metadata" do
      stub_http(&ok_responses/2)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:notifier, :deliver, :start],
          [:notifier, :deliver, :stop]
        ])

      Notifier.notify(:info, "t", "b", mode: :sync)

      assert_received {[:notifier, :deliver, :start], ^ref, %{system_time: _},
                       %{channel: :telegram, level: :info}}

      assert_received {[:notifier, :deliver, :stop], ^ref, %{duration: _},
                       %{channel: :telegram, level: :info, result: :ok}}
    end

    test "emits an exception event and returns an error when a channel raises" do
      Application.put_env(:notifier, :channels, %{boom: Notifier.RaisingChannel})
      ref = :telemetry_test.attach_event_handlers(self(), [[:notifier, :deliver, :exception]])

      capture_log(fn ->
        assert {:ok, [boom: {:error, %RuntimeError{}}]} =
                 Notifier.notify(:critical, "t", "b", mode: :sync, channels: [:boom])
      end)

      assert_received {[:notifier, :deliver, :exception], ^ref, _,
                       %{channel: :boom, level: :critical, kind: :error}}
    end
  end
end
