defmodule Notifier.Test.FakeRepo do
  @moduledoc false
  # Satisfies Oban's `repo` option validation. Oban's inline/manual testing
  # modes never query it.
  def config, do: []
end
