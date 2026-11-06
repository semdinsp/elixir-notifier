defmodule Notifier.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Used by `mode: :direct`. It is a single idle process when unused, so it
      # is always started rather than requiring every host app to add it.
      {Task.Supervisor, name: Notifier.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Notifier.Supervisor)
  end
end
