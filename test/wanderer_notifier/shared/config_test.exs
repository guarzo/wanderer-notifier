defmodule WandererNotifier.Shared.ConfigTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Shared.Config

  describe "corporation_exclude_list/0" do
    test "returns empty list when not configured" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)
      Application.delete_env(:wanderer_notifier, :corporation_exclude_list)

      assert Config.corporation_exclude_list() == []

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      end
    end

    test "returns configured list of integers" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)
      Application.put_env(:wanderer_notifier, :corporation_exclude_list, [98_000_001, 98_000_002])

      assert Config.corporation_exclude_list() == [98_000_001, 98_000_002]

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      else
        Application.delete_env(:wanderer_notifier, :corporation_exclude_list)
      end
    end

    test "returns single item list when one ID configured" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)
      Application.put_env(:wanderer_notifier, :corporation_exclude_list, [98_000_001])

      assert Config.corporation_exclude_list() == [98_000_001]

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      else
        Application.delete_env(:wanderer_notifier, :corporation_exclude_list)
      end
    end
  end

  describe "corporation_exclusion_enabled?/0" do
    test "returns false when list is empty" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)
      Application.put_env(:wanderer_notifier, :corporation_exclude_list, [])

      refute Config.corporation_exclusion_enabled?()

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      else
        Application.delete_env(:wanderer_notifier, :corporation_exclude_list)
      end
    end

    test "returns false when not configured" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)
      Application.delete_env(:wanderer_notifier, :corporation_exclude_list)

      refute Config.corporation_exclusion_enabled?()

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      end
    end

    test "returns true when list has one entry" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)
      Application.put_env(:wanderer_notifier, :corporation_exclude_list, [98_000_001])

      assert Config.corporation_exclusion_enabled?()

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      else
        Application.delete_env(:wanderer_notifier, :corporation_exclude_list)
      end
    end

    test "returns true when list has multiple entries" do
      original = Application.get_env(:wanderer_notifier, :corporation_exclude_list)

      Application.put_env(:wanderer_notifier, :corporation_exclude_list, [
        98_000_001,
        98_000_002,
        98_000_003
      ])

      assert Config.corporation_exclusion_enabled?()

      # Restore original config
      if original do
        Application.put_env(:wanderer_notifier, :corporation_exclude_list, original)
      else
        Application.delete_env(:wanderer_notifier, :corporation_exclude_list)
      end
    end
  end
end
