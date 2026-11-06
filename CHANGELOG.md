# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-06

### Added

- `Notifier.notify/4` with `:info`, `:warning` and `:critical` levels and configurable routing.
- Delivery modes: `:oban` (default), `:direct` and `:sync`.
- `Notifier.new_jobs/4` to build Oban job changesets without inserting them.
- `Notifier.Worker` Oban worker (`:notifications` queue, 5 attempts, retry vs. cancel semantics).
- Telegram channel (HTML parse mode with escaping).
- Pushover channel (priority mapping, emergency `retry`/`expire`).
- Twilio SMS channel stub (not implemented; always cancels).
- `[:notifier, :deliver, :start | :stop | :exception]` telemetry events.
