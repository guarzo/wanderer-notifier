defmodule WandererNotifier.Shared.ConfigTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Shared.Config

  # Sets up corporation_kill_focus config for test and ensures automatic restoration.
  # Pass :delete to remove the config, or a value to set it.
  defp with_corporation_kill_focus(value) do
    original = Application.get_env(:wanderer_notifier, :corporation_kill_focus)

    case value do
      :delete -> Application.delete_env(:wanderer_notifier, :corporation_kill_focus)
      _ -> Application.put_env(:wanderer_notifier, :corporation_kill_focus, value)
    end

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:wanderer_notifier, :corporation_kill_focus)
        _ -> Application.put_env(:wanderer_notifier, :corporation_kill_focus, original)
      end
    end)
  end

  describe "corporation_kill_focus/0" do
    test "returns empty list when not configured" do
      with_corporation_kill_focus(:delete)

      assert Config.corporation_kill_focus() == []
    end

    test "returns configured list of integers" do
      with_corporation_kill_focus([98_000_001, 98_000_002])

      assert Config.corporation_kill_focus() == [98_000_001, 98_000_002]
    end

    test "returns single item list when one ID configured" do
      with_corporation_kill_focus([98_000_001])

      assert Config.corporation_kill_focus() == [98_000_001]
    end
  end

  describe "corporation_kill_focus_enabled?/0" do
    test "returns false when list is empty" do
      with_corporation_kill_focus([])

      refute Config.corporation_kill_focus_enabled?()
    end

    test "returns false when not configured" do
      with_corporation_kill_focus(:delete)

      refute Config.corporation_kill_focus_enabled?()
    end

    test "returns true when list has one entry" do
      with_corporation_kill_focus([98_000_001])

      assert Config.corporation_kill_focus_enabled?()
    end

    test "returns true when list has multiple entries" do
      with_corporation_kill_focus([98_000_001, 98_000_002, 98_000_003])

      assert Config.corporation_kill_focus_enabled?()
    end
  end
end
