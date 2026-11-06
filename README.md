# Notifier

Send alerts to your phone from any Elixir app.

```elixir
Notifier.notify(:critical, "Payments down", "Webhook failures for 5 minutes",
  url: "https://example.com/admin/health")
```

Notifier is a small library with no business logic and no secrets. Every
token and ID comes from your app's runtime config. It delivers through your
app's existing [Oban](https://hexdocs.pm/oban) instance (with retries and
de-duplication). Apps without Oban can deliver directly instead.

## Channels

| Channel     | Status                    | Used by default for            |
|-------------|---------------------------|--------------------------------|
| Telegram    | ✅ supported               | `:info`, `:warning`, `:critical` |
| Pushover    | ✅ supported               | `:warning`, `:critical` (emergency priority) |
| Twilio SMS  | 🚧 **stub, not implemented** | not routed                    |

`Notifier.Channels.Twilio` exists as a placeholder for later SMS support.
Routing a message to it only logs a warning and returns
`{:cancel, :not_implemented}`.

---

## 1. Channel setup

### Telegram

1. In Telegram, open a chat with [@BotFather](https://t.me/BotFather) and send `/newbot`.
   Follow the prompts. BotFather replies with a **bot token** like
   `123456789:AA-your-bot-token-here`.
2. Open a chat with your new bot and send it any message (bots can't message
   you first). For a group, add the bot to the group and send a message there.
3. Get the **chat ID**:

   ```sh
   curl "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
   ```

   Find `"chat":{"id": ... }` in the response. Private chat IDs are positive
   numbers and group IDs are negative (e.g. `-1001234567890`).

### Pushover

1. Sign up at [pushover.net](https://pushover.net) and install the phone app.
   Your **user key** is shown on the dashboard.
2. Under **Your Applications → Create an Application/API Token**, create an
   app (e.g. "My Alerts"). Its **API token** is the app token.

Critical alerts use Pushover's emergency priority (`2`). They repeat every
`retry` seconds (default 60, minimum 30) until you acknowledge them or
`expire` seconds pass (default 3600, maximum 10800).

---

## 2. Installing into a host app

### Checklist for each app

- [ ] Add the `:notifier` dependency.
- [ ] Read the secrets in `config/runtime.exs`.
- [ ] **Add `notifications: 5` to the app's Oban `queues:`.** Without it, jobs
      are inserted but never run, so alerts silently never arrive.
- [ ] Set the secrets on Fly:

| Secret               | Needed for | Where it comes from                         |
|----------------------|------------|---------------------------------------------|
| `TELEGRAM_BOT_TOKEN` | Telegram   | @BotFather, when you create the bot         |
| `TELEGRAM_CHAT_ID`   | Telegram   | `getUpdates`, after you message the bot     |
| `PUSHOVER_TOKEN`     | Pushover   | the application you create on pushover.net  |
| `PUSHOVER_USER`      | Pushover   | your user key on the pushover.net dashboard |

Telegram alone needs only the first two. The Pushover pair is optional; when
it's unset, Pushover is skipped with a logged warning, and `:warning` and
`:critical` alerts go to Telegram only.

### Dependency

```elixir
# mix.exs
def deps do
  [
    {:notifier, github: "semdinsp/elixir-notifier"}
    # during development: {:notifier, path: "../elixir_notify"}
  ]
end
```

### Runtime config

```elixir
# config/runtime.exs
config :notifier,
  telegram_bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  telegram_chat_id: System.get_env("TELEGRAM_CHAT_ID"),
  pushover_token: System.get_env("PUSHOVER_TOKEN"),
  pushover_user: System.get_env("PUSHOVER_USER")
```

Any channel without credentials is skipped with a logged warning, so it's
fine to leave Pushover unset in dev.

Optional settings:

```elixir
config :notifier,
  mode: :oban,                 # :oban | :direct | :sync
  oban_name: Oban,             # name of your app's Oban instance
  pushover_retry: 60,          # emergency priority only
  pushover_expire: 3600,
  routes: %{info: [:telegram], warning: [:telegram, :pushover]},  # merged over defaults
  req_options: []              # extra Req options for every request
```

### Oban queue

Notifier inserts jobs into **your** Oban instance. It doesn't start Oban, own
a Repo, or ship migrations. Add the `notifications` queue:

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [default: 10, notifications: 5]
```

If your Oban instance isn't named `Oban` (e.g. `{Oban, name: MyApp.Oban}`), set
`config :notifier, oban_name: MyApp.Oban`.

In `:oban` mode, `notify/4` raises if that Oban instance isn't running. A
misconfigured alert path should fail loudly rather than go silent.

### Fly.io secrets

Telegram only:

```sh
fly secrets set \
  TELEGRAM_BOT_TOKEN="123456789:AA-your-bot-token-here" \
  TELEGRAM_CHAT_ID="your-chat-id"
```

Telegram and Pushover:

```sh
fly secrets set \
  TELEGRAM_BOT_TOKEN="123456789:AA-your-bot-token-here" \
  TELEGRAM_CHAT_ID="your-chat-id" \
  PUSHOVER_TOKEN="your-pushover-app-token" \
  PUSHOVER_USER="your-pushover-user-key"
```

Use `-a my-app` to target a specific app. Setting secrets restarts the machines.

---

## 3. Usage

### Levels

```elixir
Notifier.notify(:info, "Deploy finished", "v1.4.2 is live")
Notifier.notify(:warning, "Queue backing up", "1,200 jobs pending")
Notifier.notify(:critical, "Database unreachable", "Repo checkout timed out",
  url: "https://fly.io/apps/my-app/monitoring")
```

| level       | default channels       | Telegram | Pushover priority |
|-------------|------------------------|----------|-------------------|
| `:info`     | Telegram               | ℹ️       | –                 |
| `:warning`  | Telegram, Pushover     | ⚠️       | 0 (normal)        |
| `:critical` | Telegram, Pushover     | 🚨       | 2 (emergency)     |

(Routing `:info` to Pushover sends it at priority -1, which is quiet.)

Titles and bodies are plain text. Notifier HTML-escapes them for Telegram, so
`<`, `>` and `&` show up literally.

### Custom routes

Globally, merged over the defaults:

```elixir
config :notifier, routes: %{info: [], warning: [:telegram], critical: [:telegram, :pushover]}
```

Per call:

```elixir
Notifier.notify(:warning, "Card declined spike", "...", channels: [:pushover])
```

You can add your own channel by implementing the `Notifier.Channel` behaviour
and registering it:

```elixir
config :notifier, channels: %{slack: MyApp.SlackChannel}
```

### Delivery modes

| mode      | what happens                                          | returns |
|-----------|-------------------------------------------------------|---------|
| `:oban`   | one `Notifier.Worker` job per channel (default)       | `{:ok, [%Oban.Job{}]}` |
| `:direct` | fire-and-forget under `Notifier.TaskSupervisor`; no retries | `{:ok, [pid]}` |
| `:sync`   | delivered inline                                      | `{:ok, [telegram: :ok, pushover: {:error, ...}]}` |

**Apps without Oban** set the mode once:

```elixir
config :notifier, mode: :direct
```

You don't need to add anything to your supervision tree. Notifier's own OTP
application always starts a single `Task.Supervisor` named
`Notifier.TaskSupervisor`. It's one idle process when unused, which is simpler
and less error-prone than asking every host app to add it or starting it
conditionally based on config.

`:sync` is useful in scripts, release tasks and tests:

```elixir
{:ok, results} = Notifier.notify(:info, "Backfill done", "42 rows", mode: :sync)
```

### Uniqueness (don't page me 50 times)

In `:oban` mode, jobs are unique by default for 5 minutes on their args
(`unique: [period: 300, fields: [:args]]`). An alert that fires every few
seconds with the same title, body and URL produces one notification per
channel per 5 minutes. Override it per call:

```elixir
Notifier.notify(:critical, "Disk full", "/data at 99%", unique: [period: 3600])
Notifier.notify(:info, "User signed up", "id=123", unique: false)
```

Other Oban options pass through: `:queue` and `:priority` (Oban job
priority 0–9).

Uniqueness only applies in `:oban` mode. `:direct` and `:sync` send every call.

### Inserting inside a transaction

`Notifier.new_jobs/4` returns the job changesets without inserting them:

```elixir
multi = Ecto.Multi.insert(Ecto.Multi.new(), :order, changeset)

:info
|> Notifier.new_jobs("New order", "Order placed")
|> Enum.with_index()
|> Enum.reduce(multi, fn {job, i}, multi -> Oban.insert(multi, {:alert, i}, job) end)
|> Repo.transaction()
```

Use `Oban.insert/3` per job rather than `Oban.insert_all`, because Oban's
basic engine ignores `:unique` in `insert_all`.

### Failures and retries

`Notifier.Worker` runs in the `notifications` queue with `max_attempts: 5`.

- **Retried** (`{:error, reason}`): HTTP 5xx, 429 and transport errors such as timeouts.
- **Cancelled** (`{:cancel, reason}`): other 4xx responses (bad token, chat not
  found, invalid user key), missing credentials, and unknown channels.

Req's built-in retry is disabled because Oban owns retries. You can re-enable
it with `config :notifier, req_options: [retry: :transient]`.

---

## 4. Telemetry

Every delivery attempt, in every mode, is wrapped in `:telemetry.span/3`:

| event                                | measurements                 | metadata |
|--------------------------------------|------------------------------|----------|
| `[:notifier, :deliver, :start]`      | `system_time`, `monotonic_time` | `channel`, `level` |
| `[:notifier, :deliver, :stop]`       | `duration`, `monotonic_time` | `channel`, `level`, `result` |
| `[:notifier, :deliver, :exception]`  | `duration`, `monotonic_time` | `channel`, `level`, `kind`, `reason`, `stacktrace` |

```elixir
:telemetry.attach("notifier-logger", [:notifier, :deliver, :stop], fn _event, %{duration: d}, meta, _ ->
  ms = System.convert_time_unit(d, :native, :millisecond)
  IO.puts("#{meta.channel}/#{meta.level} -> #{inspect(meta.result)} in #{ms}ms")
end, nil)
```

---

## Sending a real test message

To check that your bot token and chat ID work end to end, send a real
notification to your phone from a checkout of this repo:

```sh
export TELEGRAM_BOT_TOKEN="123456789:AA-your-bot-token-here"
export TELEGRAM_CHAT_ID="your-chat-id"

mix run scripts/send_test_message.exs            # :info (default)
mix run scripts/send_test_message.exs warning
mix run scripts/send_test_message.exs critical
```

If your credentials are in a `.env` file (`KEY=value` lines; it's gitignored),
load them with `set -a; source .env; set +a`.

The script sends synchronously and prints each channel's result:

```text
Sending info test notification...
  telegram: ok
Done. Check your phone.
```

It exits with status 1 if a variable is missing or a channel fails. For
example, a wrong token shows `{:cancel, {:http_error, 401, ...}}`, and a chat
the bot can't reach shows `{:cancel, {:http_error, 400, ...}}`, which usually
means you haven't messaged the bot first.

`PUSHOVER_TOKEN` and `PUSHOVER_USER` are optional. When they're set, `warning`
and `critical` also go to Pushover. **`critical` uses emergency priority, so
your phone will keep alerting every 60 seconds until you acknowledge it in the
Pushover app.**

## Testing in your app

Use `mode: :sync` with a [`Req.Test`](https://hexdocs.pm/req/Req.Test.html) stub:

```elixir
# config/test.exs
config :notifier,
  mode: :sync,
  telegram_bot_token: "test-token",
  telegram_chat_id: "test-chat",
  req_options: [plug: {Req.Test, Notifier}]

# in a test
Req.Test.stub(Notifier, &Req.Test.json(&1, %{"ok" => true}))
```

Or leave credentials unset in test so every channel is skipped.

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```

The test suite doesn't need a database. HTTP is stubbed with `Req.Test`.
Worker behaviour is tested with `Oban.Testing.perform_job/3`, and job
insertion is tested by asserting on the changesets from `Notifier.new_jobs/4`.

## License

MIT. See [LICENSE](LICENSE).
