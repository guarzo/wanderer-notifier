defmodule WandererNotifier.Notifiers.TestNotificationTest do
  use ExUnit.Case

  test "basic test" do
    assert 1 + 1 == 2
  end

  test "test environment is set" do
    assert Application.get_env(:wanderer_notifier, :env) == :test
  end
end
